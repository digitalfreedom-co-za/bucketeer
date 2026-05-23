//
//  QuickLookPreviewView.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import SwiftUI
import AppKit
import Quartz

/// SwiftUI wrapper around AppKit's `QLPreviewView`. Updates the preview
/// whenever the URL binding changes; tolerates `nil` by clearing the
/// view's contents.
struct QuickLookPreviewView: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)
            ?? QLPreviewView(frame: .zero)!
        view.autostarts = true
        view.shouldCloseWithWindow = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if let url {
            // Re-assigning the same item is cheap and the view rebuilds
            // its internal renderer when the underlying file changes
            // (e.g. user picks a new object in the list).
            nsView.previewItem = url as NSURL
        } else {
            nsView.previewItem = nil
        }
    }

    static func dismantleNSView(_ nsView: QLPreviewView, coordinator: ()) {
        nsView.close()
    }
}

/// Spacebar-driven full-window Quick Look panel. Owns a single shared
/// `QLPreviewPanel` data source and toggles it open/close on demand.
///
/// `QLPreviewPanelDataSource` is an `@objc` protocol with no actor
/// isolation. The panel only ever calls back on the main thread (it's
/// part of AppKit), so we mark the conformance methods `nonisolated`
/// and back the storage with `nonisolated(unsafe)` — accesses to
/// `current` go through `show` / `close`, both of which are called from
/// SwiftUI view code (i.e. the main actor) and from AppKit's main-loop
/// dispatch back into the data source.
@MainActor
final class QuickLookPanelController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookPanelController()

    nonisolated(unsafe) private var _current: URL?

    private override init() { super.init() }

    func show(url: URL) {
        _current = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        if panel.isVisible {
            panel.refreshCurrentPreviewItem()
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func close() {
        _current = nil
        guard let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        panel.orderOut(nil)
    }

    // MARK: - QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        _current == nil ? 0 : 1
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        _current as NSURL?
    }
}
