import SwiftUI

/// Status colors used exclusively by the stress hero card.
///
/// Unlike `stressGaugeTint(for:)`, the hero design requires the "Medium"
/// category to read as amber rather than green so the label color always
/// mirrors its position on the gauge gradient.
enum StressHeroPalette {
    static func statusColor(for score: Int?) -> Color {
        guard let score else {
            return Color(red: 0.56, green: 0.64, blue: 0.76)
        }

        switch PulsarStressCategory.category(for: score) {
        case .low:
            return Color(red: 0.24, green: 0.53, blue: 0.33)
        case .balanced:
            return Color(red: 0.76, green: 0.55, blue: 0.13)
        case .elevated:
            return Color(red: 0.82, green: 0.44, blue: 0.16)
        case .high:
            return Color(red: 0.76, green: 0.28, blue: 0.26)
        }
    }
}
