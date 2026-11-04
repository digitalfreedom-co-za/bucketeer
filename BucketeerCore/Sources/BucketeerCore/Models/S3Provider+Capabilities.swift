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
        /// `x-amz-copy-source-if-match` on UploadPartCopy.
        public static let partCopySourceIfMatch = ConditionalRequests(rawValue: 1 << 6)
        /// `If-Match` on a ranged GetObject.
        public static let readIfMatch = ConditionalRequests(rawValue: 1 << 7)

        public static let all: ConditionalRequests = [
            .writeIfMatch, .writeIfAbsent, .completionConditions, .deleteIfMatch, .copySourceIfMatch, .copyIfAbsent,
            .partCopySourceIfMatch, .readIfMatch
        ]
    }

    public var conditionalRequests: ConditionalRequests {
        switch self {
        case .awsS3, .azureBlob:
            return .all
        case .cloudflareR2:
            return [.writeIfMatch, .writeIfAbsent, .copySourceIfMatch, .readIfMatch]
        case .digitalOceanSpaces:
            return [.copySourceIfMatch, .partCopySourceIfMatch, .readIfMatch]
        // Civo (live): PUT If-Match is refused even when it holds, the
        // other write conditions ignored; ranged GET If-Match holds.
        case .civo:
            return [.readIfMatch]
        // B2, Wasabi, Storj: not documented. Custom: unknown.
        case .backblazeB2, .wasabi, .storj, .custom:
            return []
        }
    }

    /// False where UploadPartCopy is not generally available: Storj
    /// enables it only on request.
    public var supportsUploadPartCopy: Bool {
        self != .storj
    }

    /// False where object tagging is documented as missing: R2 does not
    /// implement it, B2 rejects tags. Tags are then neither read nor
    /// written, so metadata editing still works.
    public var supportsObjectTagging: Bool {
        self != .cloudflareR2 && self != .backblazeB2
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
