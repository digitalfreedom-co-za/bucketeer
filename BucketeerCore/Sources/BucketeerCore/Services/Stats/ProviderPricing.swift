//
//  ProviderPricing.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import Foundation

/// Coarse monthly-storage pricing per provider in **USD per GB per
/// month** for the standard / hot tier. Phase 13.5.
///
/// Numbers are intentionally approximate — they're a "back of the
/// envelope" estimate to give the user a feel for monthly cost, not
/// a billing prediction. Regional variation, tier transitions,
/// request volume, and egress are all ignored. The dashboard
/// surfaces this caveat to the user verbatim so nobody mistakes it
/// for an invoice.
public enum ProviderPricing {

    /// USD per GB-month for the standard storage tier. `nil` means
    /// "self-hosted / unknown" — the dashboard hides the cost row
    /// in that case.
    public static func storagePerGBMonthUSD(for provider: S3Provider) -> Double? {
        switch provider {
        case .awsS3:             return 0.023
        case .azureBlob:         return 0.0184
        case .cloudflareR2:     return 0.015
        case .backblazeB2:      return 0.006
        case .wasabi:            return 0.00585
        case .digitalOceanSpaces: return 0.020
        case .civo:              return 0.005
        case .storj:             return 0.004
        case .custom:            return nil
        }
    }

    /// Estimate the monthly USD bill for `bytes` of stored data on
    /// the given provider. Returns `nil` when no pricing is on file.
    public static func estimateMonthlyUSD(bytes: Int64, provider: S3Provider) -> Double? {
        guard let rate = storagePerGBMonthUSD(for: provider) else { return nil }
        let gigabytes = Double(bytes) / (1024 * 1024 * 1024)
        return gigabytes * rate
    }
}
