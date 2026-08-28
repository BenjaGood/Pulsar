//
//  GymWorkoutWhiteGlassSurface.swift
//  Pulsar
//

import SwiftUI

struct GymWorkoutWhiteGlassSurface: ViewModifier {
    let cornerRadius: Double
    let shadowOpacity: Double

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        content
            .background {
                shape
                    .fill(Color.white.opacity(reduceTransparency ? 1 : 0.88))
                    .pulsarLiquidGlass(
                        cornerRadius: cornerRadius,
                        isClear: true
                    )
            }
            .overlay {
                shape
                    .stroke(Color.black.opacity(0.055), lineWidth: 0.7)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(shadowOpacity), radius: 18, y: 8)
    }
}

extension View {
    func gymWorkoutWhiteGlassSurface(
        cornerRadius: Double,
        shadowOpacity: Double = 0.035
    ) -> some View {
        modifier(
            GymWorkoutWhiteGlassSurface(
                cornerRadius: cornerRadius,
                shadowOpacity: shadowOpacity
            )
        )
    }
}
