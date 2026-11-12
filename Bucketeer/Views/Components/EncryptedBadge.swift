//
//  EncryptedBadge.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 12.11.26.
//

import SwiftUI
import BucketeerCore

/// Lock marking an encrypted bucket or upload. VoiceOver reads it once
/// as "Encrypted" instead of the symbol name; the tooltip says what the
/// encryption covers.
struct EncryptedBadge: View {
    let help: LocalizedStringKey
    var label: LocalizedStringKey = "encryption.badge.label"
    var systemImage = "lock.fill"

    var body: some View {
        Image(systemName: systemImage)
            .foregroundStyle(.accentInk)
            .accessibilityLabel(Text(label))
            .help(Text(help))
    }
}

/// Encryption marker of an upload row. The bucket's key state comes
/// from the in-memory key list, so rows never hit the Keychain and a
/// queued row follows key creation, deletion and reassignment. The key
/// list is passed in rather than read from the environment, so a host
/// that forgets to inject the container cannot crash the row.
struct UploadEncryptionBadge: View {
    let task: TransferTask
    let encryptionKeys: EncryptionKeysViewModel

    var body: some View {
        switch task.encryptionMarker(bucketHasKey: bucketHasKey) {
        case .encrypted:
            EncryptedBadge(help: "encryption.badge.upload.help")
        case .expected:
            EncryptedBadge(
                help: "encryption.badge.upload.expected.help",
                label: "encryption.badge.expected.label",
                systemImage: "lock"
            )
        case nil:
            EmptyView()
        }
    }

    private var bucketHasKey: Bool {
        encryptionKeys.isEncrypted(accountID: task.accountID, bucket: task.bucket)
    }
}

enum UploadEncryptionMarker: Equatable {
    /// The worker resolved the key: the bytes are being or were sealed.
    case encrypted
    /// Queued for a bucket that has a key right now. The worker decides
    /// when it starts, so the key may still change until then.
    case expected
}

extension TransferTask {
    /// `isEncrypted` is only set once the worker resolved the key, so a
    /// queued upload can only be expected to be encrypted, and a running
    /// one shows nothing until its key is resolved. A failed or
    /// cancelled upload stored nothing and shows no marker.
    func encryptionMarker(bucketHasKey: Bool) -> UploadEncryptionMarker? {
        guard direction == .upload else { return nil }
        switch state {
        case .queued: return bucketHasKey ? .expected : nil
        case .running, .completed: return isEncrypted ? .encrypted : nil
        case .failed, .cancelled: return nil
        }
    }
}
