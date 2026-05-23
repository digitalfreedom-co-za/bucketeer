//
//  ContentView.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppContainer.self) private var container
    @State private var sidebarSelection: SidebarSelection? = nil

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
    }

    @ViewBuilder
    private var contentPane: some View {
        if case .transfersRoot = sidebarSelection {
            TransferListView(viewModel: container.transferQueueViewModel)
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
