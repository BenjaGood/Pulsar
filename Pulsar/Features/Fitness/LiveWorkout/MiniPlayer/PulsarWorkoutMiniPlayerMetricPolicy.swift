import Foundation

enum PulsarWorkoutMiniPlayerMetricPolicy {
    static func runMetrics(
        workoutKind: PulsarOutdoorWorkoutKind,
        heartRate: Double?,
        distanceMeters: Double,
        paceText: String?,
        calories: Double?,
        steps: Int?,
        cadence: Double?,
        source: String
    ) -> [PulsarWorkoutMiniPlayerMetric] {
        var available: [PulsarWorkoutMiniPlayerMetric.Kind: PulsarWorkoutMiniPlayerMetric] = [:]
        if let heartRate, heartRate > 0 {
            available[.heartRate] = .init(kind: .heartRate, label: "Heart rate", value: "\(Int(heartRate.rounded())) bpm")
        }
        if distanceMeters > 10 {
            available[.distance] = .init(
                kind: .distance,
                label: "Distance",
                value: PulsarRunFormatters.distance(distanceMeters)
            )
            if let paceText, !paceText.isEmpty {
                available[.pace] = .init(kind: .pace, label: "Pace", value: paceText)
            }
        }
        if let calories, calories > 0 {
            available[.calories] = .init(kind: .calories, label: "Energy", value: "\(Int(calories.rounded())) kcal")
        }
        if let steps, steps > 0 {
            available[.steps] = .init(kind: .steps, label: "Steps", value: steps.formatted())
        }
        if let cadence, cadence > 0 {
            available[.cadence] = .init(kind: .cadence, label: "Cadence", value: "\(Int(cadence.rounded())) spm")
        }
        available[.source] = .init(kind: .source, label: "Source", value: source)

        return priority(for: workoutKind).compactMap { available[$0] }.prefix(2).map { $0 }
    }

    static func gymMetrics(
        exerciseName: String?,
        completedSets: Int,
        totalSets: Int,
        heartRate: Double?
    ) -> [PulsarWorkoutMiniPlayerMetric] {
        var metrics: [PulsarWorkoutMiniPlayerMetric] = []
        if let exerciseName = exerciseName?.trimmingCharacters(in: .whitespacesAndNewlines), !exerciseName.isEmpty {
            metrics.append(.init(kind: .exercise, label: "Exercise", value: exerciseName))
        }
        if totalSets > 0 {
            metrics.append(.init(kind: .set, label: "Sets", value: "\(completedSets)/\(totalSets) sets"))
        }
        if metrics.count < 2, let heartRate, heartRate > 0 {
            metrics.append(.init(kind: .heartRate, label: "Heart rate", value: "\(Int(heartRate.rounded())) bpm"))
        }
        return Array(metrics.prefix(2))
    }

    static func priority(for kind: PulsarOutdoorWorkoutKind) -> [PulsarWorkoutMiniPlayerMetric.Kind] {
        switch kind {
        case .running, .walking, .hiking, .cycling:
            [.heartRate, .distance, .pace, .calories, .source]
        case .indoorRunning, .elliptical, .stairClimber, .rowing:
            [.heartRate, .calories, .cadence, .steps, .source]
        case .hiit, .dance, .boxing:
            [.heartRate, .calories, .steps, .cadence, .source]
        case .strength, .swimming, .yoga, .pilates, .stretching, .core, .mobility, .cooldown:
            [.heartRate, .calories, .source]
        case .other:
            [.heartRate, .calories, .source]
        }
    }
}

