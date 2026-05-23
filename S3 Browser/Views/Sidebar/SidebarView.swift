//
//  SidebarView.swift
//  S3 Browser
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
                Text("sidebar.empty.sync")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("action.add-account", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddEditAccountSheet(mode: .create) { account, credentials in
                await viewModel.save(account: account, credentials: credentials)
            }
        }
        .sheet(item: $editingAccount) { account in
            AddEditAccountSheet(mode: .edit(account)) { updated, credentials in
                await viewModel.save(account: updated, credentials: credentials)
            }
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
}
