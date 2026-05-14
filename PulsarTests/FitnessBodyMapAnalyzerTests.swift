//
//  FitnessBodyMapAnalyzerTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct FitnessCardioMatrixRegressionTests {
    @Test func cardioWorkoutsActivateCardioMatrixRow() {
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let week = FitnessWeekCalculator.getWeekPeriod(for: start, calendar: calendar, now: start, hasWorkout: true)
        let activities = [
            makeActivity(id: "run-1", displayName: "Running", category: .running, startDate: start, duration: 1_800),
            makeActivity(id: "ride-1", displayName: "Cycling", category: .cycling, startDate: start, duration: 2_400)
        ]

        let viewModel = MuscleMatrixViewModel(week: week, activities: activities, calendar: calendar, now: start)
        let cardioCell = viewModel.cell(for: .cardio, day: TrainingDay(date: start, calendar: calendar))

        #expect(viewModel.weeklySummary.totalSessions == 2)
        #expect(viewModel.weeklySummary.totalCardioMinutes == 70)
        #expect(cardioCell.exercises.count == 2)
        #expect(cardioCell.minutes == 70)
        #expect(cardioCell.intensity == .high)
    }

    @Test func nonCardioWorkoutsKeepCardioRowInactive() {
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let week = FitnessWeekCalculator.getWeekPeriod(for: start, calendar: calendar, now: start, hasWorkout: true)
        let activities = [
            makeActivity(id: "strength-1", displayName: "Strength", category: .strength, startDate: start, duration: 2_700)
        ]

        let viewModel = MuscleMatrixViewModel(week: week, activities: activities, calendar: calendar, now: start)
        let cardioCell = viewModel.cell(for: .cardio, day: TrainingDay(date: start, calendar: calendar))

        #expect(viewModel.weeklySummary.totalCardioMinutes == 0)
        #expect(!cardioCell.isActive)
    }

    @Test func cardioKeywordFallbackHandlesUnknownAerobicNames() {
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let week = FitnessWeekCalculator.getWeekPeriod(for: start, calendar: calendar, now: start, hasWorkout: true)
        let activities = [
            makeActivity(id: "elliptical-1", displayName: "Elliptical", category: .other, startDate: start, duration: 1_500)
        ]

        let viewModel = MuscleMatrixViewModel(week: week, activities: activities, calendar: calendar, now: start)
        let cardioCell = viewModel.cell(for: .cardio, day: TrainingDay(date: start, calendar: calendar))

        #expect(viewModel.weeklySummary.totalSessions == 1)
        #expect(viewModel.weeklySummary.totalCardioMinutes == 25)
        #expect(cardioCell.intensity == .medium)
    }

    private func makeActivity(
        id: String,
        displayName: String,
        category: WeeklyActivityCategory,
        startDate: Date,
        duration: TimeInterval
    ) -> WeeklyActivity {
        WeeklyActivity(
            id: id,
            workoutUUID: nil,
            workoutType: displayName,
            displayName: displayName,
            category: category,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(duration),
            duration: duration,
            calories: nil,
            distanceMeters: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            source: .healthKit,
            sourceName: "Test"
        )
    }
}
