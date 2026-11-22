//
//  HardwareKeyView.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 25.05.26.
//

// Debug-only until v1.1 (#33): the hardware-key preview must not be
// compiled into Release builds.
#if DEBUG
import SwiftUI

/// Settings → Security. Phase 13.16. Surfaces every detected
/// CryptoTokenKit smartcard slot and the opt-in toggle that wires
/// hardware-key unlock into the secret-reveal path.
struct HardwareKeyView: View {
    /// Own string table, excluded from Release so the shipping bundle
    /// carries none of the preview's copy (#33).
    static let table = "HardwareKey"

    @Environment(AppContainer.self) private var container

    private var availability: HardwareKeyAvailability { container.hardwareKeyAvailability }

    var body: some View {
        @Bindable var settings = container.hardwareKeySettings
        Form {
            Section {
                statusRow
                if availability.slots.isEmpty {
                    Text("hardwareKey.status.noReader", tableName: Self.table)
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
                                     : "hardwareKey.slot.empty", tableName: Self.table)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("hardwareKey.section.status", tableName: Self.table)
            }
            Section {
                Toggle(isOn: $settings.enabled) {
                    Text("hardwareKey.field.enabled", tableName: Self.table)
                }
                Picker(selection: $settings.preferredSlot) {
                    Text("hardwareKey.slot.any", tableName: Self.table).tag(String?.none)
                    ForEach(availability.slots) { slot in
                        Text(slot.displayName).tag(String?.some(slot.id))
                    }
                } label: {
                    Text("hardwareKey.field.preferredSlot", tableName: Self.table)
                }
            } header: {
                Text("hardwareKey.section.preferences", tableName: Self.table)
            }
            Section {
                Label {
                    Text("hardwareKey.preview.notice", tableName: Self.table)
                } icon: {
                    Image(systemName: "flask")
                }
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
                    : "hardwareKey.status.searching"), tableName: Self.table)
        }
    }
}
#endif
