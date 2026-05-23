//
//  TransferTask.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation

public enum TransferDirection: String, Codable, Hashable, Sendable {
    case upload
    case download
}

public enum TransferState: Hashable, Sendable {
    case queued
    case running(bytesTransferred: Int64, totalBytes: Int64)
    case completed
    case failed(message: String)
    case cancelled

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        case .queued, .running:               return false
        }
    }

    public var progressFraction: Double? {
        if case let .running(transferred, total) = self, total > 0 {
            return Double(transferred) / Double(total)
        }
        return nil
    }
}

public struct TransferTask: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let direction: TransferDirection
    public let accountID: UUID
    public let bucket: String
    public let key: String
    public let localURL: URL
    public var state: TransferState
    public let startedAt: Date

    public init(
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
