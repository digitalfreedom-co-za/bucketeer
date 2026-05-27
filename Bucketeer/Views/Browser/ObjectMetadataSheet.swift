//
//  ObjectMetadataSheet.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import SwiftUI
import BucketeerCore

/// Inspector-style sheet for editing the HTTP headers, user
/// metadata, and object tags of a single object. Phase 13.7.
struct ObjectMetadataSheet: View {
    @State private var viewModel: ObjectMetadataViewModel
    @State private var newMetadataKey: String = ""
    @State private var newMetadataValue: String = ""
    @State private var newTagKey: String = ""
    @State private var newTagValue: String = ""
    @Environment(\.dismiss) private var dismiss

    init(viewModel: ObjectMetadataViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var vm = viewModel
        return NavigationStack {
            Group {
                if let error = viewModel.error,
                   case .featureNotSupported = error {
                    notSupportedState(error)
                } else if let error = viewModel.error,
                          viewModel.original == ObjectMetadata() {
                    errorState(error)
                } else if viewModel.isLoading && viewModel.original == ObjectMetadata() {
                    ProgressView().controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Form {
                        httpSection(vm: $vm)
                        userMetadataSection(vm: $vm)
                        tagsSection(vm: $vm)
                        if let storageClass = viewModel.metadata.storageClass {
                            Section("metadata.section.storageClass") {
                                LabeledContent("metadata.storageClass.label") {
                                    Text(storageClass).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let error = viewModel.error {
                            Section {
                                Label(error.errorDescription ?? "\(error)",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            .navigationTitle(Text(viewModel.key))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") {
                        Task {
                            await viewModel.save()
                            if viewModel.didSaveSuccessfully { dismiss() }
                        }
                    }
                    .disabled(!viewModel.hasChanges || viewModel.isSaving)
                }
            }
            .task { await viewModel.reload() }
        }
        .frame(minWidth: 640, minHeight: 580)
    }

    // MARK: - Sections

    @ViewBuilder
    private func httpSection(vm: Bindable<ObjectMetadataViewModel>) -> some View {
        Section("metadata.section.http") {
            TextField("metadata.field.contentType", text: vm.metadata.contentType)
            TextField("metadata.field.cacheControl", text: vm.metadata.cacheControl)
            TextField("metadata.field.contentDisposition", text: vm.metadata.contentDisposition)
            TextField("metadata.field.contentEncoding", text: vm.metadata.contentEncoding)
        }
    }

    @ViewBuilder
    private func userMetadataSection(vm: Bindable<ObjectMetadataViewModel>) -> some View {
        Section("metadata.section.userMetadata") {
            ForEach(viewModel.metadata.userMetadata.keys.sorted(), id: \.self) { key in
                HStack {
                    Text(key).font(.callout.monospaced())
                    Spacer()
                    TextField(
                        "metadata.field.value",
                        text: Binding(
                            get: { viewModel.metadata.userMetadata[key] ?? "" },
                            set: { viewModel.metadata.userMetadata[key] = $0 }
                        )
                    )
                    .frame(maxWidth: 220)
                    Button(role: .destructive) {
                        viewModel.metadata.userMetadata.removeValue(forKey: key)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("metadata.field.key", text: $newMetadataKey)
                    .textFieldStyle(.roundedBorder)
                TextField("metadata.field.value", text: $newMetadataValue)
                    .textFieldStyle(.roundedBorder)
                Button {
                    addUserMetadata()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(!isValidMetadataKey(newMetadataKey))
            }
            Text("metadata.userMetadata.hint")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func tagsSection(vm: Bindable<ObjectMetadataViewModel>) -> some View {
        Section("metadata.section.tags") {
            ForEach(viewModel.metadata.tags.keys.sorted(), id: \.self) { key in
                HStack {
                    Text(key).font(.callout.weight(.medium))
                    Spacer()
                    TextField(
                        "metadata.field.value",
                        text: Binding(
                            get: { viewModel.metadata.tags[key] ?? "" },
                            set: { viewModel.metadata.tags[key] = $0 }
                        )
                    )
                    .frame(maxWidth: 220)
                    Button(role: .destructive) {
                        viewModel.metadata.tags.removeValue(forKey: key)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("metadata.field.key", text: $newTagKey)
                    .textFieldStyle(.roundedBorder)
                TextField("metadata.field.value", text: $newTagValue)
                    .textFieldStyle(.roundedBorder)
                Button {
                    addTag()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(newTagKey.isEmpty || viewModel.metadata.tags.count >= 10)
            }
            Text("metadata.tags.hint")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func notSupportedState(_ error: BucketeerError) -> some View {
        ContentUnavailableView {
            Label("metadata.notSupported.title", systemImage: "info.circle")
        } description: {
            Text(error.errorDescription ?? "")
        }
    }

    private func errorState(_ error: BucketeerError) -> some View {
        ContentUnavailableView {
            Label("metadata.error.title", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.errorDescription ?? "\(error)")
        }
    }

    // MARK: - Actions

    private func addUserMetadata() {
        guard isValidMetadataKey(newMetadataKey) else { return }
        viewModel.metadata.userMetadata[newMetadataKey] = newMetadataValue
        newMetadataKey = ""
        newMetadataValue = ""
    }

    private func addTag() {
        guard !newTagKey.isEmpty, viewModel.metadata.tags.count < 10 else { return }
        viewModel.metadata.tags[newTagKey] = newTagValue
        newTagKey = ""
        newTagValue = ""
    }

    /// S3 lowercases user-metadata keys and the keys must be a valid
    /// HTTP header name; restricting to ASCII letters, digits, and
    /// dashes covers the common case while keeping the editor strict.
    private func isValidMetadataKey(_ key: String) -> Bool {
        guard !key.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        return key.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
