//
//  PulsarRunDerivedMetricsTests.swift
//  PulsarTests
//

import Testing
import HealthKit
@testable import Pulsar

struct PulsarRunDerivedMetricsTests {
    @Test func durationFormatterDistinguishesHours() {
        #expect(PulsarRunFormatters.duration(65) == "01:05")
        #expect(PulsarRunFormatters.duration(3_725) == "1:02:05")
    }

    @Test func paceFormatterUsesKilometerPace() {
        #expect(PulsarRunFormatters.pace(301) == "5:01 /km")
        #expect(PulsarRunFormatters.pace(nil) == "--")
    }

    @Test func autoPauseIgnoresPoorAccuracy() {
        #expect(PulsarRunDerivedMetrics.shouldAutoPause(speedMetersPerSecond: 0.2, horizontalAccuracy: 12))
        #expect(!PulsarRunDerivedMetrics.shouldAutoPause(speedMetersPerSecond: 0.2, horizontalAccuracy: 80))
        #expect(!PulsarRunDerivedMetrics.shouldAutoPause(speedMetersPerSecond: 1.4, horizontalAccuracy: 12))
    }

    @Test func elevationGainRequiresMeaningfulPositiveChange() {
        #expect(PulsarRunDerivedMetrics.elevationGain(previousAltitude: 100, nextAltitude: 101.0, verticalAccuracy: 4) == 0)
        #expect(PulsarRunDerivedMetrics.elevationGain(previousAltitude: 100, nextAltitude: 102.1, verticalAccuracy: 4) > 2)
        #expect(PulsarRunDerivedMetrics.elevationGain(previousAltitude: 100, nextAltitude: 105, verticalAccuracy: 40) == 0)
    }

    @Test func unknownHealthKitWorkoutTypeDoesNotDefaultToRunning() {
        #expect(PulsarOutdoorWorkoutKind(activityType: .traditionalStrengthTraining) == .strength)
        #expect(PulsarOutdoorWorkoutKind(activityType: .mindAndBody) != .running)
        #expect(PulsarOutdoorWorkoutKind(activityType: .hiking) == .hiking)
        #expect(PulsarOutdoorWorkoutKind(activityType: .cycling) == .cycling)
        #expect(PulsarOutdoorWorkoutKind(activityType: .barre) != .running)
    }

    @Test func pulsarWorkoutMetadataOverridesFallbackWorkoutType() {
        let metadata: [String: Any] = [
            PulsarWorkoutMetadata.workoutTypeKey: PulsarOutdoorWorkoutKind.cycling.rawValue
        ]

        #expect(PulsarOutdoorWorkoutKind(metadata: metadata, fallbackActivityType: .running) == .cycling)
    }

    @Test func staleActiveWorkoutStateIsNotRoutable() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let staleState = PulsarActiveWorkoutSyncState(
            sessionId: UUID(),
            kind: .outdoor(.walking),
            startedAt: now.addingTimeInterval(-7_200),
            startedFrom: .appleWatch,
            lastUpdatedFrom: .appleWatch,
            phase: .active,
            elapsedSeconds: 7_200,
            updatedAt: now.addingTimeInterval(-3_600)
        )
        let freshState = PulsarActiveWorkoutSyncState(
            sessionId: UUID(),
            kind: .outdoor(.walking),
            startedAt: now.addingTimeInterval(-7_200),
            startedFrom: .appleWatch,
            lastUpdatedFrom: .appleWatch,
            phase: .active,
            elapsedSeconds: 7_200,
            updatedAt: now.addingTimeInterval(-30)
        )

        #expect(!staleState.isValidLiveRouteCandidate(now: now))
        #expect(freshState.isValidLiveRouteCandidate(now: now))
    }

    @Test func runHistoryMergesSavesWithSamePulsarSessionId() async throws {
        let suiteName = "pulsar.run.history.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PulsarRunHistoryStore(defaults: defaults)
        let sessionId = UUID()
        let workoutUUID = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        await store.save(makeRunSummary(id: UUID(), sessionId: sessionId, workoutUUID: nil, start: start, distance: 0))
        await store.save(makeRunSummary(id: UUID(), sessionId: sessionId, workoutUUID: workoutUUID, start: start, distance: 1_200))

        let cachedRuns = await store.loadCachedRuns()
        #expect(cachedRuns.count == 1)
        #expect(cachedRuns.first?.pulsarWorkoutSessionId == sessionId)
        #expect(cachedRuns.first?.workoutUUID == workoutUUID)
        #expect(cachedRuns.first?.distanceMeters == 1_200)
    }

    private func makeRunSummary(
        id: UUID,
        sessionId: UUID,
        workoutUUID: UUID?,
        start: Date,
        distance: Double
    ) -> PulsarRunSummary {
        PulsarRunSummary(
            id: id,
            pulsarWorkoutSessionId: sessionId,
            workoutUUID: workoutUUID,
            workoutKind: .walking,
            startedAt: start,
            endedAt: start.addingTimeInterval(1_800),
            source: .iPhone,
            distanceMeters: distance,
            elapsedTime: 1_800,
            movingTime: 1_700,
            activeEnergyKilocalories: nil,
            elevationGainMeters: 0,
            averageHeartRate: nil,
            maxHeartRate: nil,
            steps: nil,
            averageCadenceStepsPerMinute: nil,
            route: [],
            splits: []
        )
    }
}
