//
//  HelpWindow.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 23.05.26.
//

import SwiftUI

struct HelpWindow: View {
    var body: some View {
        ScrollView {
            MarkdownView(text: loadHelp())
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(minWidth: 640, idealWidth: 800, minHeight: 480, idealHeight: 700)
    }

    /// The bundle resolves `QuickStart.md` from the `.lproj` of the
    /// user's preferred app language; English covers any locale the
    /// help has not been translated into.
    private func loadHelp() -> String {
        let candidates = [
            Bundle.main.url(forResource: "QuickStart", withExtension: "md"),
            Bundle.main.url(forResource: "QuickStart", withExtension: "md",
                            subdirectory: nil, localization: "en")
        ]
        for case let url? in candidates {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
            }
        }
        return String(localized: "help.missing",
                      defaultValue: "QuickStart.md is not bundled in this build.")
    }
}
