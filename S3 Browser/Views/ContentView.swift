//
//  ContentView.swift
//  S3 Browser
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI

struct ContentView: View {
    @State private var sidebarSelection: SidebarItem? = nil

    var body: some View {
        NavigationSplitView {
            SidebarPlaceholderView(selection: $sidebarSelection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } content: {
            ObjectListPlaceholderView()
                .navigationSplitViewColumnWidth(min: 360, ideal: 520)
        } detail: {
            DetailPlaceholderView()
                .navigationSplitViewColumnWidth(min: 320, ideal: 380)
        }
    }
}

enum SidebarItem: Hashable {
    case accounts
    case mounted
    case sync
    case transfers
}

struct SidebarPlaceholderView: View {
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section("sidebar.section.accounts") {
                Label("action.add-account", systemImage: "plus.circle")
                    .foregroundStyle(.secondary)
            }
            Section("sidebar.section.mounted") { EmptyView() }
            Section("sidebar.section.sync") { EmptyView() }
            Section("sidebar.section.transfers") { EmptyView() }
        }
        .listStyle(.sidebar)
    }
}

struct ObjectListPlaceholderView: View {
    var body: some View {
        ContentUnavailableView {
            Label("empty.no-account.title", systemImage: "externaldrive.badge.questionmark")
        } description: {
            Text("empty.no-account.message")
        }
    }
}

struct DetailPlaceholderView: View {
    var body: some View {
        Color.clear
            .overlay {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
            }
    }
}

#Preview {
    ContentView()
}
