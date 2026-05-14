//
//  RoutineBuilderViewModel.swift
//  Pulsar
//

import Combine
import Foundation

@MainActor
final class RoutineBuilderViewModel: ObservableObject {
    @Published var routineName: String
    @Published var routineEmoji: String
    @Published var searchText = ""
    @Published var selectedMuscleGroup: PulsarMuscleGroup?
    @Published private(set) var routineExercises: [PulsarRoutineExercise]
    @Published private(set) var supersetGroups: [PulsarSupersetGroup]
    @Published private(set) var lastSavedRoutineID: UUID?

    private var originalCreatedAt: Date?
    private var defaultWeightUnit: PulsarWeightUnit

    init(
        routineName: String = "New Gym Routine",
        routineEmoji: String = "",
        selectedExercises: [PulsarExercise] = [],
        defaultWeightUnit: PulsarWeightUnit = .kilograms
    ) {
        self.routineName = routineName
        let trimmedEmoji = routineEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        self.routineEmoji = trimmedEmoji.isEmpty ? "" : PulsarRoutine.normalizedEmoji(trimmedEmoji)
        self.defaultWeightUnit = defaultWeightUnit
        self.routineExercises = selectedExercises.enumerated().map { index, exercise in
            PulsarRoutineExercise(exercise: exercise, order: index, weightUnit: defaultWeightUnit)
        }
        self.supersetGroups = []
    }

    convenience init(routine: PulsarRoutine, defaultWeightUnit: PulsarWeightUnit = .kilograms) {
        self.init(
            routineName: routine.name,
            routineEmoji: routine.emoji,
            selectedExercises: [],
            defaultWeightUnit: defaultWeightUnit
        )
        self.routineExercises = routine.exercises.sorted { $0.order < $1.order }
        self.supersetGroups = PulsarRoutine.normalizedSupersetGroups(routine.supersetGroups, for: self.routineExercises)
        self.syncSupersetMetadata()
        self.lastSavedRoutineID = routine.id
        self.originalCreatedAt = routine.createdAt
    }

    var canContinue: Bool {
        !routineExercises.isEmpty
    }

    var selectedExercises: [PulsarExercise] {
        routineExercises
            .sorted { $0.order < $1.order }
            .map(\.exercise)
    }

    var resolvedRoutineName: String {
        let trimmedName = routineName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Gym Routine" : trimmedName
    }

    var resolvedRoutineEmoji: String {
        let trimmedEmoji = routineEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedEmoji.isEmpty ? PulsarRoutine.defaultEmoji(for: routineExercises) : PulsarRoutine.normalizedEmoji(trimmedEmoji)
    }

    func updateDefaultWeightUnit(_ unit: PulsarWeightUnit) {
        defaultWeightUnit = unit
    }

    func selectEmoji(_ emoji: String) {
        routineEmoji = PulsarRoutine.normalizedEmoji(emoji)
    }

    func filteredExercises(from exercises: [PulsarExercise]) -> [PulsarExercise] {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return exercises.filter { exercise in
            let matchesSearch = trimmedSearchText.isEmpty
                || exercise.name.localizedCaseInsensitiveContains(trimmedSearchText)
            let matchesGroup = selectedMuscleGroup == nil
                || exercise.primaryMuscleGroup == selectedMuscleGroup
            return matchesSearch && matchesGroup
        }
    }

    func groupedExercises(from exercises: [PulsarExercise]) -> [(group: PulsarMuscleGroup, exercises: [PulsarExercise])] {
        let filtered = filteredExercises(from: exercises)
        return PulsarMuscleGroup.allCases.compactMap { group in
            let groupedExercises = filtered.filter { $0.primaryMuscleGroup == group }
            guard !groupedExercises.isEmpty else { return nil }
            return (group, groupedExercises)
        }
    }

    func isSelected(_ exercise: PulsarExercise) -> Bool {
        routineExercises.contains(where: { $0.exercise.id == exercise.id })
    }

    func toggleExercise(_ exercise: PulsarExercise) {
        if isSelected(exercise) {
            removeExercise(exercise)
        } else {
            routineExercises.append(
                PulsarRoutineExercise(exercise: exercise, order: routineExercises.count, weightUnit: defaultWeightUnit)
            )
            normalizeOrder()
        }
    }

    func removeExercise(_ exercise: PulsarExercise) {
        let removedIDs = Set(routineExercises.filter { $0.exercise.id == exercise.id }.map(\.id))
        routineExercises.removeAll { $0.exercise.id == exercise.id }
        removeSupersetGroups(containingAny: removedIDs)
        normalizeOrder()
    }

    func removeRoutineExercise(_ routineExercise: PulsarRoutineExercise) {
        routineExercises.removeAll { $0.id == routineExercise.id }
        removeSupersetGroups(containingAny: [routineExercise.id])
        normalizeOrder()
    }

    func removeExercise(at offsets: IndexSet) {
        var removedIDs: Set<UUID> = []
        for offset in offsets.sorted(by: >) where routineExercises.indices.contains(offset) {
            removedIDs.insert(routineExercises[offset].id)
            routineExercises.remove(at: offset)
        }
        removeSupersetGroups(containingAny: removedIDs)
        normalizeOrder()
    }

    func updatePlan(
        for routineExerciseID: UUID,
        plannedSets: Int? = nil,
        plannedReps: Int? = nil,
        plannedWeight: Double? = nil,
        weightUnit: PulsarWeightUnit? = nil,
        plannedRestSeconds: Int? = nil,
        notes: String? = nil
    ) {
        guard let index = routineExercises.firstIndex(where: { $0.id == routineExerciseID }) else { return }

        if let plannedSets {
            if let groupId = routineExercises[index].supersetGroupId {
                updateSupersetSetCount(groupID: groupId, sharedSetCount: plannedSets)
            } else {
                routineExercises[index].plannedSets = max(1, plannedSets)
            }
        }
        if let plannedReps {
            routineExercises[index].plannedReps = max(1, plannedReps)
        }
        if let plannedWeight {
            routineExercises[index].plannedWeight = max(0, plannedWeight)
        }
        if let weightUnit {
            routineExercises[index].weightUnit = weightUnit
        }
        if let plannedRestSeconds {
            routineExercises[index].plannedRestSeconds = max(0, plannedRestSeconds)
        }
        if let notes {
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            routineExercises[index].notes = trimmedNotes.isEmpty ? nil : notes
        }
    }

    func makeRoutine(existingID: UUID? = nil) -> PulsarRoutine {
        let now = Date()
        let plan = orderedRoutinePlan()
        return PulsarRoutine(
            id: existingID ?? lastSavedRoutineID ?? UUID(),
            name: resolvedRoutineName,
            emoji: resolvedRoutineEmoji,
            createdAt: originalCreatedAt ?? now,
            updatedAt: now,
            exercises: plan.exercises,
            supersetGroups: plan.supersetGroups
        )
    }

    @discardableResult
    func save(using store: PulsarRoutineStore) -> PulsarRoutine {
        let routine = store.upsert(makeRoutine())
        lastSavedRoutineID = routine.id
        originalCreatedAt = routine.createdAt
        return routine
    }

    func supersetGroup(containing routineExerciseID: UUID) -> PulsarSupersetGroup? {
        supersetGroups.first { $0.exerciseIds.contains(routineExerciseID) }
    }

    func supersetGroup(id: UUID) -> PulsarSupersetGroup? {
        supersetGroups.first { $0.id == id }
    }

    func supersetLabel(for groupID: UUID) -> String {
        guard let index = orderedSupersetGroups().firstIndex(where: { $0.id == groupID }) else {
            return "Superset"
        }
        return "Superset \(Self.groupLetter(for: index))"
    }

    func supersetBadge(for routineExercise: PulsarRoutineExercise) -> String? {
        guard let groupId = routineExercise.supersetGroupId,
              let index = orderedSupersetGroups().firstIndex(where: { $0.id == groupId }) else { return nil }
        let order = (routineExercise.supersetOrder ?? 0) + 1
        return "Superset \(Self.groupLetter(for: index))\(order)"
    }

    func supersetPartnerOptions(for routineExerciseID: UUID) -> [PulsarRoutineExercise] {
        routineExercises
            .sorted { $0.order < $1.order }
            .filter { candidate in
                candidate.id != routineExerciseID
            }
    }

    func createSuperset(
        firstExerciseID: UUID,
        secondExerciseID: UUID,
        restTimeSeconds: Int = 90,
        type: PulsarSupersetType = .superset
    ) {
        guard firstExerciseID != secondExerciseID,
              let first = routineExercises.first(where: { $0.id == firstExerciseID }),
              let second = routineExercises.first(where: { $0.id == secondExerciseID }) else { return }

        removeSupersetGroups(containingAny: [firstExerciseID, secondExerciseID])

        let orderedIDs = [first, second]
            .sorted { $0.order < $1.order }
            .map(\.id)
        let sharedSetCount = max(first.plannedSets, second.plannedSets)
        let group = PulsarSupersetGroup(
            type: type,
            exerciseIds: orderedIDs,
            sharedSetCount: sharedSetCount,
            restTimeSeconds: restTimeSeconds
        )
        supersetGroups.append(group)
        syncSupersetMetadata()
    }

    func updateSupersetSetCount(groupID: UUID, sharedSetCount: Int) {
        guard let groupIndex = supersetGroups.firstIndex(where: { $0.id == groupID }) else { return }
        supersetGroups[groupIndex].sharedSetCount = max(1, sharedSetCount)
        syncSupersetMetadata()
    }

    func updateSupersetRest(groupID: UUID, restTimeSeconds: Int) {
        guard let groupIndex = supersetGroups.firstIndex(where: { $0.id == groupID }) else { return }
        supersetGroups[groupIndex].restTimeSeconds = max(0, restTimeSeconds)
        syncSupersetMetadata()
    }

    func dissolveSuperset(groupID: UUID) {
        supersetGroups.removeAll { $0.id == groupID }
        syncSupersetMetadata()
    }

    func removeFromSuperset(routineExerciseID: UUID) {
        guard let group = supersetGroup(containing: routineExerciseID) else { return }
        dissolveSuperset(groupID: group.id)
    }

    private func normalizeOrder() {
        routineExercises = routineExercises.enumerated().map { index, routineExercise in
            var next = routineExercise
            next.order = index
            return next
        }
        syncSupersetMetadata()
    }

    private func orderedRoutinePlan() -> (exercises: [PulsarRoutineExercise], supersetGroups: [PulsarSupersetGroup]) {
        let orderedExercises = routineExercises
            .sorted { $0.order < $1.order }
            .enumerated()
            .map { index, routineExercise in
                var next = routineExercise
                next.order = index
                return next
            }
        let groups = PulsarRoutine.normalizedSupersetGroups(supersetGroups, for: orderedExercises)
        var syncedExercises = orderedExercises
        for group in groups {
            for (memberIndex, exerciseID) in group.exerciseIds.enumerated() {
                guard let exerciseIndex = syncedExercises.firstIndex(where: { $0.id == exerciseID }) else { continue }
                syncedExercises[exerciseIndex].supersetGroupId = group.id
                syncedExercises[exerciseIndex].supersetOrder = memberIndex
                syncedExercises[exerciseIndex].plannedSets = group.sharedSetCount
            }
        }
        let groupedExerciseIDs = Set(groups.flatMap(\.exerciseIds))
        for index in syncedExercises.indices where !groupedExerciseIDs.contains(syncedExercises[index].id) {
            syncedExercises[index].supersetGroupId = nil
            syncedExercises[index].supersetOrder = nil
        }
        return (syncedExercises, groups)
    }

    private func orderedSupersetGroups() -> [PulsarSupersetGroup] {
        let orderByExerciseId = Dictionary(uniqueKeysWithValues: routineExercises.map { ($0.id, $0.order) })
        return supersetGroups.sorted { first, second in
            let firstOrder = first.exerciseIds.compactMap { orderByExerciseId[$0] }.min() ?? 0
            let secondOrder = second.exerciseIds.compactMap { orderByExerciseId[$0] }.min() ?? 0
            return firstOrder < secondOrder
        }
    }

    private func removeSupersetGroups(containingAny routineExerciseIDs: Set<UUID>) {
        guard !routineExerciseIDs.isEmpty else { return }
        supersetGroups.removeAll { group in
            !Set(group.exerciseIds).isDisjoint(with: routineExerciseIDs)
        }
        syncSupersetMetadata()
    }

    private func syncSupersetMetadata() {
        let normalizedGroups = PulsarRoutine.normalizedSupersetGroups(supersetGroups, for: routineExercises)
        supersetGroups = normalizedGroups

        let groupById = Dictionary(uniqueKeysWithValues: normalizedGroups.map { ($0.id, $0) })
        for index in routineExercises.indices {
            guard let groupId = routineExercises[index].supersetGroupId,
                  let group = groupById[groupId],
                  let memberIndex = group.exerciseIds.firstIndex(of: routineExercises[index].id) else {
                routineExercises[index].supersetGroupId = nil
                routineExercises[index].supersetOrder = nil
                continue
            }
            routineExercises[index].supersetOrder = memberIndex
            routineExercises[index].plannedSets = group.sharedSetCount
        }

        for group in normalizedGroups {
            for (memberIndex, exerciseID) in group.exerciseIds.enumerated() {
                guard let exerciseIndex = routineExercises.firstIndex(where: { $0.id == exerciseID }) else { continue }
                routineExercises[exerciseIndex].supersetGroupId = group.id
                routineExercises[exerciseIndex].supersetOrder = memberIndex
                routineExercises[exerciseIndex].plannedSets = group.sharedSetCount
            }
        }
    }

    private static func groupLetter(for index: Int) -> String {
        let scalar = UnicodeScalar(65 + max(0, min(index, 25)))
        return scalar.map { String(Character($0)) } ?? "A"
    }
}
