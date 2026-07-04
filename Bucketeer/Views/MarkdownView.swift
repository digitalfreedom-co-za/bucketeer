//
//  MarkdownView.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import SwiftUI

/// Minimal block-aware markdown renderer. Handles headings, paragraphs,
/// bullet lists and inline markdown (bold, italic, code, links) — which
/// is everything the bundled help and legal documents use. Tables and
/// fenced code blocks fall through to plain text by design; the goal
/// is readable, not full GitHub-flavoured fidelity.
struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Wiki rule (template checklist #3): a relative link like
        // [EULA](EULA.md) in a bundled doc must never reach
        // NSWorkspace as a raw file-relative URL — that pops macOS
        // error -50 and looks like a crash. Only real web/mail links
        // go to the system; everything else is swallowed.
        .environment(\.openURL, OpenURLAction { url in
            switch url.scheme?.lowercased() {
            case "https", "http", "mailto":
                return .systemAction
            default:
                return .discarded
            }
        })
    }

    // MARK: - Block parsing

    private enum Block {
        case h1(String)
        case h2(String)
        case h3(String)
        case bulleted([String])
        case paragraph(String)
        case spacer
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var bulletBuffer: [String] = []
        var paragraphBuffer: [String] = []

        func flushBullets() {
            if !bulletBuffer.isEmpty {
                result.append(.bulleted(bulletBuffer))
                bulletBuffer.removeAll()
            }
        }
        func flushParagraph() {
            if !paragraphBuffer.isEmpty {
                result.append(.paragraph(paragraphBuffer.joined(separator: " ")))
                paragraphBuffer.removeAll()
            }
        }
        func flushAll() {
            flushParagraph()
            flushBullets()
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushAll()
                if !(result.last.map { if case .spacer = $0 { true } else { false } } ?? false) {
                    result.append(.spacer)
                }
                continue
            }

            if trimmed.hasPrefix("### ") {
                flushAll()
                result.append(.h3(String(trimmed.dropFirst(4))))
            } else if trimmed.hasPrefix("## ") {
                flushAll()
                result.append(.h2(String(trimmed.dropFirst(3))))
            } else if trimmed.hasPrefix("# ") {
                flushAll()
                result.append(.h1(String(trimmed.dropFirst(2))))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                bulletBuffer.append(String(trimmed.dropFirst(2)))
            } else if trimmed.hasPrefix("|") {
                // Tables aren't rendered with structure — emit verbatim
                // so the reader still sees the pipes and can mentally
                // parse them. Costs nothing and avoids losing content.
                flushAll()
                result.append(.paragraph(trimmed))
            } else if trimmed.hasPrefix("---") || trimmed.hasPrefix("===") {
                flushAll()
                result.append(.spacer)
            } else {
                flushBullets()
                paragraphBuffer.append(trimmed)
            }
        }
        flushAll()
        return result
    }

    // MARK: - Block rendering

    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .h1(let s):
            inlineText(s).font(.title).bold().padding(.top, 8)
        case .h2(let s):
            inlineText(s).font(.title2).bold().padding(.top, 6)
        case .h3(let s):
            inlineText(s).font(.headline).padding(.top, 4)
        case .paragraph(let s):
            inlineText(s)
        case .bulleted(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        inlineText(item)
                    }
                }
            }
            .padding(.leading, 8)
        case .spacer:
            Color.clear.frame(height: 4)
        }
    }

    private func inlineText(_ raw: String) -> Text {
        if let attr = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return Text(attr)
        }
        return Text(raw)
    }
}
