//
//  PulsarGymSharedModels.swift
//  Pulsar
//

import Foundation

enum PulsarGymWorkoutKind: String, nonisolated Codable, Hashable, Sendable {
    case routine
    case freeWorkout

    nonisolated var displayName: String {
        switch self {
        case .routine: "Gym Workout"
        case .freeWorkout: "Free Workout"
        }
    }

    nonisolated var categoryName: String { "Gym" }

    nonisolated static func inferred(routineName: String, exerciseCount: Int) -> PulsarGymWorkoutKind {
        let normalizedName = routineName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let knownFreeWorkoutNames: Set<String> = [
            "free workout",
            "free gym",
            "empty gym workout",
            "open gym",
            "open gym workout"
        ]

        if knownFreeWorkoutNames.contains(normalizedName) {
            return .freeWorkout
        }
        return exerciseCount == 0 ? .freeWorkout : .routine
    }
}

struct WatchGymRoutinePlan: nonisolated Codable, Hashable, Identifiable, Sendable {
    var id: UUID { routineId }

    var routineId: UUID
    var name: String
    var emoji: String
    var exerciseCount: Int
    var mainMuscleGroups: [String]
    var estimatedDurationSeconds: Int
    var updatedAt: Date
    var exercises: [WatchGymRoutineExercisePlan]

    var subtitle: String {
        if !mainMuscleGroups.isEmpty {
            return mainMuscleGroups.prefix(3).joined(separator: " / ")
        }
        return exerciseCount == 1 ? "1 exercise" : "\(exerciseCount) exercises"
    }

    nonisolated var totalSetCount: Int {
        exercises.reduce(0) { $0 + max(1, $1.plannedSets) }
    }

    /// A name-only payload is never a valid representation of a non-empty
    /// routine. Reject it instead of allowing Codable defaults or an old queued
    /// transfer to erase a complete cached definition.
    nonisolated var hasCompleteExerciseDefinition: Bool {
        exerciseCount == exercises.count &&
            exercises.allSatisfy { !$0.name.isEmpty && $0.plannedSets > 0 && $0.plannedReps > 0 }
    }
}

struct SavedGymRoutinesSyncPayload: nonisolated Codable, Hashable, Sendable {
    var revision: Int
    var routines: [WatchGymRoutinePlan]
    var deletedRoutineIds: [UUID]

    nonisolated init(
        revision: Int,
        routines: [WatchGymRoutinePlan],
        deletedRoutineIds: [UUID] = []
    ) {
        self.revision = max(0, revision)
        self.routines = routines.sorted { $0.updatedAt > $1.updatedAt }
        self.deletedRoutineIds = deletedRoutineIds
    }
}

enum SavedGymRoutineDefinitionMerge {
    /// Preserves a previously decoded routine when an incoming representation
    /// claims exercises but omits their nested definitions. A genuinely empty
    /// routine (`exerciseCount == 0`) remains valid and can replace an old one.
    nonisolated static func preservingCompleteDefinitions(
        incoming: [WatchGymRoutinePlan],
        current: [WatchGymRoutinePlan],
        deletedRoutineIDs: Set<UUID> = []
    ) -> [WatchGymRoutinePlan] {
        let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.routineId, $0) })
        return incoming.compactMap { routine in
            guard !deletedRoutineIDs.contains(routine.routineId) else { return nil }
            guard routine.hasCompleteExerciseDefinition else {
                return currentByID[routine.routineId]
            }
            return routine
        }
    }
}

enum SavedGymRoutinesSyncCodec {
    static func encode(_ payload: SavedGymRoutinesSyncPayload) -> Data? {
        let data = PulsarPerformanceSignposts.measure(
            PulsarPerformanceSignposts.watchConnectivity,
            name: "encode"
        ) {
            try? encoder.encode(payload)
        }
        if let data {
            PulsarSyncDebugLogger.log(
                "[PulsarRoutineSync] source=encodedPayload revision=\(payload.revision) routineCount=\(payload.routines.count) exerciseCount=\(payload.routines.reduce(0) { $0 + $1.exercises.count }) totalSetCount=\(payload.routines.reduce(0) { $0 + $1.totalSetCount }) bytes=\(data.count)"
            )
        }
        return data
    }

    static func decode(_ data: Data) -> SavedGymRoutinesSyncPayload? {
        let payload: SavedGymRoutinesSyncPayload? = PulsarPerformanceSignposts.measure(
            PulsarPerformanceSignposts.watchConnectivity,
            name: "decode"
        ) {
            if let payload = try? decoder.decode(SavedGymRoutinesSyncPayload.self, from: data) {
                return payload
            }
            if let routines = try? decoder.decode([WatchGymRoutinePlan].self, from: data) {
                return SavedGymRoutinesSyncPayload(revision: 0, routines: routines)
            }
            if let routines = try? legacyDecoder.decode([WatchGymRoutinePlan].self, from: data) {
                return SavedGymRoutinesSyncPayload(revision: 0, routines: routines)
            }
            return nil
        }
        if let payload {
            PulsarSyncDebugLogger.log(
                "[PulsarRoutineSync] source=decodedPayload revision=\(payload.revision) routineCount=\(payload.routines.count) exerciseCount=\(payload.routines.reduce(0) { $0 + $1.exercises.count }) totalSetCount=\(payload.routines.reduce(0) { $0 + $1.totalSetCount }) bytes=\(data.count)"
            )
        } else {
            PulsarSyncDebugLogger.log("[PulsarRoutineSync] source=decodedPayloadRejected bytes=\(data.count)")
        }
        return payload
    }

    static func semanticallyEquivalent(_ lhs: Data, _ rhs: Data) -> Bool {
        if lhs == rhs { return true }
        return decodeWithoutLogging(lhs) == decodeWithoutLogging(rhs)
    }

    private static func decodeWithoutLogging(_ data: Data) -> SavedGymRoutinesSyncPayload? {
        if let payload = try? decoder.decode(SavedGymRoutinesSyncPayload.self, from: data) {
            return payload
        }
        if let routines = try? decoder.decode([WatchGymRoutinePlan].self, from: data) {
            return SavedGymRoutinesSyncPayload(revision: 0, routines: routines)
        }
        if let routines = try? legacyDecoder.decode([WatchGymRoutinePlan].self, from: data) {
            return SavedGymRoutinesSyncPayload(revision: 0, routines: routines)
        }
        return nil
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var legacyDecoder: JSONDecoder {
        JSONDecoder()
    }
}

struct WatchGymRoutineExercisePlan: nonisolated Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var exerciseId: String?
    var name: String
    var muscleGroup: String
    var equipment: String
    var plannedSets: Int
    var plannedReps: Int
    var plannedWeight: Double
    var weightUnit: String
    var plannedRestSeconds: Int
    var orderIndex: Int
    var notes: String?
    var supersetGroupId: UUID? = nil
    var supersetOrder: Int? = nil
    var supersetType: String? = nil
    var supersetRestSeconds: Int? = nil
    var supersetSharedSetCount: Int? = nil
    var seriesMemberCount: Int? = nil
    var thumbnailURL: String? = nil
    var instructionsPreview: String? = nil
}

struct ActiveGymWorkoutState: nonisolated Codable, Hashable, Identifiable, Sendable {
    var id: UUID { sessionId }

    var sessionId: UUID
    var routineId: UUID
    var routineName: String
    var routineEmoji: String?
    var workoutKind: PulsarGymWorkoutKind? = nil
    var startedFrom: PulsarWorkoutStartedFrom? = nil
    var startedAt: Date
    var elapsedSeconds: Int
    var currentExerciseIndex: Int
    var currentSetIndex: Int
    var totalExercises: Int
    var totalSets: Int
    var completedSets: Int
    var currentHeartRate: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var activeEnergyKilocalories: Double?
    var healthKitWorkoutUUID: UUID? = nil
    var restRemainingSeconds: Int?
    var restTotalSeconds: Int?
    var isHealthKitEnabled: Bool
    var healthKitStatusMessage: String?
    var isFinished: Bool
    var updatedAt: Date
    var exercises: [ActiveGymWorkoutExerciseState]
    var requestID: UUID? = nil
    var routineRevision: Int? = nil
    var lifecycleGeneration: Int? = nil
    /// An iPhone-created transport placeholder that exists only to carry the
    /// pending Watch launch identity. It is not evidence of a running workout.
    /// Optional preserves decoding compatibility with older counterpart builds.
    var isLaunchPlaceholder: Bool? = nil

    nonisolated var isPrelaunchPlaceholder: Bool {
        isLaunchPlaceholder == true
    }

    var currentExercise: ActiveGymWorkoutExerciseState? {
        if exercises.indices.contains(currentExerciseIndex) {
            return exercises[currentExerciseIndex]
        }
        return exercises.first { !$0.isCompleted } ?? exercises.last
    }

    var currentSet: ActiveGymWorkoutSetState? {
        guard let currentExercise else { return nil }
        if currentExercise.sets.indices.contains(currentSetIndex) {
            return currentExercise.sets[currentSetIndex]
        }
        return currentExercise.sets.first { !$0.isCompleted } ?? currentExercise.sets.last
    }

    var progressText: String {
        guard totalSets > 0 else { return "\(completedSets) sets" }
        return "\(completedSets)/\(totalSets) sets"
    }

    var exerciseProgressText: String {
        guard totalExercises > 0 else {
            return workoutKind == .freeWorkout ? "Open workout" : "Loading routine…"
        }
        let displayIndex = min(max(currentExerciseIndex + 1, 1), max(totalExercises, 1))
        return "Exercise \(displayIndex) of \(max(totalExercises, 1))"
    }
}

struct GymWorkoutFinishConfirmation: nonisolated Equatable, Sendable {
    var sessionID: UUID
    var confirmedAt: Date
    var healthKitWorkoutUUID: UUID?
    var source: String
    /// Raw `HKWorkoutSessionState` when HealthKit itself supplied the terminal
    /// evidence. Kept raw so this shared model does not need to import HealthKit.
    var healthKitSessionStateRawValue: Int? = nil
}

/// One accepted gym terminal commit. Subsequent HealthKit, WatchConnectivity,
/// and cleanup signals for the same session must reconcile as no-ops.
struct PulsarGymTerminalCommitRecord: Equatable, Sendable {
    var endTransactionID: UUID
    var workoutID: UUID
    var requestID: UUID?
    var source: String
    var phaseBefore: String
    var phaseAfter: String
    var accepted: Bool
    var reason: String
}

struct ActiveGymWorkoutExerciseState: nonisolated Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var exerciseId: String? = nil
    var exerciseName: String
    var muscleGroup: String
    var equipment: String
    var plannedSets: Int
    var plannedReps: Int
    var plannedWeight: Double
    var weightUnit: String
    var plannedRestSeconds: Int
    var orderIndex: Int
    var notes: String?
    var supersetGroupId: UUID? = nil
    var supersetOrder: Int? = nil
    var supersetType: String? = nil
    var supersetRestSeconds: Int? = nil
    var supersetSharedSetCount: Int? = nil
    var seriesMemberCount: Int? = nil
    var thumbnailURL: String? = nil
    var instructionsPreview: String? = nil
    var sets: [ActiveGymWorkoutSetState]

    var completedSetIndexes: [Int] {
        sets.filter(\.isCompleted).map(\.setNumber)
    }

    var completedSetCount: Int {
        sets.filter(\.isCompleted).count
    }

    var isCompleted: Bool {
        !sets.isEmpty && completedSetCount == sets.count
    }
}

extension ActiveGymWorkoutExerciseState {
    nonisolated init(routinePlan exercise: WatchGymRoutineExercisePlan) {
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
        self.init(
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
            seriesMemberCount: exercise.seriesMemberCount,
            thumbnailURL: exercise.thumbnailURL,
            instructionsPreview: exercise.instructionsPreview,
            sets: sets
        )
    }

    /// Reapplying an immutable routine definition (including a delayed durable
    /// snapshot) must not roll back edits or completion already recorded for
    /// the live workout. Exercise identity and set number form the stable join.
    nonisolated func preservingLiveSetProgress(
        from prior: ActiveGymWorkoutExerciseState?
    ) -> ActiveGymWorkoutExerciseState {
        guard let prior, prior.id == id else { return self }
        let priorBySetNumber = Dictionary(uniqueKeysWithValues: prior.sets.map { ($0.setNumber, $0) })
        var merged = self
        for index in merged.sets.indices {
            guard let previous = priorBySetNumber[merged.sets[index].setNumber] else { continue }
            // A repeated/delayed immutable snapshot describes the same logical
            // set. Preserve its runtime identity so an in-flight UI action cannot
            // target a set UUID that hydration just replaced.
            merged.sets[index].id = previous.id
            merged.sets[index].targetReps = previous.targetReps
            merged.sets[index].targetWeight = previous.targetWeight
            merged.sets[index].completedReps = previous.completedReps
            merged.sets[index].completedWeight = previous.completedWeight
            merged.sets[index].isCompleted = previous.isCompleted
            merged.sets[index].completedAt = previous.completedAt
        }
        return merged
    }
}

extension ActiveGymWorkoutState {
    var nextActionIndices: (exerciseIndex: Int, setIndex: Int)? {
        let sortedExercises = exercises.enumerated().sorted { $0.element.orderIndex < $1.element.orderIndex }
        var consumedSupersetGroupIds: Set<UUID> = []

        for sortedExercise in sortedExercises {
            let exercise = sortedExercise.element
            if let groupId = exercise.supersetGroupId {
                guard consumedSupersetGroupIds.insert(groupId).inserted else { continue }
                let members = sortedExercises
                    .filter { $0.element.supersetGroupId == groupId }
                    .sorted {
                        ($0.element.supersetOrder ?? $0.element.orderIndex) < ($1.element.supersetOrder ?? $1.element.orderIndex)
                    }
                guard members.count >= 2 else {
                    if let setIndex = exercise.sets.firstIndex(where: { !$0.isCompleted }) {
                        return (sortedExercise.offset, setIndex)
                    }
                    continue
                }

                let sharedSetCount = max(1, members.compactMap { $0.element.supersetSharedSetCount }.first ?? members.map { $0.element.sets.count }.max() ?? 1)
                for setNumber in 1...sharedSetCount {
                    for member in members {
                        guard let setIndex = member.element.sets.firstIndex(where: { $0.setNumber == setNumber }) else { continue }
                        if !member.element.sets[setIndex].isCompleted {
                            return (member.offset, setIndex)
                        }
                    }
                }
            } else if let setIndex = exercise.sets.firstIndex(where: { !$0.isCompleted }) {
                return (sortedExercise.offset, setIndex)
            }
        }

        return nil
    }
}

struct ActiveGymWorkoutSetState: nonisolated Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var setNumber: Int
    var targetReps: Int
    var targetWeight: Double
    var completedReps: Int?
    var completedWeight: Double?
    var isCompleted: Bool
    var completedAt: Date?
}

/// High-frequency progress and metric fields used while a gym session is live.
/// Durable routine/start/finish messages continue to carry the full state.
struct ActiveGymLiveStateDelta: nonisolated Codable, Hashable, Sendable {
    struct SetProgress: nonisolated Codable, Hashable, Sendable {
        var exerciseID: UUID
        var setID: UUID
        var completedReps: Int?
        var completedWeight: Double?
        var isCompleted: Bool
        var completedAt: Date?
    }

    var sessionID: UUID
    var elapsedSeconds: Int
    var currentExerciseIndex: Int
    var currentSetIndex: Int
    var completedSets: Int
    var currentHeartRate: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var activeEnergyKilocalories: Double?
    var healthKitWorkoutUUID: UUID?
    var restRemainingSeconds: Int?
    var restTotalSeconds: Int?
    var isHealthKitEnabled: Bool
    var healthKitStatusMessage: String?
    var updatedAt: Date
    var setProgress: [SetProgress]

    nonisolated init(state: ActiveGymWorkoutState) {
        sessionID = state.sessionId
        elapsedSeconds = state.elapsedSeconds
        currentExerciseIndex = state.currentExerciseIndex
        currentSetIndex = state.currentSetIndex
        completedSets = state.completedSets
        currentHeartRate = state.currentHeartRate
        averageHeartRate = state.averageHeartRate
        maxHeartRate = state.maxHeartRate
        activeEnergyKilocalories = state.activeEnergyKilocalories
        healthKitWorkoutUUID = state.healthKitWorkoutUUID
        restRemainingSeconds = state.restRemainingSeconds
        restTotalSeconds = state.restTotalSeconds
        isHealthKitEnabled = state.isHealthKitEnabled
        healthKitStatusMessage = state.healthKitStatusMessage
        updatedAt = state.updatedAt
        setProgress = state.exercises.flatMap { exercise in
            exercise.sets.map { set in
                SetProgress(
                    exerciseID: exercise.id,
                    setID: set.id,
                    completedReps: set.completedReps,
                    completedWeight: set.completedWeight,
                    isCompleted: set.isCompleted,
                    completedAt: set.completedAt
                )
            }
        }
    }

    nonisolated func applying(to state: ActiveGymWorkoutState) -> ActiveGymWorkoutState? {
        guard state.sessionId == sessionID, !state.isFinished else { return nil }
        var next = state
        next.elapsedSeconds = max(next.elapsedSeconds, elapsedSeconds)
        next.currentExerciseIndex = currentExerciseIndex
        next.currentSetIndex = currentSetIndex
        next.completedSets = completedSets
        next.currentHeartRate = currentHeartRate ?? next.currentHeartRate
        next.averageHeartRate = averageHeartRate ?? next.averageHeartRate
        next.maxHeartRate = maxHeartRate ?? next.maxHeartRate
        next.activeEnergyKilocalories = activeEnergyKilocalories ?? next.activeEnergyKilocalories
        next.healthKitWorkoutUUID = healthKitWorkoutUUID ?? next.healthKitWorkoutUUID
        next.restRemainingSeconds = restRemainingSeconds
        next.restTotalSeconds = restTotalSeconds
        next.isHealthKitEnabled = isHealthKitEnabled
        next.healthKitStatusMessage = healthKitStatusMessage
        next.updatedAt = updatedAt

        let progressBySetID = Dictionary(uniqueKeysWithValues: setProgress.map { ($0.setID, $0) })
        for exerciseIndex in next.exercises.indices {
            for setIndex in next.exercises[exerciseIndex].sets.indices {
                let setID = next.exercises[exerciseIndex].sets[setIndex].id
                guard let progress = progressBySetID[setID],
                      progress.exerciseID == next.exercises[exerciseIndex].id else { continue }
                next.exercises[exerciseIndex].sets[setIndex].completedReps = progress.completedReps
                next.exercises[exerciseIndex].sets[setIndex].completedWeight = progress.completedWeight
                next.exercises[exerciseIndex].sets[setIndex].isCompleted = progress.isCompleted
                next.exercises[exerciseIndex].sets[setIndex].completedAt = progress.completedAt
            }
        }
        return next
    }
}

extension ActiveGymWorkoutState {
    /// Removes presentation-only strings from recoverable live snapshots.
    var compactedForLiveSync: ActiveGymWorkoutState {
        var compact = self
        for index in compact.exercises.indices {
            compact.exercises[index].notes = nil
            compact.exercises[index].thumbnailURL = nil
            compact.exercises[index].instructionsPreview = nil
        }
        return compact
    }

    func preservingRoutineDefinition(from prior: ActiveGymWorkoutState?) -> ActiveGymWorkoutState {
        guard let prior, prior.sessionId == sessionId else { return self }
        guard prior.routineId == routineId else { return self }
        let priorByID = Dictionary(uniqueKeysWithValues: prior.exercises.map { ($0.id, $0) })
        var restored = self
        if let priorRevision = prior.routineRevision {
            restored.routineRevision = max(restored.routineRevision ?? 0, priorRevision)
        }

        if restored.exercises.isEmpty, !prior.exercises.isEmpty {
            restored.exercises = prior.exercises
            restored.totalExercises = prior.exercises.count
            restored.totalSets = prior.exercises.reduce(0) { $0 + $1.sets.count }
            restored.currentExerciseIndex = min(restored.currentExerciseIndex, max(restored.exercises.count - 1, 0))
            if restored.exercises.indices.contains(restored.currentExerciseIndex) {
                restored.currentSetIndex = min(
                    restored.currentSetIndex,
                    max(restored.exercises[restored.currentExerciseIndex].sets.count - 1, 0)
                )
            }
            return restored
        }

        for index in restored.exercises.indices {
            guard let previous = priorByID[restored.exercises[index].id] else { continue }
            restored.exercises[index].notes = restored.exercises[index].notes ?? previous.notes
            restored.exercises[index].thumbnailURL = restored.exercises[index].thumbnailURL ?? previous.thumbnailURL
            restored.exercises[index].instructionsPreview = restored.exercises[index].instructionsPreview ?? previous.instructionsPreview
            if restored.exercises[index].sets.isEmpty, !previous.sets.isEmpty {
                restored.exercises[index].sets = previous.sets
                restored.exercises[index].plannedSets = previous.plannedSets
            }
        }
        restored.totalExercises = restored.exercises.count
        restored.totalSets = restored.exercises.reduce(0) { $0 + $1.sets.count }
        return restored
    }
}

struct ActiveGymWorkoutAction: nonisolated Codable, Hashable, Sendable {
    enum Kind: String, nonisolated Codable, Hashable, Sendable {
        case completeSet
        case updateSetValues
        case skipRestTimer
        case finishWorkout
        case requestState
        case metricsUpdated
        case requestSavedRoutines
        case startFreeWorkoutFromWatch
        case startSavedRoutineFromWatch
    }

    var kind: Kind
    var actionId: UUID? = nil
    var sessionId: UUID?
    var routineId: UUID? = nil
    var exerciseId: UUID?
    var setId: UUID?
    var sentAt: Date
    var currentHeartRate: Double? = nil
    var averageHeartRate: Double? = nil
    var maxHeartRate: Double? = nil
    var activeEnergyKilocalories: Double? = nil
    var healthKitWorkoutUUID: UUID? = nil
    var setReps: Int? = nil
    var setWeight: Double? = nil

    var shouldQueueOverWatchConnectivity: Bool {
        switch kind {
        case .completeSet, .updateSetValues, .skipRestTimer,
             .requestState, .metricsUpdated, .requestSavedRoutines:
            return false
        case .finishWorkout,
             .startFreeWorkoutFromWatch,
             .startSavedRoutineFromWatch:
            return true
        }
    }

    static func completeSet(
        sessionId: UUID,
        exerciseId: UUID,
        setId: UUID,
        reps: Int? = nil,
        weight: Double? = nil
    ) -> ActiveGymWorkoutAction {
        var action = ActiveGymWorkoutAction(kind: .completeSet, sessionId: sessionId, exerciseId: exerciseId, setId: setId, sentAt: Date())
        action.setReps = reps
        action.setWeight = weight
        return action
    }

    static func updateSetValues(
        sessionId: UUID,
        exerciseId: UUID,
        setId: UUID,
        reps: Int? = nil,
        weight: Double? = nil
    ) -> ActiveGymWorkoutAction {
        var action = ActiveGymWorkoutAction(kind: .updateSetValues, sessionId: sessionId, exerciseId: exerciseId, setId: setId, sentAt: Date())
        action.setReps = reps
        action.setWeight = weight
        return action
    }

    static func skipRestTimer(sessionId: UUID) -> ActiveGymWorkoutAction {
        ActiveGymWorkoutAction(kind: .skipRestTimer, sessionId: sessionId, exerciseId: nil, setId: nil, sentAt: Date())
    }

    static func finishWorkout(sessionId: UUID) -> ActiveGymWorkoutAction {
        ActiveGymWorkoutAction(kind: .finishWorkout, sessionId: sessionId, exerciseId: nil, setId: nil, sentAt: Date())
    }

    static func requestState(sessionId: UUID? = nil) -> ActiveGymWorkoutAction {
        ActiveGymWorkoutAction(kind: .requestState, sessionId: sessionId, exerciseId: nil, setId: nil, sentAt: Date())
    }

    static func requestSavedRoutines() -> ActiveGymWorkoutAction {
        ActiveGymWorkoutAction(kind: .requestSavedRoutines, sessionId: nil, exerciseId: nil, setId: nil, sentAt: Date())
    }

    static func startFreeWorkoutFromWatch(sessionId: UUID) -> ActiveGymWorkoutAction {
        ActiveGymWorkoutAction(kind: .startFreeWorkoutFromWatch, sessionId: sessionId, exerciseId: nil, setId: nil, sentAt: Date())
    }

    static func startSavedRoutineFromWatch(sessionId: UUID, routineId: UUID) -> ActiveGymWorkoutAction {
        var action = ActiveGymWorkoutAction(kind: .startSavedRoutineFromWatch, sessionId: sessionId, exerciseId: nil, setId: nil, sentAt: Date())
        action.routineId = routineId
        return action
    }

    static func metricsUpdated(
        sessionId: UUID?,
        currentHeartRate: Double?,
        averageHeartRate: Double?,
        maxHeartRate: Double?,
        activeEnergyKilocalories: Double?,
        healthKitWorkoutUUID: UUID? = nil
    ) -> ActiveGymWorkoutAction {
        var action = ActiveGymWorkoutAction(kind: .metricsUpdated, sessionId: sessionId, exerciseId: nil, setId: nil, sentAt: Date())
        action.currentHeartRate = currentHeartRate
        action.averageHeartRate = averageHeartRate
        action.maxHeartRate = maxHeartRate
        action.activeEnergyKilocalories = activeEnergyKilocalories
        action.healthKitWorkoutUUID = healthKitWorkoutUUID
        return action
    }
}

enum ActiveGymWorkoutCodec {
    static func encodeState(_ state: ActiveGymWorkoutState) -> Data? {
        PulsarPerformanceSignposts.measure(
            PulsarPerformanceSignposts.watchConnectivity,
            name: "encode"
        ) {
            try? encoder.encode(state)
        }
    }

    static func decodeState(_ data: Data) -> ActiveGymWorkoutState? {
        PulsarPerformanceSignposts.measure(
            PulsarPerformanceSignposts.watchConnectivity,
            name: "decode"
        ) {
            try? decoder.decode(ActiveGymWorkoutState.self, from: data)
        }
    }

    static func encodeAction(_ action: ActiveGymWorkoutAction) -> Data? {
        PulsarPerformanceSignposts.measure(
            PulsarPerformanceSignposts.watchConnectivity,
            name: "encode"
        ) {
            try? encoder.encode(action)
        }
    }

    static func decodeAction(_ data: Data) -> ActiveGymWorkoutAction? {
        PulsarPerformanceSignposts.measure(
            PulsarPerformanceSignposts.watchConnectivity,
            name: "decode"
        ) {
            try? decoder.decode(ActiveGymWorkoutAction.self, from: data)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Cross-device gym workout start contracts

enum GymCrossDeviceSchemaVersion: Int, nonisolated Codable, Sendable, Hashable {
    case v1 = 1

    static let current: GymCrossDeviceSchemaVersion = .v1
}

enum GymWorkoutStartRequestState: String, nonisolated Codable, Sendable, Hashable {
    case created
    case prelaunchHintSent
    case watchLaunchSubmitted
    case awaitingWatchAcknowledgement
    case acknowledged
    case failed
    case cancelled
    case superseded
}

enum GymWorkoutSessionState: String, nonisolated Codable, Sendable, Hashable {
    case notStarted
    case preparing
    case running
    case paused
    case ended
}

enum GymWorkoutMirroringState: String, nonisolated Codable, Sendable, Hashable {
    case notStarted
    case pending
    case active
    case unavailableWatchRecording
    case failed
}

enum GymCrossDeviceStartError: String, nonisolated Codable, Sendable, Hashable, Error {
    case watchNotPaired
    case watchAppNotInstalled
    case watchConnectivityUnavailable
    case watchNotReachable
    case watchLaunchFailed
    case watchAcknowledgementTimedOut
    case watchAcknowledgementStale
    case watchAcknowledgementLateAfterFallback
    case mirroredSessionMissing
    case mirroringUnavailable
    case routineSnapshotRejected
    case existingWorkoutConflict
    case cancelled
    case healthKitDenied
    case unknown

    var userFacingMessage: String {
        switch self {
        case .watchNotPaired, .watchAppNotInstalled:
            "No paired Apple Watch was found, or Pulsar is not installed on Apple Watch."
        case .watchConnectivityUnavailable, .watchNotReachable:
            "We couldn't connect to your Apple Watch. Open Pulsar on Apple Watch and try again."
        case .watchLaunchFailed:
            "Apple Watch could not start this gym workout."
        case .watchAcknowledgementTimedOut:
            "Apple Watch did not confirm recording within the expected time."
        case .watchAcknowledgementStale, .watchAcknowledgementLateAfterFallback:
            "A late Apple Watch response arrived after this start attempt ended."
        case .mirroredSessionMissing:
            "Apple Watch is recording, but the mirrored session has not connected to iPhone yet."
        case .mirroringUnavailable:
            "Apple Watch is recording. Reconnecting live mirror to iPhone."
        case .routineSnapshotRejected:
            "The routine snapshot could not be applied on Apple Watch."
        case .existingWorkoutConflict:
            "Another workout is already active. Finish it before starting a new one."
        case .cancelled:
            "Gym workout start was cancelled."
        case .healthKitDenied:
            "Health permissions are required to start this workout on Apple Watch."
        case .unknown:
            "Apple Watch could not start this gym workout."
        }
    }
}

struct GymWorkoutStartRequest: nonisolated Codable, Sendable, Hashable, Identifiable {
    var id: UUID { requestID }

    var schemaVersion: Int
    var requestID: UUID
    var candidateSessionID: UUID
    var idempotencyKey: String
    var routineID: UUID
    var routineRevision: Int
    var workoutKind: PulsarGymWorkoutKind
    var activityTypeRawValue: UInt
    var locationTypeRawValue: Int
    var requestedAt: Date
    var requestedFrom: PulsarWorkoutStartedFrom
    var requestState: GymWorkoutStartRequestState

    init(
        requestID: UUID = UUID(),
        candidateSessionID: UUID = UUID(),
        idempotencyKey: String? = nil,
        routineID: UUID,
        routineRevision: Int,
        workoutKind: PulsarGymWorkoutKind,
        activityTypeRawValue: UInt,
        locationTypeRawValue: Int,
        requestedAt: Date = Date(),
        requestedFrom: PulsarWorkoutStartedFrom = .iPhoneRequestedWatchStart,
        requestState: GymWorkoutStartRequestState = .created,
        schemaVersion: Int = GymCrossDeviceSchemaVersion.current.rawValue
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.candidateSessionID = candidateSessionID
        self.idempotencyKey = idempotencyKey ?? requestID.uuidString
        self.routineID = routineID
        self.routineRevision = routineRevision
        self.workoutKind = workoutKind
        self.activityTypeRawValue = activityTypeRawValue
        self.locationTypeRawValue = locationTypeRawValue
        self.requestedAt = requestedAt
        self.requestedFrom = requestedFrom
        self.requestState = requestState
    }

    var compactPrelaunchHint: [String: Any] {
        [
            GymCrossDevicePayloadKey.schemaVersion: schemaVersion,
            GymCrossDevicePayloadKey.requestID: requestID.uuidString,
            GymCrossDevicePayloadKey.candidateSessionID: candidateSessionID.uuidString,
            GymCrossDevicePayloadKey.idempotencyKey: idempotencyKey,
            GymCrossDevicePayloadKey.routineID: routineID.uuidString,
            GymCrossDevicePayloadKey.routineRevision: routineRevision,
            GymCrossDevicePayloadKey.workoutKind: workoutKind.rawValue,
            GymCrossDevicePayloadKey.requestedAt: requestedAt.timeIntervalSince1970
        ]
    }
}

enum GymWorkoutStartRequestAdmission {
    nonisolated static let maximumAge: TimeInterval = 90

    nonisolated static func accepts(
        requestedAt: Date,
        now: Date = Date(),
        isTombstoned: Bool
    ) -> Bool {
        !isTombstoned && PulsarWorkoutSessionValidity.isRecent(
            requestedAt,
            now: now,
            interval: maximumAge
        )
    }
}

struct GymWorkoutStartAcknowledgement: nonisolated Codable, Sendable, Hashable {
    var schemaVersion: Int
    var requestID: UUID
    var candidateSessionID: UUID
    var authoritativeSessionID: UUID
    var healthKitWorkoutUUID: UUID?
    var sessionState: GymWorkoutSessionState
    var mirroringState: GymWorkoutMirroringState
    var acknowledgedAt: Date
    var isWatchGeneratedSessionID: Bool

    init(
        requestID: UUID,
        candidateSessionID: UUID,
        authoritativeSessionID: UUID,
        healthKitWorkoutUUID: UUID? = nil,
        sessionState: GymWorkoutSessionState,
        mirroringState: GymWorkoutMirroringState,
        acknowledgedAt: Date = Date(),
        isWatchGeneratedSessionID: Bool = false,
        schemaVersion: Int = GymCrossDeviceSchemaVersion.current.rawValue
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.candidateSessionID = candidateSessionID
        self.authoritativeSessionID = authoritativeSessionID
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
        self.sessionState = sessionState
        self.mirroringState = mirroringState
        self.acknowledgedAt = acknowledgedAt
        self.isWatchGeneratedSessionID = isWatchGeneratedSessionID
    }

    var isAuthoritativeWatchRunning: Bool {
        sessionState == .running
    }
}

struct GymMirroredMetricsPayload: nonisolated Codable, Sendable, Hashable {
    var sessionID: UUID
    var sampledAt: Date
    var currentHeartRate: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var activeEnergyKilocalories: Double?
}

struct GymRoutineSnapshotEnvelope: nonisolated Codable, Sendable, Hashable, Identifiable {
    var id: UUID { requestID }

    var schemaVersion: Int
    var requestID: UUID
    var sessionID: UUID
    var routineID: UUID
    var revision: Int
    var checksum: String
    var capturedAt: Date
    var routinePlan: WatchGymRoutinePlan
    /// The complete, idempotent start metadata. Older envelopes decode this as
    /// nil; newer senders no longer need a separate prelaunch hint.
    var startRequest: GymWorkoutStartRequest?

    init(
        requestID: UUID,
        sessionID: UUID,
        routineID: UUID,
        revision: Int,
        routinePlan: WatchGymRoutinePlan,
        startRequest: GymWorkoutStartRequest? = nil,
        capturedAt: Date = Date(),
        schemaVersion: Int = GymCrossDeviceSchemaVersion.current.rawValue
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.sessionID = sessionID
        self.routineID = routineID
        self.revision = revision
        self.capturedAt = capturedAt
        self.routinePlan = routinePlan
        self.startRequest = startRequest
        self.checksum = Self.checksum(for: routinePlan, revision: revision, schemaVersion: schemaVersion)
    }

    var isChecksumValid: Bool {
        checksum == Self.checksum(for: routinePlan, revision: revision, schemaVersion: schemaVersion)
    }

    nonisolated func resolvedWorkoutKind(
        pendingRequest: GymWorkoutStartRequest?,
        current: PulsarGymWorkoutKind?,
        isLaunchPlaceholder: Bool
    ) -> PulsarGymWorkoutKind {
        if let workoutKind = startRequest?.workoutKind ?? pendingRequest?.workoutKind {
            return workoutKind
        }
        if !isLaunchPlaceholder, let current {
            return current
        }
        return PulsarGymWorkoutKind.inferred(
            routineName: routinePlan.name,
            exerciseCount: routinePlan.exerciseCount
        )
    }

    static func checksum(for routinePlan: WatchGymRoutinePlan, revision: Int, schemaVersion: Int) -> String {
        let exerciseSignature = routinePlan.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { "\($0.id.uuidString):\($0.name):\($0.plannedSets)" }
            .joined(separator: "|")
        return "\(schemaVersion)-\(revision)-\(routinePlan.routineId.uuidString)-\(routinePlan.exerciseCount)-\(exerciseSignature)"
    }
}

enum GymCrossDevicePayloadKey {
    static let schemaVersion = "schemaVersion"
    static let requestID = "requestID"
    static let candidateSessionID = "candidateSessionID"
    static let authoritativeSessionID = "authoritativeSessionID"
    static let idempotencyKey = "idempotencyKey"
    static let routineID = "routineID"
    static let routineRevision = "routineRevision"
    static let workoutKind = "workoutKind"
    static let requestedAt = "requestedAt"
    static let acknowledgement = "gymWorkoutStartAcknowledgement"
    static let routineSnapshot = "gymRoutineSnapshotEnvelope"
    static let compactPrelaunchHint = "gymWorkoutStartPrelaunchHint"
}

enum GymCrossDeviceCodec {
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encodeAcknowledgement(_ acknowledgement: GymWorkoutStartAcknowledgement) -> Data? {
        PulsarPerformanceSignposts.measure(
            PulsarPerformanceSignposts.watchConnectivity,
            name: "encode"
        ) {
            try? encoder.encode(acknowledgement)
        }
    }

    static func decodeAcknowledgement(_ data: Data) -> GymWorkoutStartAcknowledgement? {
        PulsarPerformanceSignposts.measure(
            PulsarPerformanceSignposts.watchConnectivity,
            name: "decode"
        ) {
            try? decoder.decode(GymWorkoutStartAcknowledgement.self, from: data)
        }
    }

    static func encodeMirroredMetrics(_ payload: GymMirroredMetricsPayload) -> Data? {
        PulsarPerformanceSignposts.measure(
            PulsarPerformanceSignposts.watchConnectivity,
            name: "encode"
        ) {
            try? encoder.encode(payload)
        }
    }

    static func decodeMirroredMetrics(_ data: Data) -> GymMirroredMetricsPayload? {
        PulsarPerformanceSignposts.measure(
            PulsarPerformanceSignposts.watchConnectivity,
            name: "decode"
        ) {
            try? decoder.decode(GymMirroredMetricsPayload.self, from: data)
        }
    }

    static func encodeRoutineSnapshot(_ envelope: GymRoutineSnapshotEnvelope) -> Data? {
        PulsarPerformanceSignposts.measure(
            PulsarPerformanceSignposts.watchConnectivity,
            name: "encode"
        ) {
            try? encoder.encode(envelope)
        }
    }

    static func decodeRoutineSnapshot(_ data: Data) -> GymRoutineSnapshotEnvelope? {
        PulsarPerformanceSignposts.measure(
            PulsarPerformanceSignposts.watchConnectivity,
            name: "decode"
        ) {
            try? decoder.decode(GymRoutineSnapshotEnvelope.self, from: data)
        }
    }

    static func decodeAcknowledgement(from dictionary: [String: Any]) -> GymWorkoutStartAcknowledgement? {
        guard let data = dictionary[GymCrossDevicePayloadKey.acknowledgement] as? Data ??
                (dictionary[GymCrossDevicePayloadKey.acknowledgement] as? String).flatMap({ Data(base64Encoded: $0) }) else {
            return nil
        }
        return decodeAcknowledgement(data)
    }
}

enum PulsarGymFormatters {
    static func duration(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3_600
        let minutes = (clamped % 3_600) / 60
        let seconds = clamped % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func heartRate(_ bpm: Double?) -> String {
        guard let bpm, bpm > 0 else { return "--" }
        return "\(Int(bpm.rounded()))"
    }

    static func weight(_ value: Double, unit: String) -> String {
        let formatted: String
        if value.rounded() == value {
            formatted = String(Int(value))
        } else {
            formatted = String(format: "%.1f", value)
        }
        return "\(formatted) \(unit)"
    }
}
