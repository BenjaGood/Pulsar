//
//  RoutineBuilderViewModel.swift
//  Pulsar
//

import Combine
import Foundation

@MainActor
final class RoutineBuilderViewModel: ObservableObject {
    @Published var routineName: String
    @Published var searchText = ""
    @Published var selectedMuscleGroup: PulsarMuscleGroup?
    @Published private(set) var routineExercises: [PulsarRoutineExercise]
    @Published private(set) var lastSavedRoutineID: UUID?

    init(
        routineName: String = "New Gym Routine",
        selectedExercises: [PulsarExercise] = []
    ) {
        self.routineName = routineName
        self.routineExercises = selectedExercises.enumerated().map { index, exercise in
            PulsarRoutineExercise(exercise: exercise, order: index)
        }
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
                PulsarRoutineExercise(exercise: exercise, order: routineExercises.count)
            )
            normalizeOrder()
        }
    }

    func removeExercise(_ exercise: PulsarExercise) {
        routineExercises.removeAll { $0.exercise.id == exercise.id }
        normalizeOrder()
    }

    func removeRoutineExercise(_ routineExercise: PulsarRoutineExercise) {
        routineExercises.removeAll { $0.id == routineExercise.id }
        normalizeOrder()
    }

    func removeExercise(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) where routineExercises.indices.contains(offset) {
            routineExercises.remove(at: offset)
        }
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
            routineExercises[index].plannedSets = max(1, plannedSets)
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
        return PulsarRoutine(
            id: existingID ?? lastSavedRoutineID ?? UUID(),
            name: resolvedRoutineName,
            createdAt: now,
            updatedAt: now,
            exercises: orderedRoutineExercises()
        )
    }

    @discardableResult
    func save(using store: PulsarRoutineStore) -> PulsarRoutine {
        let routine = store.upsert(makeRoutine())
        lastSavedRoutineID = routine.id
        return routine
    }

    private func normalizeOrder() {
        routineExercises = routineExercises.enumerated().map { index, routineExercise in
            var next = routineExercise
            next.order = index
            return next
        }
    }

    private func orderedRoutineExercises() -> [PulsarRoutineExercise] {
        routineExercises
            .sorted { $0.order < $1.order }
            .enumerated()
            .map { index, routineExercise in
                var next = routineExercise
                next.order = index
                return next
            }
    }
}
