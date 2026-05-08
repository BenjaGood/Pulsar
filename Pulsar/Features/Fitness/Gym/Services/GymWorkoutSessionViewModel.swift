//
//  GymWorkoutSessionViewModel.swift
//  Pulsar
//

import Combine
import Foundation

@MainActor
final class GymWorkoutSessionViewModel: ObservableObject {
    @Published private(set) var session: PulsarGymWorkoutSession
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var restCountdownSeconds: Int?
    @Published private(set) var restTotalSeconds: Int?
    @Published private(set) var summary: PulsarGymWorkoutSummary?
    @Published private(set) var currentHeartRate: Double?
    @Published private(set) var averageHeartRate: Double?
    @Published private(set) var maxHeartRate: Double?
    @Published private(set) var activeEnergyKilocalories: Double?
    @Published private(set) var healthKitStatusMessage: String?
    @Published private(set) var isHealthKitEnabled = false
    @Published private(set) var isFinishing = false

    private let historyStore: PulsarGymWorkoutHistoryStore
    private let healthKitManager: GymHealthKitWorkoutManager
    private let watchSyncStore: PulsarWatchConnectivitySyncStore
    private let liveActivityManager: GymLiveActivityManager
    private var timerTask: Task<Void, Never>?
    private var restTask: Task<Void, Never>?
    private var didStartWorkoutSystems = false

    @MainActor
    init(
        routine: PulsarRoutine,
        historyStore: PulsarGymWorkoutHistoryStore? = nil,
        healthKitManager: GymHealthKitWorkoutManager? = nil,
        watchSyncStore: PulsarWatchConnectivitySyncStore? = nil,
        liveActivityManager: GymLiveActivityManager? = nil
    ) {
        self.session = PulsarGymWorkoutSession(routine: routine)
        self.historyStore = historyStore ?? PulsarGymWorkoutHistoryStore()
        self.healthKitManager = healthKitManager ?? GymHealthKitWorkoutManager()
        self.watchSyncStore = watchSyncStore ?? .shared
        self.liveActivityManager = liveActivityManager ?? GymLiveActivityManager()

        self.healthKitManager.onMetricsUpdated = { [weak self] metrics in
            Task { @MainActor in
                self?.applyHealthMetrics(metrics)
            }
        }
        self.watchSyncStore.registerGymActionHandler { [weak self] action in
            Task { @MainActor in
                await self?.handleRemoteAction(action)
            }
        }
    }

    deinit {
        timerTask?.cancel()
        restTask?.cancel()
    }

    var completedSetsCount: Int {
        session.exercises.flatMap(\.sets).filter(\.isCompleted).count
    }

    var totalSetsCount: Int {
        session.exercises.flatMap(\.sets).count
    }

    var completedExercisesCount: Int {
        session.exercises.filter(\.isCompleted).count
    }

    var totalExercisesCount: Int {
        session.exercises.count
    }

    var isWorkoutComplete: Bool {
        totalSetsCount == 0 || completedSetsCount == totalSetsCount
    }

    var progressFraction: Double {
        guard totalSetsCount > 0 else { return 1 }
        return Double(completedSetsCount) / Double(totalSetsCount)
    }

    var restProgressFraction: Double {
        guard let restCountdownSeconds, let restTotalSeconds, restTotalSeconds > 0 else { return 0 }
        return 1 - (Double(restCountdownSeconds) / Double(restTotalSeconds))
    }

    func startWorkoutIfNeeded() async {
        guard !didStartWorkoutSystems else { return }
        didStartWorkoutSystems = true
        startTimerIfNeeded()

        let initialState = activeState(isFinished: false)
        watchSyncStore.storeActiveGymState(initialState, broadcast: true, reason: "gymWorkoutStarted")
        liveActivityManager.startIfPossible(state: initialState)

        let didStartHealthKit = await healthKitManager.startWorkout(
            routineName: session.routineName,
            routineId: session.routineId,
            sessionId: session.id,
            startedAt: session.startedAt
        )
        isHealthKitEnabled = didStartHealthKit
        healthKitStatusMessage = healthKitManager.statusMessage
        session.healthKitStatusMessage = healthKitStatusMessage
        publishState(reason: "gymHealthKitStarted")
    }

    func toggleSet(exerciseID: UUID, setID: UUID) {
        guard summary == nil,
              let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseID }),
              let setIndex = session.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) else { return }

        if session.exercises[exerciseIndex].sets[setIndex].isCompleted {
            session.exercises[exerciseIndex].sets[setIndex].isCompleted = false
            session.exercises[exerciseIndex].sets[setIndex].completedAt = nil
            session.exercises[exerciseIndex].sets[setIndex].completedReps = nil
            session.exercises[exerciseIndex].sets[setIndex].completedWeight = nil
            publishState(reason: "gymSetReopened")
            return
        }

        session.exercises[exerciseIndex].sets[setIndex].isCompleted = true
        session.exercises[exerciseIndex].sets[setIndex].completedAt = .now
        session.exercises[exerciseIndex].sets[setIndex].completedReps = session.exercises[exerciseIndex].sets[setIndex].targetReps
        session.exercises[exerciseIndex].sets[setIndex].completedWeight = session.exercises[exerciseIndex].sets[setIndex].targetWeight

        let restSeconds = session.exercises[exerciseIndex].plannedRestSeconds
        if restSeconds > 0, !isWorkoutComplete {
            startRest(seconds: restSeconds)
        }
        publishState(reason: "gymSetCompleted")
    }

    func updateCompletedSet(exerciseID: UUID, setID: UUID, reps: Int? = nil, weight: Double? = nil) {
        guard let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseID }),
              let setIndex = session.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) else { return }

        if let reps {
            session.exercises[exerciseIndex].sets[setIndex].completedReps = max(1, reps)
        }
        if let weight {
            session.exercises[exerciseIndex].sets[setIndex].completedWeight = max(0, weight)
        }
        publishState(reason: "gymSetEdited")
    }

    func skipRest() {
        restTask?.cancel()
        restTask = nil
        restCountdownSeconds = nil
        restTotalSeconds = nil
        publishState(reason: "gymRestSkipped")
    }

    @discardableResult
    func finishWorkout() async -> PulsarGymWorkoutSummary {
        guard !isFinishing else {
            return summary ?? PulsarGymWorkoutSummary(session: session)
        }
        isFinishing = true
        timerTask?.cancel()
        timerTask = nil
        skipRest()

        let endedAt = Date()
        session.finishedAt = endedAt
        session.elapsedSeconds = max(elapsedSeconds, Int(endedAt.timeIntervalSince(session.startedAt)))

        watchSyncStore.sendGymAction(.finishWorkout(sessionId: session.id))

        let healthResult = await healthKitManager.finishWorkout(endedAt: endedAt)
        let finalWorkoutUUID = healthResult.workoutUUID ?? session.healthKitWorkoutUUID
        let finalEnergy = healthResult.activeEnergyKilocalories ?? activeEnergyKilocalories ?? session.activeEnergyKilocalories
        let finalAverageHeartRate = healthResult.averageHeartRate ?? averageHeartRate ?? session.averageHeartRate
        let finalMaxHeartRate = healthResult.maxHeartRate ?? maxHeartRate ?? session.maxHeartRate

        session.healthKitWorkoutUUID = finalWorkoutUUID
        session.activeEnergyKilocalories = finalEnergy
        session.averageHeartRate = finalAverageHeartRate
        session.maxHeartRate = finalMaxHeartRate
        session.healthKitStatusMessage = healthResult.statusMessage

        healthKitStatusMessage = healthResult.statusMessage
        averageHeartRate = finalAverageHeartRate
        maxHeartRate = finalMaxHeartRate
        activeEnergyKilocalories = finalEnergy

        let savedSession = historyStore.save(session)
        session = savedSession
        let workoutSummary = PulsarGymWorkoutSummary(session: savedSession)
        summary = workoutSummary

        let finishedState = activeState(isFinished: true)
        watchSyncStore.storeActiveGymState(finishedState, broadcast: true, reason: "gymWorkoutFinished")
        liveActivityManager.end(state: finishedState)
        watchSyncStore.unregisterGymActionHandler()
        isFinishing = false
        return workoutSummary
    }

    private func startTimerIfNeeded() {
        guard timerTask == nil else { return }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(self.session.startedAt))
                self.session.elapsedSeconds = self.elapsedSeconds
                self.publishState(reason: "gymWorkoutTick")
            }
        }
    }

    private func startRest(seconds: Int) {
        restTask?.cancel()
        restTotalSeconds = seconds
        restCountdownSeconds = seconds
        publishState(reason: "gymRestStarted")

        restTask = Task { [weak self] in
            var remaining = seconds
            while remaining > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                remaining -= 1
                self?.restCountdownSeconds = remaining
                self?.publishState(reason: "gymRestTick")
            }

            guard !Task.isCancelled else { return }
            self?.restCountdownSeconds = nil
            self?.restTotalSeconds = nil
            self?.restTask = nil
            self?.publishState(reason: "gymRestFinished")
        }
    }

    private func applyHealthMetrics(_ metrics: GymHealthKitWorkoutMetrics) {
        currentHeartRate = metrics.currentHeartRate ?? currentHeartRate
        averageHeartRate = metrics.averageHeartRate ?? averageHeartRate
        maxHeartRate = metrics.maxHeartRate ?? maxHeartRate
        activeEnergyKilocalories = metrics.activeEnergyKilocalories ?? activeEnergyKilocalories
        session.averageHeartRate = averageHeartRate
        session.maxHeartRate = maxHeartRate
        session.activeEnergyKilocalories = activeEnergyKilocalories
        publishState(reason: "gymHealthMetricsUpdated")
    }

    private func applyRemoteMetrics(from action: ActiveGymWorkoutAction) {
        healthKitManager.mergeExternalMetrics(
            GymHealthKitWorkoutMetrics(
                currentHeartRate: action.currentHeartRate,
                averageHeartRate: action.averageHeartRate,
                maxHeartRate: action.maxHeartRate,
                activeEnergyKilocalories: action.activeEnergyKilocalories
            )
        )

        currentHeartRate = action.currentHeartRate ?? currentHeartRate
        averageHeartRate = action.averageHeartRate ?? averageHeartRate
        maxHeartRate = action.maxHeartRate ?? maxHeartRate
        activeEnergyKilocalories = action.activeEnergyKilocalories ?? activeEnergyKilocalories
        session.averageHeartRate = averageHeartRate
        session.maxHeartRate = maxHeartRate
        session.activeEnergyKilocalories = activeEnergyKilocalories
        session.healthKitWorkoutUUID = action.healthKitWorkoutUUID ?? session.healthKitWorkoutUUID

        if action.currentHeartRate != nil || action.activeEnergyKilocalories != nil {
            isHealthKitEnabled = true
            if healthKitStatusMessage == "Apple Health could not start this strength workout. Pulsar is still tracking it locally." ||
                healthKitStatusMessage == "Apple Health permission is needed for heart rate and workout saving. Pulsar is tracking locally." {
                healthKitStatusMessage = nil
            }
        }

        publishState(reason: "gymRemoteHealthMetricsUpdated")
    }

    private func publishState(reason: String) {
        let state = activeState(isFinished: summary != nil)
        watchSyncStore.storeActiveGymState(state, broadcast: true, reason: reason)
        if summary == nil {
            liveActivityManager.update(state: state)
        }
    }

    private func activeState(isFinished: Bool) -> ActiveGymWorkoutState {
        let sortedExercises = session.exercises.sorted { $0.orderIndex < $1.orderIndex }
        let currentExerciseIndex = sortedExercises.firstIndex { !$0.isCompleted } ?? max(sortedExercises.count - 1, 0)
        let currentExercise = sortedExercises.indices.contains(currentExerciseIndex) ? sortedExercises[currentExerciseIndex] : nil
        let currentSetIndex = currentExercise?.sets.firstIndex { !$0.isCompleted } ?? 0

        return ActiveGymWorkoutState(
            sessionId: session.id,
            routineId: session.routineId,
            routineName: session.routineName,
            startedAt: session.startedAt,
            elapsedSeconds: elapsedSeconds,
            currentExerciseIndex: currentExerciseIndex,
            currentSetIndex: currentSetIndex,
            totalExercises: totalExercisesCount,
            totalSets: totalSetsCount,
            completedSets: completedSetsCount,
            currentHeartRate: currentHeartRate,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            activeEnergyKilocalories: activeEnergyKilocalories,
            restRemainingSeconds: restCountdownSeconds,
            restTotalSeconds: restTotalSeconds,
            isHealthKitEnabled: isHealthKitEnabled,
            healthKitStatusMessage: healthKitStatusMessage,
            isFinished: isFinished,
            updatedAt: Date(),
            exercises: sortedExercises.map(activeExerciseState)
        )
    }

    private func activeExerciseState(_ exercise: PulsarGymWorkoutExerciseSession) -> ActiveGymWorkoutExerciseState {
        ActiveGymWorkoutExerciseState(
            id: exercise.id,
            exerciseName: exercise.exerciseName,
            muscleGroup: exercise.primaryMuscleGroup.displayName,
            equipment: exercise.equipment,
            plannedSets: exercise.plannedSets,
            plannedReps: exercise.plannedReps,
            plannedWeight: exercise.plannedWeight,
            weightUnit: exercise.weightUnit.displayName,
            plannedRestSeconds: exercise.plannedRestSeconds,
            orderIndex: exercise.orderIndex,
            notes: exercise.notes,
            sets: exercise.sets.map { set in
                ActiveGymWorkoutSetState(
                    id: set.id,
                    setNumber: set.setNumber,
                    targetReps: set.targetReps,
                    targetWeight: set.targetWeight,
                    completedReps: set.completedReps,
                    completedWeight: set.completedWeight,
                    isCompleted: set.isCompleted,
                    completedAt: set.completedAt
                )
            }
        )
    }

    private func handleRemoteAction(_ action: ActiveGymWorkoutAction) async {
        if let actionSessionId = action.sessionId, actionSessionId != session.id {
            return
        }

        switch action.kind {
        case .completeSet:
            guard let exerciseId = action.exerciseId, let setId = action.setId else { return }
            completeSetFromRemote(exerciseID: exerciseId, setID: setId)
        case .skipRestTimer:
            skipRest()
        case .finishWorkout:
            await finishWorkout()
        case .requestState:
            publishState(reason: "gymStateRequested")
        case .metricsUpdated:
            applyRemoteMetrics(from: action)
        }
    }

    private func completeSetFromRemote(exerciseID: UUID, setID: UUID) {
        guard let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseID }),
              let setIndex = session.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) else {
            publishState(reason: "gymRemoteSetIgnored")
            return
        }
        guard !session.exercises[exerciseIndex].sets[setIndex].isCompleted else {
            publishState(reason: "gymRemoteSetAlreadyCompleted")
            return
        }
        toggleSet(exerciseID: exerciseID, setID: setID)
    }
}
