//
//  FilePickers.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import AppKit
import Foundation

/// Wrappers around NSOpenPanel / NSSavePanel that return async/await
/// results. Both panels work in the App Sandbox via the user-selected
/// files entitlement — no extra plumbing required.
enum FilePickers {

    @MainActor
    static func pickFiles(
        title: String? = nil,
        allowsMultipleSelection: Bool = true
    ) async -> [URL] {
        let panel = NSOpenPanel()
        if let title { panel.title = title }
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        let response = await withCheckedContinuation { continuation in
            panel.begin { result in
                continuation.resume(returning: result)
            }
        }
        return response == .OK ? panel.urls : []
    }

    @MainActor
    static func pickSaveLocation(
        suggestedName: String,
        contentType: UTType? = nil
    ) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        if let contentType { panel.allowedContentTypes = [contentType] }
        let response = await withCheckedContinuation { continuation in
            panel.begin { result in
                continuation.resume(returning: result)
            }
        }
        return response == .OK ? panel.url : nil
    }
}

import UniformTypeIdentifiers
