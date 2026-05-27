//
//  LocalFolderWatcher.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation
import CoreServices

/// Tracks filesystem changes underneath a local-folder sync endpoint
/// and yields a Date on every batch the system delivers. Used by
/// `SyncEngine` to drive Phase 9.10 sync-on-change schedules:
/// the engine subscribes to `events` and calls `runNow(id:)` on each
/// emission, debounced by the FSEventStream latency.
///
/// Implementation notes:
/// - Wraps the C-API `FSEventStream` with a Swift `@unchecked Sendable`
///   class. The FSEvents callback fires on a dispatch queue the watcher
///   creates; we forward through `AsyncStream.Continuation.yield`, which
///   is itself thread-safe.
/// - The caller starts and stops the watcher explicitly via `start()` /
///   `stop()`. Releasing the watcher without calling `stop()` is safe
///   — `deinit` cleans up — but the engine is explicit about lifecycle
///   so a renamed / deleted job stops watching immediately.
/// - Caller is responsible for security-scoped resource access on the
///   watched URL. The watcher itself doesn't read file contents; it
///   only registers a path with FSEvents, which works even without
///   live security-scope access. The engine's run path establishes the
///   scope before doing any I/O on triggered events.
public final class LocalFolderWatcher: @unchecked Sendable {
    /// Async stream of debounced change notifications. Each emission
    /// is a `Date` (the time the FSEvents callback fired) so consumers
    /// can additionally rate-limit at their layer if needed.
    public nonisolated let events: AsyncStream<Date>

    private let continuation: AsyncStream<Date>.Continuation
    private let rootURL: URL
    private let latencySeconds: Double
    private var stream: FSEventStreamRef?
    private let dispatchQueue: DispatchQueue

    public init(rootURL: URL, latencySeconds: Double = 3.0) {
        self.rootURL = rootURL
        self.latencySeconds = latencySeconds
        self.dispatchQueue = DispatchQueue(
            label: "co.za.digitalfreedom.bucketeer.localfolderwatcher.\(UUID().uuidString)",
            qos: .utility
        )
        let (stream, continuation) = AsyncStream<Date>.makeStream(
            bufferingPolicy: .bufferingNewest(8)
        )
        self.events = stream
        self.continuation = continuation
    }

    deinit {
        // The Sendable-violation-free way to clean up: stop is
        // idempotent and safe to call from deinit because the FSEvents
        // C API does its own thread-safety.
        if let stream = self.stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        continuation.finish()
    }

    /// Begin watching. Idempotent — calling `start()` on an already-
    /// running watcher is a no-op. Returns `false` when FSEvents
    /// refuses to create the stream (typically a permission / sandbox
    /// issue with the supplied URL).
    @discardableResult
    public func start() -> Bool {
        guard stream == nil else { return true }
        let pathsToWatch = [rootURL.path] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
            | kFSEventStreamCreateFlagWatchRoot
        )
        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<LocalFolderWatcher>
                    .fromOpaque(info)
                    .takeUnretainedValue()
                watcher.continuation.yield(Date())
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            CFTimeInterval(latencySeconds),
            flags
        ) else {
            return false
        }
        FSEventStreamSetDispatchQueue(newStream, dispatchQueue)
        guard FSEventStreamStart(newStream) else {
            FSEventStreamInvalidate(newStream)
            FSEventStreamRelease(newStream)
            return false
        }
        self.stream = newStream
        return true
    }

    /// Stop watching and close the event stream. Idempotent.
    public func stop() {
        guard let stream = self.stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
