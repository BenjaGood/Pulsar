//
//  FitnessBodyMapAnalyzerTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct FitnessBodyMapAnalyzerTests {
    @Test func cardioWorkoutsActivateHeartZone() {
        let activities = [
            makeActivity(id: "run-1", displayName: "Running", category: .running, duration: 1_800),
            makeActivity(id: "ride-1", displayName: "Cycling", category: .cycling, duration: 2_400)
        ]

        let analysis = BodyMapAnalyzer.analyze(activities: activities)
        let heart = analysis.trainedZone(for: .heart)

        #expect(analysis.cardioSessions == 2)
        #expect(analysis.cardioDuration == 4_200)
        #expect(heart?.sessions == 2)
        #expect(heart?.intensity == 0.6)
    }

    @Test func nonCardioWorkoutsKeepHeartZoneInactive() {
        let activities = [
            makeActivity(id: "strength-1", displayName: "Strength", category: .strength, duration: 2_700)
        ]

        let analysis = BodyMapAnalyzer.analyze(activities: activities)

        #expect(!analysis.isCardioActive)
        #expect(analysis.trainedZone(for: .heart) == nil)
    }

    @Test func cardioKeywordFallbackHandlesUnknownAerobicNames() {
        let activities = [
            makeActivity(id: "elliptical-1", displayName: "Elliptical", category: .other, duration: 1_500)
        ]

        let analysis = BodyMapAnalyzer.analyze(activities: activities)

        #expect(analysis.cardioSessions == 1)
        #expect(analysis.trainedZone(for: .heart)?.intensity == 0.3)
    }

    private func makeActivity(
        id: String,
        displayName: String,
        category: WeeklyActivityCategory,
        duration: TimeInterval
    ) -> WeeklyActivity {
        WeeklyActivity(
            id: id,
            workoutUUID: nil,
            workoutType: displayName,
            displayName: displayName,
            category: category,
            startDate: .now,
            endDate: .now.addingTimeInterval(duration),
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
