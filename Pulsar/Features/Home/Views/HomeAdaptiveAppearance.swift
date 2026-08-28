//
//  HomeAdaptiveAppearance.swift
//  Pulsar
//

import SwiftUI

/// Home's calm, light editorial palette. `style` remains part of the value so
/// existing preview and settings call sites do not need to change.
struct HomeAdaptiveAppearance {
    var style: HomeBackgroundStyle

    static let premium = HomeAdaptiveAppearance(style: .day)
    static let night = premium

    var preferredColorScheme: ColorScheme? { .light }
    var usesLightText: Bool { false }
    var primaryText: Color { HomePremiumDesign.primaryText }
    var secondaryText: Color { HomePremiumDesign.secondaryText }
    var tertiaryText: Color { HomePremiumDesign.tertiaryText }
    var timeAccentText: Color { HomePremiumDesign.accent }
    var glassShadowOpacity: Double { 0.075 }
    var glassShadowRadius: CGFloat { 18 }
    var glassShadowY: CGFloat { 9 }
    var nativeGlassTintOpacity: Double { 0.12 }
    var nativeGlassTint: Color { .white }
    var metricTrackColor: Color { Color(red: 0.12, green: 0.16, blue: 0.23).opacity(0.09) }
    var metricRecessColor: Color { Color.black.opacity(0.025) }
    var metricCenterBlackOpacity: Double { 0 }
    var headerShadowOpacity: Double { 0.055 }
    var headerBorderColor: Color { HomePremiumDesign.border }

    func glassFillColors(tint: Color) -> [Color] {
        [
            Color.white.opacity(0.82),
            Color.white.opacity(0.66),
            tint.opacity(0.025),
            Color(red: 0.92, green: 0.94, blue: 0.97).opacity(0.30)
        ]
    }

    func glassRadialColors(tint: Color) -> [Color] {
        [tint.opacity(0.045), Color.white.opacity(0.15), .clear]
    }

    func glassBorderColors(tint: Color) -> [Color] {
        [Color.white.opacity(0.95), tint.opacity(0.15), HomePremiumDesign.border]
    }

    func glassHighlightColors() -> [Color] {
        [Color.white.opacity(0.72), Color.white.opacity(0.12), .clear]
    }

    func glassInnerBorderColors(tint: Color) -> [Color] {
        [Color.white.opacity(0.72), .clear, tint.opacity(0.10)]
    }

    func contactGlowOpacity(for tint: Color) -> Double { 0.07 }

    func pillFillColors(tint: Color) -> [Color] {
        [Color.white.opacity(0.84), Color.white.opacity(0.64), tint.opacity(0.035)]
    }

    func pillBorderColors(tint: Color) -> [Color] {
        [Color.white.opacity(0.94), tint.opacity(0.14), HomePremiumDesign.border]
    }

    func headerFillColors(tint: Color = .white) -> [Color] {
        [Color.white.opacity(0.94), Color.white.opacity(0.72), tint.opacity(0.05)]
    }
}

private struct HomeAdaptiveAppearanceKey: EnvironmentKey {
    static let defaultValue = HomeAdaptiveAppearance.premium
}

extension EnvironmentValues {
    var homeAdaptiveAppearance: HomeAdaptiveAppearance {
        get { self[HomeAdaptiveAppearanceKey.self] }
        set { self[HomeAdaptiveAppearanceKey.self] = newValue }
    }
}
