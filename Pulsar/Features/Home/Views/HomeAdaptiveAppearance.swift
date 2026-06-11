//
//  HomeAdaptiveAppearance.swift
//  Pulsar
//

import SwiftUI

struct HomeAdaptiveAppearance {
    var style: HomeBackgroundStyle

    static let night = HomeAdaptiveAppearance(style: .night)

    var preferredColorScheme: ColorScheme? {
        .dark
    }

    var usesLightText: Bool {
        true
    }

    var primaryText: Color {
        .white.opacity(0.96)
    }

    var secondaryText: Color {
        .white.opacity(0.68)
    }

    var tertiaryText: Color {
        .white.opacity(0.56)
    }

    var timeAccentText: Color {
        Color(red: 0.66, green: 0.78, blue: 1.0).opacity(0.92)
    }

    var glassShadowOpacity: Double {
        switch style {
        case .day: 0.070
        case .sunrise: 0.076
        case .sunset: 0.088
        case .night: 0.095
        }
    }

    var glassShadowRadius: CGFloat {
        switch style {
        case .day: 16
        case .sunrise: 17
        case .sunset: 19
        case .night: 20
        }
    }

    var glassShadowY: CGFloat {
        switch style {
        case .day, .sunrise: 8
        case .sunset: 10
        case .night: 11
        }
    }

    var nativeGlassTintOpacity: Double {
        switch style {
        case .day: 0.080
        case .sunrise: 0.085
        case .sunset: 0.090
        case .night: 0.095
        }
    }

    var nativeGlassTint: Color {
        switch style {
        case .day:
            return Color(red: 0.015, green: 0.040, blue: 0.075)
        case .sunrise:
            return Color(red: 0.035, green: 0.030, blue: 0.060)
        case .sunset:
            return Color(red: 0.035, green: 0.025, blue: 0.050)
        case .night:
            return Color(red: 0.010, green: 0.022, blue: 0.052)
        }
    }

    var metricTrackColor: Color {
        Color.white.opacity(0.055)
    }

    var metricRecessColor: Color {
        Color.black.opacity(0.105)
    }

    var metricCenterBlackOpacity: Double {
        switch style {
        case .day: 0.070
        case .sunrise: 0.080
        case .sunset: 0.090
        case .night: 0.105
        }
    }

    var headerShadowOpacity: Double {
        0.09
    }

    func glassFillColors(tint: Color) -> [Color] {
        switch style {
        case .day:
            return [
                Color(red: 0.015, green: 0.040, blue: 0.075).opacity(0.078),
                Color.black.opacity(0.052),
                Color(red: 0.020, green: 0.055, blue: 0.095).opacity(0.038),
                tint.opacity(0.010)
            ]
        case .sunrise:
            return [
                Color(red: 0.035, green: 0.030, blue: 0.060).opacity(0.084),
                Color.black.opacity(0.056),
                Color(red: 0.070, green: 0.040, blue: 0.070).opacity(0.036),
                tint.opacity(0.010)
            ]
        case .sunset:
            return [
                Color(red: 0.030, green: 0.032, blue: 0.060).opacity(0.088),
                Color.black.opacity(0.060),
                Color(red: 0.085, green: 0.040, blue: 0.050).opacity(0.038),
                tint.opacity(0.011)
            ]
        case .night:
            return [
                Color(red: 0.010, green: 0.022, blue: 0.052).opacity(0.096),
                Color.black.opacity(0.064),
                Color(red: 0.035, green: 0.055, blue: 0.100).opacity(0.038),
                tint.opacity(0.010)
            ]
        }
    }

    func glassRadialColors(tint: Color) -> [Color] {
        switch style {
        case .day:
            return [tint.opacity(0.015), Color.black.opacity(0.018), .clear]
        case .sunrise:
            return [tint.opacity(0.016), Color.black.opacity(0.020), .clear]
        case .sunset:
            return [tint.opacity(0.019), Color.black.opacity(0.024), .clear]
        case .night:
            return [tint.opacity(0.017), Color.black.opacity(0.026), .clear]
        }
    }

    func glassBorderColors(tint: Color) -> [Color] {
        switch style {
        case .day:
            return [.white.opacity(0.24), .white.opacity(0.056), tint.opacity(0.16), .white.opacity(0.036)]
        case .sunrise:
            return [.white.opacity(0.25), .white.opacity(0.058), tint.opacity(0.17), .white.opacity(0.038)]
        case .sunset:
            return [.white.opacity(0.28), .white.opacity(0.064), tint.opacity(0.20), .white.opacity(0.040)]
        case .night:
            return [.white.opacity(0.30), .white.opacity(0.060), tint.opacity(0.20), .white.opacity(0.035)]
        }
    }

    func glassHighlightColors() -> [Color] {
        switch style {
        case .day:
            return [.white.opacity(0.062), .white.opacity(0.012), .clear]
        case .sunrise:
            return [.white.opacity(0.066), .white.opacity(0.013), .clear]
        case .sunset:
            return [.white.opacity(0.074), .white.opacity(0.014), .clear]
        case .night:
            return [.white.opacity(0.070), .white.opacity(0.012), .clear]
        }
    }

    func glassInnerBorderColors(tint: Color) -> [Color] {
        switch style {
        case .day:
            return [.white.opacity(0.090), .clear, tint.opacity(0.070)]
        case .sunrise:
            return [.white.opacity(0.096), .clear, tint.opacity(0.074)]
        case .sunset:
            return [.white.opacity(0.112), .clear, tint.opacity(0.080)]
        case .night:
            return [.white.opacity(0.105), .clear, tint.opacity(0.075)]
        }
    }

    func contactGlowOpacity(for tint: Color) -> Double {
        switch style {
        case .day: 0.15
        case .sunrise: 0.16
        case .sunset: 0.18
        case .night: 0.19
        }
    }

    func pillFillColors(tint: Color) -> [Color] {
        switch style {
        case .day:
            return [Color(red: 0.018, green: 0.036, blue: 0.070).opacity(0.088), Color.black.opacity(0.044), tint.opacity(0.012)]
        case .sunrise:
            return [Color(red: 0.034, green: 0.030, blue: 0.058).opacity(0.090), Color.black.opacity(0.048), tint.opacity(0.012)]
        case .sunset:
            return [Color(red: 0.035, green: 0.026, blue: 0.052).opacity(0.096), Color.black.opacity(0.052), tint.opacity(0.013)]
        case .night:
            return [Color(red: 0.010, green: 0.024, blue: 0.052).opacity(0.102), Color.black.opacity(0.056), tint.opacity(0.012)]
        }
    }

    func pillBorderColors(tint: Color) -> [Color] {
        switch style {
        case .day:
            return [.white.opacity(0.17), tint.opacity(0.12), .white.opacity(0.034)]
        case .sunrise:
            return [.white.opacity(0.18), tint.opacity(0.12), .white.opacity(0.036)]
        case .sunset:
            return [.white.opacity(0.21), tint.opacity(0.12), .white.opacity(0.042)]
        case .night:
            return [.white.opacity(0.18), tint.opacity(0.12), .white.opacity(0.035)]
        }
    }

    func headerFillColors(tint: Color = .white) -> [Color] {
        switch style {
        case .day:
            return [Color(red: 0.016, green: 0.034, blue: 0.068).opacity(0.18), Color.black.opacity(0.100), tint.opacity(0.020)]
        case .sunrise:
            return [Color(red: 0.034, green: 0.030, blue: 0.060).opacity(0.18), Color.black.opacity(0.110), tint.opacity(0.019)]
        case .sunset:
            return [Color(red: 0.034, green: 0.026, blue: 0.052).opacity(0.19), Color.black.opacity(0.115), tint.opacity(0.020)]
        case .night:
            return [Color(red: 0.010, green: 0.026, blue: 0.058).opacity(0.20), Color.black.opacity(0.125), tint.opacity(0.019)]
        }
    }

    var headerBorderColor: Color {
        .white.opacity(0.22)
    }
}

private struct HomeAdaptiveAppearanceKey: EnvironmentKey {
    static let defaultValue = HomeAdaptiveAppearance.night
}

extension EnvironmentValues {
    var homeAdaptiveAppearance: HomeAdaptiveAppearance {
        get { self[HomeAdaptiveAppearanceKey.self] }
        set { self[HomeAdaptiveAppearanceKey.self] = newValue }
    }
}
