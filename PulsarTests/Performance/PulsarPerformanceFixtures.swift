//
//  PulsarPerformanceFixtures.swift
//  PulsarTests
//

import Foundation
@testable import Pulsar

enum PulsarPerformanceFixtures {
    static func completedGymSessions(count: Int) -> [PulsarGymWorkoutSession] {
        (0..<count).map { index in
            let startedAt = Date(timeIntervalSince1970: 1_700_000_000 - Double(index * 86_400))
            var session = PulsarGymWorkoutSession(
                activeGymState: activeGymState(seed: index, startedAt: startedAt)
            )
            session.finishedAt = startedAt.addingTimeInterval(3_600)
            session.elapsedSeconds = 3_600
            session.activeEnergyKilocalories = 420
            session.averageHeartRate = 132
            session.maxHeartRate = 168
            session.trainedMuscleGroups = [.chest, .back, .quadriceps, .glutes]
            session.muscleLoadByGroup = [
                PulsarMuscleGroup.chest.rawValue: 18,
                PulsarMuscleGroup.back.rawValue: 16,
                PulsarMuscleGroup.quadriceps.rawValue: 14,
                PulsarMuscleGroup.glutes.rawValue: 12
            ]
            return session
        }
    }

    static func activeGymState(
        seed: Int = 0,
        startedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        exerciseCount: Int = 6,
        setsPerExercise: Int = 4
    ) -> ActiveGymWorkoutState {
        let exercises = (0..<exerciseCount).map { exerciseIndex in
            let sets = (0..<setsPerExercise).map { setIndex in
                ActiveGymWorkoutSetState(
                    id: uuid(seed * 1_000 + exerciseIndex * 10 + setIndex + 100),
                    setNumber: setIndex + 1,
                    targetReps: 8 + setIndex,
                    targetWeight: 60 + Double(exerciseIndex * 5),
                    completedReps: setIndex < 2 ? 8 + setIndex : nil,
                    completedWeight: setIndex < 2 ? 60 + Double(exerciseIndex * 5) : nil,
                    isCompleted: setIndex < 2,
                    completedAt: setIndex < 2
                        ? startedAt.addingTimeInterval(Double((exerciseIndex * setsPerExercise + setIndex + 1) * 90))
                        : nil
                )
            }

            return ActiveGymWorkoutExerciseState(
                id: uuid(seed * 1_000 + exerciseIndex + 10),
                exerciseId: "fixture-exercise-\(exerciseIndex)",
                exerciseName: "Fixture Exercise \(exerciseIndex + 1)",
                muscleGroup: exerciseIndex.isMultiple(of: 2) ? "Chest" : "Back",
                equipment: exerciseIndex.isMultiple(of: 2) ? "Barbell" : "Cable",
                plannedSets: setsPerExercise,
                plannedReps: 10,
                plannedWeight: 60 + Double(exerciseIndex * 5),
                weightUnit: PulsarWeightUnit.kilograms.rawValue,
                plannedRestSeconds: 90,
                orderIndex: exerciseIndex,
                notes: "Deterministic performance fixture notes",
                thumbnailURL: "https://example.invalid/exercise-\(exerciseIndex).jpg",
                instructionsPreview: "Use a controlled tempo and full range of motion.",
                sets: sets
            )
        }

        return ActiveGymWorkoutState(
            sessionId: uuid(seed + 1),
            routineId: uuid(seed + 2),
            routineName: "Performance Fixture",
            routineEmoji: "🏋️",
            workoutKind: .routine,
            startedFrom: .iPhone,
            startedAt: startedAt,
            elapsedSeconds: 1_800,
            currentExerciseIndex: min(2, max(exercises.count - 1, 0)),
            currentSetIndex: 2,
            totalExercises: exercises.count,
            totalSets: exercises.reduce(0) { $0 + $1.sets.count },
            completedSets: exercises.reduce(0) { $0 + $1.completedSetCount },
            currentHeartRate: 138,
            averageHeartRate: 132,
            maxHeartRate: 168,
            activeEnergyKilocalories: 420,
            restRemainingSeconds: 45,
            restTotalSeconds: 90,
            isHealthKitEnabled: true,
            healthKitStatusMessage: nil,
            isFinished: false,
            updatedAt: startedAt.addingTimeInterval(1_800),
            exercises: exercises
        )
    }

    static func exerciseCatalogData(count: Int = 1_324) throws -> Data {
        let exercises: [[String: Any]] = (0..<count).map { index in
            [
                "id": String(format: "%04d", index + 1),
                "name": "performance fixture exercise \(index + 1)",
                "category": index.isMultiple(of: 2) ? "chest" : "back",
                "body_part": index.isMultiple(of: 2) ? "chest" : "back",
                "equipment": index.isMultiple(of: 3) ? "barbell" : "cable",
                "instructions": [
                    "en": "Use a controlled tempo and full range of motion."
                ],
                "instruction_steps": [
                    "en": [
                        "Set up with stable posture.",
                        "Complete the repetition with control.",
                        "Return to the starting position."
                    ]
                ],
                "muscle_group": index.isMultiple(of: 2) ? "chest" : "back",
                "secondary_muscles": ["triceps", "shoulders"],
                "target": index.isMultiple(of: 2) ? "pectorals" : "lats",
                "image": "images/fixture-\(index).jpg",
                "gif_url": "videos/fixture-\(index).gif",
                "created_at": "2026-07-12T12:00:00Z"
            ]
        }
        return try JSONSerialization.data(withJSONObject: exercises, options: [.sortedKeys])
    }

    private static func uuid(_ value: Int) -> UUID {
        let normalized = abs(value) % 1_000_000_000
        return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", normalized))!
    }
}
