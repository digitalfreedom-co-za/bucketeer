//
//  AboutWindow.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import AppKit
import SwiftUI

struct AboutWindow: View {
    @State private var selectedSection: Section = .about

    enum Section: String, CaseIterable, Identifiable {
        case about
        case license
        case eula
        case privacy
        case openSource
        case impressum

        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .about:      return "about.section.about"
            case .license:    return "about.section.license"
            case .eula:       return "about.section.eula"
            case .privacy:    return "about.section.privacy"
            case .openSource: return "about.section.openSource"
            case .impressum:  return "about.section.impressum"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("", selection: $selectedSection) {
                ForEach(Section.allCases) { section in
                    Text(section.label).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                content
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .frame(width: 760, height: 620)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(appName)
                    .font(.title)
                    .bold()
                Text("about.version.\(version).build.\(build)")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Text(copyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Link("about.link.website",
                         destination: URL(string: "https://digitalfreedom.co.za")!)
                    Link("about.link.github",
                         destination: URL(string: "https://github.com/digitalfreedom-co-za/bucketeer")!)
                    Link("about.link.issues",
                         destination: URL(string: "https://github.com/digitalfreedom-co-za/bucketeer/issues")!)
                }
                .font(.callout)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch selectedSection {
        case .about:
            aboutBody
        case .license:
            MarkdownView(text: loadMarkdown(named: "LICENSE"))
        case .eula:
            MarkdownView(text: loadMarkdown(named: "EULA"))
        case .privacy:
            MarkdownView(text: loadMarkdown(named: "PRIVACY_POLICY"))
        case .openSource:
            MarkdownView(text: loadMarkdown(named: "OPEN_SOURCE_NOTICES"))
        case .impressum:
            MarkdownView(text: loadMarkdown(named: "IMPRESSUM"))
        }
    }

    private var aboutBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("about.tagline")
                .font(.body)

            Text("about.publisher.title")
                .font(.headline)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text("DigitalFreedom — a brand of Berger & Rosenstock GbR")
                Text("Dieselstr. 22e, 61231 Bad Nauheim, Germany")
                    .foregroundStyle(.secondary)
                Text("VAT-ID: DE455096022")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Text("about.contact.title")
                .font(.headline)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Link("hello@digitalfreedom.co.za",
                     destination: URL(string: "mailto:hello@digitalfreedom.co.za")!)
                Link("data-protection@digitalfreedom.co.za",
                     destination: URL(string: "mailto:data-protection@digitalfreedom.co.za")!)
            }

            Text("about.legal.summary")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    // MARK: - Bundle helpers

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Bucketeer"
    }
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
    private var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "© 2026 DigitalFreedom — Berger & Rosenstock GbR"
    }

    private func loadMarkdown(named name: String) -> String {
        if let url = Bundle.main.url(forResource: name, withExtension: "md") {
            return (try? String(contentsOf: url, encoding: .utf8)) ?? fallback(name)
        }
        return fallback(name)
    }

    private func fallback(_ name: String) -> String {
        String(localized: "about.markdown.missing",
               defaultValue: "Document \(name).md is not bundled in this build.")
    }
}
