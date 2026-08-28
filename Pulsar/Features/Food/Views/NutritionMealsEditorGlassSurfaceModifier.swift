//
//  NutritionMealsEditorGlassSurfaceModifier.swift
//  Pulsar
//

import SwiftUI

struct NutritionMealsEditorGlassSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat
    var isInteractive: Bool
    var fillOpacity: Double
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
                shape.fill(.white.opacity(reduceTransparency ? 0.94 : fillOpacity))
            }
            .overlay {
                shape
                    .strokeBorder(.black.opacity(borderOpacity), lineWidth: borderWidth)
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
    func nutritionMealsEditorGlassSurface(
        cornerRadius: CGFloat,
        isInteractive: Bool = false,
        fillOpacity: Double,
        borderOpacity: Double,
        borderWidth: CGFloat = 0.5,
        shadowOpacity: Double,
        shadowRadius: CGFloat,
        shadowY: CGFloat
    ) -> some View {
        modifier(
            NutritionMealsEditorGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                isInteractive: isInteractive,
                fillOpacity: fillOpacity,
                borderOpacity: borderOpacity,
                borderWidth: borderWidth,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }
}
