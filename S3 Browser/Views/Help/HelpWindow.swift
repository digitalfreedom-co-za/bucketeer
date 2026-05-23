//
//  HelpWindow.swift
//  S3 Browser
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

    private func loadHelp() -> String {
        if let url = Bundle.main.url(forResource: "QuickStart", withExtension: "md") {
            return (try? String(contentsOf: url, encoding: .utf8))
                ?? String(localized: "help.missing",
                          defaultValue: "QuickStart.md is not bundled in this build.")
        }
        return String(localized: "help.missing",
                      defaultValue: "QuickStart.md is not bundled in this build.")
    }
}
