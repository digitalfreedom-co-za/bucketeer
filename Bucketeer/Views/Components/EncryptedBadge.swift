//
//  EncryptedBadge.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 12.11.26.
//

import SwiftUI

/// Lock marking an encrypted bucket or upload. VoiceOver reads it once
/// as "Encrypted" instead of the symbol name; the tooltip says what the
/// encryption covers.
struct EncryptedBadge: View {
    let help: LocalizedStringKey

    var body: some View {
        Image(systemName: "lock.fill")
            .foregroundStyle(.accentInk)
            .accessibilityLabel(Text("encryption.badge.label"))
            .help(Text(help))
    }
}
