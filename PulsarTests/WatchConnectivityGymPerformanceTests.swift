//
//  WatchConnectivityGymPerformanceTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

@MainActor
struct WatchConnectivityGymPerformanceTests {
    @Test func liveAndRestCadenceUseExpectedBoundaries() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)

        #expect(!ActiveGymSyncCadencePolicy.shouldSendReachable(
            lastSentAt: now.addingTimeInterval(-1.999),
            now: now,
            restIsActive: false
        ))
        #expect(ActiveGymSyncCadencePolicy.shouldSendReachable(
            lastSentAt: now.addingTimeInterval(-2),
            now: now,
            restIsActive: false
        ))
        #expect(!ActiveGymSyncCadencePolicy.shouldSendReachable(
            lastSentAt: now.addingTimeInterval(-4.999),
            now: now,
            restIsActive: true
        ))
        #expect(ActiveGymSyncCadencePolicy.shouldSendReachable(
            lastSentAt: now.addingTimeInterval(-5),
            now: now,
            restIsActive: true
        ))
        #expect(ActiveGymSyncCadencePolicy.isVolatile(reason: "watchGymWorkoutTick", isFinished: false))
        #expect(ActiveGymSyncCadencePolicy.isVolatile(reason: "gymRemoteHealthMetricsUpdated", isFinished: false))
        #expect(!ActiveGymSyncCadencePolicy.isVolatile(reason: "gymWorkoutFinished", isFinished: true))
        #expect(
            !PulsarWatchConnectivityTransportPolicy.usesInteractiveSend(
                messageType: "activeGymState",
                reason: "watchGymWorkoutTick",
                isReachable: true,
                hasLiveWorkout: true
            )
        )
    }

    @Test func compactDeltaRoundTripsOffMainCodecAndAppliesToBaseline() async throws {
        let baseline = makeState()
        var updated = baseline
        updated.elapsedSeconds = 126
        updated.currentExerciseIndex = 0
        updated.currentSetIndex = 1
        updated.completedSets = 1
        updated.currentHeartRate = 142
        updated.activeEnergyKilocalories = 48
        updated.restRemainingSeconds = 55
        updated.restTotalSeconds = 90
        updated.updatedAt = baseline.updatedAt.addingTimeInterval(6)
        updated.exercises[0].sets[0].isCompleted = true
        updated.exercises[0].sets[0].completedReps = 10
        updated.exercises[0].sets[0].completedWeight = 60
        updated.exercises[0].sets[0].completedAt = updated.updatedAt

        let delta = ActiveGymLiveStateDelta(state: updated)
        let data = try #require(await PulsarWatchConnectivityCodecActor.shared.encodeActiveGymDelta(delta))
        let snapshot = PulsarWatchConnectivityIncomingSnapshot(
            dictionary: ["pulsar.activeGymWorkout.liveDelta.v2": data]
        )
        let decoded = await PulsarWatchConnectivityCodecActor.shared.decode(snapshot)
        let roundTrippedDelta = try #require(decoded.activeGymDelta)
        let applied = try #require(roundTrippedDelta.applying(to: baseline))

        #expect(applied.sessionId == baseline.sessionId)
        #expect(applied.elapsedSeconds == 126)
        #expect(applied.completedSets == 1)
        #expect(applied.currentHeartRate == 142)
        #expect(applied.activeEnergyKilocalories == 48)
        #expect(applied.restRemainingSeconds == 55)
        #expect(applied.exercises[0].sets[0].isCompleted)
        #expect(applied.exercises[0].sets[0].completedReps == 10)
        #expect(applied.exercises[0].sets[0].completedWeight == 60)
        #expect(applied.exercises[0].thumbnailURL == baseline.exercises[0].thumbnailURL)
        #expect(applied.exercises[0].instructionsPreview == baseline.exercises[0].instructionsPreview)
    }

    @Test func compactLiveSnapshotStripsPresentationFieldsAndCanRestoreThem() {
        let state = makeState()
        let compact = state.compactedForLiveSync

        #expect(compact.exercises[0].notes == nil)
        #expect(compact.exercises[0].thumbnailURL == nil)
        #expect(compact.exercises[0].instructionsPreview == nil)
        #expect(compact.exercises[0].sets == state.exercises[0].sets)

        let restored = compact.preservingRoutineDefinition(from: state)
        #expect(restored.exercises[0].notes == state.exercises[0].notes)
        #expect(restored.exercises[0].thumbnailURL == state.exercises[0].thumbnailURL)
        #expect(restored.exercises[0].instructionsPreview == state.exercises[0].instructionsPreview)
    }

    @Test func partialLiveSnapshotCannotEraseExercisesOrSetProgress() {
        let state = makeState()
        var partial = state
        partial.exercises = []
        partial.totalExercises = 0
        partial.totalSets = 0
        partial.completedSets = 1
        partial.elapsedSeconds += 2
        partial.updatedAt = state.updatedAt.addingTimeInterval(2)

        let merged = partial.preservingRoutineDefinition(from: state)

        #expect(merged.exercises == state.exercises)
        #expect(merged.totalExercises == 1)
        #expect(merged.totalSets == 2)
        #expect(merged.completedSets == 1)
        #expect(merged.elapsedSeconds == state.elapsedSeconds + 2)
    }

    @Test func delayedRoutineSnapshotCannotRollBackCompletedSetProgress() {
        let state = makeState()
        var liveExercise = state.exercises[0]
        liveExercise.sets[0].targetReps = 8
        liveExercise.sets[0].targetWeight = 62.5
        liveExercise.sets[0].completedReps = 8
        liveExercise.sets[0].completedWeight = 62.5
        liveExercise.sets[0].isCompleted = true
        liveExercise.sets[0].completedAt = state.updatedAt

        let reapplied = state.exercises[0].preservingLiveSetProgress(from: liveExercise)

        #expect(reapplied.sets[0].targetReps == 8)
        #expect(reapplied.sets[0].targetWeight == 62.5)
        #expect(reapplied.sets[0].completedReps == 8)
        #expect(reapplied.sets[0].completedWeight == 62.5)
        #expect(reapplied.sets[0].isCompleted)
        #expect(reapplied.sets[1] == state.exercises[0].sets[1])
    }

    @Test func mixedApplicationContextSeparatesWorkoutFromNonWorkoutWork() async {
        let snapshot = PulsarWatchConnectivityIncomingSnapshot(dictionary: [
            "pulsar.workoutSync.messageId.v1": "mixed-1",
            "pulsar.activeGymWorkout.state.v1": Data([0x01]),
            "pulsar.dailyMetricsPayload": Data([0x02]),
            "pulsar.watchHeartbeat.payload.v1": Data([0x03])
        ])
        let decoded = await PulsarWatchConnectivityCodecActor.shared.decode(snapshot)

        #expect(decoded.hasWorkoutCriticalPayload)
        #expect(decoded.hasNonWorkoutPayload)

        let workout = decoded.workoutCriticalOnly()
        #expect(workout.snapshot.containsActiveGym)
        #expect(workout.snapshot.dailyMetricsData == nil)
        #expect(workout.snapshot.heartbeatData == nil)
        #expect(workout.snapshot.messageID == "mixed-1")

        let nonWorkout = decoded.nonWorkoutOnly()
        #expect(!nonWorkout.snapshot.containsActiveGym)
        #expect(nonWorkout.snapshot.activeGymData == nil)
        #expect(nonWorkout.snapshot.dailyMetricsData != nil)
        #expect(nonWorkout.snapshot.heartbeatData != nil)
        #expect(nonWorkout.snapshot.messageID == nil)
    }

    @Test func durableTransferDiagnosticsClassifyKnownPayloads() {
        let daily = PulsarWatchConnectivitySyncStore.userInfoTransferDescriptor([
            "pulsar.dailyMetricsPayload": Data(repeating: 0x01, count: 12)
        ])
        let workout = PulsarWatchConnectivitySyncStore.userInfoTransferDescriptor([
            "pulsar.workoutSync.category.v1": "activeWorkoutState",
            "pulsar.workoutSync.sessionId.v1": "session-1",
            "pulsar.activeWorkout.state.v1": Data(repeating: 0x02, count: 24)
        ])

        #expect(daily.contains("dailyMetrics"))
        #expect(daily.contains("dataBytes=12"))
        #expect(workout.contains("workout.activeWorkoutState"))
        #expect(workout.contains("workoutID=session-1"))
        #expect(workout.contains("dataBytes=24"))
        #expect(!daily.contains("untyped"))
        #expect(!workout.contains("untyped"))
    }

    @Test func savedRoutineDurableQueueDeduplicatesButHonorsExplicitRequests() {
        let payload = SavedGymRoutinesSyncCodec.encode(
            SavedGymRoutinesSyncPayload(revision: 7, routines: [])
        )!
        var semanticallyIdenticalData = payload
        semanticallyIdenticalData.insert(0x20, at: 0)

        #expect(payload != semanticallyIdenticalData)
        #expect(SavedGymRoutinesSyncCodec.semanticallyEquivalent(payload, semanticallyIdenticalData))

        #expect(!PulsarWatchConnectivitySyncStore.shouldQueueSavedGymRoutinesPayload(
            data: payload,
            revision: 7,
            lastQueuedData: semanticallyIdenticalData,
            lastQueuedRevision: 7,
            hasOutstandingMatchingPayload: false,
            respondingToVerifiedInboundRequest: false
        ))
        #expect(!PulsarWatchConnectivitySyncStore.shouldQueueSavedGymRoutinesPayload(
            data: payload,
            revision: 7,
            lastQueuedData: nil,
            lastQueuedRevision: nil,
            hasOutstandingMatchingPayload: true,
            respondingToVerifiedInboundRequest: true
        ))
        #expect(PulsarWatchConnectivitySyncStore.shouldQueueSavedGymRoutinesPayload(
            data: payload,
            revision: 7,
            lastQueuedData: payload,
            lastQueuedRevision: 7,
            hasOutstandingMatchingPayload: false,
            respondingToVerifiedInboundRequest: true
        ))
    }

    @Test func routineSnapshotDurableQueueTracksOutstandingTransfersNotStickyHistory() throws {
        let routineID = UUID()
        let request = GymWorkoutStartRequest(
            routineID: routineID,
            routineRevision: 3,
            workoutKind: .routine,
            activityTypeRawValue: 50,
            locationTypeRawValue: 1
        )
        let envelope = GymRoutineSnapshotEnvelope(
            requestID: request.requestID,
            sessionID: request.candidateSessionID,
            routineID: routineID,
            revision: 3,
            routinePlan: WatchGymRoutinePlan(
                routineId: routineID,
                name: "Friday",
                emoji: "🏋️",
                exerciseCount: 0,
                mainMuscleGroups: [],
                estimatedDurationSeconds: 0,
                updatedAt: Date(),
                exercises: []
            ),
            startRequest: request
        )
        let data = try #require(GymCrossDeviceCodec.encodeRoutineSnapshot(envelope))

        #expect(!PulsarWatchConnectivitySyncStore.shouldQueueGymRoutineSnapshotPayload(
            requestID: envelope.requestID,
            checksum: envelope.checksum,
            outstandingPayloads: [data]
        ))
        #expect(PulsarWatchConnectivitySyncStore.shouldQueueGymRoutineSnapshotPayload(
            requestID: envelope.requestID,
            checksum: envelope.checksum,
            outstandingPayloads: []
        ))
        #expect(PulsarWatchConnectivitySyncStore.shouldQueueGymRoutineSnapshotPayload(
            requestID: envelope.requestID,
            checksum: envelope.checksum + "-changed",
            outstandingPayloads: [data]
        ))
    }

    private func makeState() -> ActiveGymWorkoutState {
        let startedAt = Date(timeIntervalSinceReferenceDate: 9_000)
        let exerciseID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        return ActiveGymWorkoutState(
            sessionId: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            routineId: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            routineName: "Push",
            routineEmoji: "🏋️",
            workoutKind: .routine,
            startedFrom: .appleWatch,
            startedAt: startedAt,
            elapsedSeconds: 120,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: 1,
            totalSets: 2,
            completedSets: 0,
            currentHeartRate: 130,
            averageHeartRate: 124,
            maxHeartRate: 138,
            activeEnergyKilocalories: 40,
            restRemainingSeconds: nil,
            restTotalSeconds: nil,
            isHealthKitEnabled: true,
            healthKitStatusMessage: nil,
            isFinished: false,
            updatedAt: startedAt.addingTimeInterval(120),
            exercises: [
                ActiveGymWorkoutExerciseState(
                    id: exerciseID,
                    exerciseId: "barbell-bench-press",
                    exerciseName: "Bench Press",
                    muscleGroup: "Chest",
                    equipment: "Barbell",
                    plannedSets: 2,
                    plannedReps: 10,
                    plannedWeight: 60,
                    weightUnit: "kg",
                    plannedRestSeconds: 90,
                    orderIndex: 0,
                    notes: "Controlled eccentric",
                    thumbnailURL: "https://example.invalid/bench.png",
                    instructionsPreview: "Lower to chest and press.",
                    sets: [
                        ActiveGymWorkoutSetState(
                            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                            setNumber: 1,
                            targetReps: 10,
                            targetWeight: 60,
                            completedReps: nil,
                            completedWeight: nil,
                            isCompleted: false,
                            completedAt: nil
                        ),
                        ActiveGymWorkoutSetState(
                            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                            setNumber: 2,
                            targetReps: 10,
                            targetWeight: 60,
                            completedReps: nil,
                            completedWeight: nil,
                            isCompleted: false,
                            completedAt: nil
                        )
                    ]
                )
            ]
        )
    }
}
