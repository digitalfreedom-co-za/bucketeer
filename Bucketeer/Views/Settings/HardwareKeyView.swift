//
//  HardwareKeyView.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

import SwiftUI
import BucketeerCore

/// Settings → Security. Phase 13.16. Surfaces every detected
/// CryptoTokenKit smartcard slot and the opt-in toggle that wires
/// hardware-key unlock into the secret-reveal path.
struct HardwareKeyView: View {
    @Environment(AppContainer.self) private var container
    @State private var availability = HardwareKeyAvailability()

    var body: some View {
        @Bindable var settings = container.hardwareKeySettings
        Form {
            Section("hardwareKey.section.status") {
                statusRow
                if availability.slots.isEmpty {
                    Text("hardwareKey.status.noReader")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(availability.slots) { slot in
                        HStack {
                            Image(systemName: slot.cardPresent
                                  ? "key.fill"
                                  : "key.slash")
                                .foregroundStyle(slot.cardPresent ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(slot.displayName)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(slot.cardPresent
                                     ? "hardwareKey.slot.cardPresent"
                                     : "hardwareKey.slot.empty")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("hardwareKey.section.preferences") {
                Toggle("hardwareKey.field.enabled", isOn: $settings.enabled)
                Picker("hardwareKey.field.preferredSlot", selection: $settings.preferredSlot) {
                    Text("hardwareKey.slot.any").tag(String?.none)
                    ForEach(availability.slots) { slot in
                        Text(slot.displayName).tag(String?.some(slot.id))
                    }
                }
            }
            Section {
                Label("hardwareKey.preview.notice", systemImage: "flask")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 480, minHeight: 360)
        .task {
            await availability.refresh()
            availability.startMonitoring()
        }
        .onDisappear { availability.stopMonitoring() }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: availability.hasInsertedToken
                  ? "checkmark.shield.fill"
                  : (availability.hasReader ? "exclamationmark.shield" : "shield"))
                .foregroundStyle(availability.hasInsertedToken
                                 ? .green
                                 : (availability.hasReader ? .orange : .secondary))
            Text(availability.hasInsertedToken
                 ? "hardwareKey.status.ready"
                 : (availability.hasReader
                    ? "hardwareKey.status.readerWithoutCard"
                    : "hardwareKey.status.searching"))
        }
    }
}
