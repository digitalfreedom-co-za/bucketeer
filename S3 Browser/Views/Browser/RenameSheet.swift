//
//  RenameSheet.swift
//  S3 Browser
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import SwiftUI

struct RenameSheet: View {
    let original: String
    let onRename: @MainActor (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var isRenaming: Bool = false

    private var isCommitDisabled: Bool {
        isRenaming
            || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || name.contains("/")
            || name == original
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("browser.action.rename.section") {
                    LabeledContent("browser.action.rename.current") {
                        Text(original).monospaced()
                    }
                    TextField("browser.action.rename.newName", text: $name)
                        .autocorrectionDisabled()
                    if name.contains("/") {
                        Label(
                            "browser.action.rename.noSlash",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                        .font(.caption)
                    }
                    Text("browser.action.rename.hint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("browser.action.rename.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                        .disabled(isRenaming)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") {
                        Task {
                            isRenaming = true
                            await onRename(name)
                            isRenaming = false
                            dismiss()
                        }
                    }
                    .disabled(isCommitDisabled)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .overlay {
                if isRenaming {
                    ProgressView()
                        .controlSize(.large)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .onAppear {
                name = original
            }
        }
        .frame(minWidth: 480, minHeight: 260)
    }
}
