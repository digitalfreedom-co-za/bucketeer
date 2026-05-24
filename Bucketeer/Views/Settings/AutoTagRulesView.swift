//
//  AutoTagRulesView.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import SwiftUI
import BucketeerCore

/// Settings pane that lets the user add / edit / delete auto-tagging
/// rules. Phase 13.8.
struct AutoTagRulesView: View {
    @Environment(AppContainer.self) private var container
    @State private var editingRule: AutoTagRule?
    @State private var creatingNewRule: Bool = false
    @State private var pendingDeletion: AutoTagRule?

    var body: some View {
        let viewModel = container.autoTagRulesViewModel
        VStack(spacing: 0) {
            if viewModel.rules.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(viewModel.rules) { rule in
                        rulesRow(rule)
                            .contextMenu {
                                Button("action.edit", systemImage: "pencil") {
                                    editingRule = rule
                                }
                                Button("action.delete", systemImage: "trash", role: .destructive) {
                                    pendingDeletion = rule
                                }
                            }
                    }
                }
            }
            Divider()
            HStack {
                Button {
                    creatingNewRule = true
                } label: {
                    Label("autoTag.action.new", systemImage: "plus")
                }
                Spacer()
                if let error = viewModel.error {
                    Label(error.errorDescription ?? "\(error)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .padding(8)
        }
        .frame(minWidth: 420, minHeight: 320)
        .task { await viewModel.reload() }
        .sheet(isPresented: $creatingNewRule) {
            AutoTagRuleEditor(
                rule: AutoTagRule(name: String(
                    localized: "autoTag.defaultName",
                    defaultValue: "New rule"
                )),
                onSave: { rule in
                    await viewModel.save(rule)
                }
            )
        }
        .sheet(item: $editingRule) { rule in
            AutoTagRuleEditor(
                rule: rule,
                onSave: { updated in
                    await viewModel.save(updated)
                }
            )
        }
        .confirmationDialog(
            "autoTag.delete.confirm.title",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { rule in
            Button("action.delete", role: .destructive) {
                Task { await container.autoTagRulesViewModel.delete(rule) }
                pendingDeletion = nil
            }
            Button("common.cancel", role: .cancel) { pendingDeletion = nil }
        } message: { rule in
            Text(rule.name)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("autoTag.empty.title", systemImage: "tag")
        } description: {
            Text("autoTag.empty.message")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rulesRow(_ rule: AutoTagRule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: rule.enabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(rule.enabled ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name).font(.callout.weight(.medium))
                HStack(spacing: 8) {
                    if !rule.filenameGlob.isEmpty {
                        Label(rule.filenameGlob, systemImage: "doc.text")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !rule.mimePrefix.isEmpty {
                        Label(rule.mimePrefix, systemImage: "tag")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    let summary = "\(rule.tags.count) tags / \(rule.userMetadata.count) metadata"
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

/// Modal editor for a single rule. Reuses the dict-editor pattern
/// from `ObjectMetadataSheet` for the tags + metadata maps.
private struct AutoTagRuleEditor: View {
    @State var rule: AutoTagRule
    let onSave: @Sendable (AutoTagRule) async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var newTagKey: String = ""
    @State private var newTagValue: String = ""
    @State private var newMetaKey: String = ""
    @State private var newMetaValue: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("autoTag.section.identity") {
                    TextField("autoTag.field.name", text: $rule.name)
                    Toggle("autoTag.field.enabled", isOn: $rule.enabled)
                }
                Section("autoTag.section.match") {
                    TextField("autoTag.field.glob", text: $rule.filenameGlob)
                    Text("autoTag.glob.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("autoTag.field.mime", text: $rule.mimePrefix)
                    Text("autoTag.mime.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("autoTag.section.tags") {
                    ForEach(rule.tags.keys.sorted(), id: \.self) { key in
                        keyValueRow(
                            key: key,
                            value: Binding(
                                get: { rule.tags[key] ?? "" },
                                set: { rule.tags[key] = $0 }
                            ),
                            remove: { rule.tags.removeValue(forKey: key) }
                        )
                    }
                    addRow(
                        keyField: $newTagKey,
                        valueField: $newTagValue,
                        canAdd: !newTagKey.isEmpty && rule.tags.count < 10
                    ) {
                        rule.tags[newTagKey] = newTagValue
                        newTagKey = ""
                        newTagValue = ""
                    }
                }
                Section("autoTag.section.metadata") {
                    ForEach(rule.userMetadata.keys.sorted(), id: \.self) { key in
                        keyValueRow(
                            key: key,
                            value: Binding(
                                get: { rule.userMetadata[key] ?? "" },
                                set: { rule.userMetadata[key] = $0 }
                            ),
                            remove: { rule.userMetadata.removeValue(forKey: key) }
                        )
                    }
                    addRow(
                        keyField: $newMetaKey,
                        valueField: $newMetaValue,
                        canAdd: !newMetaKey.isEmpty
                    ) {
                        rule.userMetadata[newMetaKey] = newMetaValue
                        newMetaKey = ""
                        newMetaValue = ""
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("autoTag.editor.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") {
                        Task { await onSave(rule); dismiss() }
                    }
                    .disabled(rule.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 540)
    }

    private func keyValueRow(
        key: String,
        value: Binding<String>,
        remove: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(key).font(.callout.monospaced())
            Spacer()
            TextField("autoTag.field.value", text: value).frame(maxWidth: 220)
            Button(role: .destructive, action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private func addRow(
        keyField: Binding<String>,
        valueField: Binding<String>,
        canAdd: Bool,
        add: @escaping () -> Void
    ) -> some View {
        HStack {
            TextField("autoTag.field.key", text: keyField)
                .textFieldStyle(.roundedBorder)
            TextField("autoTag.field.value", text: valueField)
                .textFieldStyle(.roundedBorder)
            Button(action: add) {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.borderless)
            .disabled(!canAdd)
        }
    }
}
