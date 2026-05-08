//
//  StressVisualStyle.swift
//  Pulsar
//

import SwiftUI

extension StressLevel {
    func stressTint(colorScheme: ColorScheme) -> Color {
        switch self {
        case .low:
            return PulsarStressRingTheme.tint(for: 0)
        case .balanced:
            return PulsarStressRingTheme.tint(for: 25)
        case .elevated:
            return PulsarStressRingTheme.tint(for: 50)
        case .high:
            return PulsarStressRingTheme.tint(for: 75)
        }
    }

    func stressGradientColors(colorScheme: ColorScheme) -> [Color] {
        PulsarStressRingTheme.gradient(tint: stressTint(colorScheme: colorScheme))
    }
}

extension StressSummary {
    var displayLevelText: String {
        if state == .workoutPaused || state == .cooldown {
            return stressStatusText ?? state.displayText
        }
        if let level {
            return level.displayText
        }
        switch state {
        case .buildingBaseline:
            return "Building baseline"
        case .noData:
            return "Not enough data"
        case .ready:
            return "Ready"
        case .lowConfidence:
            return "Low confidence"
        case .workoutPaused:
            return "Paused during workout"
        case .cooldown:
            return "Cooldown pause"
        }
    }

    var displayScoreText: String {
        switch state {
        case .buildingBaseline:
            return "Baseline"
        case .noData:
            return "No data"
        case .workoutPaused, .cooldown:
            return "Paused"
        case .ready, .lowConfidence:
            return score.map(String.init) ?? "No data"
        }
    }

    var stressAccentColor: Color {
        level?.stressTint(colorScheme: .dark) ?? PulsarStressRingTheme.tint(for: nil)
    }
}

private extension StressLevel {
    var displayText: String {
        switch self {
        case .low:
            return "Low"
        case .balanced:
            return "Medium"
        case .elevated:
            return "Elevated"
        case .high:
            return "High"
        }
    }
}

private extension StressSummaryState {
    var displayText: String {
        switch self {
        case .workoutPaused:
            return "Paused during workout"
        case .cooldown:
            return "Cooldown pause"
        case .noData:
            return "Not enough data"
        case .buildingBaseline:
            return "Building baseline"
        case .ready:
            return "Ready"
        case .lowConfidence:
            return "Low confidence"
        }
    }
}
