//
//  ScreenshotDemoDirector.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

#if DEBUG
import AppKit
import SwiftUI
import BucketeerCore

/// What the views show once the demo data is in place. Each view reads
/// the part it owns.
struct ScreenshotDemoStage: Equatable {
    enum ObjectSheet: Equatable {
        case dashboard
        case versions(key: String)
        case metadata(key: String)
    }

    var sidebarSelection: SidebarSelection?
    var objectSheet: ObjectSheet?
    var addAccountSheet = false
    var settingsTab: SettingsTab?
    var activityWindow = false
    var paywall = false
}

/// Seeds a demo container and drives it to one screenshot screen, so the
/// capture needs no clicks. Debug builds of the QA copy only — see
/// `ScreenshotDemoLaunch`.
@MainActor
@Observable
final class ScreenshotDemoDirector {
    /// Fills an App Store Mac screenshot (2880 × 1800 px) on a Retina display.
    static let mainWindowSize = CGSize(width: 1440, height: 900)

    /// `nil` until the seed is applied and the browser has navigated.
    private(set) var stage: ScreenshotDemoStage?

    private let launch: ScreenshotDemoLaunch
    private unowned let container: AppContainer

    private init(launch: ScreenshotDemoLaunch, container: AppContainer) {
        self.launch = launch
        self.container = container
    }

    static func makeContainer(for launch: ScreenshotDemoLaunch) throws -> AppContainer {
        let container = try AppContainer(configuration: launch.containerConfiguration)
        let director = ScreenshotDemoDirector(launch: launch, container: container)
        container.screenshotDemo = director
        Task { await director.run() }
        return container
    }

    private func run() async {
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        guard let seedPath = launch.seedPath else { return }
        do {
            let seed = try ScreenshotDemoSeed.load(path: seedPath)
            let accounts = try await seed.apply(to: container)
            await container.accountListViewModel.refresh()
            guard let screen = launch.screen, let account = accounts[seed.showcase.account] else { return }
            stage = await prepare(screen, showcase: seed.showcase, account: account)
        } catch {
            NSLog("Screenshot demo: seeding failed: %@", String(describing: error))
        }
    }

    /// Navigates the browser and returns what the views should present.
    private func prepare(
        _ screen: ScreenshotDemoScreen,
        showcase: ScreenshotDemoSeed.Showcase,
        account: S3Account
    ) async -> ScreenshotDemoStage {
        var stage = ScreenshotDemoStage(sidebarSelection: .account(account.id))
        switch screen {
        case .browser:
            await browse(account, showcase.bucket, folder: showcase.folder, selecting: showcase.object)
        case .addAccount:
            await browse(account, showcase.bucket, folder: showcase.folder)
            stage.addAccountSheet = true
        case .dashboard:
            await browse(account, showcase.bucket, folder: "")
            stage.objectSheet = .dashboard
        case .versions:
            await browse(account, showcase.bucket, folder: showcase.versionedFolder, selecting: showcase.versionedObject)
            stage.objectSheet = .versions(key: showcase.versionedObject)
        case .metadata:
            await browse(account, showcase.bucket, folder: showcase.folder, selecting: showcase.object)
            stage.objectSheet = .metadata(key: showcase.object)
        case .sync:
            stage.sidebarSelection = .syncRoot
        case .activity:
            await browse(account, showcase.bucket, folder: showcase.folder)
            stage.activityWindow = true
        case .encryption, .pro:
            await browse(account, showcase.bucket, folder: showcase.folder)
            stage.settingsTab = screen == .pro ? .pro : .encryption
        case .paywall:
            await container.entitlementManager.bootstrap()
            await browse(account, showcase.bucket, folder: showcase.folder)
            stage.paywall = true
        }
        return stage
    }

    private func browse(_ account: S3Account, _ bucket: String, folder: String, selecting key: String? = nil) async {
        let browser = container.browserViewModel
        await browser.openAccount(account)
        await browser.openBucket(bucket)
        if !folder.isEmpty {
            await browser.navigate(to: BreadcrumbCrumb(label: folder, bucket: bucket, prefix: folder))
        }
        if let key {
            browser.selection = [key]
        }
    }
}

/// Places the hosting window for the capture when the demo mode runs;
/// no-op otherwise.
struct ScreenshotDemoWindow: ViewModifier {
    /// `nil` keeps the window's own size.
    let size: CGSize?
    @Environment(AppContainer.self) private var container

    func body(content: Content) -> some View {
        if container.screenshotDemo != nil {
            content.background(ScreenshotDemoWindowPlacer(size: size))
        } else {
            content
        }
    }
}

/// Applies the demo stage to the main window: sidebar selection,
/// paywall, and the Activity Log and Settings windows.
struct ScreenshotDemoMainWindow: ViewModifier {
    @Binding var sidebarSelection: SidebarSelection?
    @Binding var showingPaywall: Bool
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content
            .modifier(ScreenshotDemoWindow(size: ScreenshotDemoDirector.mainWindowSize))
            .task(id: container.screenshotDemo?.stage) { apply(container.screenshotDemo?.stage) }
    }

    private func apply(_ stage: ScreenshotDemoStage?) {
        guard let stage else { return }
        sidebarSelection = stage.sidebarSelection
        showingPaywall = stage.paywall
        if stage.activityWindow {
            openWindow(id: "activity")
        }
        if stage.settingsTab != nil {
            openSettings()
        }
    }
}

/// Moves its window onto a Retina display, so captures come out at 2x,
/// optionally resizes it, and brings the app to the front.
private struct ScreenshotDemoWindowPlacer: NSViewRepresentable {
    let size: CGSize?

    func makeNSView(context: Context) -> NSView { PlacingView(size: size) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class PlacingView: NSView {
        private let size: CGSize?

        init(size: CGSize?) {
            self.size = size
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // Next turn: SwiftUI sizes a new window after inserting its content.
            Task { @MainActor [size] in
                Self.place(window, size: size)
            }
        }

        private static func place(_ window: NSWindow, size: CGSize?) {
            let screen = NSScreen.screens.first { $0.backingScaleFactor >= 2 } ?? window.screen
            guard let area = screen?.visibleFrame else { return }
            let size = size ?? window.frame.size
            let origin = CGPoint(x: area.midX - size.width / 2, y: max(area.minY, area.midY - size.height / 2))
            window.setFrame(CGRect(origin: origin, size: size), display: true)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
#endif
