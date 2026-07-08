//
//  PulsarCircularGlassSurface.swift
//  Pulsar
//

import SwiftUI

public struct PulsarCircularGlassSurface: View {
    var cornerRadius: CGFloat
    var tint: Color = Color(red: 0.68, green: 0.80, blue: 0.92)
    var opacity: Double = 1

    @Environment(\.colorScheme) private var colorScheme

    public init(
        cornerRadius: CGFloat,
        tint: Color = Color(red: 0.68, green: 0.80, blue: 0.92),
        opacity: Double = 1
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.opacity = opacity
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(iOS 26.0, *) {
            Color.clear
                .background(.white.opacity((colorScheme == .dark ? 0.050 : 0.42) * opacity), in: shape)
                .glassEffect(
                    .regular.tint(tint.opacity(0.055 * opacity)).interactive(),
                    in: .rect(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    border(shape: shape)
                }
                .shadow(color: .black.opacity((colorScheme == .dark ? 0.20 : 0.08) * opacity), radius: 18, x: 0, y: 10)
        } else {
            Color.clear
                .background(.ultraThinMaterial, in: shape)
                .background(.white.opacity((colorScheme == .dark ? 0.055 : 0.45) * opacity), in: shape)
                .overlay {
                    border(shape: shape)
                }
                .shadow(color: .black.opacity((colorScheme == .dark ? 0.18 : 0.08) * opacity), radius: 16, x: 0, y: 9)
        }
    }

    private func border(shape: RoundedRectangle) -> some View {
        shape
            .stroke(.white.opacity((colorScheme == .dark ? 0.20 : 0.70) * opacity), lineWidth: 0.65)
    }
}
