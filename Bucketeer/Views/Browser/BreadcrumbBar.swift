//
//  BreadcrumbBar.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 22.05.26.
//

import SwiftUI

struct BreadcrumbBar: View {
    @Bindable var viewModel: BrowserViewModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(viewModel.breadcrumbs.enumerated()), id: \.element.id) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button {
                    Task { await viewModel.navigate(to: crumb) }
                } label: {
                    Text(crumb.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .foregroundStyle(index == viewModel.breadcrumbs.count - 1
                                  ? Color.primary
                                  : Color.secondary)
            }
        }
        .font(.subheadline)
    }
}
