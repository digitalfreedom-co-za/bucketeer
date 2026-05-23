//
//  S3Provider.swift
//  S3 Browser
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation

/// One of the recognised S3-compatible providers. Defines the endpoint
/// template, default region behaviour, and addressing-style default. Per-
/// account overrides live on `S3Account`.
enum S3Provider: String, Codable, CaseIterable, Sendable {
    case awsS3
    case civo
    case cloudflareR2
    case backblazeB2
    case wasabi
    case digitalOceanSpaces
    case storj
    case custom

    var displayName: String {
        switch self {
        case .awsS3:             return "AWS S3"
        case .civo:              return "Civo Object Storage"
        case .cloudflareR2:      return "Cloudflare R2"
        case .backblazeB2:       return "Backblaze B2"
        case .wasabi:            return "Wasabi"
        case .digitalOceanSpaces: return "DigitalOcean Spaces"
        case .storj:             return "Storj"
        case .custom:            return "Custom Endpoint"
        }
    }

    var iconSystemName: String {
        switch self {
        case .awsS3:             return "shippingbox.fill"
        case .civo:              return "cube.fill"
        case .cloudflareR2:      return "bolt.horizontal.fill"
        case .backblazeB2:       return "flame.fill"
        case .wasabi:            return "leaf.fill"
        case .digitalOceanSpaces: return "drop.fill"
        case .storj:             return "asterisk.circle.fill"
        case .custom:            return "wrench.adjustable.fill"
        }
    }

    /// The default region offered when a user picks this provider in the
    /// new-account flow. Free-form for `.custom`; opinionated otherwise.
    var defaultRegion: String {
        switch self {
        case .awsS3:             return "us-east-1"
        case .civo:              return "fra1"
        case .cloudflareR2:      return "auto"
        case .backblazeB2:       return "us-west-002"
        case .wasabi:            return "eu-central-1"
        case .digitalOceanSpaces: return "fra1"
        case .storj:             return "global"
        case .custom:            return ""
        }
    }

    /// Concrete region picker offered in the UI for providers with a fixed
    /// region list. `nil` means free text input (only `.custom`).
    var fixedRegions: [String]? {
        switch self {
        case .awsS3: return [
            // North America
            "us-east-1", "us-east-2", "us-west-1", "us-west-2",
            "ca-central-1", "ca-west-1",
            // South America
            "sa-east-1",
            // Europe
            "eu-central-1", "eu-central-2",
            "eu-west-1", "eu-west-2", "eu-west-3",
            "eu-north-1", "eu-south-1", "eu-south-2",
            // Middle East / Africa
            "af-south-1", "il-central-1", "me-central-1", "me-south-1",
            // Asia Pacific
            "ap-east-1",
            "ap-south-1", "ap-south-2",
            "ap-northeast-1", "ap-northeast-2", "ap-northeast-3",
            "ap-southeast-1", "ap-southeast-2", "ap-southeast-3",
            "ap-southeast-4", "ap-southeast-5", "ap-southeast-7",
            // Independent regions (different partitions still reach via
            // standard S3 — listed here for completeness)
            "cn-north-1", "cn-northwest-1",
            "us-gov-east-1", "us-gov-west-1"
        ]
        case .civo:               return ["fra1", "lon1", "nyc1", "phx1"]
        case .cloudflareR2:       return ["auto", "wnam", "enam", "weur", "eeur", "apac", "oc"]
        case .backblazeB2:        return ["us-west-001", "us-west-002", "us-west-004", "eu-central-003"]
        case .wasabi:             return ["us-east-1", "us-east-2", "us-central-1", "us-west-1",
                                          "eu-central-1", "eu-central-2", "eu-west-1", "eu-west-2",
                                          "ap-northeast-1", "ap-northeast-2", "ap-southeast-1",
                                          "ap-southeast-2", "ca-central-1"]
        case .digitalOceanSpaces: return ["nyc3", "sfo2", "sfo3", "ams3", "sgp1", "fra1", "syd1", "blr1", "tor1"]
        case .storj:              return ["global"]
        case .custom:             return nil
        }
    }

    /// Default addressing style. Most modern providers serve virtual-host
    /// requests; Storj's S3 gateway and MinIO need path-style.
    var usesPathStyleByDefault: Bool {
        switch self {
        case .storj, .custom: return true
        default:              return false
        }
    }

    /// True when the provider needs an extra account-identifier field
    /// (Cloudflare R2 hostname includes the account ID).
    var requiresAccountID: Bool {
        self == .cloudflareR2
    }

    /// True when the provider needs the user to enter the full endpoint
    /// URL themselves (no preset hostname).
    var requiresEndpointOverride: Bool {
        self == .custom
    }

    /// AWS routes virtual-host vs path-style by URL pattern, so the
    /// account-level path-style toggle has no effect for `.awsS3` and
    /// is hidden in the UI to avoid misleading users.
    var supportsPathStyleToggle: Bool {
        self != .awsS3
    }
}
