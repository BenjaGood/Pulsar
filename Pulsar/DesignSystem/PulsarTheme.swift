//
//  PulsarTheme.swift
//  Pulsar
//

import SwiftUI

enum PulsarTheme {
    static func fitnessPrimaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? .white.opacity(0.97)
            : Color(red: 0.06, green: 0.08, blue: 0.12)
    }

    static func fitnessSecondaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? .white.opacity(0.68)
            : Color(red: 0.29, green: 0.34, blue: 0.42)
    }

    static func fitnessTertiaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? .white.opacity(0.48)
            : Color(red: 0.43, green: 0.48, blue: 0.57)
    }

    static func glassCardBackground(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.11),
                    Color(red: 0.035, green: 0.045, blue: 0.070).opacity(0.90),
                    Color(red: 0.16, green: 0.12, blue: 0.30).opacity(0.30)
                ]
                : [
                    Color.white.opacity(0.98),
                    Color(red: 0.91, green: 0.96, blue: 1.00).opacity(0.90),
                    Color(red: 0.66, green: 0.76, blue: 1.00).opacity(0.16)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func glassCardBorder(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(colorScheme == .dark ? 0.22 : 0.95),
                Color(red: 0.50, green: 0.70, blue: 1.00).opacity(colorScheme == .dark ? 0.24 : 0.34),
                .black.opacity(colorScheme == .dark ? 0.22 : 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func matrixPanelBackground(for colorScheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.black.opacity(0.28),
                    Color(red: 0.04, green: 0.05, blue: 0.09).opacity(0.78),
                    Color(red: 0.12, green: 0.08, blue: 0.24).opacity(0.34)
                ]
                : [
                    Color(red: 0.98, green: 0.99, blue: 1.00).opacity(0.96),
                    Color(red: 0.88, green: 0.93, blue: 0.98).opacity(0.82),
                    Color(red: 0.70, green: 0.78, blue: 1.00).opacity(0.14)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func matrixInactiveDot(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? .white.opacity(0.13)
            : Color(red: 0.52, green: 0.58, blue: 0.68).opacity(0.24)
    }

    static func matrixSelectedDayBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.green.opacity(0.08)
            : Color.green.opacity(0.13)
    }

    static func matrixSelectedDayBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color.green.opacity(0.20)
            : Color.green.opacity(0.38)
    }

    static func matrixPillBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? .white.opacity(0.075)
            : .white.opacity(0.72)
    }
}
