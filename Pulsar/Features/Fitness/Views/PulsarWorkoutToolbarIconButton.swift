//
//  PulsarWorkoutToolbarIconButton.swift
//  Pulsar
//

import SwiftUI

struct PulsarWorkoutToolbarIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var size: CGFloat = 40
    var font: Font = .headline.weight(.bold)
    var foregroundStyle: Color = .primary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(font)
                .foregroundStyle(foregroundStyle)
                .frame(width: size, height: size)
                .modifier(PulsarWorkoutToolbarGlassCircle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct PulsarWorkoutToolbarGlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}
