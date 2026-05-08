import Foundation

enum PulsarStressCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case low = "Low"
    case balanced = "Balanced"
    case elevated = "Elevated"
    case high = "High"

    nonisolated var id: String { rawValue }

    nonisolated var displayText: String {
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

    nonisolated var lowerBound: Double {
        switch self {
        case .low:
            return 0
        case .balanced:
            return 25
        case .elevated:
            return 50
        case .high:
            return 75
        }
    }

    nonisolated var upperBound: Double {
        switch self {
        case .low:
            return 25
        case .balanced:
            return 50
        case .elevated:
            return 75
        case .high:
            return 100
        }
    }

    nonisolated static func category(for score: Int) -> PulsarStressCategory {
        category(for: Double(score))
    }

    nonisolated static func category(for score: Double) -> PulsarStressCategory {
        switch PulsarStressScale.clampedScore(score) {
        case 0..<25:
            return .low
        case 25..<50:
            return .balanced
        case 50..<75:
            return .elevated
        default:
            return .high
        }
    }
}

enum PulsarSharedStressMovementState: String, Codable, Equatable, Hashable, Sendable {
    case inactive
    case lightMovement
    case activeMovement
    case workout
    case cooldown
    case unknown

    nonisolated var displayText: String {
        switch self {
        case .inactive:
            return "Inactive"
        case .lightMovement:
            return "Light movement"
        case .activeMovement:
            return "Moving"
        case .workout:
            return "Workout"
        case .cooldown:
            return "Cooldown"
        case .unknown:
            return "Unknown"
        }
    }
}

enum PulsarSharedStressCalculationState: String, Codable, Equatable, Hashable, Sendable {
    case measuring
    case workoutPaused
    case cooldownPaused
    case lowConfidence

    nonisolated var isPaused: Bool {
        self == .workoutPaused || self == .cooldownPaused
    }

    nonisolated var displayText: String {
        switch self {
        case .measuring:
            return "Measuring"
        case .workoutPaused:
            return "Paused during workout"
        case .cooldownPaused:
            return "Cooldown pause"
        case .lowConfidence:
            return "Low confidence"
        }
    }
}

struct PulsarStressBand: Codable, Equatable, Hashable, Identifiable, Sendable {
    nonisolated var id: String { category.rawValue }
    var category: PulsarStressCategory
    var lowerBound: Double
    var upperBound: Double

    nonisolated init(category: PulsarStressCategory) {
        self.category = category
        self.lowerBound = category.lowerBound
        self.upperBound = category.upperBound
    }
}

enum PulsarStressScale {
    nonisolated static let minimumScore = 0.0
    nonisolated static let maximumScore = 100.0
    nonisolated static let lowUpperBound = 25.0
    nonisolated static let balancedUpperBound = 50.0
    nonisolated static let elevatedUpperBound = 75.0
    nonisolated static let highLowerBound = 75.0

    nonisolated static let bands: [PulsarStressBand] = [
        PulsarStressBand(category: .high),
        PulsarStressBand(category: .elevated),
        PulsarStressBand(category: .balanced),
        PulsarStressBand(category: .low)
    ]

    nonisolated static func clampedScore(_ score: Double) -> Double {
        guard score.isFinite else { return minimumScore }
        return min(maximumScore, max(minimumScore, score))
    }

    nonisolated static func roundedScore(_ score: Double) -> Int {
        Int(clampedScore(score).rounded())
    }

    nonisolated static func levelText(for score: Int) -> String {
        PulsarStressCategory.category(for: score).displayText
    }

    nonisolated static func maxContinuousTimelineGap(rangeDuration: TimeInterval) -> TimeInterval {
        min(90 * 60, max(35 * 60, rangeDuration / 10))
    }
}

struct PulsarStressTimelineSample: Codable, Equatable, Hashable, Sendable {
    var timestamp: Date
    var score: Double
}

struct PulsarStressDurationBucket: Identifiable, Equatable, Sendable {
    nonisolated var id: String { category.rawValue }
    var category: PulsarStressCategory
    var duration: TimeInterval
    var totalDuration: TimeInterval

    nonisolated var percentage: Double {
        guard totalDuration > 0 else { return 0 }
        return duration / totalDuration
    }
}

enum PulsarStressTimelineDistribution {
    nonisolated static func buckets(samples: [PulsarStressTimelineSample], range: DateInterval? = nil) -> [PulsarStressDurationBucket] {
        let sorted = samples
            .filter { $0.timestamp.timeIntervalSinceReferenceDate.isFinite && $0.score.isFinite }
            .sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 else {
            return buckets(from: emptyDurations())
        }

        let resolvedRange = range ?? DateInterval(start: sorted[0].timestamp, end: sorted[sorted.count - 1].timestamp)
        let maxGap = PulsarStressScale.maxContinuousTimelineGap(rangeDuration: resolvedRange.duration)
        var durations = emptyDurations()

        for index in 1..<sorted.count {
            let previous = sorted[index - 1]
            let current = sorted[index]
            let duration = current.timestamp.timeIntervalSince(previous.timestamp)
            guard duration > 0, duration <= maxGap else { continue }
            let averageScore = (previous.score + current.score) / 2
            let category = PulsarStressCategory.category(for: averageScore)
            durations[category, default: 0] += duration
        }

        return buckets(from: durations)
    }

    nonisolated static func weightedAverage(samples: [PulsarStressTimelineSample], range: DateInterval? = nil) -> Double? {
        let sorted = samples
            .filter { $0.timestamp.timeIntervalSinceReferenceDate.isFinite && $0.score.isFinite }
            .sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 else { return nil }

        let resolvedRange = range ?? DateInterval(start: sorted[0].timestamp, end: sorted[sorted.count - 1].timestamp)
        let maxGap = PulsarStressScale.maxContinuousTimelineGap(rangeDuration: resolvedRange.duration)
        var weightedTotal = 0.0
        var totalDuration = 0.0

        for index in 1..<sorted.count {
            let previous = sorted[index - 1]
            let current = sorted[index]
            let duration = current.timestamp.timeIntervalSince(previous.timestamp)
            guard duration > 0, duration <= maxGap else { continue }
            weightedTotal += ((previous.score + current.score) / 2) * duration
            totalDuration += duration
        }

        guard totalDuration > 0 else { return nil }
        return weightedTotal / totalDuration
    }

    nonisolated private static func emptyDurations() -> [PulsarStressCategory: TimeInterval] {
        Dictionary(uniqueKeysWithValues: PulsarStressCategory.allCases.map { ($0, 0) })
    }

    nonisolated private static func buckets(from durations: [PulsarStressCategory: TimeInterval]) -> [PulsarStressDurationBucket] {
        let totalDuration = durations.values.reduce(0, +)
        return [.low, .balanced, .elevated, .high].map { category in
            PulsarStressDurationBucket(
                category: category,
                duration: durations[category] ?? 0,
                totalDuration: totalDuration
            )
        }
    }
}
