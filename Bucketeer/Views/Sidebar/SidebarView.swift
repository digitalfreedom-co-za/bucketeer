//
//  SidebarView.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI
import BucketeerCore

enum SidebarSelection: Hashable {
    case account(UUID)
    case syncRoot
    case transfersRoot
}

struct SidebarView: View {
    @Bindable var viewModel: AccountListViewModel
    @Binding var selection: SidebarSelection?
    @Environment(AppContainer.self) private var container
    @State private var showingAddSheet: Bool = false
    @State private var editingAccount: S3Account?
    @State private var pendingDeletion: S3Account?
    @State private var deletionKeyCount = 0
    @State private var deletionError: String?
    @State private var showingPaywall: Bool = false

    private var transferActiveCount: Int {
        container.transferQueueViewModel.activeCount
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(viewModel.accounts) { account in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                            Text(account.provider.localizedDisplayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: account.provider.iconSystemName)
                            .foregroundStyle(.accentInk)
                    }
                    .tag(SidebarSelection.account(account.id))
                    .contextMenu {
                        Button("action.edit", systemImage: "pencil") {
                            editingAccount = account
                        }
                        Divider()
                        Button("action.delete", systemImage: "trash", role: .destructive) {
                            Task {
                                do {
                                    deletionKeyCount = try await container.encryptionKeysViewModel.keyCount(accountID: account.id)
                                    pendingDeletion = account
                                } catch {
                                    deletionError = error.localizedDescription
                                }
                            }
                        }
                    }
                }

                Button {
                    showingAddSheet = true
                } label: {
                    Label("action.add-account", systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            } header: {
                Text("sidebar.section.accounts")
            }

            Section {
                Text("sidebar.empty.mounted")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } header: {
                Text("sidebar.section.mounted")
            }

            Section {
                NavigationLink(value: SidebarSelection.syncRoot) {
                    Label("sidebar.section.sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .tag(SidebarSelection.syncRoot)
            } header: {
                Text("sidebar.section.sync")
            }

            Section {
                NavigationLink(value: SidebarSelection.transfersRoot) {
                    Label {
                        HStack {
                            Text("sidebar.section.transfers")
                            Spacer()
                            if transferActiveCount > 0 {
                                Text("\(transferActiveCount)")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.tint, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                    } icon: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }
                .tag(SidebarSelection.transfersRoot)
            } header: {
                Text("sidebar.section.transfers")
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                ErrorBanner(error: viewModel.error)
                entitlementFooter
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("action.add-account", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallSheet(feature: nil)
                .environment(container)
        }
        .sheet(isPresented: $showingAddSheet) {
            AddEditAccountSheet(
                mode: .create,
                onSave: { account, credentials in
                    await viewModel.save(account: account, credentials: credentials)
                },
                onTest: { account, credentials in
                    await viewModel.testConnection(account: account, credentials: credentials)
                },
                onLoadCredentials: { id in
                    await viewModel.loadCredentials(for: id)
                }
            )
        }
        .sheet(item: $editingAccount) { account in
            AddEditAccountSheet(
                mode: .edit(account),
                onSave: { updated, credentials in
                    let failure = await viewModel.save(account: updated, credentials: credentials)
                    // The browser keeps its own copy of the account; reopen
                    // it so a new bucket or region applies right away.
                    let browser = container.browserViewModel
                    if failure == nil, browser.account?.id == updated.id {
                        Task { await browser.openAccount(updated) }
                    }
                    return failure
                },
                onTest: { updated, credentials in
                    await viewModel.testConnection(account: updated, credentials: credentials)
                },
                onLoadCredentials: { id in
                    await viewModel.loadCredentials(for: id)
                }
            )
        }
        .confirmationDialog(
            "account.delete.confirm.title",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { account in
            Button("action.delete", role: .destructive) {
                Task {
                    if let error = await viewModel.delete(account: account) {
                        deletionError = error.localizedDescription
                    }
                    await container.encryptionKeysViewModel.reload()
                }
                pendingDeletion = nil
            }
            Button("action.cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: { account in
            if deletionKeyCount > 0 {
                Text("account.delete.confirm.message \(account.name)")
                    + Text("\n\n")
                    + Text("account.delete.encryptionWarning \(deletionKeyCount)")
            } else {
                Text("account.delete.confirm.message \(account.name)")
            }
        }
        .alert("browser.error.title", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("action.cancel", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "")
        }
        .task { await viewModel.refresh() }
        #if DEBUG
        .task(id: container.screenshotDemo?.stage?.addAccountSheet) {
            if container.screenshotDemo?.stage?.addAccountSheet == true {
                showingAddSheet = true
            }
        }
        #endif
    }

    @ViewBuilder
    private var entitlementFooter: some View {
        switch container.entitlementManager.state {
        case .pro:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.accentInk)
                Text("paywall.badge.pro")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        case .trial(let days):
            Button {
                showingPaywall = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.checkmark")
                        .foregroundStyle(.accentInk)
                    Text("paywall.badge.trial \(days)")
                        .font(.caption)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.borderless)
        case .free:
            Button {
                showingPaywall = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lock.open")
                        .foregroundStyle(.accentInk)
                    Text("paywall.badge.upgrade")
                        .font(.caption)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.borderless)
        }
    }
}
