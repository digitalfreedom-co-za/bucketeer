//
//  S3Provider+Capabilities.swift
//  BucketeerCore
//
//  Created by Marcel R. G. Berger on 04.11.26.
//

import Foundation

extension S3Provider {

    /// The conditional request headers a provider enforces, according
    /// to its documentation or a live test (see the provider audit). A
    /// condition outside this set is never sent: the app compares the
    /// object with a HEAD right before the request instead
    /// (`PreconditionCheck`). That leaves a short window in which
    /// another writer can still slip in, but no header the provider
    /// ignores — or refuses although it holds — is relied on.
    public struct ConditionalRequests: OptionSet, Sendable, Hashable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// `If-Match` on PutObject.
        public static let writeIfMatch = ConditionalRequests(rawValue: 1 << 0)
        /// `If-None-Match: *` on PutObject.
        public static let writeIfAbsent = ConditionalRequests(rawValue: 1 << 1)
        /// The write conditions above also hold on CompleteMultipartUpload.
        public static let completionConditions = ConditionalRequests(rawValue: 1 << 5)
        /// `If-Match` on DeleteObject.
        public static let deleteIfMatch = ConditionalRequests(rawValue: 1 << 2)
        /// `x-amz-copy-source-if-match` on CopyObject.
        public static let copySourceIfMatch = ConditionalRequests(rawValue: 1 << 3)
        /// `If-None-Match: *` on CopyObject.
        public static let copyIfAbsent = ConditionalRequests(rawValue: 1 << 4)

        public static let all: ConditionalRequests = [
            .writeIfMatch, .writeIfAbsent, .completionConditions, .deleteIfMatch, .copySourceIfMatch, .copyIfAbsent
        ]
    }

    public var conditionalRequests: ConditionalRequests {
        switch self {
        case .awsS3, .azureBlob:
            return .all
        case .cloudflareR2:
            return [.writeIfMatch, .writeIfAbsent, .copySourceIfMatch]
        case .digitalOceanSpaces:
            return [.copySourceIfMatch]
        // Civo (live): If-Match is refused even when it holds, the rest
        // ignored. B2, Wasabi, Storj: not documented. Custom: unknown.
        case .civo, .backblazeB2, .wasabi, .storj, .custom:
            return []
        }
    }

    /// The SigV4 region for requests. R2 accepts only `auto`; earlier
    /// builds offered its location hints as regions.
    public func signingRegion(for region: String) -> String {
        self == .cloudflareR2 ? "auto" : region
    }
}

/// The app-side stand-in for a condition the provider does not enforce.
public enum PreconditionCheck {

    /// Throws `.preconditionFailed` unless `precondition` holds for the
    /// object's current ETag (`nil` when there is no object).
    public static func verify(_ precondition: WritePrecondition, current: String?, key: String) throws {
        let holds: Bool
        switch precondition {
        case .ifMatch(let base): holds = ETag.matches(base: base, current: current)
        case .ifAbsent: holds = current == nil
        }
        guard holds else { throw BucketeerError.preconditionFailed(key: key) }
    }
}
