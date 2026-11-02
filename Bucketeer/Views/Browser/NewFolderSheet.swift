//
//  NewFolderSheet.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import SwiftUI

struct NewFolderSheet: View {
    let onCreate: @MainActor (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var folderName: String = ""
    @State private var isCreating: Bool = false

    private var isCommitDisabled: Bool {
        isCreating
            || folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || folderName.contains("/")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("browser.action.newFolder.section") {
                    TextField(
                        "browser.action.newFolder.placeholder",
                        text: $folderName
                    )
                    .autocorrectionDisabled()
                    if folderName.contains("/") {
                        Label(
                            "browser.action.newFolder.noSlash",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                        .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("browser.action.newFolder.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("browser.action.newFolder.create") {
                        Task {
                            isCreating = true
                            await onCreate(folderName)
                            isCreating = false
                            dismiss()
                        }
                    }
                    .disabled(isCommitDisabled)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .overlay {
                if isCreating {
                    ProgressView()
                        .controlSize(.large)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .frame(minWidth: 420, minHeight: 220)
    }
}
