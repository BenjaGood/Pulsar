//
//  GymFreeWorkoutTelemetry.swift
//  Pulsar
//

import Foundation

enum GymFreeWorkoutTelemetry {
    static let title = PulsarGymWorkoutKind.freeWorkout.displayName
    static let mirroredSubtitle = "Live workout mirrored from Apple Watch"

    static func usesDedicatedPresentation(_ state: ActiveGymWorkoutState) -> Bool {
        state.workoutKind == .freeWorkout
    }

    static func elapsedSeconds(for state: ActiveGymWorkoutState, at date: Date) -> Int {
        guard !state.isFinished else { return state.elapsedSeconds }
        return max(state.elapsedSeconds, Int(date.timeIntervalSince(state.startedAt)))
    }

    static func caloriesText(_ kilocalories: Double?) -> String {
        guard let kilocalories, kilocalories.isFinite, kilocalories >= 0 else { return "--" }
        return "\(Int(kilocalories.rounded()))"
    }

    /// HealthKit fallback chrome must never infer Free Workout from empty exercises.
    /// An explicit kind on the matching gym placeholder always wins. The in-flight
    /// start transaction may identify Free Workout only when that kind is still unknown.
    static func resolvedFallbackWorkoutKind(
        placeholderKind: PulsarGymWorkoutKind?,
        startTransactionWorkoutType: String?
    ) -> PulsarGymWorkoutKind {
        if let placeholderKind {
            return placeholderKind
        }
        if startTransactionWorkoutType == PulsarGymWorkoutKind.freeWorkout.rawValue {
            return .freeWorkout
        }
        return .routine
    }
}
