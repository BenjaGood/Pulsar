//
//  WatchGymSessionManager.swift
//  Pulsar Watch App Watch App
//

import Combine
import Foundation
import HealthKit
import WatchKit

@MainActor
final class WatchGymSessionManager: NSObject, ObservableObject {
    static let shared = WatchGymSessionManager()

    @Published private(set) var currentHeartRate: Double?
    @Published private(set) var averageHeartRate: Double?
    @Published private(set) var maxHeartRate: Double?
    @Published private(set) var activeEnergyKilocalories: Double?
    @Published private(set) var message: String?

    private let healthStore = HKHealthStore()
    private let syncStore = PulsarWatchConnectivitySyncStore.shared
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var activeSessionId: UUID?
    private var startedAt: Date?
    private var tickTask: Task<Void, Never>?
    private var restTask: Task<Void, Never>?
    private var stateTickTask: Task<Void, Never>?
    private var finishFallbackTask: Task<Void, Never>?
    private var isFinishing = false
    private var lastMetricsSentAt = Date.distantPast

    private override init() {
        super.init()
        syncStore.registerGymActionHandler { [weak self] action in
            Task { @MainActor in
                await self?.handle(action)
            }
        }
    }

    func startFromCompanion(configuration: HKWorkoutConfiguration) async {
        if let state = syncStore.activeGymState,
           syncStore.isRoutableActiveGymState(state),
           state.startedFrom == .iPhone {
            activeSessionId = state.sessionId
            startedAt = state.startedAt
            startStateTicking()
            syncStore.sendGymAction(.requestState(sessionId: state.sessionId))
            PulsarSyncDebugLogger.log("Watch Gym companion launch joined iPhone session without creating duplicate HealthKit workout session=\(state.sessionId.uuidString)")
            return
        }
        if let state = await companionRequestedWatchGymState(),
           syncStore.isRoutableActiveGymState(state) {
            activeSessionId = state.sessionId
            startedAt = state.startedAt
            startStateTicking()
            PulsarSyncDebugLogger.log("Watch Gym companion launch accepted iPhone-requested Watch start session=\(state.sessionId.uuidString) type=\(state.workoutKind?.rawValue ?? "unknown")")
            await startWorkoutIfNeeded(configuration: configuration)
            return
        }
        await startWorkoutIfNeeded(configuration: configuration)
        syncStore.sendGymAction(.requestState())
    }

    func startIfNeeded(for state: ActiveGymWorkoutState) async {
        activeSessionId = state.sessionId
        if state.isFinished {
            await finishCurrentWorkoutIfNeeded()
            return
        }
        startStateTicking()
        guard state.startedFrom?.isAppleWatchRecorder == true else {
            PulsarSyncDebugLogger.log("Watch Gym displaying iPhone-owned workout without starting duplicate HealthKit workout session=\(state.sessionId.uuidString)")
            return
        }
        await startWorkoutIfNeeded(configuration: Self.strengthConfiguration)
    }

    func startFreeWorkoutFromWatch() async {
        if let activeState = syncStore.activeGymState,
           syncStore.isRoutableActiveGymState(activeState) {
            activeSessionId = activeState.sessionId
            await startIfNeeded(for: activeState)
            return
        }

        let sessionId = UUID()
        let now = Date()
        let state = ActiveGymWorkoutState(
            sessionId: sessionId,
            routineId: sessionId,
            routineName: PulsarGymWorkoutKind.freeWorkout.displayName,
            routineEmoji: "🏋️",
            workoutKind: .freeWorkout,
            startedFrom: .appleWatch,
            startedAt: now,
            elapsedSeconds: 0,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: 0,
            totalSets: 0,
            completedSets: 0,
            currentHeartRate: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            activeEnergyKilocalories: nil,
            restRemainingSeconds: nil,
            restTotalSeconds: nil,
            isHealthKitEnabled: true,
            healthKitStatusMessage: nil,
            isFinished: false,
            updatedAt: now,
            exercises: []
        )

        activeSessionId = sessionId
        startedAt = now
        syncStore.storeActiveGymState(state, broadcast: true, reason: "watchGymFreeWorkoutStarted")
        syncStore.sendGymAction(.startFreeWorkoutFromWatch(sessionId: sessionId))
        startStateTicking()
        await startWorkoutIfNeeded(configuration: Self.strengthConfiguration)
    }

    func recoverActiveWorkoutSession(_ session: HKWorkoutSession) {
        guard workoutSession == nil else {
            PulsarSyncDebugLogger.log("Watch Gym recovery skipped because an active HealthKit session is already attached session=\(activeSessionId?.uuidString ?? "none")")
            return
        }

        let configuration = session.workoutConfiguration
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self

        workoutSession = session
        workoutBuilder = builder

        let recoveredState = syncStore.activeGymState.flatMap { state -> ActiveGymWorkoutState? in
            guard syncStore.isRoutableActiveGymState(state),
                  !state.isFinished else { return nil }
            return state
        }
        if let recoveredState {
            activeSessionId = recoveredState.sessionId
            startedAt = session.startDate ?? recoveredState.startedAt
        } else {
            let sessionId = UUID()
            let start = session.startDate ?? Date()
            activeSessionId = sessionId
            startedAt = start
            syncStore.storeActiveGymState(
                ActiveGymWorkoutState(
                    sessionId: sessionId,
                    routineId: sessionId,
                    routineName: "Recovered Workout",
                    routineEmoji: "🏋️",
                    workoutKind: .freeWorkout,
                    startedFrom: .appleWatch,
                    startedAt: start,
                    elapsedSeconds: max(0, Int(Date().timeIntervalSince(start))),
                    currentExerciseIndex: 0,
                    currentSetIndex: 0,
                    totalExercises: 0,
                    totalSets: 0,
                    completedSets: 0,
                    currentHeartRate: nil,
                    averageHeartRate: nil,
                    maxHeartRate: nil,
                    activeEnergyKilocalories: nil,
                    restRemainingSeconds: nil,
                    restTotalSeconds: nil,
                    isHealthKitEnabled: true,
                    healthKitStatusMessage: nil,
                    isFinished: false,
                    updatedAt: Date(),
                    exercises: []
                ),
                broadcast: true,
                reason: "watchGymRecovered"
            )
        }

        startTicking()
        startStateTicking()
        applyHealthStatusToActiveState(isEnabled: true)
        sendMetricsIfNeeded(force: true)
        message = nil
        PulsarSyncDebugLogger.log("Watch Gym recovered active HealthKit workout session=\(activeSessionId?.uuidString ?? "none") state=\(session.state.rawValue)")
    }

    func startRoutineFromWatch(_ routine: WatchGymRoutinePlan) async {
        if let activeState = syncStore.activeGymState,
           syncStore.isRoutableActiveGymState(activeState) {
            activeSessionId = activeState.sessionId
            await startIfNeeded(for: activeState)
            return
        }

        let sessionId = UUID()
        let now = Date()
        let exercises = routine.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map(Self.activeExerciseState)
        let totalSets = exercises.reduce(0) { $0 + $1.sets.count }
        let state = ActiveGymWorkoutState(
            sessionId: sessionId,
            routineId: routine.routineId,
            routineName: routine.name,
            routineEmoji: routine.emoji,
            workoutKind: .routine,
            startedFrom: .appleWatch,
            startedAt: now,
            elapsedSeconds: 0,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: exercises.count,
            totalSets: totalSets,
            completedSets: 0,
            currentHeartRate: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            activeEnergyKilocalories: nil,
            restRemainingSeconds: nil,
            restTotalSeconds: nil,
            isHealthKitEnabled: true,
            healthKitStatusMessage: nil,
            isFinished: false,
            updatedAt: now,
            exercises: exercises
        )

        activeSessionId = sessionId
        startedAt = now
        syncStore.storeActiveGymState(state, broadcast: true, reason: "watchGymSavedRoutineStarted")
        syncStore.sendGymAction(.startSavedRoutineFromWatch(sessionId: sessionId, routineId: routine.routineId))
        startStateTicking()
        await startWorkoutIfNeeded(configuration: Self.strengthConfiguration)
    }

    func completeSet(
        sessionId: UUID,
        exerciseId: UUID,
        setId: UUID,
        reps: Int? = nil,
        weight: Double? = nil,
        sendsAction: Bool = true
    ) {
        guard var state = syncStore.activeGymState,
              state.sessionId == sessionId,
              !state.isFinished,
              let exerciseIndex = state.exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIndex = state.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
            if sendsAction {
                syncStore.sendGymAction(.completeSet(sessionId: sessionId, exerciseId: exerciseId, setId: setId, reps: reps, weight: weight))
            }
            return
        }

        if state.exercises[exerciseIndex].sets[setIndex].isCompleted {
            return
        }

        let actualReps = max(1, reps ?? state.exercises[exerciseIndex].sets[setIndex].targetReps)
        let actualWeight = max(0, weight ?? state.exercises[exerciseIndex].sets[setIndex].targetWeight)
        state.exercises[exerciseIndex].sets[setIndex].targetReps = actualReps
        state.exercises[exerciseIndex].sets[setIndex].targetWeight = actualWeight
        state.exercises[exerciseIndex].sets[setIndex].isCompleted = true
        state.exercises[exerciseIndex].sets[setIndex].completedAt = Date()
        state.exercises[exerciseIndex].sets[setIndex].completedReps = actualReps
        state.exercises[exerciseIndex].sets[setIndex].completedWeight = actualWeight

        let restDecision = restDecisionAfterCompleting(exerciseIndex: exerciseIndex, setIndex: setIndex, in: state)
        state = normalizedState(state)
        if let restSeconds = restDecision, restSeconds > 0 && state.completedSets < state.totalSets {
            state.restTotalSeconds = restSeconds
            state.restRemainingSeconds = restSeconds
            startRest(seconds: restSeconds, sessionId: sessionId)
        } else {
            stopRest()
            state.restTotalSeconds = nil
            state.restRemainingSeconds = nil
        }

        WKInterfaceDevice.current().play(.success)
        syncStore.storeActiveGymState(state, broadcast: true, reason: "watchGymSetCompleted")
        if sendsAction {
            syncStore.sendGymAction(.completeSet(sessionId: sessionId, exerciseId: exerciseId, setId: setId, reps: actualReps, weight: actualWeight))
        }
    }

    func updateSetValues(
        sessionId: UUID,
        exerciseId: UUID,
        setId: UUID,
        reps: Int? = nil,
        weight: Double? = nil,
        sendsAction: Bool = true,
        playsHaptic: Bool = true
    ) {
        let nextReps = reps.map { max(1, $0) }
        let nextWeight = weight.map { max(0, $0) }
        guard nextReps != nil || nextWeight != nil else { return }

        guard var state = syncStore.activeGymState,
              state.sessionId == sessionId,
              !state.isFinished,
              let exerciseIndex = state.exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIndex = state.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
            if sendsAction {
                syncStore.sendGymAction(.updateSetValues(sessionId: sessionId, exerciseId: exerciseId, setId: setId, reps: nextReps, weight: nextWeight))
            }
            return
        }

        var didUpdate = false
        if let nextReps {
            if state.exercises[exerciseIndex].sets[setIndex].targetReps != nextReps {
                state.exercises[exerciseIndex].sets[setIndex].targetReps = nextReps
                didUpdate = true
            }
            if state.exercises[exerciseIndex].sets[setIndex].isCompleted,
               state.exercises[exerciseIndex].sets[setIndex].completedReps != nextReps {
                state.exercises[exerciseIndex].sets[setIndex].completedReps = nextReps
                didUpdate = true
            }
        }
        if let nextWeight {
            if state.exercises[exerciseIndex].sets[setIndex].targetWeight != nextWeight {
                state.exercises[exerciseIndex].sets[setIndex].targetWeight = nextWeight
                didUpdate = true
            }
            if state.exercises[exerciseIndex].sets[setIndex].isCompleted,
               state.exercises[exerciseIndex].sets[setIndex].completedWeight != nextWeight {
                state.exercises[exerciseIndex].sets[setIndex].completedWeight = nextWeight
                didUpdate = true
            }
        }

        guard didUpdate else { return }
        state = normalizedState(state)
        if playsHaptic {
            WKInterfaceDevice.current().play(.click)
        }
        syncStore.storeActiveGymState(state, broadcast: true, reason: "watchGymSetAdjusted")
        if sendsAction {
            syncStore.sendGymAction(.updateSetValues(sessionId: sessionId, exerciseId: exerciseId, setId: setId, reps: nextReps, weight: nextWeight))
        }
    }

    func skipRest(sessionId: UUID) {
        stopRest()
        if var state = syncStore.activeGymState, state.sessionId == sessionId {
            state.restRemainingSeconds = nil
            state.restTotalSeconds = nil
            state.updatedAt = Date()
            syncStore.storeActiveGymState(state, broadcast: true, reason: "watchGymRestSkipped")
        }
        syncStore.sendGymAction(.skipRestTimer(sessionId: sessionId))
    }

    func finishWorkoutFromUser(sessionId: UUID) async {
        WKInterfaceDevice.current().play(.stop)
        syncStore.sendGymAction(.finishWorkout(sessionId: sessionId))
        await finishCurrentWorkoutIfNeeded()
    }

    func finishCurrentWorkoutIfNeeded() async {
        guard workoutSession != nil || workoutBuilder != nil else {
            markActiveStateFinished(workoutUUID: nil)
            return
        }
        requestWorkoutSessionStop(reason: "watchGymFinish")
    }

    private func startWorkoutIfNeeded(configuration: HKWorkoutConfiguration) async {
        if workoutSession != nil {
            activeSessionId = activeSessionId ?? syncStore.activeGymState?.sessionId
            return
        }

        guard await requestAuthorization() else {
            applyHealthStatusToActiveState(isEnabled: false)
            syncStore.sendGymAction(.requestState())
            return
        }

        do {
            activeSessionId = syncStore.activeGymState?.sessionId ?? activeSessionId
            currentHeartRate = nil
            averageHeartRate = nil
            maxHeartRate = nil
            activeEnergyKilocalories = nil
            message = nil

            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self

            workoutSession = session
            workoutBuilder = builder

            let start = syncStore.activeGymState?.startedAt ?? Date()
            startedAt = start
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            addMetadata(to: builder, startedFrom: syncStore.activeGymState?.startedFrom ?? .appleWatch)
            PulsarSyncDebugLogger.log("Watch Gym HealthKit mirroring deferred; gym state sync is handled by WatchConnectivity session=\(activeSessionId?.uuidString ?? "none")")
            startTicking()
            startStateTicking()
            applyHealthStatusToActiveState(isEnabled: true)
            sendMetricsIfNeeded(force: true)
            WKInterfaceDevice.current().play(.start)
        } catch {
            message = "Apple Watch could not start Health recording for this gym workout."
            PulsarSyncDebugLogger.log("Watch Gym workout start failed: \(error.localizedDescription)")
            applyHealthStatusToActiveState(isEnabled: false)
            cleanup()
        }
    }

    private func companionRequestedWatchGymState(timeoutSeconds: TimeInterval = 2.0) async -> ActiveGymWorkoutState? {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if let state = syncStore.activeGymState,
               !state.isFinished,
               state.startedFrom?.isAppleWatchRecorder == true {
                return state
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        PulsarSyncDebugLogger.log("Watch Gym companion launch did not receive an iPhone-requested Watch state before timeout")
        return syncStore.activeGymState?.startedFrom?.isAppleWatchRecorder == true ? syncStore.activeGymState : nil
    }

    private func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            message = "Health is unavailable on this Apple Watch."
            return false
        }

        do {
            try await healthStore.requestAuthorization(toShare: Self.healthShareTypes, read: Self.healthReadTypes)
            let workoutStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
            guard workoutStatus != .sharingDenied else {
                message = "Allow Health workout access on Apple Watch to read heart rate."
                return false
            }
            message = nil
            return true
        } catch {
            message = "Allow Health access on Apple Watch to read heart rate and calories."
            return false
        }
    }

    private func updateBuilderStatistics(for collectedTypes: Set<HKSampleType>) {
        guard let builder = workoutBuilder else { return }

        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let statistics = builder.statistics(for: quantityType)
            switch quantityType.identifier {
            case HKQuantityTypeIdentifier.heartRate.rawValue:
                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                currentHeartRate = statistics?.mostRecentQuantity()?.doubleValue(for: bpmUnit)
                averageHeartRate = statistics?.averageQuantity()?.doubleValue(for: bpmUnit)
                maxHeartRate = statistics?.maximumQuantity()?.doubleValue(for: bpmUnit)
            case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                activeEnergyKilocalories = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie())
            default:
                break
            }
        }

        sendMetricsIfNeeded()
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run {
                    self?.sendMetricsIfNeeded(force: true)
                }
            }
        }
    }

    private func startStateTicking() {
        stateTickTask?.cancel()
        stateTickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    self?.tickActiveState()
                }
            }
        }
    }

    private func tickActiveState() {
        guard var state = syncStore.activeGymState,
              !state.isFinished else { return }
        let sessionId = activeSessionId ?? state.sessionId
        guard state.sessionId == sessionId else { return }
        state = normalizedState(state)
        syncStore.storeActiveGymState(state, broadcast: true, reason: "watchGymWorkoutTick")
    }

    private func startRest(seconds: Int, sessionId: UUID) {
        restTask?.cancel()
        guard seconds > 0 else { return }
        restTask = Task { [weak self] in
            var remaining = seconds
            while remaining > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                remaining -= 1
                await MainActor.run {
                    self?.updateRest(remaining: remaining, total: seconds, sessionId: sessionId)
                }
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                WKInterfaceDevice.current().play(.notification)
                self?.stopRest()
                self?.clearRest(sessionId: sessionId, reason: "watchGymRestFinished")
            }
        }
    }

    private func updateRest(remaining: Int, total: Int, sessionId: UUID) {
        guard var state = syncStore.activeGymState,
              state.sessionId == sessionId,
              !state.isFinished else { return }
        state.restRemainingSeconds = max(remaining, 0)
        state.restTotalSeconds = total
        state.updatedAt = Date()
        syncStore.storeActiveGymState(state, broadcast: true, reason: "watchGymRestTick")
    }

    private func clearRest(sessionId: UUID, reason: String) {
        guard var state = syncStore.activeGymState, state.sessionId == sessionId else { return }
        state.restRemainingSeconds = nil
        state.restTotalSeconds = nil
        state.updatedAt = Date()
        syncStore.storeActiveGymState(state, broadcast: true, reason: reason)
    }

    private func stopRest() {
        restTask?.cancel()
        restTask = nil
    }

    private func sendMetricsIfNeeded(force: Bool = false, workoutUUID: UUID? = nil) {
        let now = Date()
        guard force || now.timeIntervalSince(lastMetricsSentAt) >= 1.5 else { return }
        lastMetricsSentAt = now

        let sessionId = activeSessionId ?? syncStore.activeGymState?.sessionId
        guard currentHeartRate != nil ||
            averageHeartRate != nil ||
            maxHeartRate != nil ||
            activeEnergyKilocalories != nil ||
            workoutUUID != nil else { return }

        applyMetricsToActiveState(workoutUUID: workoutUUID)

        syncStore.sendGymAction(
            .metricsUpdated(
                sessionId: sessionId,
                currentHeartRate: currentHeartRate,
                averageHeartRate: averageHeartRate,
                maxHeartRate: maxHeartRate,
                activeEnergyKilocalories: activeEnergyKilocalories,
                healthKitWorkoutUUID: workoutUUID
            )
        )
    }

    private func applyHealthStatusToActiveState(isEnabled: Bool) {
        guard var state = syncStore.activeGymState,
              !state.isFinished else { return }
        let sessionId = activeSessionId ?? state.sessionId
        guard state.sessionId == sessionId else { return }
        state.isHealthKitEnabled = isEnabled
        state.healthKitStatusMessage = message
        state.updatedAt = Date()
        syncStore.storeActiveGymState(state, broadcast: true, reason: "watchGymHealthStatusUpdated")
    }

    private func addMetadata(to builder: HKLiveWorkoutBuilder, startedFrom: PulsarWorkoutStartedFrom) {
        guard let state = syncStore.activeGymState else { return }
        let workoutKind = state.workoutKind ?? PulsarGymWorkoutKind.inferred(
            routineName: state.routineName,
            exerciseCount: state.exercises.count
        )
        let metadata = gymMetadata(
            state: state,
            workoutKind: workoutKind,
            startedFrom: startedFrom
        )
        builder.addMetadata(metadata) { success, error in
            if success {
                PulsarSyncDebugLogger.log("Watch Gym HealthKit metadata added session=\(state.sessionId.uuidString) type=\(workoutKind.rawValue) startedFrom=\(startedFrom.rawValue)")
            } else if let error {
                PulsarSyncDebugLogger.log("Watch Gym HealthKit metadata failed session=\(state.sessionId.uuidString) error=\(error.localizedDescription)")
            }
        }
    }

    private func gymMetadata(
        state: ActiveGymWorkoutState,
        workoutKind: PulsarGymWorkoutKind,
        startedFrom: PulsarWorkoutStartedFrom
    ) -> [String: Any] {
        let displayName = workoutKind == .freeWorkout ? workoutKind.displayName : state.routineName
        var metadata = PulsarWorkoutMetadata.base(
            sessionId: state.sessionId,
            workoutType: workoutKind.rawValue,
            startedFrom: startedFrom
        )
        metadata["PulsarWorkoutCategory"] = workoutKind.categoryName
        metadata["PulsarWorkoutKind"] = workoutKind.rawValue
        metadata["PulsarWorkoutDisplayName"] = displayName
        metadata["PulsarRoutineName"] = state.routineName
        metadata["PulsarRoutineID"] = state.routineId.uuidString
        metadata[PulsarWorkoutMetadata.legacySessionIdKey] = state.sessionId.uuidString
        return metadata
    }

    private func applyMetricsToActiveState(workoutUUID: UUID?) {
        guard var state = syncStore.activeGymState else { return }
        let sessionId = activeSessionId ?? state.sessionId
        guard state.sessionId == sessionId else { return }
        state.currentHeartRate = currentHeartRate ?? state.currentHeartRate
        state.averageHeartRate = averageHeartRate ?? state.averageHeartRate
        state.maxHeartRate = maxHeartRate ?? state.maxHeartRate
        state.activeEnergyKilocalories = activeEnergyKilocalories ?? state.activeEnergyKilocalories
        state.healthKitWorkoutUUID = workoutUUID ?? state.healthKitWorkoutUUID
        state.isHealthKitEnabled = state.isHealthKitEnabled || currentHeartRate != nil || activeEnergyKilocalories != nil
        state.healthKitStatusMessage = message
        state.updatedAt = Date()
        syncStore.storeActiveGymState(state, broadcast: true, reason: workoutUUID == nil ? "watchGymMetricsUpdated" : "watchGymWorkoutSaved")
    }

    private func markActiveStateFinished(workoutUUID: UUID?) {
        guard var state = syncStore.activeGymState else { return }
        let sessionId = activeSessionId ?? state.sessionId
        guard state.sessionId == sessionId else { return }
        state = normalizedState(state)
        state.isFinished = true
        state.restRemainingSeconds = nil
        state.restTotalSeconds = nil
        state.currentHeartRate = currentHeartRate ?? state.currentHeartRate
        state.averageHeartRate = averageHeartRate ?? state.averageHeartRate
        state.maxHeartRate = maxHeartRate ?? state.maxHeartRate
        state.activeEnergyKilocalories = activeEnergyKilocalories ?? state.activeEnergyKilocalories
        state.healthKitWorkoutUUID = workoutUUID ?? state.healthKitWorkoutUUID
        state.healthKitStatusMessage = message
        state.updatedAt = Date()
        syncStore.storeActiveGymState(state, broadcast: true, reason: workoutUUID == nil ? "watchGymWorkoutFinished" : "watchGymWorkoutFinishedWithHealthKit")
    }

    private func normalizedState(_ state: ActiveGymWorkoutState) -> ActiveGymWorkoutState {
        var next = state
        next.exercises.sort { $0.orderIndex < $1.orderIndex }
        next.totalExercises = next.exercises.count
        next.totalSets = next.exercises.reduce(0) { $0 + $1.sets.count }
        next.completedSets = next.exercises.reduce(0) { total, exercise in
            total + exercise.sets.filter(\.isCompleted).count
        }
        next.elapsedSeconds = max(next.elapsedSeconds, Int(Date().timeIntervalSince(next.startedAt)))

        if let exerciseIndex = next.exercises.firstIndex(where: { !$0.isCompleted }) {
            if let nextAction = next.nextActionIndices {
                next.currentExerciseIndex = nextAction.exerciseIndex
                next.currentSetIndex = nextAction.setIndex
            } else {
                next.currentExerciseIndex = exerciseIndex
                next.currentSetIndex = next.exercises[exerciseIndex].sets.firstIndex(where: { !$0.isCompleted }) ?? 0
            }
        } else if let lastExerciseIndex = next.exercises.indices.last {
            next.currentExerciseIndex = lastExerciseIndex
            next.currentSetIndex = max(next.exercises[lastExerciseIndex].sets.count - 1, 0)
        } else {
            next.currentExerciseIndex = 0
            next.currentSetIndex = 0
        }

        next.updatedAt = Date()
        return next
    }

    private static func activeExerciseState(_ exercise: WatchGymRoutineExercisePlan) -> ActiveGymWorkoutExerciseState {
        let plannedSets = max(1, exercise.plannedSets)
        let sets = (1...plannedSets).map { setNumber in
            ActiveGymWorkoutSetState(
                id: UUID(),
                setNumber: setNumber,
                targetReps: max(1, exercise.plannedReps),
                targetWeight: max(0, exercise.plannedWeight),
                completedReps: nil,
                completedWeight: nil,
                isCompleted: false,
                completedAt: nil
            )
        }

        return ActiveGymWorkoutExerciseState(
            id: exercise.id,
            exerciseId: exercise.exerciseId,
            exerciseName: exercise.name,
            muscleGroup: exercise.muscleGroup,
            equipment: exercise.equipment,
            plannedSets: plannedSets,
            plannedReps: max(1, exercise.plannedReps),
            plannedWeight: max(0, exercise.plannedWeight),
            weightUnit: exercise.weightUnit,
            plannedRestSeconds: max(0, exercise.plannedRestSeconds),
            orderIndex: exercise.orderIndex,
            notes: exercise.notes,
            supersetGroupId: exercise.supersetGroupId,
            supersetOrder: exercise.supersetOrder,
            supersetType: exercise.supersetType,
            supersetRestSeconds: exercise.supersetRestSeconds,
            supersetSharedSetCount: exercise.supersetSharedSetCount,
            sets: sets
        )
    }

    private func restDecisionAfterCompleting(
        exerciseIndex: Int,
        setIndex: Int,
        in state: ActiveGymWorkoutState
    ) -> Int? {
        let exercise = state.exercises[exerciseIndex]
        guard let groupID = exercise.supersetGroupId else {
            return exercise.plannedRestSeconds
        }

        let members = state.exercises.enumerated()
            .filter { $0.element.supersetGroupId == groupID }
            .sorted {
                ($0.element.supersetOrder ?? $0.element.orderIndex) < ($1.element.supersetOrder ?? $1.element.orderIndex)
            }
        guard members.count >= 2 else {
            return exercise.plannedRestSeconds
        }

        let completedSetNumber = exercise.sets[setIndex].setNumber
        let roundIsComplete = members.prefix(2).allSatisfy { member in
            guard let matchingSet = member.element.sets.first(where: { $0.setNumber == completedSetNumber }) else { return false }
            return matchingSet.isCompleted
        }
        guard roundIsComplete else { return nil }

        let sharedSetCount = max(1, exercise.supersetSharedSetCount ?? members.map { $0.element.sets.count }.max() ?? 1)
        guard completedSetNumber < sharedSetCount else { return nil }
        return exercise.supersetRestSeconds ?? members.compactMap { $0.element.supersetRestSeconds }.first ?? exercise.plannedRestSeconds
    }

    private func handle(_ action: ActiveGymWorkoutAction) async {
        switch action.kind {
        case .finishWorkout:
            guard shouldHandleSessionScopedAction(action, reason: "watchGymFinishFromPhone") != nil else { return }
            await finishCurrentWorkoutIfNeeded()
        case .requestState:
            activeSessionId = activeSessionId ?? action.sessionId
            syncStore.sendGymAction(.requestState(sessionId: activeSessionId))
        case .skipRestTimer:
            if let sessionId = shouldHandleSessionScopedAction(action, reason: "watchGymRestSkippedFromPhone") {
                clearRest(sessionId: sessionId, reason: "watchGymRestSkippedFromPhone")
            }
        case .updateSetValues:
            guard let sessionId = shouldHandleSessionScopedAction(action, reason: "watchGymSetAdjustedFromPhone"),
                  let exerciseId = action.exerciseId,
                  let setId = action.setId else { return }
            updateSetValues(sessionId: sessionId, exerciseId: exerciseId, setId: setId, reps: action.setReps, weight: action.setWeight, sendsAction: false, playsHaptic: false)
        case .completeSet:
            guard let sessionId = shouldHandleSessionScopedAction(action, reason: "watchGymSetCompletedFromPhone"),
                  let exerciseId = action.exerciseId,
                  let setId = action.setId else { return }
            completeSet(sessionId: sessionId, exerciseId: exerciseId, setId: setId, reps: action.setReps, weight: action.setWeight, sendsAction: false)
        case .metricsUpdated,
             .requestSavedRoutines,
             .startFreeWorkoutFromWatch,
             .startSavedRoutineFromWatch:
            break
        }
    }

    private func shouldHandleSessionScopedAction(_ action: ActiveGymWorkoutAction, reason: String) -> UUID? {
        guard let incomingSessionId = action.sessionId else {
            PulsarSyncDebugLogger.log("Watch Gym action ignored because it has no session kind=\(action.kind.rawValue) reason=\(reason)")
            return nil
        }
        guard let activeSessionId else {
            PulsarSyncDebugLogger.log("Watch Gym action ignored because no local session is active kind=\(action.kind.rawValue) session=\(incomingSessionId.uuidString) reason=\(reason)")
            return nil
        }
        guard activeSessionId == incomingSessionId else {
            PulsarSyncDebugLogger.log("Watch Gym action ignored because session does not match kind=\(action.kind.rawValue) incoming=\(incomingSessionId.uuidString) active=\(activeSessionId.uuidString) reason=\(reason)")
            return nil
        }
        return incomingSessionId
    }

    private func finishWorkout() async {
        guard !isFinishing, workoutSession != nil || workoutBuilder != nil else { return }
        isFinishing = true
        let session = workoutSession
        let builder = workoutBuilder
        tickTask?.cancel()
        tickTask = nil
        stateTickTask?.cancel()
        stateTickTask = nil
        finishFallbackTask?.cancel()
        finishFallbackTask = nil
        stopRest()

        let end = Date()
        defer {
            session?.end()
            PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Watch Gym HealthKit session ended after builder finish session=\(activeSessionId?.uuidString ?? "none")")
        }
        do {
            try await builder?.endCollection(at: end)
            let workout = try await builder?.finishWorkout()
            sendMetricsIfNeeded(force: true, workoutUUID: workout?.uuid)
            markActiveStateFinished(workoutUUID: workout?.uuid)
            WKInterfaceDevice.current().play(.success)
        } catch {
            message = "Apple Watch saved the local gym state, but Health finish failed."
            PulsarSyncDebugLogger.log("Watch Gym workout finish failed: \(error.localizedDescription)")
            sendMetricsIfNeeded(force: true)
            markActiveStateFinished(workoutUUID: nil)
        }
        cleanup()
    }

    private func cleanup() {
        tickTask?.cancel()
        tickTask = nil
        stateTickTask?.cancel()
        stateTickTask = nil
        finishFallbackTask?.cancel()
        finishFallbackTask = nil
        stopRest()
        workoutSession = nil
        workoutBuilder = nil
        startedAt = nil
        isFinishing = false
    }

    private func requestWorkoutSessionStop(reason: String) {
        guard let workoutSession else {
            PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Watch Gym HealthKit stop skipped because session is nil reason=\(reason) session=\(activeSessionId?.uuidString ?? "none")")
            Task { await finishWorkout() }
            return
        }
        switch workoutSession.state {
        case .ended, .stopped:
            PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Watch Gym HealthKit stop skipped because session is already terminal reason=\(reason) state=\(Self.describe(workoutSession.state)) session=\(activeSessionId?.uuidString ?? "none")")
            Task { await finishWorkout() }
        default:
            workoutSession.stopActivity(with: Date())
            PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Watch Gym HealthKit stopActivity requested reason=\(reason) state=\(Self.describe(workoutSession.state)) session=\(activeSessionId?.uuidString ?? "none")")
            finishFallbackTask?.cancel()
            finishFallbackTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await MainActor.run {
                    guard let self,
                          !self.isFinishing,
                          self.workoutSession != nil || self.workoutBuilder != nil else { return }
                    PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Watch Gym stopped callback timed out; finishing builder fallback session=\(self.activeSessionId?.uuidString ?? "none")")
                    Task { await self.finishWorkout() }
                }
            }
        }
    }

    private static func describe(_ state: HKWorkoutSessionState) -> String {
        switch state {
        case .notStarted:
            "notStarted"
        case .prepared:
            "prepared"
        case .running:
            "running"
        case .paused:
            "paused"
        case .stopped:
            "stopped"
        case .ended:
            "ended"
        @unknown default:
            "unknown(\(state.rawValue))"
        }
    }

    private static let strengthConfiguration: HKWorkoutConfiguration = {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        return configuration
    }()

    private static var healthShareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        [
            HKQuantityTypeIdentifier.activeEnergyBurned
        ].compactMap { HKObjectType.quantityType(forIdentifier: $0) }.forEach { types.insert($0) }
        return types
    }

    private static var healthReadTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = healthShareTypes
        [
            HKQuantityTypeIdentifier.heartRate,
            .activeEnergyBurned
        ].compactMap { HKObjectType.quantityType(forIdentifier: $0) }.forEach { types.insert($0) }
        return types
    }
}

extension WatchGymSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            if toState == .stopped {
                await self.finishWorkout()
            } else if toState == .ended {
                PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Watch Gym HealthKit session ended callback session=\(self.activeSessionId?.uuidString ?? "none")")
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.message = error.localizedDescription
            PulsarSyncDebugLogger.log("Watch Gym workout session failed: \(error.localizedDescription)")
        }
    }
}

extension WatchGymSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            self.updateBuilderStatistics(for: collectedTypes)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
