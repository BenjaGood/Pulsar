//
//  MuscleTrainingAnalyticsServiceTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct MuscleTrainingAnalyticsServiceTests {
    @Test func primaryAndSecondaryMusclesContributeWeightedTrainingLoad() {
        let primary = PulsarMuscle(name: "Lats", englishName: "lats", group: .lats)
        let secondary = PulsarMuscle(name: "Biceps", englishName: "biceps", group: .biceps)
        let exercise = PulsarExercise(
            id: "free-exercise-db-test-row",
            wgerID: nil,
            wgerUUID: nil,
            name: "Seated Cable Row",
            instructions: nil,
            primaryMuscles: [primary],
            secondaryMuscles: [secondary],
            primaryMuscleGroup: .lats,
            equipment: [PulsarEquipment(name: "Cable")],
            imageURLs: [],
            thumbnailURL: nil,
            attribution: .freeExerciseDB(sourceExerciseID: "Seated_Cable_Rows"),
            category: "Strength",
            level: "Beginner",
            force: "Pull",
            mechanic: "Compound"
        )
        let routine = PulsarRoutine(
            name: "Pull Day",
            exercises: [PulsarRoutineExercise(exercise: exercise, order: 0, plannedSets: 4)]
        )
        var session = PulsarGymWorkoutSession(routine: routine)
        session.exercises[0].sets = session.exercises[0].sets.map { set in
            var completedSet = set
            completedSet.isCompleted = true
            return completedSet
        }

        let summary = MuscleTrainingAnalyticsService.summary(for: session)

        #expect(summary.loadByGroup[.lats] == 4)
        #expect(summary.loadByGroup[.biceps] == 2)
        #expect(summary.loadByMatrixGroup[.back] == 4)
        #expect(summary.loadByMatrixGroup[.biceps] == 2)
    }
}
