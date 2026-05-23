//
//  MenuBarContent.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import SwiftUI
import AppKit
import BucketeerCore

/// SwiftUI content for the system menubar item. Shows live transfer
/// state plus shortcuts that mirror the app menu. Mount and Sync rows
/// land in Phases 9 and 10; for now they're placeholders so the layout
/// is stable.
struct MenuBarContent: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 4)
            transfersSection
            Divider().padding(.vertical, 4)
            mountedSection
            Divider().padding(.vertical, 4)
            syncSection
            Divider().padding(.vertical, 4)
            actionsSection
        }
        .padding(12)
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("app.name")
                    .font(.headline)
                Text("menubar.subtitle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Transfers

    private var transfersSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("menubar.section.transfers")
            let active = container.transferQueueViewModel.tasks
                .filter { !$0.state.isTerminal }
            if active.isEmpty {
                Text("menubar.transfers.empty")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(active.prefix(4)) { task in
                    transferRow(task)
                }
                if active.count > 4 {
                    Text("menubar.transfers.more \(active.count - 4)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func transferRow(_ task: TransferTask) -> some View {
        HStack(spacing: 8) {
            Image(systemName: task.direction == .upload
                  ? "arrow.up.circle"
                  : "arrow.down.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.key)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let fraction = task.state.progressFraction {
                    ProgressView(value: fraction)
                        .controlSize(.small)
                } else if case .queued = task.state {
                    Text("transfer.state.queued")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 4)
        }
    }

    // MARK: - Mount + Sync placeholders

    private var mountedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("menubar.section.mounted")
            Text("menubar.mounted.empty")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("menubar.section.sync")
            Text("menubar.sync.empty")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                openMainWindow()
            } label: {
                Label("menubar.action.openBrowser", systemImage: "macwindow")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("menubar.action.quit", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private func openMainWindow() {
        // Bring the app to the foreground regardless of activation
        // policy — in `.accessory` mode there is no Dock icon to click
        // so this is the only way back to the window.
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.bottom, 2)
    }
}
