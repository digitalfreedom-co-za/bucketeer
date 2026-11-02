//
//  OpenWithController.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation
import AppKit
import UniformTypeIdentifiers
import BucketeerCore

/// "Open" / "Open With…" for objects in the browser. Downloads the
/// object into a temp folder of this launch, opens it in another app,
/// watches the file and uploads every save back (debounced). The
/// upload is conditional on the ETag the download was based on; if
/// the object changed on the server meanwhile, the save goes up as a
/// conflict copy next to it and the user is told.
///
/// Temp files are removed when the editing app quits, when Bucketeer
/// quits, and at the next launch (leftovers of a crash).
@MainActor
@Observable
final class OpenWithController {
    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let message: String
    }

    /// Shown as an alert by `ContentView`.
    var notice: Notice?

    private struct OpenFile {
        let folder: URL
        let watcher: FileChangeWatcher
        let applicationPID: pid_t
        var pendingSync: Task<Void, Never>?
    }

    /// Wait after the last write before uploading, so an app that
    /// writes a document in several steps causes one upload.
    private static let debounce: Duration = .seconds(2)
    private static let rootFolderName = "BucketeerOpenWith"

    private let browser: any S3Browsing
    private let transferManager: TransferManager
    private let roundTrip: OpenWithRoundTrip
    private let sessionFolder: URL
    private var files: [URL: OpenFile] = [:]
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    init(browser: any S3Browsing, transferManager: TransferManager, accountStore: any AccountStoring) {
        self.browser = browser
        self.transferManager = transferManager
        self.roundTrip = OpenWithRoundTrip(remote: OpenWithTransferRemote(
            browser: browser,
            transferManager: transferManager,
            accountStore: accountStore
        ))
        self.sessionFolder = Self.rootFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                self?.applicationDidQuit(pid: pid)
            }
        }
    }

    // MARK: - Temp folders

    private static var rootFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(rootFolderName, isDirectory: true)
    }

    /// Launch cleanup: every folder except this launch's own belongs to
    /// an earlier launch that crashed or was killed.
    func removeLeftovers() {
        let current = sessionFolder.lastPathComponent
        Task.detached(priority: .utility) { [rootFolder = Self.rootFolder] in
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: rootFolder,
                includingPropertiesForKeys: nil
            )) ?? []
            for url in entries where url.lastPathComponent != current {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    var hasOpenFiles: Bool { !files.isEmpty }

    /// Quit cleanup. Saves still waiting for the debounce are uploaded
    /// first.
    func flushAndRemoveAll() async {
        for url in Array(files.keys) {
            await syncNow(url)
            await close(url)
        }
        try? FileManager.default.removeItem(at: sessionFolder)
    }

    // MARK: - Opening

    /// Apps that declare they can open files of this name's type, for
    /// the "Open With" submenu.
    static func applications(forFileNamed name: String) -> [URL] {
        let type = UTType(filenameExtension: (name as NSString).pathExtension) ?? .data
        return NSWorkspace.shared.urlsForApplications(toOpen: type)
    }

    /// `application == nil` uses the default app; if there is none the
    /// user picks one.
    func open(_ object: S3Object, account: S3Account, bucket: String, application: URL? = nil) async {
        let localURL: URL
        do {
            localURL = try await download(object, account: account, bucket: bucket)
        } catch {
            report(error, for: object.displayName)
            return
        }
        guard let appURL = application
                ?? NSWorkspace.shared.urlForApplication(toOpen: localURL)
                ?? chooseApplication()
        else {
            await discard(localURL)
            return
        }
        do {
            let app = try await NSWorkspace.shared.open(
                [localURL],
                withApplicationAt: appURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
            startWatching(localURL, applicationPID: app.processIdentifier)
        } catch {
            await discard(localURL)
            report(error, for: object.displayName)
        }
    }

    /// "Other…" entry of the submenu.
    func openWithChosenApplication(_ object: S3Object, account: S3Account, bucket: String) async {
        guard let appURL = chooseApplication() else { return }
        await open(object, account: account, bucket: bucket, application: appURL)
    }

    private func chooseApplication() -> URL? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = String(localized: "browser.action.open", defaultValue: "Open")
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// HEAD before the download: if the object changes in between, the
    /// older ETag makes the first save a conflict copy, never a silent
    /// overwrite.
    private func download(_ object: S3Object, account: S3Account, bucket: String) async throws -> URL {
        let head = try await browser.head(account: account, bucket: bucket, key: object.key)
        let folder = sessionFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let localURL = folder.appendingPathComponent(object.displayName)

        let id = await transferManager.enqueueDownload(
            account: account,
            bucket: bucket,
            key: object.key,
            localURL: localURL
        )
        switch await transferManager.awaitCompletion(id: id) {
        case .completed:
            break
        case .failed(let message):
            try? FileManager.default.removeItem(at: folder)
            throw BucketeerError.unknown(message: message)
        default:
            try? FileManager.default.removeItem(at: folder)
            throw BucketeerError.cancelled
        }
        try await roundTrip.register(
            localURL: localURL,
            object: RemoteObjectRef(accountID: account.id, bucket: bucket, key: object.key),
            etag: head.etag.isEmpty ? nil : head.etag
        )
        return localURL
    }

    // MARK: - Watching and uploading

    private func startWatching(_ localURL: URL, applicationPID: pid_t) {
        let watcher = FileChangeWatcher(fileURL: localURL) { [weak self] in
            self?.scheduleSync(localURL)
        }
        files[localURL] = OpenFile(
            folder: localURL.deletingLastPathComponent(),
            watcher: watcher,
            applicationPID: applicationPID
        )
        watcher.start()
    }

    private func scheduleSync(_ localURL: URL) {
        guard files[localURL] != nil else { return }
        files[localURL]?.pendingSync?.cancel()
        files[localURL]?.pendingSync = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.syncNow(localURL)
        }
    }

    private func syncNow(_ localURL: URL) async {
        files[localURL]?.pendingSync?.cancel()
        files[localURL]?.pendingSync = nil
        // The editing app may be mid-save (file briefly missing).
        guard FileManager.default.fileExists(atPath: localURL.path) else { return }
        let originalKey = await roundTrip.object(for: localURL)?.key ?? localURL.lastPathComponent
        do {
            switch try await roundTrip.syncChanges(at: localURL) {
            case .unchanged, .uploaded:
                break
            case .conflict(let copyKey):
                let name = (originalKey as NSString).lastPathComponent
                let copyName = (copyKey as NSString).lastPathComponent
                show(Notice(
                    title: String(localized: "openWith.conflict.title", defaultValue: "Saved as a conflict copy"),
                    message: String(
                        localized: "openWith.conflict.message",
                        defaultValue: "\"\(name)\" was changed on the server after you opened it. Your version was uploaded next to it as \"\(copyName)\"."
                    )
                ))
            }
        } catch {
            report(error, for: (originalKey as NSString).lastPathComponent)
        }
    }

    // MARK: - Closing

    private func applicationDidQuit(pid: pid_t) {
        let closed = files.filter { $0.value.applicationPID == pid }.map(\.key)
        guard !closed.isEmpty else { return }
        Task {
            for url in closed {
                await syncNow(url)
                await close(url)
            }
        }
    }

    private func close(_ localURL: URL) async {
        guard let file = files.removeValue(forKey: localURL) else { return }
        file.pendingSync?.cancel()
        file.watcher.stop()
        await roundTrip.unregister(localURL: localURL)
        try? FileManager.default.removeItem(at: file.folder)
    }

    private func discard(_ localURL: URL) async {
        await roundTrip.unregister(localURL: localURL)
        try? FileManager.default.removeItem(at: localURL.deletingLastPathComponent())
    }

    // MARK: - Notices

    private func report(_ error: Error, for name: String) {
        if case .cancelled = error as? BucketeerError { return }
        let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        show(Notice(
            title: String(localized: "openWith.error.title", defaultValue: "Open With failed"),
            message: String(
                localized: "openWith.error.message",
                defaultValue: "\"\(name)\": \(reason)"
            )
        ))
    }

    /// The user is usually in the other app when a save is processed:
    /// bounce the Dock icon so the alert is not missed.
    private func show(_ newNotice: Notice) {
        notice = newNotice
        NSApp.requestUserAttention(.informationalRequest)
    }
}
