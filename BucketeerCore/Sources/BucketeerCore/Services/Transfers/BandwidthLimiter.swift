//
//  BandwidthLimiter.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation

/// Token-bucket rate limiter shared by `TransferManager` and
/// `AzureBlobTransporter`. Phase 13.2.
///
/// API contract:
///
/// - `setLimit(bytesPerSecond:)` of `0` means **unlimited** — every
///   `consume(bytes:)` returns immediately. Otherwise the bucket
///   refills at `bytesPerSecond` and burst-caps at `bytesPerSecond`,
///   so a request bigger than the burst still completes but takes
///   `bytes / bytesPerSecond` seconds.
///
/// - `consume(bytes:)` is "post-charge": call it once the bytes are
///   actually on the wire (or about to be queued) so the bucket
///   reflects real traffic. Sleeping inside the callback then
///   back-pressures the next chunk.
///
/// - The actor is `Sendable` and safe to share across upload /
///   download paths. Concurrent transfers serialise on the bucket and
///   collectively never exceed the limit.
///
/// Honesty about scope: this limiter regulates wire-level throughput
/// precisely for the Azure block-blob path (we own every chunk read /
/// write), and best-effort for the Soto S3 path — Soto's
/// `multipartUpload` / `multipartDownload` only surface fractional
/// progress callbacks, so we can charge the bucket per progress tick
/// but cannot delay parts already in flight.
public actor BandwidthLimiter {
    private var bytesPerSecond: Int = 0
    private var tokens: Double = 0
    private var lastRefill: Date = .now

    public init(bytesPerSecond: Int = 0) {
        let normalised = max(0, bytesPerSecond)
        self.bytesPerSecond = normalised
        self.tokens = Double(normalised)
        self.lastRefill = .now
    }

    /// Update the cap. Passing `0` (or a negative) disables the
    /// limiter and clears the bucket.
    public func setLimit(bytesPerSecond: Int) {
        let normalised = max(0, bytesPerSecond)
        self.bytesPerSecond = normalised
        self.tokens = Double(normalised)
        self.lastRefill = .now
    }

    public var currentLimit: Int { bytesPerSecond }

    /// Charge the bucket for `bytes`. Returns immediately when the
    /// limiter is disabled. Otherwise sleeps until the token bucket
    /// has enough capacity to cover all the requested bytes, draining
    /// available tokens on each iteration so large requests (bigger
    /// than the bucket capacity) converge correctly.
    public func consume(bytes: Int) async {
        guard bytesPerSecond > 0, bytes > 0 else { return }
        var remaining = Double(bytes)
        while remaining > 0 {
            refill()
            if tokens >= remaining {
                tokens -= remaining
                return
            }
            // Drain whatever tokens are available, then sleep for one
            // refill period so the bucket tops back up to capacity.
            remaining -= tokens
            tokens = 0
            let sleepSeconds = min(remaining / Double(bytesPerSecond), 1.0)
            try? await Task.sleep(nanoseconds: UInt64(max(0.001, sleepSeconds) * 1_000_000_000))
        }
    }

    // MARK: - Private

    private func refill() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRefill)
        let capacity = Double(bytesPerSecond)
        tokens = min(capacity, tokens + elapsed * Double(bytesPerSecond))
        lastRefill = now
    }
}
