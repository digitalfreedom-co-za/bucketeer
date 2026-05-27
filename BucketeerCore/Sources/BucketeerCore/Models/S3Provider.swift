//
//  S3Provider.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import Foundation

/// One of the recognised S3-compatible providers. Defines the endpoint
/// template, default region behaviour, and addressing-style default. Per-
/// account overrides live on `S3Account`.
public enum S3Provider: String, Codable, CaseIterable, Sendable {
    case awsS3
    case civo
    case cloudflareR2
    case backblazeB2
    case wasabi
    case digitalOceanSpaces
    case storj
    case azureBlob
    case custom

    /// Native protocol family. Drives router dispatch in `ProviderRouter`
    /// and `TransferManager` so the S3 and Azure code paths stay isolated
    /// from each other.
    public enum Family: Sendable {
        case s3
        case azureBlob
    }

    public var family: Family {
        switch self {
        case .azureBlob: return .azureBlob
        default:         return .s3
        }
    }

    public var displayName: String {
        switch self {
        case .awsS3:             return "AWS S3"
        case .civo:              return "Civo Object Storage"
        case .cloudflareR2:      return "Cloudflare R2"
        case .backblazeB2:       return "Backblaze B2"
        case .wasabi:            return "Wasabi"
        case .digitalOceanSpaces: return "DigitalOcean Spaces"
        case .storj:             return "Storj"
        case .azureBlob:         return "Azure Blob Storage"
        case .custom:            return "Custom Endpoint"
        }
    }

    public var iconSystemName: String {
        switch self {
        case .awsS3:             return "shippingbox.fill"
        case .civo:              return "cube.fill"
        case .cloudflareR2:      return "bolt.horizontal.fill"
        case .backblazeB2:       return "flame.fill"
        case .wasabi:            return "leaf.fill"
        case .digitalOceanSpaces: return "drop.fill"
        case .storj:             return "asterisk.circle.fill"
        case .azureBlob:         return "cloud.fill"
        case .custom:            return "wrench.adjustable.fill"
        }
    }

    /// The default region offered when a user picks this provider in the
    /// new-account flow. Free-form for `.custom`; opinionated otherwise.
    public var defaultRegion: String {
        switch self {
        case .awsS3:             return "us-east-1"
        case .civo:              return "fra1"
        case .cloudflareR2:      return "auto"
        case .backblazeB2:       return "us-west-002"
        case .wasabi:            return "eu-central-1"
        case .digitalOceanSpaces: return "fra1"
        case .storj:             return "global"
        case .azureBlob:         return "auto"
        case .custom:            return ""
        }
    }

    /// Concrete region picker offered in the UI for providers with a fixed
    /// region list. `nil` means free text input (only `.custom`).
    public var fixedRegions: [String]? {
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
        case .azureBlob:          return ["auto"]
        case .custom:             return nil
        }
    }

    /// Default addressing style. AWS and most "AWS-style" hyperscalers
    /// serve virtual-host requests; Civo, Storj's S3 gateway, MinIO and
    /// generic custom endpoints typically need path-style (their TLS
    /// certs do not cover bucket-as-subdomain hostnames). Azure has no
    /// path/virtual concept — the toggle is hidden for it entirely.
    public var usesPathStyleByDefault: Bool {
        switch self {
        case .civo, .storj, .custom: return true
        default:                     return false
        }
    }

    /// True when the provider needs an extra account-identifier field
    /// (Cloudflare R2 hostname includes the account ID; Azure uses the
    /// storage-account name as the URL prefix).
    public var requiresAccountID: Bool {
        self == .cloudflareR2 || self == .azureBlob
    }

    /// True when the provider needs the user to enter the full endpoint
    /// URL themselves (no preset hostname).
    public var requiresEndpointOverride: Bool {
        self == .custom
    }

    /// True when the provider can take an *optional* endpoint override —
    /// e.g. Azure sovereign clouds (`*.blob.core.usgovcloudapi.net`,
    /// `*.blob.core.chinacloudapi.cn`). Combined with `requiresAccountID`
    /// so the field defaults to `https://{accountID}.blob.core.windows.net`
    /// when blank.
    public var supportsOptionalEndpointOverride: Bool {
        self == .azureBlob
    }

    /// AWS routes virtual-host vs path-style by URL pattern, so the
    /// account-level path-style toggle has no effect for `.awsS3` and
    /// is hidden in the UI to avoid misleading users. Azure has no
    /// path-style concept — also hidden.
    public var supportsPathStyleToggle: Bool {
        self != .awsS3 && self != .azureBlob
    }

    /// Hidden region picker — Azure derives region from the storage
    /// account itself, so a separate region field would mislead users.
    public var hidesRegionPicker: Bool {
        self == .azureBlob
    }

    /// True when the access-key field in the credentials section is
    /// hidden. For Azure the storage-account name already lives in the
    /// `accountID` field — the credentials section then only shows the
    /// secret. On save the persistence layer mirrors `accountID` into
    /// `AccountCredentials.accessKey` so the signer has both pieces
    /// available from the Keychain alone.
    public var hidesAccessKeyField: Bool {
        self == .azureBlob
    }

    // MARK: - Localised terminology

    /// String-catalog key for the sidebar / list section header. Azure
    /// terminology is "container", every S3-compatible provider uses
    /// "bucket".
    public var bucketTerminologyKey: String {
        switch family {
        case .azureBlob: return "term.container"
        case .s3:        return "term.bucket"
        }
    }

    /// String-catalog key for the accountID field label. Cloudflare R2
    /// uses "Cloudflare account ID"; Azure uses "Storage account name".
    public var accountIDFieldLabelKey: String {
        switch self {
        case .azureBlob:    return "account.field.azure.accountName"
        case .cloudflareR2: return "account.field.r2.accountID"
        default:            return "account.field.accountID"
        }
    }

    /// String-catalog key for the secret-key field label.
    public var secretKeyFieldLabelKey: String {
        switch family {
        case .azureBlob: return "account.field.azure.accountKey"
        case .s3:        return "account.field.secretKey"
        }
    }

    /// String-catalog key for the placeholder shown in the optional
    /// endpoint-override field (Azure sovereign clouds).
    public var endpointPlaceholderKey: String {
        switch self {
        case .azureBlob: return "account.field.azure.endpoint.placeholder"
        default:         return "account.field.endpoint"
        }
    }
}
