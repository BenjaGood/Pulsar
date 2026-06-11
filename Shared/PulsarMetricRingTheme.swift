import SwiftUI

enum PulsarMetricRingKind {
    case sleep
    case recovery
    case strain
}

enum PulsarMetricRingTheme {
    static func tint(for kind: PulsarMetricRingKind) -> Color {
        switch kind {
        case .sleep:
            return Color(red: 0.56, green: 0.43, blue: 1.00)
        case .recovery:
            return Color(red: 0.45, green: 0.91, blue: 0.42)
        case .strain:
            return Color(red: 1.00, green: 0.62, blue: 0.13)
        }
    }

    static var track: Color {
        Color.white.opacity(0.12)
    }

    static var centerStroke: Color {
        Color.white.opacity(0.12)
    }

    static func progressGradient(tint: Color) -> LinearGradient {
        LinearGradient(
            colors: progressColors(tint: tint),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func progressColors(tint: Color) -> [Color] {
        [
            tint.opacity(0.70),
            tint,
            Color.white.opacity(0.82)
        ]
    }

    static func ringShadow(tint: Color) -> Color {
        tint.opacity(0.22)
    }

    static func cardFill(tint: Color) -> LinearGradient {
        LinearGradient(
            colors: [
                tint.opacity(0.20),
                Color.white.opacity(0.075),
                Color.black.opacity(0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func cardStroke(tint: Color) -> LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.18),
                tint.opacity(0.18),
                Color.black.opacity(0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func cardShadow(tint: Color) -> Color {
        tint.opacity(0.14)
    }
}

enum PulsarStressRingTheme {
    static func tint(for score: Int?) -> Color {
        guard let score else { return Color(red: 0.55, green: 0.62, blue: 0.74) }
        switch PulsarStressCategory.category(for: score) {
        case .low:
            return Color(red: 0.25, green: 0.80, blue: 0.58)
        case .balanced:
            return Color(red: 0.35, green: 0.74, blue: 0.95)
        case .elevated:
            return Color(red: 0.95, green: 0.68, blue: 0.25)
        case .high:
            return Color(red: 1.00, green: 0.40, blue: 0.30)
        }
    }

    static func gradient(for score: Int?) -> [Color] {
        gradient(tint: tint(for: score))
    }

    static func gradient(tint: Color) -> [Color] {
        [Color.white.opacity(0.82), tint, tint.opacity(0.72)]
    }
}
