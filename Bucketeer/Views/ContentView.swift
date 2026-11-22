//
//  ContentView.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI
import BucketeerCore

struct ContentView: View {
    @Environment(AppContainer.self) private var container
    @State private var sidebarSelection: SidebarSelection? = nil
    @State private var paywallFeature: EntitlementManager.ProFeature?
    @State private var showingPaywall: Bool = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                viewModel: container.accountListViewModel,
                selection: $sidebarSelection
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } content: {
            contentPane
                .navigationSplitViewColumnWidth(min: 420, ideal: 620)
        } detail: {
            ObjectDetailView(viewModel: container.browserViewModel)
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        }
        .onChange(of: sidebarSelection) { _, new in
            handleSelectionChange(new)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallSheet(feature: paywallFeature)
                .environment(container)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showBucketeerPaywall)) { note in
            paywallFeature = note.object as? EntitlementManager.ProFeature
            showingPaywall = true
        }
        #if DEBUG
        .modifier(ScreenshotDemoMainWindow(sidebarSelection: $sidebarSelection, showingPaywall: $showingPaywall))
        #endif
        .alert(
            "browser.action.errorTitle",
            isPresented: Binding(
                get: { container.dragDropCoordinator.lastError != nil },
                set: { if !$0 { container.dragDropCoordinator.lastError = nil } }
            ),
            presenting: container.dragDropCoordinator.lastError
        ) { _ in
            Button("action.ok", role: .cancel) {
                container.dragDropCoordinator.lastError = nil
            }
        } message: { error in
            Text(error.errorDescription ?? "")
        }
        .alert(
            "encryption.plainCopy.title",
            isPresented: unencryptedDropAlertPresented,
            presenting: container.dragDropCoordinator.pendingUnencryptedDrops.first
        ) { drop in
            Button("action.cancel", role: .cancel) {
                container.dragDropCoordinator.discardUnencryptedDrop(drop)
            }
            .keyboardShortcut(.defaultAction)
            Button("encryption.plainCopy.confirm", role: .destructive) {
                Task { await container.dragDropCoordinator.confirmUnencryptedDrop(drop) }
            }
        } message: { drop in
            Text("encryption.plainCopy.message \(drop.sourceBucket) \(drop.destinationBucket)")
        }
        .alert(
            "browser.action.errorTitle",
            isPresented: Binding(
                get: { container.mountController.lastError != nil },
                set: { if !$0 { container.mountController.lastError = nil } }
            ),
            presenting: container.mountController.lastError
        ) { _ in
            Button("action.ok", role: .cancel) {
                container.mountController.lastError = nil
            }
        } message: { error in
            Text(error.errorDescription ?? "")
        }
        .alert(
            container.openWithController.notice?.title ?? "",
            isPresented: Binding(
                get: { container.openWithController.notice != nil },
                set: { if !$0 { container.openWithController.notice = nil } }
            ),
            presenting: container.openWithController.notice
        ) { _ in
            Button("action.ok", role: .cancel) {
                container.openWithController.notice = nil
            }
        } message: { notice in
            Text(notice.message)
        }
        .alert(
            "openWith.recovery.title",
            isPresented: Binding(
                get: { container.openWithController.recoveryPrompt != nil },
                set: { _ in }
            ),
            presenting: container.openWithController.recoveryPrompt
        ) { entry in
            let openWith = container.openWithController
            Button("openWith.recovery.retry") {
                Task { await openWith.retry(entry) }
            }
            Button("openWith.recovery.export") {
                openWith.export(entry)
            }
            Button("openWith.recovery.discard", role: .destructive) {
                openWith.discardRecovery(entry)
            }
            Button("openWith.recovery.later", role: .cancel) {
                openWith.postpone(entry)
            }
        } message: { entry in
            Text(container.openWithController.recoveryMessage(for: entry))
        }
    }

    /// Dismissing discards only the drop the alert was built for: the
    /// confirm task may already have removed it, and the next pending
    /// drop must stay for its own alert.
    private var unencryptedDropAlertPresented: Binding<Bool> {
        let coordinator = container.dragDropCoordinator
        let shown = coordinator.pendingUnencryptedDrops.first
        return Binding(
            get: { !coordinator.pendingUnencryptedDrops.isEmpty },
            set: { if !$0, let shown { coordinator.discardUnencryptedDrop(shown) } }
        )
    }

    @ViewBuilder
    private var contentPane: some View {
        if case .transfersRoot = sidebarSelection {
            TransferListView(viewModel: container.transferQueueViewModel,
                             encryptionKeys: container.encryptionKeysViewModel)
        } else if case .syncRoot = sidebarSelection {
            SyncJobListView(viewModel: container.syncJobListViewModel)
        } else {
            browserPane
        }
    }

    @ViewBuilder
    private var browserPane: some View {
        let vm = container.browserViewModel
        if vm.account == nil {
            ContentUnavailableView {
                Label("empty.no-account.title",
                      systemImage: "externaldrive.badge.questionmark")
            } description: {
                Text("empty.no-account.message")
            }
        } else if vm.bucket == nil {
            BucketListView(viewModel: vm)
        } else {
            ObjectListView(viewModel: vm)
        }
    }

    private func handleSelectionChange(_ selection: SidebarSelection?) {
        switch selection {
        case .account(let id):
            guard let account = container.accountListViewModel.accounts
                .first(where: { $0.id == id })
            else { return }
            if container.browserViewModel.account?.id != id {
                Task { await container.browserViewModel.openAccount(account) }
            }
        case .none:
            container.browserViewModel.clear()
        default:
            break
        }
    }
}
