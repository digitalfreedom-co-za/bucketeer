//
//  TransferTask.swift
//  S3 Browser
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation

enum TransferDirection: String, Codable, Hashable, Sendable {
    case upload
    case download
}

enum TransferState: Hashable, Sendable {
    case queued
    case running(bytesTransferred: Int64, totalBytes: Int64)
    case completed
    case failed(message: String)
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        case .queued, .running:               return false
        }
    }

    var progressFraction: Double? {
        if case let .running(transferred, total) = self, total > 0 {
            return Double(transferred) / Double(total)
        }
        return nil
    }
}

struct TransferTask: Identifiable, Hashable, Sendable {
    let id: UUID
    let direction: TransferDirection
    let accountID: UUID
    let bucket: String
    let key: String
    let localURL: URL
    var state: TransferState
    let startedAt: Date

    init(
        id: UUID = UUID(),
        direction: TransferDirection,
        accountID: UUID,
        bucket: String,
        key: String,
        localURL: URL,
        state: TransferState = .queued,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.direction = direction
        self.accountID = accountID
        self.bucket = bucket
        self.key = key
        self.localURL = localURL
        self.state = state
        self.startedAt = startedAt
    }
}
