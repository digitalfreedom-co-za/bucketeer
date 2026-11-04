//
//  Broadcast.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation

/// Fans one producer out to any number of independent `AsyncStream`
/// subscribers. A plain `AsyncStream` hands each value to only one of
/// its iterators, so two consumers of the same stream would split the
/// values between them.
///
/// `.snapshots` subscribers receive the latest value right away and then
/// only the newest one (state streams); `.events` subscribers receive
/// every value published after they subscribed (completion events).
public final class Broadcast<Value: Sendable>: Sendable {
    public enum Delivery: Sendable {
        case snapshots
        case events
    }

    private struct State {
        var subscribers: [UUID: AsyncStream<Value>.Continuation] = [:]
        var latest: Value?
        var isFinished = false
    }

    private let delivery: Delivery
    private let state = NSLockedState(State())

    public init(delivery: Delivery) {
        self.delivery = delivery
    }

    public func subscribe() -> AsyncStream<Value> {
        let policy: AsyncStream<Value>.Continuation.BufferingPolicy =
            delivery == .snapshots ? .bufferingNewest(1) : .unbounded
        let (stream, continuation) = AsyncStream<Value>.makeStream(bufferingPolicy: policy)
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) }
        }
        // Yielding under the lock keeps the replay ahead of any value
        // published concurrently. (`finish` must stay outside: it runs
        // `onTermination`, which takes the lock.)
        let registered = state.withLock { state in
            guard !state.isFinished else { return false }
            state.subscribers[id] = continuation
            if delivery == .snapshots, let latest = state.latest { continuation.yield(latest) }
            return true
        }
        if !registered { continuation.finish() }
        return stream
    }

    public func publish(_ value: Value) {
        state.withLock { state in
            state.latest = value
            for subscriber in state.subscribers.values { subscriber.yield(value) }
        }
    }

    public func finish() {
        let subscribers = state.withLock { state in
            state.isFinished = true
            defer { state.subscribers.removeAll() }
            return Array(state.subscribers.values)
        }
        for subscriber in subscribers { subscriber.finish() }
    }
}

/// Minimal lock-protected box (Foundation's `NSLock` around a value).
final class NSLockedState<State>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: State

    init(_ value: State) {
        self.value = value
    }

    func withLock<T>(_ body: (inout State) -> T) -> T {
        lock.withLock { body(&value) }
    }
}
