//
//  MealScannerGlassSurfaceModifier.swift
//  Pulsar
//

import SwiftUI

struct MealScannerGlassSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat
    var isInteractive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        if reduceTransparency {
            content
                .background(.black.opacity(0.76), in: shape)
                .overlay {
                    shape.strokeBorder(.white.opacity(0.24), lineWidth: 0.7)
                }
        } else {
            content
                .background(.black.opacity(0.14), in: shape)
                .pulsarLiquidGlass(
                    cornerRadius: cornerRadius,
                    interactive: isInteractive,
                    isClear: true
                )
        }
    }
}

extension View {
    func mealScannerGlassSurface(
        cornerRadius: CGFloat,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            MealScannerGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                isInteractive: isInteractive
            )
        )
    }

    @ViewBuilder
    func mealScannerSelectionGlass(isSelected: Bool) -> some View {
        if #available(iOS 26.0, *), isSelected {
            glassEffect(.clear.tint(.black.opacity(0.04)), in: .capsule)
        } else if isSelected {
            background(.white.opacity(0.12), in: Capsule())
        } else {
            self
        }
    }
}
