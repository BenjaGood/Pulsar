//
//  WorkoutCompletionPresentationStoreTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

@MainActor
struct WorkoutCompletionPresentationStoreTests {
    @Test func consumePersistsSessionAndBlocksAutoPresentation() throws {
        let (suiteName, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sessionID = UUID()

        let store = WorkoutCompletionPresentationStore(defaults: defaults)
        #expect(store.shouldAutoPresent(sessionID: sessionID))

        store.consume(sessionID: sessionID, reason: "test")

        #expect(!store.shouldAutoPresent(sessionID: sessionID))
        let restored = WorkoutCompletionPresentationStore(defaults: defaults)
        #expect(!restored.shouldAutoPresent(sessionID: sessionID))
    }

    @Test func markPendingIgnoresConsumedSession() throws {
        let (suiteName, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sessionID = UUID()
        let store = WorkoutCompletionPresentationStore(defaults: defaults)
        store.markEligibleForSummary(sessionID: sessionID)
        store.consume(sessionID: sessionID, reason: "test")

        store.markPending(
            WorkoutCompletionPresentation(
                sessionID: sessionID,
                kind: .gym(makeGymSummary(sessionID: sessionID)),
                presentedAt: Date(),
                source: .localFinish
            )
        )

        #expect(store.pendingPresentation == nil)
    }

    @Test func markPendingRequiresSummaryEligibility() throws {
        let (suiteName, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sessionID = UUID()
        let store = WorkoutCompletionPresentationStore(defaults: defaults)

        store.markPending(
            WorkoutCompletionPresentation(
                sessionID: sessionID,
                kind: .gym(makeGymSummary(sessionID: sessionID)),
                presentedAt: Date(),
                source: .localFinish
            )
        )
        #expect(store.pendingPresentation == nil)

        store.markEligibleForSummary(sessionID: sessionID)
        store.markPending(
            WorkoutCompletionPresentation(
                sessionID: sessionID,
                kind: .gym(makeGymSummary(sessionID: sessionID)),
                presentedAt: Date(),
                source: .localFinish
            )
        )
        #expect(store.pendingPresentation?.sessionID == sessionID)
    }

    @Test func watchSummaryEligibilityRequiresObservedActiveSession() throws {
        let (suiteName, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let expectedSessionID = UUID()
        let staleSessionID = UUID()
        let store = WorkoutCompletionPresentationStore(defaults: defaults)

        #expect(!store.isEligibleForSummary(sessionID: expectedSessionID))
        #expect(!store.isEligibleForSummary(sessionID: staleSessionID))

        store.markEligibleForSummary(sessionID: expectedSessionID)

        #expect(store.isEligibleForSummary(sessionID: expectedSessionID))
        #expect(!store.isEligibleForSummary(sessionID: staleSessionID))
        let restored = WorkoutCompletionPresentationStore(defaults: defaults)
        #expect(restored.isEligibleForSummary(sessionID: expectedSessionID))
    }

    @Test func consumingSummaryClearsEligibility() throws {
        let (suiteName, defaults) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sessionID = UUID()
        let store = WorkoutCompletionPresentationStore(defaults: defaults)
        store.markEligibleForSummary(sessionID: sessionID)

        store.consume(sessionID: sessionID, reason: "test")

        #expect(!store.isEligibleForSummary(sessionID: sessionID))
    }

    @Test func watchMirrorBlocksFinishedSummaryForMissingOrMismatchedActiveSession() {
        let expectedSessionID = UUID()

        #expect(!GymWatchMirroredWorkoutView.canPresentFinishedSummary(
            expectedSessionID: expectedSessionID,
            finishedSessionID: expectedSessionID,
            isSummaryEligible: false
        ))
        #expect(!GymWatchMirroredWorkoutView.canPresentFinishedSummary(
            expectedSessionID: expectedSessionID,
            finishedSessionID: UUID(),
            isSummaryEligible: true
        ))
        #expect(GymWatchMirroredWorkoutView.canPresentFinishedSummary(
            expectedSessionID: expectedSessionID,
            finishedSessionID: expectedSessionID,
            isSummaryEligible: true
        ))
    }

    @Test func gymMetricsIncludeFullWidthCalories() {
        let summary = makeGymSummary(sessionID: UUID())
        let metrics = WorkoutCompletionContentBuilder.metrics(for: summary)

        #expect(metrics.contains { $0.id == "duration" })
        #expect(metrics.contains { $0.id == "active-calories" && $0.layout == .fullWidth })
    }

    @Test func runMetricsIncludeDistanceAndCalories() {
        let summary = PulsarRunSummary(
            id: UUID(),
            pulsarWorkoutSessionId: UUID(),
            workoutUUID: nil,
            workoutKind: .running,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_003_000),
            source: .iPhone,
            distanceMeters: 5_000,
            elapsedTime: 3_000,
            movingTime: 2_900,
            activeEnergyKilocalories: 420,
            elevationGainMeters: 0,
            averageHeartRate: 145,
            maxHeartRate: 170,
            steps: nil,
            averageCadenceStepsPerMinute: nil,
            route: [],
            splits: []
        )

        let metrics = WorkoutCompletionContentBuilder.metrics(for: summary)

        #expect(metrics.contains { $0.id == "distance" })
        #expect(metrics.contains { $0.id == "active-calories" && $0.layout == .fullWidth })
    }

    private func makeGymSummary(sessionID: UUID) -> PulsarGymWorkoutSummary {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let state = ActiveGymWorkoutState(
            sessionId: sessionID,
            routineId: UUID(),
            routineName: "Push Day",
            routineEmoji: "💪",
            workoutKind: .routine,
            startedFrom: .iPhone,
            startedAt: now.addingTimeInterval(-3_000),
            elapsedSeconds: 3_000,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: 4,
            totalSets: 12,
            completedSets: 12,
            currentHeartRate: nil,
            averageHeartRate: 132,
            maxHeartRate: 168,
            activeEnergyKilocalories: 320,
            restRemainingSeconds: nil,
            restTotalSeconds: nil,
            isHealthKitEnabled: true,
            healthKitStatusMessage: nil,
            isFinished: true,
            updatedAt: now,
            exercises: []
        )
        return PulsarGymWorkoutSummary(activeGymState: state)
    }

    private func makeDefaults() throws -> (String, UserDefaults) {
        let suiteName = "pulsar.tests.workoutCompletion.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (suiteName, defaults)
    }
}
