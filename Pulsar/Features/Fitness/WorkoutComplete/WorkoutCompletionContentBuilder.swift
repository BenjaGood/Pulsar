//
//  WorkoutCompletionContentBuilder.swift
//  Pulsar
//

import SwiftUI

enum WorkoutMetricLayout: Equatable {
    case halfWidth
    case fullWidth
}

struct WorkoutSummaryMetric: Identifiable {
    let id: String
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    let layout: WorkoutMetricLayout
    let accessibilityValue: String
}

enum WorkoutCompletionContentBuilder {
    static func metrics(for summary: PulsarGymWorkoutSummary) -> [WorkoutSummaryMetric] {
        var metrics: [WorkoutSummaryMetric] = [
            WorkoutSummaryMetric(
                id: "duration",
                title: "Duration",
                value: summary.durationSeconds.formattedGymDuration,
                systemImage: "clock.fill",
                tint: Color(red: 0.62, green: 1.0, blue: 0.68),
                layout: .halfWidth,
                accessibilityValue: summary.durationSeconds.formattedGymDuration
            ),
            WorkoutSummaryMetric(
                id: "exercises",
                title: "Exercises",
                value: "\(summary.exercisesCompleted)/\(summary.totalExercises)",
                systemImage: "dumbbell.fill",
                tint: Color(red: 0.48, green: 0.68, blue: 1.0),
                layout: .halfWidth,
                accessibilityValue: "\(summary.exercisesCompleted) of \(summary.totalExercises)"
            ),
            WorkoutSummaryMetric(
                id: "sets",
                title: "Sets",
                value: "\(summary.setsCompleted)/\(summary.totalSets)",
                systemImage: "list.number",
                tint: Color(red: 0.73, green: 0.48, blue: 1.0),
                layout: .halfWidth,
                accessibilityValue: "\(summary.setsCompleted) of \(summary.totalSets)"
            ),
            WorkoutSummaryMetric(
                id: "volume",
                title: "Volume",
                value: "\(summary.totalVolume.formattedGymDecimal) \(summary.weightUnit.displayName)",
                systemImage: "drop.fill",
                tint: Color(red: 0.45, green: 0.88, blue: 1.0),
                layout: .halfWidth,
                accessibilityValue: "\(summary.totalVolume.formattedGymDecimal) \(summary.weightUnit.displayName)"
            )
        ]

        if summary.averageHeartRate != nil || summary.maxHeartRate != nil {
            metrics.append(
                WorkoutSummaryMetric(
                    id: "average-heart-rate",
                    title: "Avg HR",
                    value: summary.averageHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "--",
                    systemImage: "heart.fill",
                    tint: Color(red: 1.0, green: 0.36, blue: 0.44),
                    layout: .halfWidth,
                    accessibilityValue: summary.averageHeartRate.map { "\(Int($0.rounded())) beats per minute" } ?? "Unavailable"
                )
            )
            metrics.append(
                WorkoutSummaryMetric(
                    id: "maximum-heart-rate",
                    title: "Max HR",
                    value: summary.maxHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "--",
                    systemImage: "bolt.heart.fill",
                    tint: Color(red: 1.0, green: 0.36, blue: 0.44),
                    layout: .halfWidth,
                    accessibilityValue: summary.maxHeartRate.map { "\(Int($0.rounded())) beats per minute" } ?? "Unavailable"
                )
            )
        }

        metrics.append(
            WorkoutSummaryMetric(
                id: "active-calories",
                title: "Active Calories",
                value: summary.activeEnergyKilocalories.map { "\(Int($0.rounded())) kcal" } ?? "--",
                systemImage: "flame.fill",
                tint: Color(red: 1.0, green: 0.65, blue: 0.28),
                layout: .fullWidth,
                accessibilityValue: summary.activeEnergyKilocalories.map { "\(Int($0.rounded())) kilocalories" } ?? "Unavailable"
            )
        )

        return metrics
    }

    static func metrics(for summary: PulsarRunSummary) -> [WorkoutSummaryMetric] {
        var metrics: [WorkoutSummaryMetric] = [
            WorkoutSummaryMetric(
                id: "duration",
                title: "Duration",
                value: PulsarRunFormatters.duration(summary.elapsedTime),
                systemImage: "clock.fill",
                tint: Color(red: 0.62, green: 1.0, blue: 0.68),
                layout: .halfWidth,
                accessibilityValue: PulsarRunFormatters.duration(summary.elapsedTime)
            )
        ]

        if summary.workoutKind.isOutdoorDistanceWorkout || summary.distanceMeters > 10 {
            metrics.append(
                WorkoutSummaryMetric(
                    id: "distance",
                    title: "Distance",
                    value: PulsarRunFormatters.distance(summary.distanceMeters),
                    systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                    tint: summary.workoutKind.accentColor,
                    layout: .halfWidth,
                    accessibilityValue: PulsarRunFormatters.distance(summary.distanceMeters)
                )
            )
            metrics.append(
                WorkoutSummaryMetric(
                    id: "average-pace-speed",
                    title: PulsarRunFormatters.paceOrSpeedTitle(for: summary.workoutKind, average: true),
                    value: PulsarRunFormatters.paceOrSpeed(
                        workoutKind: summary.workoutKind,
                        paceSecondsPerKilometer: summary.averagePaceSecondsPerKilometer,
                        speedMetersPerSecond: summary.averageSpeedMetersPerSecond
                    ),
                    systemImage: "speedometer",
                    tint: Color(red: 0.48, green: 0.68, blue: 1.0),
                    layout: .halfWidth,
                    accessibilityValue: PulsarRunFormatters.paceOrSpeed(
                        workoutKind: summary.workoutKind,
                        paceSecondsPerKilometer: summary.averagePaceSecondsPerKilometer,
                        speedMetersPerSecond: summary.averageSpeedMetersPerSecond
                    )
                )
            )
        }

        if summary.averageHeartRate != nil {
            metrics.append(
                WorkoutSummaryMetric(
                    id: "average-heart-rate",
                    title: "Avg HR",
                    value: "\(PulsarRunFormatters.heartRate(summary.averageHeartRate)) bpm",
                    systemImage: "heart.fill",
                    tint: Color(red: 1.0, green: 0.36, blue: 0.44),
                    layout: .halfWidth,
                    accessibilityValue: "\(PulsarRunFormatters.heartRate(summary.averageHeartRate)) beats per minute"
                )
            )
        }

        if summary.maxHeartRate != nil {
            metrics.append(
                WorkoutSummaryMetric(
                    id: "maximum-heart-rate",
                    title: "Max HR",
                    value: "\(PulsarRunFormatters.heartRate(summary.maxHeartRate)) bpm",
                    systemImage: "bolt.heart.fill",
                    tint: Color(red: 1.0, green: 0.36, blue: 0.44),
                    layout: .halfWidth,
                    accessibilityValue: "\(PulsarRunFormatters.heartRate(summary.maxHeartRate)) beats per minute"
                )
            )
        }

        metrics.append(
            WorkoutSummaryMetric(
                id: "active-calories",
                title: "Active Calories",
                value: "\(PulsarRunFormatters.calories(summary.activeEnergyKilocalories)) kcal",
                systemImage: "flame.fill",
                tint: Color(red: 1.0, green: 0.65, blue: 0.28),
                layout: .fullWidth,
                accessibilityValue: "\(PulsarRunFormatters.calories(summary.activeEnergyKilocalories)) kilocalories"
            )
        )

        return metrics
    }
}
