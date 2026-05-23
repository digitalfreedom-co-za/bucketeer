//
//  SyncJobSheet.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import SwiftUI

/// Single-page sync job editor. Spec §7.3 calls for a multi-step
/// wizard; v1 ships a compact one-page form so power users can
/// configure jobs in seconds. The wizard layout is parked for v1.1
/// when we have a/b data on how users actually pick endpoints.
struct SyncJobSheet: View {
    enum Mode: Equatable {
        case create
        case edit(SyncJob)
    }

    let mode: Mode
    let accounts: [S3Account]
    let onSave: @MainActor (SyncJob) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var mode_: SyncMode = .copy
    @State private var sourceAccountID: UUID?
    @State private var sourceBucket: String = ""
    @State private var sourcePrefix: String = ""
    @State private var destAccountID: UUID?
    @State private var destBucket: String = ""
    @State private var destPrefix: String = ""
    @State private var diffStrategy: SyncDiffStrategy = .nameAndSize
    @State private var includeGlobs: String = ""
    @State private var excludeGlobs: String = ""
    @State private var deletePropagation: Bool = false
    @State private var scheduleKind: ScheduleKind = .manual
    @State private var intervalMinutes: Int = 60
    @State private var concurrency: Int = 4
    @State private var enabled: Bool = true
    @State private var hasHydrated: Bool = false
    @State private var saving: Bool = false

    private enum ScheduleKind: String, CaseIterable {
        case manual, onLaunch, interval
    }

    private var isEditing: Bool { if case .edit = mode { return true }; return false }

    private var canSave: Bool {
        !saving
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && sourceAccountID != nil
            && destAccountID != nil
            && !sourceBucket.trimmingCharacters(in: .whitespaces).isEmpty
            && !destBucket.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                generalSection
                sourceSection
                destinationSection
                rulesSection
                scheduleSection
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "sync.edit.title" : "sync.new.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { commit() }
                        .disabled(!canSave)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .onAppear(perform: hydrate)
        }
        .frame(minWidth: 600, minHeight: 600)
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section("sync.section.general") {
            TextField("sync.field.name", text: $name)
            Picker("sync.field.mode", selection: $mode_) {
                Text("sync.mode.copy").tag(SyncMode.copy)
                Text("sync.mode.move").tag(SyncMode.move)
                Text("sync.mode.mirror").tag(SyncMode.mirror)
            }
            Toggle("sync.field.enabled", isOn: $enabled)
        }
    }

    private var sourceSection: some View {
        Section("sync.section.source") {
            accountPicker(selection: $sourceAccountID)
            TextField("sync.field.bucket", text: $sourceBucket)
                .autocorrectionDisabled()
            TextField("sync.field.prefix", text: $sourcePrefix)
                .autocorrectionDisabled()
        }
    }

    private var destinationSection: some View {
        Section("sync.section.destination") {
            accountPicker(selection: $destAccountID)
            TextField("sync.field.bucket", text: $destBucket)
                .autocorrectionDisabled()
            TextField("sync.field.prefix", text: $destPrefix)
                .autocorrectionDisabled()
        }
    }

    private var rulesSection: some View {
        Section("sync.section.rules") {
            Picker("sync.field.diffStrategy", selection: $diffStrategy) {
                Text("sync.diff.nameAndSize").tag(SyncDiffStrategy.nameAndSize)
                Text("sync.diff.nameAndEtag").tag(SyncDiffStrategy.nameAndEtag)
            }
            TextField("sync.field.includeGlobs", text: $includeGlobs, prompt: Text("*.jpg, *.pdf"))
                .autocorrectionDisabled()
            TextField("sync.field.excludeGlobs", text: $excludeGlobs, prompt: Text("*.tmp, *.log"))
                .autocorrectionDisabled()
            if mode_ == .mirror {
                Toggle("sync.field.deletePropagation", isOn: $deletePropagation)
                Text("sync.delete.hint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Stepper(value: $concurrency, in: 1...8) {
                Text("sync.field.concurrency \(concurrency)")
            }
        }
    }

    private var scheduleSection: some View {
        Section("sync.section.schedule") {
            Picker("sync.field.schedule", selection: $scheduleKind) {
                Text("sync.schedule.manual").tag(ScheduleKind.manual)
                Text("sync.schedule.onLaunch").tag(ScheduleKind.onLaunch)
                Text("sync.schedule.interval").tag(ScheduleKind.interval)
            }
            if scheduleKind == .interval {
                Stepper(value: $intervalMinutes, in: 5...1440, step: 5) {
                    Text("sync.field.intervalMinutes \(intervalMinutes)")
                }
            }
        }
    }

    @ViewBuilder
    private func accountPicker(selection: Binding<UUID?>) -> some View {
        Picker("sync.field.account", selection: selection) {
            Text("sync.account.placeholder").tag(UUID?.none)
            ForEach(accounts) { account in
                Label {
                    Text("\(account.name) (\(account.provider.displayName))")
                } icon: {
                    Image(systemName: account.provider.iconSystemName)
                }
                .tag(Optional(account.id))
            }
        }
    }

    // MARK: - Hydrate / commit

    private func hydrate() {
        guard !hasHydrated else { return }
        defer { hasHydrated = true }
        if case .edit(let job) = mode {
            name = job.name
            mode_ = job.mode
            sourceAccountID = job.source.accountID
            sourceBucket = job.source.bucket
            sourcePrefix = job.source.prefix
            destAccountID = job.destination.accountID
            destBucket = job.destination.bucket
            destPrefix = job.destination.prefix
            diffStrategy = job.diffStrategy
            includeGlobs = job.includeGlobs.joined(separator: ", ")
            excludeGlobs = job.excludeGlobs.joined(separator: ", ")
            deletePropagation = job.deletePropagation
            switch job.schedule {
            case .manual:
                scheduleKind = .manual
            case .onLaunch:
                scheduleKind = .onLaunch
            case .interval(let seconds):
                scheduleKind = .interval
                intervalMinutes = max(5, seconds / 60)
            }
            concurrency = job.concurrency
            enabled = job.enabled
        } else if let first = accounts.first {
            sourceAccountID = first.id
            destAccountID = first.id
        }
    }

    private func commit() {
        guard let sourceAccountID, let destAccountID else { return }
        saving = true
        let normalisedSourcePrefix = normalise(prefix: sourcePrefix)
        let normalisedDestPrefix = normalise(prefix: destPrefix)
        let job = SyncJob(
            id: { if case .edit(let j) = mode { return j.id }; return UUID() }(),
            name: name.trimmingCharacters(in: .whitespaces),
            mode: mode_,
            source: SyncEndpoint(
                accountID: sourceAccountID,
                bucket: sourceBucket.trimmingCharacters(in: .whitespaces),
                prefix: normalisedSourcePrefix
            ),
            destination: SyncEndpoint(
                accountID: destAccountID,
                bucket: destBucket.trimmingCharacters(in: .whitespaces),
                prefix: normalisedDestPrefix
            ),
            diffStrategy: diffStrategy,
            includeGlobs: splitGlobs(includeGlobs),
            excludeGlobs: splitGlobs(excludeGlobs),
            deletePropagation: deletePropagation,
            schedule: {
                switch scheduleKind {
                case .manual:   return .manual
                case .onLaunch: return .onLaunch
                case .interval: return .interval(seconds: intervalMinutes * 60)
                }
            }(),
            concurrency: concurrency,
            enabled: enabled
        )
        Task {
            await onSave(job)
            dismiss()
        }
    }

    private func splitGlobs(_ raw: String) -> [String] {
        raw
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalise(prefix: String) -> String {
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "" }
        return trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
    }
}
