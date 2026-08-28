//
//  NutritionWorkoutTypeMapper.swift
//  Pulsar
//

import Foundation
import HealthKit

enum NutritionWorkoutTypeMapper {
    static func normalizedType(for workout: WorkoutLoadInput) -> NutritionWorkoutType {
        let normalized = workout.type.lowercased()
        if normalized.contains("gym") || normalized.contains("strength") || normalized.contains("weight") {
            return .gymStrength
        }
        if normalized.contains("cycle") || normalized.contains("bike") {
            return .cycling
        }
        if normalized.contains("run") {
            return .running
        }
        if normalized.contains("walk") {
            return .walking
        }
        if normalized.contains("hike") {
            return .hiking
        }
        if normalized.contains("swim") {
            return .swimming
        }
        if normalized.contains("row") {
            return .rowing
        }
        if normalized.contains("hiit") || normalized.contains("circuit") {
            return .hiitCircuit
        }
        if normalized.contains("soccer") || normalized.contains("basketball") || normalized.contains("football")
            || normalized.contains("hockey") || normalized.contains("sport") {
            return .teamSport
        }
        if normalized.contains("yoga") || normalized.contains("pilates") || normalized.contains("mobility") {
            return .yogaMobility
        }
        return .mixedOther
    }

    static func deduplicatedWorkouts(_ workouts: [WorkoutLoadInput]) -> [WorkoutLoadInput] {
        var kept: [WorkoutLoadInput] = []
        for workout in workouts.sorted(by: { $0.start < $1.start }) {
            if let duplicateIndex = kept.firstIndex(where: { overlaps($0, workout) }) {
                let existing = kept[duplicateIndex]
                kept[duplicateIndex] = preferredWorkout(existing, workout)
            } else {
                kept.append(workout)
            }
        }
        return kept
    }

    static func observedIntensity(
        for workouts: [WorkoutLoadInput],
        age: Int
    ) -> NutritionWorkoutIntensity? {
        let heartRates = workouts.flatMap(\.heartRateSamples).map(\.bpm).filter { $0 > 0 }
        guard heartRates.count >= 6 else { return nil }
        let median = NutritionHealthKitCalibration.winsorizedMedian(heartRates) ?? 0
        let maxHR = Double(220 - age)
        guard maxHR > 0 else { return nil }
        let fraction = median / maxHR
        switch fraction {
        case ..<0.55: return .light
        case ..<0.75: return .moderate
        default: return .vigorous
        }
    }

    private static func overlaps(_ lhs: WorkoutLoadInput, _ rhs: WorkoutLoadInput) -> Bool {
        let start = max(lhs.start, rhs.start)
        let end = min(lhs.end, rhs.end)
        guard end > start else { return false }
        let overlap = end.timeIntervalSince(start)
        let shorter = min(lhs.end.timeIntervalSince(lhs.start), rhs.end.timeIntervalSince(rhs.start))
        guard shorter > 0 else { return false }
        return overlap / shorter >= 0.80
    }

    private static func preferredWorkout(_ lhs: WorkoutLoadInput, _ rhs: WorkoutLoadInput) -> WorkoutLoadInput {
        score(lhs) >= score(rhs) ? lhs : rhs
    }

    private static func score(_ workout: WorkoutLoadInput) -> Int {
        var value = 0
        if workout.provenance.sourceName.localizedCaseInsensitiveContains("pulsar") { value += 4 }
        if !workout.heartRateSamples.isEmpty { value += 2 }
        if workout.activeEnergyKilocalories != nil { value += 1 }
        if workout.distanceMeters != nil { value += 1 }
        return value
    }
}

struct NutritionObservedWorkoutAggregate: Codable, Equatable, Hashable {
    var workoutType: NutritionWorkoutType
    var averageSessionsPerWeek: Double
    var medianMinutesPerSession: Double
    var observedIntensity: NutritionWorkoutIntensity?
    var weeklyEnergyKilocalories: Double
}

extension NutritionWorkoutTypeMapper {
    static func observedAggregates(
        workouts: [WorkoutLoadInput],
        windowDays: Int,
        age: Int
    ) -> [NutritionObservedWorkoutAggregate] {
        let deduplicated = deduplicatedWorkouts(workouts)
        let grouped = Dictionary(grouping: deduplicated) { normalizedType(for: $0) }
        let weeks = max(Double(windowDays) / 7, 1)
        return grouped.map { type, items in
            let durations = items.map(\.durationMinutes).sorted()
            let medianMinutes: Double
            if durations.isEmpty {
                medianMinutes = 0
            } else if durations.count.isMultiple(of: 2) {
                medianMinutes = (durations[durations.count / 2 - 1] + durations[durations.count / 2]) / 2
            } else {
                medianMinutes = durations[durations.count / 2]
            }
            let weeklyEnergy = items.reduce(0) { $0 + ($1.activeEnergyKilocalories ?? 0) } / weeks
            return NutritionObservedWorkoutAggregate(
                workoutType: type,
                averageSessionsPerWeek: Double(items.count) / weeks,
                medianMinutesPerSession: medianMinutes,
                observedIntensity: observedIntensity(for: items, age: age),
                weeklyEnergyKilocalories: weeklyEnergy
            )
        }
        .sorted { $0.workoutType.title < $1.workoutType.title }
    }

    static func suggestedPlanEntries(from aggregates: [NutritionObservedWorkoutAggregate]) -> [NutritionWorkoutPlanEntry] {
        aggregates.compactMap { aggregate in
            guard aggregate.averageSessionsPerWeek >= 0.5 else { return nil }
            let sessions = max(1, Int(aggregate.averageSessionsPerWeek.rounded()))
            let minutes = max(5, Int((aggregate.medianMinutesPerSession / 5).rounded() * 5))
            return NutritionWorkoutPlanEntry(
                workoutType: aggregate.workoutType,
                daysPerWeek: min(sessions, 7),
                sessionsPerDay: 1,
                minutesPerSession: min(minutes, 300),
                intensity: aggregate.observedIntensity ?? .moderate
            )
        }
    }
}
