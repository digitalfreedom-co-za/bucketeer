//
//  ContentView.swift
//  S3 Browser
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppContainer.self) private var container
    @State private var sidebarSelection: SidebarSelection? = nil

    var body: some View {
        NavigationSplitView {
            SidebarView(
                viewModel: container.accountListViewModel,
                selection: $sidebarSelection
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } content: {
            ObjectListPlaceholderView(selection: sidebarSelection)
                .navigationSplitViewColumnWidth(min: 360, ideal: 520)
        } detail: {
            DetailPlaceholderView()
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        }
    }
}

private struct ObjectListPlaceholderView: View {
    let selection: SidebarSelection?

    var body: some View {
        Group {
            switch selection {
            case .account(let id):
                ContentUnavailableView {
                    Label("browser.account.title", systemImage: "tray.full")
                } description: {
                    Text("browser.account.description \(id.uuidString)")
                }
            default:
                ContentUnavailableView {
                    Label("empty.no-account.title",
                          systemImage: "externaldrive.badge.questionmark")
                } description: {
                    Text("empty.no-account.message")
                }
            }
        }
    }
}

private struct DetailPlaceholderView: View {
    var body: some View {
        Color.clear
            .overlay {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
            }
    }
}
