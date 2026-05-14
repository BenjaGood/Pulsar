//
//  GymWorkoutSessionViewModel.swift
//  Pulsar
//

import Combine
import Foundation
import HealthKit

struct GymWorkoutSetFocusTarget: Identifiable, Equatable {
    let id = UUID()
    var exerciseID: UUID
    var setID: UUID
    var setNumber: Int
    var supersetGroupID: UUID?
}

struct GymRestContext: Equatable {
    var title: String
    var supersetGroupID: UUID?
}

enum GymSetToggleOutcome: Equatable {
    case ignored
    case reopened
    case completed
    case completedSupersetRound
}

@MainActor
final class GymWorkoutSessionViewModel: ObservableObject {
    @Published private(set) var session: PulsarGymWorkoutSession
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var restCountdownSeconds: Int?
    @Published private(set) var restTotalSeconds: Int?
    @Published private(set) var restContext: GymRestContext?
    @Published private(set) var focusTarget: GymWorkoutSetFocusTarget?
    @Published private(set) var highlightedSetID: UUID?
    @Published private(set) var supersetRoundCompletionPulse = UUID()
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
    private let previousPerformanceByExerciseKey: [String: RoutinePerformanceSnapshot]
    private var timerTask: Task<Void, Never>?
    private var restTask: Task<Void, Never>?
    private var highlightTask: Task<Void, Never>?
    private var restEndsAt: Date?
    private var pendingRestFocusTarget: GymWorkoutSetFocusTarget?
    private var didStartWorkoutSystems = false

    @MainActor
    init(
        routine: PulsarRoutine,
        workoutWeightUnit: PulsarWeightUnit? = nil,
        historyStore: PulsarGymWorkoutHistoryStore? = nil,
        healthKitManager: GymHealthKitWorkoutManager? = nil,
        watchSyncStore: PulsarWatchConnectivitySyncStore? = nil,
        liveActivityManager: GymLiveActivityManager? = nil
    ) {
        let resolvedHistoryStore = historyStore ?? PulsarGymWorkoutHistoryStore()
        let displayUnit = workoutWeightUnit ?? routine.exercises.first?.weightUnit ?? .kilograms
        let snapshots = StrengthProgressAnalyticsService.performanceSnapshots(
            for: routine,
            sessions: resolvedHistoryStore.sessions,
            displayUnit: displayUnit
        )
        let preparedRoutine = StrengthProgressAnalyticsService.routineWithLatestPerformanceOverlay(
            routine,
            sessions: resolvedHistoryStore.sessions,
            displayUnit: displayUnit
        )

        self.session = PulsarGymWorkoutSession(routine: preparedRoutine)
        self.historyStore = resolvedHistoryStore
        self.healthKitManager = healthKitManager ?? GymHealthKitWorkoutManager()
        self.watchSyncStore = watchSyncStore ?? .shared
        self.liveActivityManager = liveActivityManager ?? GymLiveActivityManager()
        self.previousPerformanceByExerciseKey = snapshots

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
        highlightTask?.cancel()
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

    func previousPerformance(for exercise: PulsarGymWorkoutExerciseSession) -> RoutinePerformanceSnapshot? {
        let key = StrengthProgressAnalyticsService.exerciseKey(id: exercise.exerciseId, name: exercise.exerciseName)
        return previousPerformanceByExerciseKey[key]
    }

    func startWorkoutIfNeeded() async {
        guard !didStartWorkoutSystems else { return }
        didStartWorkoutSystems = true
        startTimerIfNeeded()

        let initialState = activeState(isFinished: false)
        watchSyncStore.storeActiveGymState(initialState, broadcast: true, reason: "gymWorkoutStarted")
        liveActivityManager.startIfPossible(state: initialState)
        PulsarSyncDebugLogger.log("Gym workout start selectedType=\(session.workoutKind.rawValue) hkType=\(HKWorkoutActivityType.traditionalStrengthTraining.rawValue) session=\(session.id.uuidString) startedFrom=iPhone")

        let didStartHealthKit = await healthKitManager.startWorkout(
            routineName: session.routineName,
            workoutKind: session.workoutKind,
            routineId: session.routineId,
            sessionId: session.id,
            startedAt: session.startedAt
        )
        isHealthKitEnabled = didStartHealthKit
        healthKitStatusMessage = healthKitManager.statusMessage
        session.healthKitStatusMessage = healthKitStatusMessage
        publishState(reason: "gymHealthKitStarted")
    }

    @discardableResult
    func toggleSet(exerciseID: UUID, setID: UUID) -> GymSetToggleOutcome {
        guard summary == nil,
              let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseID }),
              let setIndex = session.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) else { return .ignored }

        if session.exercises[exerciseIndex].sets[setIndex].isCompleted {
            session.exercises[exerciseIndex].sets[setIndex].isCompleted = false
            session.exercises[exerciseIndex].sets[setIndex].completedAt = nil
            session.exercises[exerciseIndex].sets[setIndex].completedReps = nil
            session.exercises[exerciseIndex].sets[setIndex].completedWeight = nil
            cancelRestIfNeeded(for: exerciseID, setNumber: session.exercises[exerciseIndex].sets[setIndex].setNumber)
            requestFocus(
                GymWorkoutSetFocusTarget(
                    exerciseID: exerciseID,
                    setID: setID,
                    setNumber: session.exercises[exerciseIndex].sets[setIndex].setNumber,
                    supersetGroupID: session.exercises[exerciseIndex].supersetGroupId
                )
            )
            publishState(reason: "gymSetReopened")
            return .reopened
        }

        session.exercises[exerciseIndex].sets[setIndex].isCompleted = true
        session.exercises[exerciseIndex].sets[setIndex].completedAt = .now
        session.exercises[exerciseIndex].sets[setIndex].completedReps = session.exercises[exerciseIndex].sets[setIndex].targetReps
        session.exercises[exerciseIndex].sets[setIndex].completedWeight = session.exercises[exerciseIndex].sets[setIndex].targetWeight

        let outcome = handleCompletedSet(exerciseIndex: exerciseIndex, setIndex: setIndex)
        publishState(reason: "gymSetCompleted")
        return outcome
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

    func updateSetValues(exerciseID: UUID, setID: UUID, reps: Int? = nil, weight: Double? = nil) {
        guard summary == nil,
              let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseID }),
              let setIndex = session.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) else { return }

        if let reps {
            let nextReps = max(1, reps)
            session.exercises[exerciseIndex].sets[setIndex].targetReps = nextReps
            if session.exercises[exerciseIndex].sets[setIndex].isCompleted {
                session.exercises[exerciseIndex].sets[setIndex].completedReps = nextReps
            }
        }

        if let weight {
            let nextWeight = max(0, weight)
            session.exercises[exerciseIndex].sets[setIndex].targetWeight = nextWeight
            if session.exercises[exerciseIndex].sets[setIndex].isCompleted {
                session.exercises[exerciseIndex].sets[setIndex].completedWeight = nextWeight
            }
        }

        publishState(reason: "gymSetAdjusted")
    }

    func addSet(to exerciseID: UUID) {
        guard summary == nil,
              let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }

        if let group = supersetGroup(containing: exerciseID) {
            updateSupersetSetCount(groupID: group.id, sharedSetCount: group.sharedSetCount + 1)
            publishState(reason: "gymSupersetSetAdded")
            return
        }

        let sets = session.exercises[exerciseIndex].sets
        let lastSet = sets.last
        let nextSetNumber = sets.count + 1
        let nextSet = PulsarGymWorkoutSetSession(
            setNumber: nextSetNumber,
            targetReps: lastSet?.completedReps ?? lastSet?.targetReps ?? session.exercises[exerciseIndex].plannedReps,
            targetWeight: lastSet?.completedWeight ?? lastSet?.targetWeight ?? session.exercises[exerciseIndex].plannedWeight
        )
        session.exercises[exerciseIndex].sets.append(nextSet)
        session.exercises[exerciseIndex].plannedSets = session.exercises[exerciseIndex].sets.count
        publishState(reason: "gymSetAdded")
    }

    func removeLastSet(from exerciseID: UUID) {
        guard summary == nil,
              let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }

        if let group = supersetGroup(containing: exerciseID) {
            updateSupersetSetCount(groupID: group.id, sharedSetCount: group.sharedSetCount - 1)
            publishState(reason: "gymSupersetSetRemoved")
            return
        }

        guard session.exercises[exerciseIndex].sets.count > 1 else { return }
        session.exercises[exerciseIndex].sets.removeLast()
        session.exercises[exerciseIndex].plannedSets = session.exercises[exerciseIndex].sets.count
        publishState(reason: "gymSetRemoved")
    }

    func skipRest() {
        let target = pendingRestFocusTarget
        clearRestState()
        if let target {
            requestFocus(target)
        }
        publishState(reason: "gymRestSkipped")
    }

    func refreshRestCountdown() {
        guard let restEndsAt else { return }
        let remaining = max(0, Int(ceil(restEndsAt.timeIntervalSinceNow)))
        if remaining > 0 {
            restCountdownSeconds = remaining
            publishState(reason: "gymRestRefreshed")
        } else {
            finishRest(reason: "gymRestFinishedAfterResume")
        }
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

    private func startRest(
        seconds: Int,
        context: GymRestContext? = nil,
        targetAfterRest: GymWorkoutSetFocusTarget? = nil
    ) {
        restTask?.cancel()
        guard seconds > 0 else {
            if let targetAfterRest {
                requestFocus(targetAfterRest)
            }
            return
        }
        restTotalSeconds = seconds
        restCountdownSeconds = seconds
        restContext = context
        restEndsAt = Date().addingTimeInterval(Double(seconds))
        pendingRestFocusTarget = targetAfterRest
        publishState(reason: "gymRestStarted")

        restTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                let remaining = max(0, Int(ceil((self.restEndsAt ?? Date()).timeIntervalSinceNow)))
                if remaining <= 0 { break }
                self.restCountdownSeconds = remaining
                self.publishState(reason: "gymRestTick")
            }

            guard !Task.isCancelled else { return }
            self?.finishRest(reason: "gymRestFinished")
        }
    }

    private func finishRest(reason: String) {
        let target = pendingRestFocusTarget
        clearRestState()
        if let target {
            requestFocus(target)
        }
        publishState(reason: reason)
    }

    private func clearRestState() {
        restTask?.cancel()
        restTask = nil
        restCountdownSeconds = nil
        restTotalSeconds = nil
        restContext = nil
        restEndsAt = nil
        pendingRestFocusTarget = nil
    }

    private func handleCompletedSet(exerciseIndex: Int, setIndex: Int) -> GymSetToggleOutcome {
        let exercise = session.exercises[exerciseIndex]
        let completedSet = exercise.sets[setIndex]

        guard let group = supersetGroup(containing: exercise.id),
              supersetMemberIndices(for: group).count >= 2 else {
            let restSeconds = exercise.plannedRestSeconds
            if restSeconds > 0, !isWorkoutComplete {
                startRest(seconds: restSeconds)
            }
            return .completed
        }

        let memberIndices = supersetMemberIndices(for: group)
        for memberIndex in memberIndices {
            guard let matchingSetIndex = session.exercises[memberIndex].sets.firstIndex(where: { $0.setNumber == completedSet.setNumber }) else {
                continue
            }
            if !session.exercises[memberIndex].sets[matchingSetIndex].isCompleted {
                requestFocus(
                    GymWorkoutSetFocusTarget(
                        exerciseID: session.exercises[memberIndex].id,
                        setID: session.exercises[memberIndex].sets[matchingSetIndex].id,
                        setNumber: completedSet.setNumber,
                        supersetGroupID: group.id
                    )
                )
                return .completed
            }
        }

        supersetRoundCompletionPulse = UUID()
        let targetAfterRest = nextSupersetRoundTarget(after: completedSet.setNumber, in: group)
        if let targetAfterRest, group.restTimeSeconds > 0 {
            startRest(
                seconds: group.restTimeSeconds,
                context: GymRestContext(title: "\(supersetLabel(for: group.id)) rest", supersetGroupID: group.id),
                targetAfterRest: targetAfterRest
            )
        } else if let targetAfterRest {
            requestFocus(targetAfterRest)
        }
        return .completedSupersetRound
    }

    private func supersetGroup(containing exerciseID: UUID) -> PulsarSupersetGroup? {
        session.supersetGroups.first { $0.exerciseIds.contains(exerciseID) }
    }

    func supersetGroup(id groupID: UUID) -> PulsarSupersetGroup? {
        session.supersetGroups.first { $0.id == groupID }
    }

    func supersetMembers(for group: PulsarSupersetGroup) -> [PulsarGymWorkoutExerciseSession] {
        supersetMemberIndices(for: group).map { session.exercises[$0] }
    }

    func supersetLabel(for groupID: UUID) -> String {
        guard let index = orderedSupersetGroups().firstIndex(where: { $0.id == groupID }) else {
            return "Superset"
        }
        return "Superset \(Self.groupLetter(for: index))"
    }

    func supersetBadge(for exercise: PulsarGymWorkoutExerciseSession) -> String? {
        guard let groupID = exercise.supersetGroupId,
              let index = orderedSupersetGroups().firstIndex(where: { $0.id == groupID }) else { return nil }
        let order = (exercise.supersetOrder ?? 0) + 1
        return "\(Self.groupLetter(for: index))\(order)"
    }

    func isFirstSupersetMember(_ exercise: PulsarGymWorkoutExerciseSession) -> Bool {
        guard let group = supersetGroup(containing: exercise.id) else { return false }
        return supersetMemberIndices(for: group).first.flatMap { session.exercises[$0].id } == exercise.id
    }

    private func supersetMemberIndices(for group: PulsarSupersetGroup) -> [Int] {
        group.exerciseIds.compactMap { exerciseID in
            session.exercises.firstIndex(where: { $0.id == exerciseID })
        }
        .sorted {
            let first = session.exercises[$0]
            let second = session.exercises[$1]
            return (first.supersetOrder ?? first.orderIndex) < (second.supersetOrder ?? second.orderIndex)
        }
    }

    private func orderedSupersetGroups() -> [PulsarSupersetGroup] {
        session.supersetGroups.sorted { first, second in
            let firstOrder = first.exerciseIds.compactMap { exerciseID in
                session.exercises.first(where: { $0.id == exerciseID })?.orderIndex
            }.min() ?? 0
            let secondOrder = second.exerciseIds.compactMap { exerciseID in
                session.exercises.first(where: { $0.id == exerciseID })?.orderIndex
            }.min() ?? 0
            return firstOrder < secondOrder
        }
    }

    private func nextSupersetRoundTarget(after setNumber: Int, in group: PulsarSupersetGroup) -> GymWorkoutSetFocusTarget? {
        guard let firstMemberIndex = supersetMemberIndices(for: group).first else { return nil }
        let nextSetNumber = setNumber + 1
        guard let nextSet = session.exercises[firstMemberIndex].sets.first(where: { $0.setNumber == nextSetNumber }) else { return nil }
        return GymWorkoutSetFocusTarget(
            exerciseID: session.exercises[firstMemberIndex].id,
            setID: nextSet.id,
            setNumber: nextSetNumber,
            supersetGroupID: group.id
        )
    }

    private func updateSupersetSetCount(groupID: UUID, sharedSetCount: Int) {
        guard let groupIndex = session.supersetGroups.firstIndex(where: { $0.id == groupID }) else { return }
        let nextCount = max(1, sharedSetCount)
        session.supersetGroups[groupIndex].sharedSetCount = nextCount
        let group = session.supersetGroups[groupIndex]

        for exerciseID in group.exerciseIds {
            guard let exerciseIndex = session.exercises.firstIndex(where: { $0.id == exerciseID }) else { continue }
            session.exercises[exerciseIndex].alignSetCount(to: nextCount)
            session.exercises[exerciseIndex].supersetGroupId = group.id
            session.exercises[exerciseIndex].supersetOrder = group.exerciseIds.firstIndex(of: exerciseID)
            session.exercises[exerciseIndex].supersetRestSeconds = group.restTimeSeconds
        }
    }

    private func cancelRestIfNeeded(for exerciseID: UUID, setNumber: Int) {
        guard let group = supersetGroup(containing: exerciseID),
              restContext?.supersetGroupID == group.id else { return }
        clearRestState()
    }

    private func requestFocus(_ target: GymWorkoutSetFocusTarget) {
        focusTarget = target
        highlightedSetID = target.setID
        highlightTask?.cancel()
        highlightTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_650_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self?.highlightedSetID == target.setID {
                    self?.highlightedSetID = nil
                }
            }
        }
    }

    private static func groupLetter(for index: Int) -> String {
        let scalar = UnicodeScalar(65 + max(0, min(index, 25)))
        return scalar.map { String(Character($0)) } ?? "A"
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
        let currentTarget = currentActionTarget(in: sortedExercises)
        let currentExerciseIndex = currentTarget?.exerciseIndex ?? sortedExercises.firstIndex { !$0.isCompleted } ?? max(sortedExercises.count - 1, 0)
        let currentExercise = sortedExercises.indices.contains(currentExerciseIndex) ? sortedExercises[currentExerciseIndex] : nil
        let currentSetIndex = currentTarget?.setIndex ?? currentExercise?.sets.firstIndex { !$0.isCompleted } ?? 0

        return ActiveGymWorkoutState(
            sessionId: session.id,
            routineId: session.routineId,
            routineName: session.routineName,
            routineEmoji: session.routineEmoji,
            workoutKind: session.workoutKind,
            startedFrom: .iPhone,
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
            healthKitWorkoutUUID: session.healthKitWorkoutUUID,
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
        let group = exercise.supersetGroupId.flatMap { supersetGroup(id: $0) }
        return ActiveGymWorkoutExerciseState(
            id: exercise.id,
            exerciseId: exercise.exerciseId,
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
            supersetGroupId: exercise.supersetGroupId,
            supersetOrder: exercise.supersetOrder,
            supersetType: group?.type.rawValue,
            supersetRestSeconds: group?.restTimeSeconds,
            supersetSharedSetCount: group?.sharedSetCount,
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

    private func currentActionTarget(in sortedExercises: [PulsarGymWorkoutExerciseSession]) -> (exerciseIndex: Int, setIndex: Int)? {
        if let focusTarget,
           let exerciseIndex = sortedExercises.firstIndex(where: { $0.id == focusTarget.exerciseID }),
           let setIndex = sortedExercises[exerciseIndex].sets.firstIndex(where: { $0.id == focusTarget.setID }),
           !sortedExercises[exerciseIndex].sets[setIndex].isCompleted {
            return (exerciseIndex, setIndex)
        }

        var consumedSupersetGroupIds: Set<UUID> = []
        for exercise in sortedExercises {
            guard let originalIndex = sortedExercises.firstIndex(where: { $0.id == exercise.id }) else { continue }
            if let groupID = exercise.supersetGroupId {
                guard consumedSupersetGroupIds.insert(groupID).inserted,
                      let group = supersetGroup(id: groupID) else { continue }
                let members = group.exerciseIds.compactMap { memberID in
                    sortedExercises.firstIndex(where: { $0.id == memberID })
                }
                .sorted {
                    let first = sortedExercises[$0]
                    let second = sortedExercises[$1]
                    return (first.supersetOrder ?? first.orderIndex) < (second.supersetOrder ?? second.orderIndex)
                }
                guard members.count >= 2 else {
                    if let setIndex = exercise.sets.firstIndex(where: { !$0.isCompleted }) {
                        return (originalIndex, setIndex)
                    }
                    continue
                }

                for setNumber in 1...max(1, group.sharedSetCount) {
                    for memberIndex in members.prefix(2) {
                        guard let setIndex = sortedExercises[memberIndex].sets.firstIndex(where: { $0.setNumber == setNumber }) else { continue }
                        if !sortedExercises[memberIndex].sets[setIndex].isCompleted {
                            return (memberIndex, setIndex)
                        }
                    }
                }
            } else if let setIndex = exercise.sets.firstIndex(where: { !$0.isCompleted }) {
                return (originalIndex, setIndex)
            }
        }

        return nil
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
        case .requestSavedRoutines,
             .startFreeWorkoutFromWatch,
             .startSavedRoutineFromWatch:
            break
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
