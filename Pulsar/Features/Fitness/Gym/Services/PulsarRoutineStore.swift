//
//  PulsarRoutineStore.swift
//  Pulsar
//

import Combine
import Foundation

@MainActor
final class PulsarRoutineStore: ObservableObject {
    @Published private(set) var routines: [PulsarRoutine]

    private let defaults: UserDefaults
    private let storageKey = "pulsar.gym.routines.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let routines = try? decoder.decode([PulsarRoutine].self, from: data) {
            self.routines = routines.sorted { $0.updatedAt > $1.updatedAt }
        } else {
            self.routines = []
        }
        syncRoutinesToWatch(reason: "routineStoreLoaded", broadcast: false)
    }

    @discardableResult
    func upsert(_ routine: PulsarRoutine) -> PulsarRoutine {
        var nextRoutine = routine
        nextRoutine.updatedAt = .now
        if let existing = routines.first(where: { $0.id == routine.id }) {
            nextRoutine.createdAt = existing.createdAt
        }

        routines.removeAll { $0.id == routine.id }
        routines.insert(nextRoutine, at: 0)
        persist()
        return nextRoutine
    }

    @discardableResult
    func duplicate(_ routine: PulsarRoutine) -> PulsarRoutine {
        var duplicate = routine
        duplicate.id = UUID()
        duplicate.name = "\(routine.name) Copy"
        duplicate.createdAt = .now
        duplicate.updatedAt = .now
        let exerciseIdMap = Dictionary(uniqueKeysWithValues: routine.exercises.map { ($0.id, UUID()) })
        let groupIdMap = Dictionary(uniqueKeysWithValues: routine.supersetGroups.map { ($0.id, UUID()) })
        duplicate.exercises = routine.exercises.enumerated().map { index, exercise in
            var next = exercise
            next.id = exerciseIdMap[exercise.id] ?? UUID()
            next.order = index
            if let groupId = exercise.supersetGroupId,
               let nextGroupId = groupIdMap[groupId] {
                next.supersetGroupId = nextGroupId
            } else {
                next.supersetGroupId = nil
                next.supersetOrder = nil
            }
            return next
        }
        duplicate.supersetGroups = routine.supersetGroups.compactMap { group in
            guard let nextGroupId = groupIdMap[group.id] else { return nil }
            let nextExerciseIds = group.exerciseIds.compactMap { exerciseIdMap[$0] }
            guard nextExerciseIds.count == 2 else { return nil }
            return PulsarSupersetGroup(
                id: nextGroupId,
                type: group.type,
                exerciseIds: nextExerciseIds,
                sharedSetCount: group.sharedSetCount,
                restTimeSeconds: group.restTimeSeconds
            )
        }
        routines.insert(duplicate, at: 0)
        persist()
        return duplicate
    }

    func delete(_ routine: PulsarRoutine) {
        routines.removeAll { $0.id == routine.id }
        persist()
    }

    private func persist() {
        guard let data = try? encoder.encode(routines) else { return }
        defaults.set(data, forKey: storageKey)
        syncRoutinesToWatch(reason: "routineStorePersisted", broadcast: true)
    }

    private func syncRoutinesToWatch(reason: String, broadcast: Bool) {
        let plans = routines.map(WatchGymRoutinePlan.init(routine:))
        PulsarWatchConnectivitySyncStore.shared.storeSavedGymRoutines(plans, broadcast: broadcast, reason: reason)
    }
}

extension WatchGymRoutinePlan {
    init(routine: PulsarRoutine) {
        self.init(
            routineId: routine.id,
            name: routine.name,
            emoji: routine.emoji,
            exerciseCount: routine.exercises.count,
            mainMuscleGroups: routine.mainMuscleGroupNames,
            estimatedDurationSeconds: routine.estimatedDurationSeconds,
            updatedAt: routine.updatedAt,
            exercises: routine.exercises
                .sorted { $0.order < $1.order }
                .map { routineExercise in
                    var plan = WatchGymRoutineExercisePlan(routineExercise: routineExercise)
                    if let groupId = routineExercise.supersetGroupId,
                       let group = routine.supersetGroups.first(where: { $0.id == groupId }) {
                        plan.supersetType = group.type.rawValue
                        plan.supersetRestSeconds = group.restTimeSeconds
                        plan.supersetSharedSetCount = group.sharedSetCount
                    }
                    return plan
                }
        )
    }
}

extension WatchGymRoutineExercisePlan {
    init(routineExercise: PulsarRoutineExercise) {
        self.init(
            id: routineExercise.id,
            exerciseId: routineExercise.exercise.id,
            name: routineExercise.exercise.name,
            muscleGroup: routineExercise.primaryMuscleGroup.displayName,
            equipment: routineExercise.equipmentSummary,
            plannedSets: routineExercise.plannedSets,
            plannedReps: routineExercise.plannedReps,
            plannedWeight: routineExercise.plannedWeight,
            weightUnit: routineExercise.weightUnit.displayName,
            plannedRestSeconds: routineExercise.plannedRestSeconds,
            orderIndex: routineExercise.orderIndex,
            notes: routineExercise.notes,
            supersetGroupId: routineExercise.supersetGroupId,
            supersetOrder: routineExercise.supersetOrder,
            supersetType: routineExercise.supersetGroupId == nil ? nil : PulsarSupersetType.superset.rawValue,
            supersetRestSeconds: routineExercise.supersetGroupId == nil ? nil : routineExercise.plannedRestSeconds,
            supersetSharedSetCount: routineExercise.supersetGroupId == nil ? nil : routineExercise.plannedSets
        )
    }
}
