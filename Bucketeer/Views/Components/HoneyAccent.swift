//
//  HoneyAccent.swift
//  Bucketeer
//
//  Created by Marcel R. G. Berger on 03.11.26.
//

import SwiftUI

extension ShapeStyle where Self == Color {
    /// The app icon's honey yellow (`AccentColor`), for fills only. On a
    /// light background it reaches just 2:1, so text and icons use
    /// `accentInk`, and text on a honey fill uses `onAccent`.
    static var honey: Color { Color("AccentColor") }
}

extension View {
    /// Tints controls with the accent ink regardless of the user's
    /// system accent colour: macOS honours an app's `AccentColor` asset
    /// only while the system accent is set to Multicolour. Ink rather
    /// than honey, because borderless buttons, links and checkmarks
    /// draw the tint as text on a light background.
    func honeyAccent() -> some View {
        tint(.accentInk)
    }
}

/// Honey-filled primary button with a dark label. The native
/// `.borderedProminent` style picks a white label on the light-mode
/// honey fill (2:1) and ignores `foregroundStyle`.
struct HoneyProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, controlSize == .large ? 14 : 10)
            .padding(.vertical, controlSize == .large ? 7 : 3)
            .foregroundStyle(isEnabled ? Color.onAccent : Color.secondary)
            .background(Capsule().fill(isEnabled ? Color.honey : Color.secondary.opacity(0.2)))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == HoneyProminentButtonStyle {
    static var honeyProminent: HoneyProminentButtonStyle { HoneyProminentButtonStyle() }
}
