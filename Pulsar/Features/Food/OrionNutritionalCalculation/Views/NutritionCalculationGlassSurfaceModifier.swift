//
//  NutritionCalculationGlassSurfaceModifier.swift
//  Pulsar
//

import SwiftUI

struct NutritionCalculationGlassSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat
    var isInteractive: Bool
    var fillColor: Color
    var fillOpacity: Double
    var borderColor: Color
    var borderOpacity: Double
    var borderWidth: CGFloat
    var shadowOpacity: Double
    var shadowRadius: CGFloat
    var shadowY: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let surfacedContent = content
            .background {
                shape.fill(
                    fillColor.opacity(reduceTransparency ? max(fillOpacity, 0.94) : fillOpacity)
                )
            }
            .overlay {
                shape
                    .strokeBorder(borderColor.opacity(borderOpacity), lineWidth: borderWidth)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(shadowOpacity),
                radius: shadowRadius,
                y: shadowY
            )

        if #available(iOS 26.0, *) {
            surfacedContent
                .glassEffect(
                    .clear
                        .tint(.white.opacity(0.018))
                        .interactive(isInteractive),
                    in: shape
                )
        } else {
            surfacedContent
                .background(.ultraThinMaterial, in: shape)
        }
    }
}

extension View {
    func nutritionCalculationGlassSurface(
        cornerRadius: CGFloat,
        isInteractive: Bool = false,
        fillColor: Color = .white,
        fillOpacity: Double,
        borderColor: Color = .black,
        borderOpacity: Double,
        borderWidth: CGFloat = 0.5,
        shadowOpacity: Double,
        shadowRadius: CGFloat,
        shadowY: CGFloat
    ) -> some View {
        modifier(
            NutritionCalculationGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                isInteractive: isInteractive,
                fillColor: fillColor,
                fillOpacity: fillOpacity,
                borderColor: borderColor,
                borderOpacity: borderOpacity,
                borderWidth: borderWidth,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }
}
