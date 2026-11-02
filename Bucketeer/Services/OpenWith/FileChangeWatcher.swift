//
//  FileChangeWatcher.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import Foundation

/// Reports writes to one file. Watches the file itself (in-place
/// writes) and its folder (atomic saves, which replace the file and
/// would leave a file-only watcher on the old, deleted inode). Each
/// opened file lives in its own folder, so folder events always mean
/// this file.
@MainActor
final class FileChangeWatcher {
    private let fileURL: URL
    private let onChange: @MainActor () -> Void
    private var fileSource: DispatchSourceFileSystemObject?
    private var folderSource: DispatchSourceFileSystemObject?

    init(fileURL: URL, onChange: @escaping @MainActor () -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
    }

    func start() {
        folderSource = makeSource(
            path: fileURL.deletingLastPathComponent().path,
            events: .write
        ) { [weak self] in
            self?.armFileSource()
            self?.onChange()
        }
        armFileSource()
    }

    func stop() {
        fileSource?.cancel()
        fileSource = nil
        folderSource?.cancel()
        folderSource = nil
    }

    /// Re-armed after every folder event: an atomic save swaps the
    /// inode, so the old source would never fire again.
    private func armFileSource() {
        fileSource?.cancel()
        fileSource = makeSource(path: fileURL.path, events: [.write, .extend]) { [weak self] in
            self?.onChange()
        }
    }

    private func makeSource(
        path: String,
        events: DispatchSource.FileSystemEvent,
        handler: @escaping @MainActor () -> Void
    ) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: events,
            queue: .main
        )
        source.setEventHandler {
            MainActor.assumeIsolated { handler() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }
}
