//
//  ErrorBanner.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 02.11.26.
//

import SwiftUI
import BucketeerCore

/// Inline, non-modal display of a view model's last error. Renders
/// nothing when there is no error.
struct ErrorBanner: View {
    let error: BucketeerError?

    var body: some View {
        if let error {
            Label(error.errorDescription ?? "\(error)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
    }
}
