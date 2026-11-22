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
/// A temp copy is deleted only once the server has exactly its bytes.
/// Edits that could not be uploaded (offline, error, an edit during the
/// final upload, a crash) are kept in Application Support and offered
/// for upload, export or discarding — after the failure and at the next
/// launch.
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
    /// Kept edits waiting for a decision, oldest first.
    private(set) var recoveries: [OpenWithRecoveryEntry] = []
    /// Kept edits the user put off until the next launch.
    private var postponed: Set<URL> = []
    /// Why the last upload of a kept edit failed, when known.
    private var failureReasons: [URL: String] = [:]

    private struct OpenFile {
        let watcher: FileChangeWatcher
        let applicationPID: pid_t
        var pendingSync: Task<Void, Never>?
    }

    /// Wait after the last write before uploading, so an app that
    /// writes a document in several steps causes one upload.
    private static let debounce: Duration = .seconds(2)
    private static let workFolderName = "BucketeerOpenWith"
    private static let recoveryFolderName = "OpenWithRecovery"

    private let browser: any S3Browsing
    private let transferManager: TransferManager
    private let workspace: OpenWithWorkspace
    private let roundTrip: OpenWithRoundTrip
    private var files: [URL: OpenFile] = [:]
    /// Closes in progress, so the editor quitting and Bucketeer quitting
    /// at the same time close each file once.
    private var closing: [URL: Task<OpenWithCloseResult, Never>] = [:]
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    init(browser: any S3Browsing, transferManager: TransferManager, accountStore: any AccountStoring) {
        self.browser = browser
        self.transferManager = transferManager
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let workspace = OpenWithWorkspace(
            workRoot: FileManager.default.temporaryDirectory
                .appendingPathComponent(Self.workFolderName, isDirectory: true),
            recoveryRoot: support.appendingPathComponent(Self.recoveryFolderName, isDirectory: true)
        )
        self.workspace = workspace
        self.roundTrip = OpenWithRoundTrip(
            remote: OpenWithTransferRemote(
                browser: browser,
                transferManager: transferManager,
                accountStore: accountStore
            ),
            workspace: workspace
        )
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

    // MARK: - Launch and quit

    /// Launch: unsynced files of an earlier launch that crashed move to
    /// recovery, the rest of its folders are removed; then every kept
    /// edit is offered.
    func prepareWorkspace() {
        Task.detached(priority: .utility) { [workspace] in
            workspace.scavengeLeftovers()
            let kept = workspace.recoveries()
            await MainActor.run { [weak self] in
                self?.recoveries = kept
            }
        }
    }

    var hasOpenFiles: Bool { !files.isEmpty || !closing.isEmpty }

    /// Quit: uploads what is still waiting and closes every file.
    /// Returns how many edits could not be uploaded and were kept.
    func flushAndRemoveAll() async -> Int {
        var kept = 0
        for url in Array(files.keys) + Array(closing.keys) {
            if await close(url)?.retained != nil {
                kept += 1
            }
        }
        return kept
    }

    /// Asked when quitting left edits that could not be uploaded. They
    /// are already safe in recovery either way; the user may stay to
    /// deal with them now.
    func confirmQuit(keeping kept: Int) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "openWith.quit.kept.title", defaultValue: "Some edits were not uploaded")
        alert.informativeText = String(
            localized: "openWith.quit.kept.message",
            defaultValue: "Edited files that could not be uploaded: \(kept). They are kept on this Mac and offered again the next time you open Bucketeer."
        )
        alert.addButton(withTitle: String(localized: "openWith.quit.kept.quit", defaultValue: "Quit"))
        alert.addButton(withTitle: String(localized: "openWith.quit.kept.stay", defaultValue: "Don't Quit"))
        return alert.runModal() == .alertFirstButtonReturn
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
            // Take only the process id across the await. NSRunningApplication
            // is not Sendable on the Xcode 16.0 SDK.
            let pid: pid_t = try await withCheckedThrowingContinuation { continuation in
                NSWorkspace.shared.open(
                    [localURL],
                    withApplicationAt: appURL,
                    configuration: NSWorkspace.OpenConfiguration()
                ) { app, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let app {
                        continuation.resume(returning: app.processIdentifier)
                    } else {
                        continuation.resume(throwing: CocoaError(.fileNoSuchFile))
                    }
                }
            }
            startWatching(localURL, applicationPID: pid)
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
        let folder = try workspace.makeFileFolder()
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
        files[localURL] = OpenFile(watcher: watcher, applicationPID: applicationPID)
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

    /// Upload while the file is still open. A failure is reported and
    /// retried with the next save; closing decides what to keep.
    private func syncNow(_ localURL: URL) async {
        files[localURL]?.pendingSync = nil
        // The editing app may be mid-save (file briefly missing).
        guard FileManager.default.fileExists(atPath: localURL.path) else { return }
        let originalKey = await roundTrip.object(for: localURL)?.key ?? localURL.lastPathComponent
        do {
            let outcome = try await roundTrip.syncChanges(at: localURL)
            announce(outcome, originalKey: originalKey)
        } catch {
            report(error, for: (originalKey as NSString).lastPathComponent)
        }
    }

    private func announce(_ outcome: RoundTripOutcome, originalKey: String) {
        guard case .conflict(let copyKey) = outcome else { return }
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

    // MARK: - Closing

    private func applicationDidQuit(pid: pid_t) {
        let closed = files.filter { $0.value.applicationPID == pid }.map(\.key)
        guard !closed.isEmpty else { return }
        Task {
            for url in closed {
                await close(url)
            }
        }
    }

    /// Stops watching, runs the final upload and lets the round-trip
    /// delete the copy or keep it. `nil` for files that are not open.
    @discardableResult
    private func close(_ localURL: URL) async -> OpenWithCloseResult? {
        if let running = closing[localURL] {
            return await running.value
        }
        guard let file = files.removeValue(forKey: localURL) else { return nil }
        file.pendingSync?.cancel()
        file.watcher.stop()
        let originalKey = await roundTrip.object(for: localURL)?.key ?? localURL.lastPathComponent
        let task = Task { [roundTrip] in await roundTrip.close(localURL) }
        closing[localURL] = task
        let result = await task.value
        closing[localURL] = nil
        handle(result, originalKey: originalKey)
        return result
    }

    private func handle(_ result: OpenWithCloseResult, originalKey: String) {
        switch result.sync {
        case .success(let outcome):
            announce(outcome, originalKey: originalKey)
        case .failure(let error):
            if result.retained == nil {
                report(error, for: (originalKey as NSString).lastPathComponent)
            }
        }
        if let kept = result.retained {
            if case .failure(let error) = result.sync {
                failureReasons[kept.fileURL] = Self.reason(error)
            }
            offer(kept)
        }
    }

    private func discard(_ localURL: URL) async {
        await roundTrip.unregister(localURL: localURL)
        try? FileManager.default.removeItem(at: localURL.deletingLastPathComponent())
    }

    // MARK: - Recovery

    /// The kept edit to ask about now (`ContentView` shows it).
    var recoveryPrompt: OpenWithRecoveryEntry? {
        recoveries.first { !postponed.contains($0.fileURL) }
    }

    func recoveryMessage(for entry: OpenWithRecoveryEntry) -> String {
        let object = entry.manifest.object
        let target = "\(object.bucket)/\(object.key)"
        let reason = failureReasons[entry.fileURL]
            ?? String(localized: "openWith.recovery.reasonUnknown", defaultValue: "The upload did not finish.")
        return String(
            localized: "openWith.recovery.message",
            defaultValue: "Your edit of \"\(target)\" is kept on this Mac but was not uploaded. \(reason)"
        )
    }

    /// Uploads the kept edit again against the version it was based on,
    /// so a newer server version still becomes a conflict copy.
    func retry(_ entry: OpenWithRecoveryEntry) async {
        forget(entry)
        let result = await roundTrip.retry(entry)
        handle(result, originalKey: entry.manifest.object.key)
    }

    /// Saves the kept edit wherever the user wants; only then removed.
    func export(_ entry: OpenWithRecoveryEntry) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = entry.fileURL.lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: entry.fileURL)
            } else {
                try FileManager.default.copyItem(at: entry.fileURL, to: destination)
            }
        } catch {
            report(error, for: entry.fileURL.lastPathComponent)
            return
        }
        forget(entry)
        workspace.discard(entry)
    }

    func discardRecovery(_ entry: OpenWithRecoveryEntry) {
        forget(entry)
        workspace.discard(entry)
    }

    /// Stays on disk; asked again at the next launch.
    func postpone(_ entry: OpenWithRecoveryEntry) {
        postponed.insert(entry.fileURL)
    }

    private func offer(_ entry: OpenWithRecoveryEntry) {
        guard !recoveries.contains(entry) else { return }
        recoveries.append(entry)
        NSApp.requestUserAttention(.informationalRequest)
    }

    private func forget(_ entry: OpenWithRecoveryEntry) {
        recoveries.removeAll { $0 == entry }
        failureReasons[entry.fileURL] = nil
    }

    // MARK: - Notices

    private func report(_ error: Error, for name: String) {
        if case .cancelled = error as? BucketeerError { return }
        show(Notice(
            title: String(localized: "openWith.error.title", defaultValue: "Open With failed"),
            message: String(
                localized: "openWith.error.message",
                defaultValue: "\"\(name)\": \(Self.reason(error))"
            )
        ))
    }

    private static func reason(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// The user is usually in the other app when a save is processed:
    /// bounce the Dock icon so the alert is not missed.
    private func show(_ newNotice: Notice) {
        notice = newNotice
        NSApp.requestUserAttention(.informationalRequest)
    }
}
