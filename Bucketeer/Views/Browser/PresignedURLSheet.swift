//
//  PresignedURLSheet.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 24.05.26.
//

import SwiftUI
import AppKit
import BucketeerCore

/// Sheet that lets the user pick a TTL and generate a presigned
/// download URL for the selected object. S3 and Azure both supported;
/// the generator picks Soto sign-v4 or Azure Service SAS via the
/// `ProviderRouter`. Phase 9.9.
struct PresignedURLSheet: View {
    let account: S3Account
    let bucket: String
    let object: S3Object
    let generator: any S3Browsing

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTTL: TTLOption = .oneHour
    @State private var customMinutes: Int = 60
    @State private var generatedURL: URL?
    @State private var expiryDate: Date?
    @State private var inFlight: Bool = false
    @State private var errorMessage: String?

    enum TTLOption: String, CaseIterable, Identifiable {
        case fifteenMinutes
        case oneHour
        case sixHours
        case oneDay
        case sevenDays
        case custom

        var id: String { rawValue }

        var labelKey: LocalizedStringKey {
            switch self {
            case .fifteenMinutes: return "share.ttl.15min"
            case .oneHour:        return "share.ttl.1h"
            case .sixHours:       return "share.ttl.6h"
            case .oneDay:         return "share.ttl.1d"
            case .sevenDays:      return "share.ttl.7d"
            case .custom:         return "share.ttl.custom"
            }
        }

        func seconds(custom: Int) -> TimeInterval {
            switch self {
            case .fifteenMinutes: return 15 * 60
            case .oneHour:        return 60 * 60
            case .sixHours:       return 6 * 60 * 60
            case .oneDay:         return 24 * 60 * 60
            case .sevenDays:      return 7 * 24 * 60 * 60
            case .custom:         return TimeInterval(max(1, custom) * 60)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            ttlPicker
            if selectedTTL == .custom {
                customMinutesField
            }
            Divider()
            generatedSection
            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .frame(width: 520, height: generatedURL == nil ? 320 : 400)
        .onAppear { Task { await generate() } }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("share.title", systemImage: "link")
                .font(.title3)
                .bold()
            Text(object.displayName)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var ttlPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("share.field.ttl")
                .font(.callout)
            Picker("share.field.ttl", selection: $selectedTTL) {
                ForEach(TTLOption.allCases) { option in
                    Text(option.labelKey).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedTTL) { _, _ in
                Task { await generate() }
            }
        }
    }

    private var customMinutesField: some View {
        HStack {
            Text("share.field.customMinutes")
                .font(.callout)
            Spacer()
            TextField("", value: $customMinutes, format: .number)
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
                .onSubmit { Task { await generate() } }
            Stepper(value: $customMinutes, in: 1...10_080, step: 5, label: { EmptyView() })
                .labelsHidden()
        }
    }

    @ViewBuilder
    private var generatedSection: some View {
        if let url = generatedURL {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("share.status.ready")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let expiryDate {
                        Text("share.expiresAt \(formattedExpiry(expiryDate))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(url.absoluteString)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                }
                .frame(height: 60)
            }
        } else if let errorMessage {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        } else {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("share.status.generating")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("action.cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if let url = generatedURL {
                Button("share.action.share") {
                    presentShareSheet(for: url)
                }
                Button("share.action.copy") {
                    copyToClipboard(url.absoluteString)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Actions

    private func generate() async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        errorMessage = nil
        generatedURL = nil
        expiryDate = nil
        let ttl = selectedTTL.seconds(custom: customMinutes)
        do {
            let url = try await generator.presignedDownloadURL(
                account: account,
                bucket: bucket,
                key: object.key,
                ttl: ttl
            )
            generatedURL = url
            expiryDate = Date().addingTimeInterval(ttl)
        } catch let error as BucketeerError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copyToClipboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(value, forType: .string)
    }

    /// Hands the URL to macOS's NSSharingServicePicker so the user can
    /// shoot it to Mail / Messages / AirDrop / Slack etc.
    private func presentShareSheet(for url: URL) {
        let picker = NSSharingServicePicker(items: [url])
        if let window = NSApp.keyWindow,
           let contentView = window.contentView {
            picker.show(
                relativeTo: .zero,
                of: contentView,
                preferredEdge: .minY
            )
        }
    }

    private func formattedExpiry(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
