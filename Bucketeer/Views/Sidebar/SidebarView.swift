//
//  SidebarView.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI

enum SidebarSelection: Hashable {
    case accountsRoot
    case account(UUID)
    case mountedRoot
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
                            Text(account.provider.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: account.provider.iconSystemName)
                            .foregroundStyle(.tint)
                    }
                    .tag(SidebarSelection.account(account.id))
                    .contextMenu {
                        Button("action.edit", systemImage: "pencil") {
                            editingAccount = account
                        }
                        Divider()
                        Button("action.delete", systemImage: "trash", role: .destructive) {
                            pendingDeletion = account
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
            entitlementFooter
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
                    await viewModel.save(account: updated, credentials: credentials)
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
                Task { await viewModel.delete(account: account) }
                pendingDeletion = nil
            }
            Button("action.cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: { account in
            Text("account.delete.confirm.message \(account.name)")
        }
        .task { await viewModel.refresh() }
    }

    @ViewBuilder
    private var entitlementFooter: some View {
        switch container.entitlementManager.state {
        case .pro:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.tint)
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
                        .foregroundStyle(.tint)
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
                        .foregroundStyle(.tint)
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
