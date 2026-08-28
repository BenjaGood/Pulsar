//
//  PulsarWatchLiveWorkoutPresentationTests.swift
//  PulsarTests
//

import Testing
@testable import Pulsar

struct PulsarWatchLiveWorkoutPresentationTests {
    @Test func outdoorRunUsesDistancePaceHeartRateAndZone() {
        var snapshot = PulsarRunMetricSnapshot.empty
        snapshot.workoutKind = .running
        snapshot.distanceMeters = 1_250
        snapshot.currentPaceSecondsPerKilometer = 300
        snapshot.currentHeartRate = 148

        let presentation = PulsarWatchLiveWorkoutPresentationBuilder.make(
            snapshot: snapshot,
            heartRateZoneProfile: PulsarLiveHeartRateZoneProfile(maxHeartRate: 185, source: .ageFormula)
        )

        #expect(presentation.title == "Outdoor Run")
        #expect(presentation.metrics.map(\.title) == ["Distance", "Pace", "Heart Rate", "Zone"])
        #expect(presentation.metrics[3].value == "4")
    }

    @Test func indoorRunNeverDuplicatesElapsedTimeInMetricGrid() {
        var snapshot = PulsarRunMetricSnapshot.empty
        snapshot.workoutKind = .indoorRunning
        snapshot.elapsedTime = 600
        snapshot.activeEnergyKilocalories = 81
        snapshot.averageHeartRate = 122
        snapshot.currentHeartRate = 128

        let presentation = PulsarWatchLiveWorkoutPresentationBuilder.make(
            snapshot: snapshot,
            heartRateZoneProfile: PulsarLiveHeartRateZoneProfile(maxHeartRate: 180, source: .ageFormula)
        )

        #expect(presentation.elapsedTimeText == "10:00")
        #expect(presentation.metrics.map(\.title) == ["Calories", "Avg HR", "Heart Rate", "Zone"])
        #expect(!presentation.metrics.contains { $0.title == "Time" })
    }

    @Test func cyclingUsesSpeedAndPausedTimerState() {
        var snapshot = PulsarRunMetricSnapshot.empty
        snapshot.workoutKind = .cycling
        snapshot.phase = .paused
        snapshot.currentPaceSecondsPerKilometer = 180

        let presentation = PulsarWatchLiveWorkoutPresentationBuilder.make(
            snapshot: snapshot,
            heartRateZoneProfile: .init()
        )

        #expect(presentation.metrics.map(\.title) == ["Distance", "Speed", "Heart Rate", "Zone"])
        #expect(presentation.timerState == .paused)
        #expect(presentation.statusText == "Paused")
    }

    @Test func unavailableProfileMakesZoneStateExplicit() {
        var snapshot = PulsarRunMetricSnapshot.empty
        snapshot.workoutKind = .strength
        snapshot.currentHeartRate = 134

        let presentation = PulsarWatchLiveWorkoutPresentationBuilder.make(
            snapshot: snapshot,
            heartRateZoneProfile: .init()
        )

        let zoneMetric = presentation.metrics[3]
        #expect(zoneMetric.value == "--")
        #expect(zoneMetric.detail == "Set max HR")
    }
}
