//
//  PulsarTheme.swift
//  Pulsar
//

import SwiftUI

enum PulsarTheme {
    static func fitnessPrimaryText(for colorScheme: ColorScheme) -> Color {
        PulsarFitnessMonochromeDesign.primaryText
    }

    static func fitnessSecondaryText(for colorScheme: ColorScheme) -> Color {
        PulsarFitnessMonochromeDesign.secondaryText
    }

    static func fitnessTertiaryText(for colorScheme: ColorScheme) -> Color {
        PulsarFitnessMonochromeDesign.tertiaryText
    }

    static func glassCardBackground(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.96),
                Color.white.opacity(0.72),
                Color.black.opacity(0.035)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func glassCardBorder(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(0.96),
                .black.opacity(0.045),
                .black.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func matrixPanelBackground(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.94),
                Color(red: 0.95, green: 0.95, blue: 0.96).opacity(0.84),
                Color.black.opacity(0.035)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func matrixInactiveDot(for colorScheme: ColorScheme) -> Color {
        PulsarFitnessMonochromeDesign.inactive
    }

    static func matrixSelectedDayBackground(for colorScheme: ColorScheme) -> Color {
        Color.black.opacity(0.045)
    }

    static func matrixSelectedDayBorder(for colorScheme: ColorScheme) -> Color {
        Color.black.opacity(0.13)
    }

    static func matrixPillBackground(for colorScheme: ColorScheme) -> Color {
        .white.opacity(0.72)
    }
}
