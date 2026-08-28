//
//  MuscleFocusMapPresentationTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct MuscleFocusMapPresentationTests {
    @Test func mapUsesExistingWeeklyMuscleLoadsForFocusAndIntensity() {
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let week = FitnessWeekCalculator.getWeekPeriod(for: start, calendar: calendar, now: start, hasWorkout: true)
        let activity = WeeklyActivity(
            id: "balanced-strength",
            workoutUUID: nil,
            workoutType: "Gym",
            displayName: "Balanced Strength",
            category: .gym,
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            duration: 3_600,
            calories: nil,
            distanceMeters: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            source: .localGym,
            sourceName: "Test",
            completedSets: 17,
            totalSets: 17,
            mainMuscleGroups: ["Chest", "Back", "Quadriceps", "Core"],
            muscleLoadByMatrixGroup: [.chest: 6, .back: 5, .quads: 4, .core: 2],
            muscleExercisesByMatrixGroup: [:]
        )

        let matrix = MuscleMatrixViewModel(week: week, activities: [activity], calendar: calendar, now: start)
        let presentation = MuscleFocusMapPresentation(viewModel: matrix)

        #expect(presentation.hasTrainingData)
        #expect(presentation.entry(for: .chest).intensity == .high)
        #expect(presentation.entry(for: .back).intensity == .medium)
        #expect(presentation.entry(for: .cardio).intensity == .none)
        #expect(presentation.primaryFocus.map(\.muscleGroup) == [.chest, .back, .quads, .core])
        #expect(presentation.balanceScore == 67)
        #expect(presentation.balanceLabel == "Building")
        #expect(presentation.overallIntensity == .high)
    }

    @Test func mapUsesAQuietEmptyStateWithoutDemoHighlights() {
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let week = FitnessWeekCalculator.getWeekPeriod(for: start, calendar: calendar, now: start)
        let matrix = MuscleMatrixViewModel(week: week, activities: [], calendar: calendar, now: start)
        let presentation = MuscleFocusMapPresentation(viewModel: matrix)

        #expect(!presentation.hasTrainingData)
        #expect(presentation.primaryFocus.isEmpty)
        #expect(presentation.balanceScore == 0)
        #expect(presentation.balanceLabel == "Ready")
        #expect(presentation.overallIntensity == .none)
        #expect(presentation.entries.allSatisfy { !$0.isActive })
    }
}
