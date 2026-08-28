//
//  GymRoutineExperienceTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

@MainActor
struct GymRoutineExperienceTests {
    @Test func savedRoutinesPersistEmojiPlanningAndDuplicateSafely() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        let exercise = Self.makeExercise()
        let routineExercise = PulsarRoutineExercise(
            exercise: exercise,
            order: 0,
            plannedSets: 4,
            plannedReps: 8,
            plannedWeight: 135,
            weightUnit: .pounds,
            plannedRestSeconds: 90,
            notes: "Top set"
        )
        let routine = PulsarRoutine(name: "Push Day", emoji: "💪", exercises: [routineExercise])

        let store = PulsarRoutineStore(defaults: defaults)
        let saved = store.upsert(routine)
        let reloaded = PulsarRoutineStore(defaults: defaults)
        let restored = try #require(reloaded.routines.first)

        #expect(restored.id == saved.id)
        #expect(restored.emoji == "💪")
        #expect(restored.exercises.first?.plannedWeight == 135)
        #expect(restored.exercises.first?.weightUnit == .pounds)
        #expect(restored.exercises.first?.plannedRestSeconds == 90)
        #expect(restored.exercises.first?.notes == "Top set")

        let duplicate = reloaded.duplicate(restored)

        #expect(duplicate.id != restored.id)
        #expect(duplicate.name == "Push Day Copy")
        #expect(duplicate.exercises.first?.id != restored.exercises.first?.id)
        #expect(duplicate.exercises.first?.weightUnit == .pounds)
    }

    @Test func routineStoreRevisionIncrementsForUpsertAndDelete() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        let store = PulsarRoutineStore(defaults: defaults)
        #expect(store.routinesRevision == 0)

        let routine = PulsarRoutine(
            name: "Push Day",
            emoji: "💪",
            exercises: [PulsarRoutineExercise(exercise: Self.makeExercise(), order: 0)]
        )
        let saved = store.upsert(routine)
        #expect(store.routinesRevision == 1)

        store.delete(saved)
        #expect(store.routinesRevision == 2)

        let reloaded = PulsarRoutineStore(defaults: defaults)
        #expect(reloaded.routinesRevision == 2)
        #expect(reloaded.routines.isEmpty)
    }

    @Test func savedGymRoutinesPayloadDecodesLegacyRoutineArray() throws {
        let routine = PulsarRoutine(
            name: "Push Day",
            emoji: "💪",
            exercises: [PulsarRoutineExercise(exercise: Self.makeExercise(), order: 0)]
        )
        let plan = WatchGymRoutinePlan(routine: routine)
        let legacyData = try JSONEncoder().encode([plan])

        let decoded = try #require(SavedGymRoutinesSyncCodec.decode(legacyData))

        #expect(decoded.revision == 0)
        #expect(decoded.routines.map(\.routineId) == [routine.id])
        #expect(decoded.deletedRoutineIds.isEmpty)
    }

    @Test func savedGymRoutinesPayloadPreservesRevisionAndDeletes() throws {
        let routine = PulsarRoutine(
            name: "Pull Day",
            emoji: "🏋️",
            exercises: [PulsarRoutineExercise(exercise: Self.makeExercise(), order: 0)]
        )
        let deletedID = UUID()
        let payload = SavedGymRoutinesSyncPayload(
            revision: 7,
            routines: [WatchGymRoutinePlan(routine: routine)],
            deletedRoutineIds: [deletedID]
        )
        let data = try #require(SavedGymRoutinesSyncCodec.encode(payload))
        let decoded = try #require(SavedGymRoutinesSyncCodec.decode(data))

        #expect(decoded.revision == 7)
        #expect(decoded.routines.first?.routineId == routine.id)
        #expect(decoded.deletedRoutineIds == [deletedID])
    }

    @Test func savedRoutineTransportPreservesNestedExerciseAndSetTemplates() throws {
        let groupID = UUID()
        let exercises = [
            PulsarRoutineExercise(
                exercise: Self.makeExercise(id: "bench", name: "Bench Press"),
                order: 0,
                plannedSets: 4,
                plannedReps: 6,
                plannedWeight: 82.5,
                weightUnit: .kilograms,
                plannedRestSeconds: 120,
                notes: "Pause on chest",
                supersetGroupId: groupID,
                supersetOrder: 0
            ),
            PulsarRoutineExercise(
                exercise: Self.makeExercise(id: "row", name: "Cable Row", primaryGroup: .back),
                order: 1,
                plannedSets: 3,
                plannedReps: 10,
                plannedWeight: 55,
                plannedRestSeconds: 75,
                supersetGroupId: groupID,
                supersetOrder: 1
            ),
            PulsarRoutineExercise(
                exercise: Self.makeExercise(id: "fly", name: "Cable Fly"),
                order: 2,
                plannedSets: 2,
                plannedReps: 15,
                plannedWeight: 20,
                plannedRestSeconds: 45
            )
        ]
        let routine = PulsarRoutine(
            name: "Friday",
            exercises: exercises,
            supersetGroups: [
                PulsarSupersetGroup(
                    id: groupID,
                    exerciseIds: Array(exercises.prefix(2).map(\.id)),
                    sharedSetCount: 4,
                    restTimeSeconds: 90
                )
            ]
        )
        let payload = SavedGymRoutinesSyncPayload(
            revision: 11,
            routines: [WatchGymRoutinePlan(routine: routine)]
        )

        let data = try #require(SavedGymRoutinesSyncCodec.encode(payload))
        let decoded = try #require(SavedGymRoutinesSyncCodec.decode(data)).routines[0]

        #expect(decoded.hasCompleteExerciseDefinition)
        #expect(decoded.exercises.map(\.exerciseId) == ["bench", "row", "fly"])
        #expect(decoded.exercises.map(\.orderIndex) == [0, 1, 2])
        #expect(decoded.exercises.map(\.plannedSets) == [4, 3, 2])
        #expect(decoded.exercises.map(\.plannedReps) == [6, 10, 15])
        #expect(decoded.exercises.map(\.plannedWeight) == [82.5, 55, 20])
        #expect(decoded.exercises.map(\.plannedRestSeconds) == [120, 75, 45])
        #expect(decoded.exercises[0].supersetGroupId == groupID)
        #expect(decoded.exercises[0].supersetSharedSetCount == 4)
        #expect(decoded.totalSetCount == 9)
    }

    @Test func partialRoutineCatalogCannotReplaceCompleteCachedDefinition() {
        let routine = PulsarRoutine(
            name: "Friday",
            exercises: [PulsarRoutineExercise(exercise: Self.makeExercise(), order: 0, plannedSets: 4)]
        )
        let complete = WatchGymRoutinePlan(routine: routine)
        var partial = complete
        partial.exercises = []

        let merged = SavedGymRoutineDefinitionMerge.preservingCompleteDefinitions(
            incoming: [partial],
            current: [complete]
        )

        #expect(merged == [complete])
    }

    @Test func fridaySnapshotBuildsSameExerciseOrderAndSetsForActiveWorkout() throws {
        let exercises = [
            PulsarRoutineExercise(exercise: Self.makeExercise(id: "bench", name: "Bench"), order: 0, plannedSets: 4),
            PulsarRoutineExercise(exercise: Self.makeExercise(id: "row", name: "Row", primaryGroup: .back), order: 1, plannedSets: 3),
            PulsarRoutineExercise(exercise: Self.makeExercise(id: "fly", name: "Fly"), order: 2, plannedSets: 3),
            PulsarRoutineExercise(exercise: Self.makeExercise(id: "press", name: "Press"), order: 3, plannedSets: 3),
            PulsarRoutineExercise(exercise: Self.makeExercise(id: "raise", name: "Raise"), order: 4, plannedSets: 3),
            PulsarRoutineExercise(exercise: Self.makeExercise(id: "extension", name: "Extension"), order: 5, plannedSets: 2)
        ]
        let routine = PulsarRoutine(name: "Friday", exercises: exercises)
        let plan = WatchGymRoutinePlan(routine: routine)
        let envelope = GymRoutineSnapshotEnvelope(
            requestID: UUID(),
            sessionID: UUID(),
            routineID: routine.id,
            revision: 12,
            routinePlan: plan
        )
        let encoded = try #require(GymCrossDeviceCodec.encodeRoutineSnapshot(envelope))
        let decoded = try #require(GymCrossDeviceCodec.decodeRoutineSnapshot(encoded))
        let activeExercises = decoded.routinePlan.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map(ActiveGymWorkoutExerciseState.init(routinePlan:))

        #expect(decoded.routinePlan.hasCompleteExerciseDefinition)
        #expect(activeExercises.map(\.exerciseId) == ["bench", "row", "fly", "press", "raise", "extension"])
        #expect(activeExercises.map { $0.sets.count } == [4, 3, 3, 3, 3, 2])
        #expect(activeExercises.reduce(0) { $0 + $1.sets.count } == 18)

        var rehydrated = ActiveGymWorkoutExerciseState(routinePlan: decoded.routinePlan.exercises[0])
        let originalSetID = activeExercises[0].sets[0].id
        rehydrated = rehydrated.preservingLiveSetProgress(from: activeExercises[0])
        #expect(rehydrated.sets[0].id == originalSetID)
    }

    @Test func malformedPresentExercisePayloadDoesNotDecodeAsNameOnlyRoutine() throws {
        let routine = PulsarRoutine(
            name: "Friday",
            exercises: [PulsarRoutineExercise(exercise: Self.makeExercise(), order: 0)]
        )
        let encoded = try JSONEncoder().encode(routine)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["exercises"] = "malformed"
        let malformed = try JSONSerialization.data(withJSONObject: object)

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(PulsarRoutine.self, from: malformed)
        }
    }

    @Test func routineBuilderUsesGymPreferenceForNewLifts() {
        let exercise = Self.makeExercise()
        let viewModel = RoutineBuilderViewModel(defaultWeightUnit: .pounds)

        viewModel.toggleExercise(exercise)
        let routine = viewModel.makeRoutine()

        #expect(routine.exercises.first?.weightUnit == .pounds)
        #expect(routine.emoji == "💪")
    }

    @Test func routineBuilderPreservesExerciseMediaAndInstructions() throws {
        let exercise = Self.makeExercise(
            thumbnailURL: "images/bench-press.jpg"
        )
        let viewModel = RoutineBuilderViewModel(defaultWeightUnit: .pounds)

        viewModel.toggleExercise(exercise)
        let routine = viewModel.makeRoutine()
        let routineExercise = try #require(routine.exercises.first)

        #expect(routineExercise.exercise.thumbnailURL == "images/bench-press.jpg")
        #expect(routineExercise.exercise.instructions == "Press with control.")
    }

    @Test func routineBuilderReordersStableEntriesAndCarriesOrderThroughSaveWorkoutAndWatch() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        let bench = Self.makeExercise()
        let duplicateBench = Self.makeExercise()
        let rowOne = PulsarRoutineExercise(
            exercise: bench,
            order: 0,
            plannedSets: 5,
            plannedReps: 5,
            plannedWeight: 100,
            weightUnit: .kilograms,
            plannedRestSeconds: 150,
            notes: "Heavy first"
        )
        let rowTwo = PulsarRoutineExercise(
            exercise: duplicateBench,
            order: 1,
            plannedSets: 3,
            plannedReps: 12,
            plannedWeight: 60,
            weightUnit: .pounds,
            plannedRestSeconds: 75,
            notes: "Back-off duplicate"
        )
        let rowThree = PulsarRoutineExercise(
            exercise: Self.makeExercise(id: "free-exercise-db-test-row", name: "Cable Row", primaryGroup: .back, primaryMuscleName: "Back", equipmentName: "Cable"),
            order: 2
        )
        let viewModel = RoutineBuilderViewModel(
            routine: PulsarRoutine(name: "Reorder", exercises: [rowOne, rowTwo, rowThree])
        )

        #expect(viewModel.moveRoutineExercise(id: rowOne.id, to: 3))
        #expect(viewModel.routineExercises.map(\.id) == [rowTwo.id, rowThree.id, rowOne.id])
        #expect(viewModel.routineExercises.map(\.order) == [0, 1, 2])
        let movedRow = try #require(viewModel.routineExercises.last)
        #expect(movedRow.id == rowOne.id)
        #expect(movedRow.exercise.id == rowOne.exercise.id)
        #expect(movedRow.plannedSets == 5)
        #expect(movedRow.plannedReps == 5)
        #expect(movedRow.plannedWeight == 100)
        #expect(movedRow.plannedRestSeconds == 150)
        #expect(movedRow.notes == "Heavy first")

        #expect(viewModel.moveRoutineExercise(id: rowOne.id, to: 0))
        #expect(viewModel.routineExercises.map(\.id) == [rowOne.id, rowTwo.id, rowThree.id])
        #expect(!viewModel.moveRoutineExercise(id: rowOne.id, to: 0))
        #expect(!viewModel.moveRoutineExercise(id: UUID(), to: 1))

        let store = PulsarRoutineStore(defaults: defaults)
        let saved = viewModel.save(using: store)
        let restored = try #require(PulsarRoutineStore(defaults: defaults).routines.first)
        let session = PulsarGymWorkoutSession(routine: saved)
        let watchPlan = WatchGymRoutinePlan(routine: saved)

        #expect(restored.exercises.map(\.id) == [rowOne.id, rowTwo.id, rowThree.id])
        #expect(session.exercises.map(\.routineExerciseId) == [rowOne.id, rowTwo.id, rowThree.id])
        #expect(watchPlan.exercises.map(\.id) == [rowOne.id, rowTwo.id, rowThree.id])
        #expect(watchPlan.exercises.map(\.orderIndex) == [0, 1, 2])
    }

    @Test func routineBuilderMovesSupersetsAsContiguousBlocks() throws {
        let first = PulsarRoutineExercise(exercise: Self.makeExercise(id: "first", name: "First"), order: 0)
        let groupedFirst = PulsarRoutineExercise(exercise: Self.makeExercise(id: "grouped-first", name: "Grouped First"), order: 1)
        let groupedSecond = PulsarRoutineExercise(exercise: Self.makeExercise(id: "grouped-second", name: "Grouped Second"), order: 2)
        let last = PulsarRoutineExercise(exercise: Self.makeExercise(id: "last", name: "Last"), order: 3)
        let group = PulsarSupersetGroup(
            exerciseIds: [groupedFirst.id, groupedSecond.id],
            sharedSetCount: 4,
            restTimeSeconds: 75
        )
        let routine = PulsarRoutine(
            name: "Grouped",
            exercises: [first, groupedFirst, groupedSecond, last],
            supersetGroups: [group]
        )
        let viewModel = RoutineBuilderViewModel(routine: routine)

        #expect(viewModel.moveRoutineExercise(id: groupedFirst.id, to: 4))
        #expect(viewModel.routineExercises.map(\.id) == [first.id, last.id, groupedFirst.id, groupedSecond.id])
        #expect(viewModel.routineExercises.map(\.order) == [0, 1, 2, 3])
        let movedGroup = try #require(viewModel.supersetGroup(id: group.id))
        #expect(movedGroup.exerciseIds == [groupedFirst.id, groupedSecond.id])
        #expect(viewModel.routineExercises.filter { $0.supersetGroupId == group.id }.map(\.supersetOrder) == [0, 1])

        #expect(viewModel.moveRoutineExerciseUp(id: groupedSecond.id))
        #expect(viewModel.routineExercises.map(\.id) == [first.id, groupedFirst.id, groupedSecond.id, last.id])
        #expect(viewModel.moveRoutineExerciseDown(id: groupedFirst.id))
        #expect(viewModel.routineExercises.map(\.id) == [first.id, last.id, groupedFirst.id, groupedSecond.id])
    }

    @Test func routineSupersetConfigurationPersistsAndDuplicatesSafely() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        let bench = Self.makeExercise()
        let curl = Self.makeExercise(
            id: "free-exercise-db-test-curl",
            name: "Biceps Curl",
            primaryGroup: .biceps,
            primaryMuscleName: "Biceps",
            equipmentName: "Dumbbell"
        )
        let viewModel = RoutineBuilderViewModel(defaultWeightUnit: .kilograms)
        viewModel.toggleExercise(bench)
        viewModel.toggleExercise(curl)

        let firstID = try #require(viewModel.routineExercises.first?.id)
        let secondID = try #require(viewModel.routineExercises.last?.id)
        viewModel.createSuperset(firstExerciseID: firstID, secondExerciseID: secondID, restTimeSeconds: 75)
        let groupID = try #require(viewModel.supersetGroups.first?.id)
        viewModel.updateSupersetSetCount(groupID: groupID, sharedSetCount: 4)

        let store = PulsarRoutineStore(defaults: defaults)
        let saved = store.upsert(viewModel.makeRoutine())
        let reloaded = PulsarRoutineStore(defaults: defaults)
        let restored = try #require(reloaded.routines.first)
        let restoredGroup = try #require(restored.supersetGroups.first)

        #expect(saved.supersetGroups.count == 1)
        #expect(restoredGroup.restTimeSeconds == 75)
        #expect(restoredGroup.sharedSetCount == 4)
        #expect(restored.exercises.map(\.plannedSets) == [4, 4])
        #expect(restored.exercises.compactMap(\.supersetOrder) == [0, 1])

        let duplicate = reloaded.duplicate(restored)
        let duplicateGroup = try #require(duplicate.supersetGroups.first)

        #expect(duplicateGroup.id != restoredGroup.id)
        #expect(Set(duplicateGroup.exerciseIds) == Set(duplicate.exercises.map(\.id)))
        #expect(duplicate.exercises.allSatisfy { $0.supersetGroupId == duplicateGroup.id })
    }

    @Test func supersetSessionProgressionFocusesPartnerBeforeStartingGroupRest() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        let bench = Self.makeExercise()
        let curl = Self.makeExercise(
            id: "free-exercise-db-test-curl",
            name: "Biceps Curl",
            primaryGroup: .biceps,
            primaryMuscleName: "Biceps",
            equipmentName: "Dumbbell"
        )
        let first = PulsarRoutineExercise(exercise: bench, order: 0, plannedSets: 2, plannedReps: 8, plannedWeight: 80)
        let second = PulsarRoutineExercise(exercise: curl, order: 1, plannedSets: 2, plannedReps: 12, plannedWeight: 14)
        let group = PulsarSupersetGroup(
            exerciseIds: [first.id, second.id],
            sharedSetCount: 2,
            restTimeSeconds: 75
        )
        var routine = PulsarRoutine(name: "Upper Pair", emoji: "💪", exercises: [first, second], supersetGroups: [group])
        for index in routine.exercises.indices {
            routine.exercises[index].supersetGroupId = group.id
            routine.exercises[index].supersetOrder = index
            routine.exercises[index].plannedSets = group.sharedSetCount
        }

        let viewModel = GymWorkoutSessionViewModel(
            routine: routine,
            historyStore: PulsarGymWorkoutHistoryStore(defaults: defaults)
        )
        let firstExercise = try #require(viewModel.session.exercises.first)
        let secondExercise = try #require(viewModel.session.exercises.last)
        let firstSet = try #require(firstExercise.sets.first)
        let secondSet = try #require(secondExercise.sets.first)

        viewModel.updateSetValues(exerciseID: firstExercise.id, setID: firstSet.id, reps: 8, weight: 80)
        viewModel.updateSetValues(exerciseID: secondExercise.id, setID: secondSet.id, reps: 12, weight: 14)

        #expect(viewModel.toggleSet(exerciseID: firstExercise.id, setID: firstSet.id) == .completed)
        #expect(viewModel.restCountdownSeconds == nil)
        #expect(viewModel.focusTarget?.exerciseID == secondExercise.id)
        #expect(viewModel.focusTarget?.setNumber == 1)

        #expect(viewModel.toggleSet(exerciseID: secondExercise.id, setID: secondSet.id) == .completedSupersetRound)
        #expect(viewModel.restCountdownSeconds == 75)
        #expect(viewModel.restContext?.supersetGroupID != nil)

        viewModel.skipRest()
        #expect(viewModel.restCountdownSeconds == nil)
        #expect(viewModel.focusTarget?.exerciseID == firstExercise.id)
        #expect(viewModel.focusTarget?.setNumber == 2)

        viewModel.addSet(to: firstExercise.id)
        #expect(viewModel.session.exercises[0].sets.count == 3)
        #expect(viewModel.session.exercises[1].sets.count == 3)
        viewModel.removeLastSet(from: secondExercise.id)
        #expect(viewModel.session.exercises[0].sets.count == 2)
        #expect(viewModel.session.exercises[1].sets.count == 2)
    }

    @Test func editedSetValuesSaveAsActualsAndSummaryBreakdown() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        let exercise = Self.makeExercise()
        let routineExercise = PulsarRoutineExercise(
            exercise: exercise,
            order: 0,
            plannedSets: 1,
            plannedReps: 10,
            plannedWeight: 60,
            weightUnit: .pounds,
            plannedRestSeconds: 0
        )
        let routine = PulsarRoutine(name: "Push Day", emoji: "💪", exercises: [routineExercise])
        let historyStore = PulsarGymWorkoutHistoryStore(defaults: defaults)
        let viewModel = GymWorkoutSessionViewModel(routine: routine, historyStore: historyStore)
        let sessionExercise = try #require(viewModel.session.exercises.first)
        let set = try #require(sessionExercise.sets.first)

        viewModel.updateSetValues(exerciseID: sessionExercise.id, setID: set.id, reps: 7, weight: 72.5)
        #expect(viewModel.toggleSet(exerciseID: sessionExercise.id, setID: set.id) == .completed)

        let saved = historyStore.save(viewModel.session)
        let savedSet = try #require(saved.exercises.first?.sets.first)
        let summary = PulsarGymWorkoutSummary(session: saved)
        let exerciseSummary = try #require(summary.completedExerciseSummaries.first)
        let setSummary = try #require(exerciseSummary.sets.first)

        #expect(savedSet.completedReps == 7)
        #expect(savedSet.completedWeight == 72.5)
        #expect(summary.totalVolume == 507.5)
        #expect(setSummary.reps == 7)
        #expect(setSummary.weight == 72.5)
        #expect(exerciseSummary.weightUnit == .pounds)
        #expect(exerciseSummary.exerciseId == exercise.id)
        #expect(exerciseSummary.primaryMuscleGroup == .chest)
        #expect(exerciseSummary.equipment == "Barbell")
    }

    @Test func workoutSummaryCarriesExerciseSnapshotFields() throws {
        let exercise = Self.makeExercise(thumbnailURL: "file:///tmp/bench.jpg")
        let routineExercise = PulsarRoutineExercise(
            exercise: exercise,
            order: 0,
            plannedSets: 1,
            plannedReps: 10,
            plannedWeight: 60,
            weightUnit: .pounds
        )
        let routine = PulsarRoutine(name: "Push Day", emoji: "💪", exercises: [routineExercise])
        var session = Self.makeCompletedSession(
            routine: routine,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedWeight: 60,
            reps: 10
        )
        session.exercises[0].supersetGroupId = UUID()

        let summary = PulsarGymWorkoutSummary(session: session)
        let exerciseSummary = try #require(summary.completedExerciseSummaries.first)

        #expect(session.exercises.first?.thumbnailURL == "file:///tmp/bench.jpg")
        #expect(session.exercises.first?.instructionsPreview == "Press with control.")
        #expect(exerciseSummary.exerciseId == exercise.id)
        #expect(exerciseSummary.thumbnailURL == "file:///tmp/bench.jpg")
        #expect(exerciseSummary.primaryMuscleGroup == .chest)
        #expect(exerciseSummary.equipment == "Barbell")
        #expect(exerciseSummary.supersetGroupId == session.exercises[0].supersetGroupId)
    }

    @Test func circuitSessionProgressionFocusesAllMembersBeforeRest() throws {
        let bench = Self.makeExercise()
        let curl = Self.makeExercise(
            id: "free-exercise-db-test-curl",
            name: "Biceps Curl",
            primaryGroup: .biceps,
            primaryMuscleName: "Biceps",
            equipmentName: "Dumbbell"
        )
        let press = Self.makeExercise(
            id: "free-exercise-db-test-press",
            name: "Shoulder Press",
            primaryGroup: .shoulders,
            primaryMuscleName: "Shoulders",
            equipmentName: "Dumbbell"
        )
        let first = PulsarRoutineExercise(exercise: bench, order: 0, plannedSets: 2, plannedReps: 8, plannedWeight: 80)
        let second = PulsarRoutineExercise(exercise: curl, order: 1, plannedSets: 2, plannedReps: 12, plannedWeight: 14)
        let third = PulsarRoutineExercise(exercise: press, order: 2, plannedSets: 2, plannedReps: 10, plannedWeight: 30)
        let group = PulsarSupersetGroup(
            type: .circuit,
            exerciseIds: [first.id, second.id, third.id],
            sharedSetCount: 2,
            restTimeSeconds: 75,
            label: "Series A"
        )
        var routine = PulsarRoutine(name: "Upper Circuit", emoji: "💪", exercises: [first, second, third], supersetGroups: [group])
        for index in routine.exercises.indices {
            routine.exercises[index].supersetGroupId = group.id
            routine.exercises[index].supersetOrder = index
            routine.exercises[index].plannedSets = group.sharedSetCount
        }

        let viewModel = GymWorkoutSessionViewModel(routine: routine)
        let exercises = viewModel.session.exercises
        let firstSet = try #require(exercises[0].sets.first)
        let secondSet = try #require(exercises[1].sets.first)
        let thirdSet = try #require(exercises[2].sets.first)

        #expect(viewModel.session.supersetGroups.first?.exerciseIds.count == 3)
        #expect(viewModel.session.supersetGroups.first?.type == .circuit)

        #expect(viewModel.toggleSet(exerciseID: exercises[0].id, setID: firstSet.id) == .completed)
        #expect(viewModel.focusTarget?.exerciseID == exercises[1].id)
        #expect(viewModel.restCountdownSeconds == nil)

        #expect(viewModel.toggleSet(exerciseID: exercises[1].id, setID: secondSet.id) == .completed)
        #expect(viewModel.focusTarget?.exerciseID == exercises[2].id)
        #expect(viewModel.restCountdownSeconds == nil)

        #expect(viewModel.toggleSet(exerciseID: exercises[2].id, setID: thirdSet.id) == .completedSupersetRound)
        #expect(viewModel.restCountdownSeconds == 75)
        #expect(viewModel.restContext?.supersetGroupID == group.id)
    }

    @Test func gymSetActionCodecPreservesEditedActualValues() throws {
        let sessionId = UUID()
        let exerciseId = UUID()
        let setId = UUID()
        let action = ActiveGymWorkoutAction.completeSet(
            sessionId: sessionId,
            exerciseId: exerciseId,
            setId: setId,
            reps: 7,
            weight: 72.5
        )

        let data = try #require(ActiveGymWorkoutCodec.encodeAction(action))
        let decoded = try #require(ActiveGymWorkoutCodec.decodeAction(data))

        #expect(decoded.kind == .completeSet)
        #expect(decoded.sessionId == sessionId)
        #expect(decoded.exerciseId == exerciseId)
        #expect(decoded.setId == setId)
        #expect(decoded.setReps == 7)
        #expect(decoded.setWeight == 72.5)
    }

    @Test func gymWeightPreferencePersistsAndResolvesIndependentlyFromAppUnits() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        let settings = GymSettingsStore(defaults: defaults)
        #expect(settings.weightUnitPreference == .followApp)
        #expect(settings.resolvedWeightUnit(appUnits: .metric) == .kilograms)

        settings.setWeightUnitPreference(.pounds)

        let restored = GymSettingsStore(defaults: defaults)
        #expect(restored.weightUnitPreference == .pounds)
        #expect(restored.resolvedWeightUnit(appUnits: .metric) == .pounds)
    }

    @Test func savedRoutineStartOverlaysLatestPerformanceWithoutMutatingTemplate() {
        let exercise = Self.makeExercise()
        let routineExercise = PulsarRoutineExercise(
            exercise: exercise,
            order: 0,
            plannedSets: 3,
            plannedReps: 10,
            plannedWeight: 60,
            weightUnit: .pounds,
            plannedRestSeconds: 90
        )
        let routine = PulsarRoutine(name: "Push Day", emoji: "💪", exercises: [routineExercise])
        let session = Self.makeCompletedSession(
            routine: routine,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedWeight: 65,
            reps: 10
        )

        let preparedRoutine = StrengthProgressAnalyticsService.routineWithLatestPerformanceOverlay(
            routine,
            sessions: [session],
            displayUnit: .pounds
        )

        #expect(routine.exercises.first?.plannedWeight == 60)
        #expect(preparedRoutine.exercises.first?.plannedWeight == 65)
        #expect(preparedRoutine.exercises.first?.plannedReps == 10)
        #expect(preparedRoutine.exercises.first?.plannedSets == 3)
    }

    @Test func strengthProgressDashboardComputesExerciseDelta() throws {
        let exercise = Self.makeExercise()
        let routineExercise = PulsarRoutineExercise(
            exercise: exercise,
            order: 0,
            plannedSets: 3,
            plannedReps: 10,
            plannedWeight: 60,
            weightUnit: .pounds,
            plannedRestSeconds: 90
        )
        let routine = PulsarRoutine(name: "Push Day", emoji: "💪", exercises: [routineExercise])
        let first = Self.makeCompletedSession(
            routine: routine,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedWeight: 60,
            reps: 10
        )
        let second = Self.makeCompletedSession(
            routine: routine,
            startedAt: Date(timeIntervalSince1970: 1_700_086_400),
            completedWeight: 70,
            reps: 10
        )

        let dashboard = StrengthProgressAnalyticsService.dashboard(
            sessions: [second, first],
            timeRange: .allTime,
            displayUnit: .pounds,
            now: Date(timeIntervalSince1970: 1_700_172_800),
            calendar: Calendar(identifier: .gregorian)
        )
        let bench = try #require(dashboard.exercises.first(where: { $0.name == "Bench Press" }))

        #expect(bench.latestBestWeight == 70)
        #expect(bench.previousBestWeight == 60)
        #expect(bench.weightDelta == 10)
        #expect(bench.bestEstimatedOneRepMax != nil)
    }

    @Test func dailyExerciseProgressUsesSelectedLocalDayOnly() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let selectedDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 12)))
        let includedStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 0, minute: 30)))
        let excludedStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 23, minute: 30)))

        let exercise = Self.makeExercise()
        let routineExercise = PulsarRoutineExercise(
            exercise: exercise,
            order: 0,
            plannedSets: 3,
            plannedReps: 8,
            plannedWeight: 80,
            weightUnit: .pounds
        )
        let routine = PulsarRoutine(name: "Push Day", emoji: "💪", exercises: [routineExercise])
        let included = Self.makeCompletedSession(routine: routine, startedAt: includedStart, completedWeight: 80, reps: 8)
        let excluded = Self.makeCompletedSession(routine: routine, startedAt: excludedStart, completedWeight: 100, reps: 5)

        let summaries = ExerciseProgressService.getDailyExerciseSummary(
            date: selectedDay,
            sessions: [excluded, included],
            displayUnit: .pounds,
            calendar: calendar
        )
        let summary = try #require(summaries.first)

        #expect(summaries.count == 1)
        #expect(summary.exerciseName == "Bench Press")
        #expect(summary.completedSets == 3)
        #expect(summary.totalReps == 24)
        #expect(summary.maxWeight == 80)
        #expect(summary.totalVolume == 1_920)
    }

    @Test func exerciseHistoryAggregatesSameDaySessionsIntoOnePoint() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let firstStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 7)))
        let secondStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 18)))
        let nextStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 18, hour: 7)))

        let exercise = Self.makeExercise()
        let routineExercise = PulsarRoutineExercise(
            exercise: exercise,
            order: 0,
            plannedSets: 3,
            plannedReps: 10,
            plannedWeight: 60,
            weightUnit: .pounds
        )
        let routine = PulsarRoutine(name: "Push Day", emoji: "💪", exercises: [routineExercise])
        let first = Self.makeCompletedSession(routine: routine, startedAt: firstStart, completedWeight: 60, reps: 10)
        let second = Self.makeCompletedSession(routine: routine, startedAt: secondStart, completedWeight: 70, reps: 10)
        let next = Self.makeCompletedSession(routine: routine, startedAt: nextStart, completedWeight: 80, reps: 8)
        let target = ExerciseProgressLookup(
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            primaryMuscleGroup: exercise.primaryMuscleGroup,
            equipment: exercise.equipmentSummary,
            displayUnit: .pounds
        )

        let history = ExerciseProgressService.getExerciseHistory(
            target: target,
            sessions: [next, second, first],
            displayUnit: .pounds,
            calendar: calendar
        )
        let firstPoint = try #require(history.points.first)

        #expect(history.points.count == 2)
        #expect(history.totalTimesTrained == 3)
        #expect(firstPoint.sessionCount == 2)
        #expect(firstPoint.completedSets == 6)
        #expect(firstPoint.totalReps == 60)
        #expect(firstPoint.maxWeight == 70)
        #expect(firstPoint.totalVolume == 3_900)
        #expect(history.bestWeightEver == 80)
    }

    @Test func exerciseProgressRecentSessionsReturnsWorkoutNamesAndSetRows() throws {
        let firstStart = Date(timeIntervalSince1970: 1_700_000_000)
        let secondStart = firstStart.addingTimeInterval(86_400)
        let exercise = Self.makeExercise()
        let routineExercise = PulsarRoutineExercise(
            exercise: exercise,
            order: 0,
            plannedSets: 2,
            plannedReps: 10,
            plannedWeight: 60,
            weightUnit: .pounds
        )
        let routine = PulsarRoutine(name: "Push Day", emoji: "💪", exercises: [routineExercise])
        let first = Self.makeCompletedSession(routine: routine, startedAt: firstStart, completedWeight: 60, reps: 10)
        let second = Self.makeCompletedSession(routine: routine, startedAt: secondStart, completedWeight: 70, reps: 8)
        let target = ExerciseProgressLookup(
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            primaryMuscleGroup: exercise.primaryMuscleGroup,
            equipment: exercise.equipmentSummary,
            displayUnit: .pounds
        )

        let recent = ExerciseProgressService.recentSessions(
            target: target,
            sessions: [first, second],
            displayUnit: .pounds,
            limit: 1
        )
        let latest = try #require(recent.first)

        #expect(recent.count == 1)
        #expect(latest.workoutName == "Push Day")
        #expect(latest.performedAt == secondStart)
        #expect(latest.sets.count == 2)
        #expect(latest.sets.first?.weight == 70)
        #expect(latest.bestSet?.reps == 8)
    }

    @Test func completedWorkoutResolverFallsBackToCatalogByName() throws {
        let catalogExercise = Self.makeExercise(
            id: "free-exercise-db-catalog-incline",
            name: "Barbell Incline Bench Press",
            thumbnailURL: "images/incline.jpg"
        )
        let summary = PulsarGymCompletedExerciseSummary(
            id: UUID(),
            exerciseName: "Barbell Incline Bench Press",
            primaryMuscleGroup: .other,
            equipment: "Bodyweight",
            weightUnit: .pounds,
            sets: [
                PulsarGymCompletedSetSummary(id: UUID(), setNumber: 1, reps: 10, weight: 140)
            ]
        )

        let presentations = CompletedWorkoutExerciseResolver.presentations(
            summaries: [summary],
            sourceSession: nil,
            catalogExercises: [catalogExercise]
        )
        let presentation = try #require(presentations.first)
        let set = try #require(presentation.sets.first)

        #expect(presentation.exerciseId == catalogExercise.id)
        #expect(presentation.thumbnailURL == "images/incline.jpg")
        #expect(presentation.instructionsPreview == "Press with control.")
        #expect(presentation.primaryMuscleGroup == .chest)
        #expect(presentation.equipment == "Barbell")
        #expect(set.estimatedOneRepMax == 140 * (1 + Double(10) / 30))
    }

    @Test func completedWorkoutEditorPersistsCompletedSetEdits() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        let exercise = Self.makeExercise()
        let routineExercise = PulsarRoutineExercise(
            exercise: exercise,
            order: 0,
            plannedSets: 1,
            plannedReps: 10,
            plannedWeight: 60,
            weightUnit: .pounds
        )
        let routine = PulsarRoutine(name: "Push Day", emoji: "💪", exercises: [routineExercise])
        let session = Self.makeCompletedSession(
            routine: routine,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            completedWeight: 60,
            reps: 10
        )
        let historyStore = PulsarGymWorkoutHistoryStore(defaults: defaults)
        let saved = historyStore.save(session)
        let savedExercise = try #require(saved.exercises.first)
        let savedSet = try #require(savedExercise.sets.first)

        let edited = try CompletedWorkoutEditor(historyStore: historyStore).updateSet(
            sessionId: saved.id,
            exerciseId: savedExercise.id,
            setId: savedSet.id,
            reps: 7,
            weight: 72.5
        )
        let editedSet = try #require(edited.exercises.first?.sets.first)
        let reloadedSet = try #require(PulsarGymWorkoutHistoryStore(defaults: defaults).sessions.first?.exercises.first?.sets.first)

        #expect(editedSet.completedReps == 7)
        #expect(editedSet.completedWeight == 72.5)
        #expect(editedSet.targetReps == 7)
        #expect(editedSet.targetWeight == 72.5)
        #expect(reloadedSet.completedReps == 7)
        #expect(reloadedSet.completedWeight == 72.5)
    }

    @Test func legacyGymExerciseAndSummaryDecodeWithoutSnapshotFields() throws {
        let exerciseId = UUID()
        let setId = UUID()
        let exerciseJSON = """
        {
          "id": "\(exerciseId.uuidString)",
          "routineExerciseId": "\(UUID().uuidString)",
          "exerciseName": "Bench Press",
          "primaryMuscleGroup": "chest",
          "primaryMuscles": [],
          "secondaryMuscles": [],
          "equipment": "Barbell",
          "plannedSets": 1,
          "plannedReps": 10,
          "plannedWeight": 60,
          "weightUnit": "lb",
          "plannedRestSeconds": 90,
          "orderIndex": 0,
          "sets": []
        }
        """.data(using: .utf8)!
        let summaryJSON = """
        {
          "id": "\(exerciseId.uuidString)",
          "exerciseName": "Bench Press",
          "weightUnit": "lb",
          "sets": [
            { "id": "\(setId.uuidString)", "setNumber": 1, "reps": 10, "weight": 60 }
          ]
        }
        """.data(using: .utf8)!

        let exercise = try JSONDecoder().decode(PulsarGymWorkoutExerciseSession.self, from: exerciseJSON)
        let summary = try JSONDecoder().decode(PulsarGymCompletedExerciseSummary.self, from: summaryJSON)

        #expect(exercise.thumbnailURL == nil)
        #expect(exercise.instructionsPreview == nil)
        #expect(summary.exerciseId == nil)
        #expect(summary.thumbnailURL == nil)
        #expect(summary.primaryMuscleGroup == .other)
        #expect(summary.equipment == "Bodyweight")
        #expect(summary.supersetGroupId == nil)
    }

    @Test func freeWorkoutPersistsAsGymFreeWorkout() throws {
        let defaults = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        var session = PulsarGymWorkoutSession(routine: .emptyGymWorkout(startedAt: startedAt), startedAt: startedAt)
        session.finishedAt = startedAt.addingTimeInterval(1_500)
        session.elapsedSeconds = 1_500

        let store = PulsarGymWorkoutHistoryStore(defaults: defaults)
        let saved = store.save(session)
        let reloaded = try #require(PulsarGymWorkoutHistoryStore(defaults: defaults).sessions.first)

        #expect(saved.workoutKind == .freeWorkout)
        #expect(saved.activityLogDisplayName == "Free Workout")
        #expect(reloaded.workoutKind == .freeWorkout)
        #expect(reloaded.activityLogDisplayName == "Free Workout")
    }

    @Test func watchFreeWorkoutStateRestoresAsGymFreeWorkout() {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let state = ActiveGymWorkoutState(
            sessionId: UUID(),
            routineId: UUID(),
            routineName: "Free Gym",
            routineEmoji: "🏋️",
            startedAt: startedAt,
            elapsedSeconds: 900,
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
            isFinished: true,
            updatedAt: startedAt.addingTimeInterval(900),
            exercises: []
        )

        let session = PulsarGymWorkoutSession(activeGymState: state)

        #expect(session.workoutKind == .freeWorkout)
        #expect(session.activityLogDisplayName == "Free Workout")
    }

    @Test func gymFinishActionsAreDurableAndIdempotencyTagged() throws {
        let sessionId = UUID()
        let actionId = UUID()
        var action = ActiveGymWorkoutAction.finishWorkout(sessionId: sessionId)
        action.actionId = actionId

        #expect(action.shouldQueueOverWatchConnectivity)

        let data = try #require(ActiveGymWorkoutCodec.encodeAction(action))
        let decoded = try #require(ActiveGymWorkoutCodec.decodeAction(data))

        #expect(decoded.kind == .finishWorkout)
        #expect(decoded.sessionId == sessionId)
        #expect(decoded.actionId == actionId)
        #expect(decoded.shouldQueueOverWatchConnectivity)
    }

    private static func makeExercise(
        id: String = "free-exercise-db-test-bench",
        name: String = "Bench Press",
        primaryGroup: PulsarMuscleGroup = .chest,
        primaryMuscleName: String = "Chest",
        equipmentName: String = "Barbell",
        thumbnailURL: String? = nil
    ) -> PulsarExercise {
        PulsarExercise(
            id: id,
            wgerID: nil,
            wgerUUID: nil,
            name: name,
            instructions: "Press with control.",
            primaryMuscles: [PulsarMuscle(name: primaryMuscleName, englishName: primaryMuscleName.lowercased(), group: primaryGroup)],
            secondaryMuscles: [PulsarMuscle(name: "Triceps", englishName: "triceps", group: .triceps)],
            primaryMuscleGroup: primaryGroup,
            equipment: [PulsarEquipment(name: equipmentName)],
            imageURLs: thumbnailURL.map { [$0] } ?? [],
            thumbnailURL: thumbnailURL,
            attribution: .freeExerciseDB(sourceExerciseID: id)
        )
    }

    private static func makeCompletedSession(
        routine: PulsarRoutine,
        startedAt: Date,
        completedWeight: Double,
        reps: Int
    ) -> PulsarGymWorkoutSession {
        var session = PulsarGymWorkoutSession(routine: routine, startedAt: startedAt)
        session.finishedAt = startedAt.addingTimeInterval(3_600)
        session.elapsedSeconds = 3_600

        for exerciseIndex in session.exercises.indices {
            for setIndex in session.exercises[exerciseIndex].sets.indices {
                session.exercises[exerciseIndex].sets[setIndex].targetReps = reps
                session.exercises[exerciseIndex].sets[setIndex].targetWeight = completedWeight
                session.exercises[exerciseIndex].sets[setIndex].completedReps = reps
                session.exercises[exerciseIndex].sets[setIndex].completedWeight = completedWeight
                session.exercises[exerciseIndex].sets[setIndex].isCompleted = true
                session.exercises[exerciseIndex].sets[setIndex].completedAt = startedAt.addingTimeInterval(Double(setIndex + 1) * 120)
            }
        }

        return session
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "PulsarTests.GymRoutineExperience.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(suiteName, forKey: "__suiteName")
        return defaults
    }

    private func defaultsSuiteName(_ defaults: UserDefaults) -> String {
        defaults.string(forKey: "__suiteName") ?? "PulsarTests.GymRoutineExperience"
    }
}
