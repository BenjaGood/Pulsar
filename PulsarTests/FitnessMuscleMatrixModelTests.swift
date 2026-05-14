//
//  FitnessMuscleMatrixModelTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct FitnessMuscleMatrixModelTests {
    @Test func cardioActivitiesPopulateCardioRowByDuration() {
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let week = FitnessWeekCalculator.getWeekPeriod(for: start, calendar: calendar, now: start, hasWorkout: true)
        let activity = WeeklyActivity(
            id: "run",
            workoutUUID: nil,
            workoutType: "Running",
            displayName: "Morning Run",
            category: .running,
            startDate: start,
            endDate: start.addingTimeInterval(2_400),
            duration: 2_400,
            calories: nil,
            distanceMeters: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            source: .healthKit,
            sourceName: "Test"
        )

        let viewModel = MuscleMatrixViewModel(week: week, activities: [activity], calendar: calendar, now: start)
        let cardioCell = viewModel.cell(for: .cardio, day: TrainingDay(date: start, calendar: calendar))

        #expect(cardioCell.minutes == 40)
        #expect(cardioCell.intensity == .high)
        #expect(viewModel.weeklySummary.totalSessions == 1)
        #expect(viewModel.weeklySummary.totalCardioMinutes == 40)
        #expect(viewModel.weeklySummary.focusArea == "Cardio dominant")
        #expect(viewModel.weeklySummary.insight == "Cardio dominated this week. Add strength work for a more balanced training load.")
        #expect(viewModel.state.totalCardioMinutes == 40)
    }

    @Test func emptyHistoryDoesNotUseDemoData() {
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let week = FitnessWeekCalculator.getWeekPeriod(for: start, calendar: calendar, now: start)

        let viewModel = MuscleMatrixViewModel(week: week, activities: [], calendar: calendar, now: start)

        #expect(!viewModel.isUsingDemoData)
        #expect(viewModel.cells.allSatisfy { !$0.isActive })
        #expect(viewModel.weeklySummary.totalSessions == 0)
        #expect(viewModel.weeklySummary.totalSets == 0)
        #expect(viewModel.weeklySummary.totalCardioMinutes == 0)
    }

    @Test func pushDominantWeekGeneratesDynamicInsight() {
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let week = FitnessWeekCalculator.getWeekPeriod(for: start, calendar: calendar, now: start, hasWorkout: true)
        let activity = WeeklyActivity(
            id: "push",
            workoutUUID: nil,
            workoutType: "Gym",
            displayName: "Push Day",
            category: .gym,
            startDate: start,
            endDate: start.addingTimeInterval(3_000),
            duration: 3_000,
            calories: nil,
            distanceMeters: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            source: .localGym,
            sourceName: "Test",
            completedSets: 6,
            totalSets: 6,
            mainMuscleGroups: ["Chest", "Shoulders"],
            muscleLoadByMatrixGroup: [.chest: 3, .shoulders: 2, .triceps: 1],
            muscleExercisesByMatrixGroup: [.chest: ["Bench Press"], .shoulders: ["Shoulder Press"]]
        )

        let viewModel = MuscleMatrixViewModel(week: week, activities: [activity], calendar: calendar, now: start)

        #expect(viewModel.weeklySummary.dominantFocus == .pushDominant)
        #expect(viewModel.weeklySummary.insight.contains("Push muscles are leading"))
        #expect(viewModel.weeklySummary.topAreas.first == "Chest")
        #expect(viewModel.weeklySummary.undertrainedAreas.contains("Core"))
    }
}
