//
//  PulsarFitnessMonochromeDesign.swift
//  Pulsar
//

import SwiftUI
import UIKit

enum PulsarTabPalette {
    static let pageBackgroundTop = Color.white
    static let pageBackgroundMiddle = Color(red: 0.985, green: 0.982, blue: 0.975)
    static let pageBackgroundBottom = Color(red: 0.965, green: 0.966, blue: 0.969)

    static var pageBackground: LinearGradient {
        LinearGradient(
            colors: [
                pageBackgroundTop,
                pageBackgroundMiddle,
                pageBackgroundBottom
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static let cardBackground = Color.white
    static let primaryText = Color(red: 0.075, green: 0.082, blue: 0.095)
    static let secondaryText = Color(red: 0.38, green: 0.39, blue: 0.43)
    static let tertiaryText = Color(red: 0.54, green: 0.55, blue: 0.59)
    static let separator = Color.black.opacity(0.075)
    static let shadowColor = Color.black
    static let inactive = Color.black.opacity(0.16)
    static let active = Color(red: 0.12, green: 0.13, blue: 0.15)
    static let selectedTabAccent = Color(red: 36.0 / 255.0, green: 73.0 / 255.0, blue: 75.0 / 255.0)
    static let selectedTabAccentUIColor = UIColor(red: 36.0 / 255.0, green: 73.0 / 255.0, blue: 75.0 / 255.0, alpha: 1.0)
}

enum PulsarFitnessMonochromeDesign {
    static let background = PulsarTabPalette.pageBackgroundMiddle
    static let backgroundTop = PulsarTabPalette.pageBackgroundTop
    static let cardBackground = PulsarTabPalette.cardBackground
    static let primaryText = PulsarTabPalette.primaryText
    static let secondaryText = PulsarTabPalette.secondaryText
    static let tertiaryText = PulsarTabPalette.tertiaryText
    static let hairline = PulsarTabPalette.separator
    static let separator = PulsarTabPalette.separator
    static let shadowColor = PulsarTabPalette.shadowColor
    static let inactive = PulsarTabPalette.inactive
    static let active = PulsarTabPalette.active
}

extension EnvironmentValues {
    @Entry var pulsarFitnessUsesMonochromeAppearance = false
}

extension View {
    func pulsarFitnessMonochromeAppearance() -> some View {
        environment(\.pulsarFitnessUsesMonochromeAppearance, true)
            .preferredColorScheme(.light)
            .tint(PulsarFitnessMonochromeDesign.primaryText)
    }
}

struct PulsarFitnessMonochromeBackground: View {
    var body: some View {
        PulsarTabPalette.pageBackground
            .ignoresSafeArea()
    }
}

struct PulsarFitnessMonochromeSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat
    var isInteractive = false
    var shadowOpacity = 0.065
    var shadowRadius: CGFloat = 22
    var shadowY: CGFloat = 12
    var usesCompactHighlight = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let highlightWhite = reduceTransparency ? 0.38 : (usesCompactHighlight ? 0.28 : 0.58)
        let strokeBlackEnd = usesCompactHighlight ? 0.05 : 0.085

        content
            .background {
                shape.fill(PulsarTabPalette.cardBackground.opacity(reduceTransparency ? 0.98 : 0.82))
            }
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(highlightWhite),
                            .white.opacity(0.10),
                            Color.black.opacity(reduceTransparency ? 0.015 : 0.028)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.92),
                            Color.black.opacity(0.045),
                            Color.black.opacity(strokeBlackEnd)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
                .allowsHitTesting(false)
            }
            .shadow(
                color: PulsarTabPalette.shadowColor.opacity(shadowOpacity),
                radius: shadowRadius,
                y: shadowY
            )
            .pulsarLiquidGlass(
                cornerRadius: cornerRadius,
                interactive: isInteractive,
                isClear: true
            )
    }
}

extension View {
    func pulsarFitnessMonochromeSurface(
        cornerRadius: CGFloat,
        isInteractive: Bool = false,
        shadowOpacity: Double = 0.065,
        shadowRadius: CGFloat = 22,
        shadowY: CGFloat = 12,
        usesCompactHighlight: Bool = false
    ) -> some View {
        modifier(
            PulsarFitnessMonochromeSurfaceModifier(
                cornerRadius: cornerRadius,
                isInteractive: isInteractive,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY,
                usesCompactHighlight: usesCompactHighlight
            )
        )
    }
}
