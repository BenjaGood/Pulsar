//
//  MuscleFocusMapPreviewData.swift
//  Pulsar
//

#if DEBUG
import Foundation

extension MuscleMatrixViewModel {
    static let previewUpperBody: MuscleMatrixViewModel = {
        preview(
            id: "muscle-focus-map-upper",
            name: "Upper Body Strength",
            loads: [.chest: 6, .back: 5, .shoulders: 4, .biceps: 3, .triceps: 2, .core: 2],
            exercises: [
                .chest: ["Bench Press"],
                .back: ["Lat Pulldown"],
                .shoulders: ["Overhead Press"],
                .biceps: ["Cable Curl"]
            ]
        )
    }()

    static let previewLowerBody: MuscleMatrixViewModel = {
        preview(
            id: "muscle-focus-map-lower",
            name: "Lower Body Strength",
            loads: [.quads: 7, .glutes: 6, .hamstrings: 5, .calves: 3, .core: 2],
            exercises: [
                .quads: ["Leg Press"],
                .glutes: ["Hip Thrust"],
                .hamstrings: ["Romanian Deadlift"]
            ]
        )
    }()

    static let previewFullBody: MuscleMatrixViewModel = {
        preview(
            id: "muscle-focus-map-full",
            name: "Full Body Strength",
            loads: [
                .chest: 5, .back: 5, .shoulders: 4, .biceps: 3, .triceps: 3,
                .core: 3, .quads: 4, .glutes: 4, .hamstrings: 3, .calves: 2
            ],
            exercises: [
                .chest: ["Bench Press"],
                .back: ["Pull-Up"],
                .quads: ["Squat"]
            ]
        )
    }()

    static let previewCardioActive: MuscleMatrixViewModel = {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date.now
        let week = FitnessWeekCalculator.getWeekPeriod(for: now, calendar: calendar, now: now, hasWorkout: true)
        let strength = WeeklyActivity(
            id: "muscle-focus-map-cardio-strength",
            workoutUUID: nil,
            workoutType: "Gym",
            displayName: "Upper Body",
            category: .gym,
            startDate: now.addingTimeInterval(-4_800),
            endDate: now.addingTimeInterval(-1_200),
            duration: 3_600,
            calories: 320,
            distanceMeters: nil,
            averageHeartRate: 128,
            maxHeartRate: 152,
            source: .localGym,
            sourceName: "Pulsar Preview",
            completedSets: 10,
            totalSets: 10,
            mainMuscleGroups: ["Chest", "Delts"],
            muscleLoadByMatrixGroup: [.chest: 4, .shoulders: 3],
            muscleExercisesByMatrixGroup: [:]
        )
        let cardio = WeeklyActivity(
            id: "muscle-focus-map-cardio-run",
            workoutUUID: nil,
            workoutType: "Running",
            displayName: "Running",
            category: .running,
            startDate: now,
            endDate: now.addingTimeInterval(2_400),
            duration: 2_400,
            calories: 280,
            distanceMeters: 5_200,
            averageHeartRate: 154,
            maxHeartRate: 172,
            source: .healthKit,
            sourceName: "Pulsar Preview",
            completedSets: nil,
            totalSets: nil,
            mainMuscleGroups: [],
            muscleLoadByMatrixGroup: [:],
            muscleExercisesByMatrixGroup: [:]
        )
        return MuscleMatrixViewModel(
            week: week,
            activities: [strength, cardio],
            calendar: calendar,
            now: now
        )
    }()

    static let previewNoMuscles: MuscleMatrixViewModel = {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date.now
        let week = FitnessWeekCalculator.getWeekPeriod(for: now, calendar: calendar, now: now)
        return MuscleMatrixViewModel(week: week, activities: [], calendar: calendar, now: now)
    }()

    static let previewPushBalanced: MuscleMatrixViewModel = previewUpperBody

    private static func preview(
        id: String,
        name: String,
        loads: [MuscleMatrixGroup: Double],
        exercises: [MuscleMatrixGroup: [String]]
    ) -> MuscleMatrixViewModel {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date.now
        let week = FitnessWeekCalculator.getWeekPeriod(for: now, calendar: calendar, now: now, hasWorkout: true)
        let activity = WeeklyActivity(
            id: id,
            workoutUUID: nil,
            workoutType: "Gym",
            displayName: name,
            category: .gym,
            startDate: now,
            endDate: now.addingTimeInterval(3_600),
            duration: 3_600,
            calories: 420,
            distanceMeters: nil,
            averageHeartRate: 132,
            maxHeartRate: 158,
            source: .localGym,
            sourceName: "Pulsar Preview",
            completedSets: loads.values.reduce(0, +).roundedInt,
            totalSets: loads.values.reduce(0, +).roundedInt,
            mainMuscleGroups: loads.keys.map(\.displayName),
            muscleLoadByMatrixGroup: loads,
            muscleExercisesByMatrixGroup: exercises
        )
        return MuscleMatrixViewModel(week: week, activities: [activity], calendar: calendar, now: now)
    }
}

private extension Double {
    var roundedInt: Int {
        Int(rounded(.toNearestOrAwayFromZero))
    }
}
#endif
