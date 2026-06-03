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

    @Test func routineBuilderUsesGymPreferenceForNewLifts() {
        let exercise = Self.makeExercise()
        let viewModel = RoutineBuilderViewModel(defaultWeightUnit: .pounds)

        viewModel.toggleExercise(exercise)
        let routine = viewModel.makeRoutine()

        #expect(routine.exercises.first?.weightUnit == .pounds)
        #expect(routine.emoji == "💪")
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
        equipmentName: String = "Barbell"
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
            imageURLs: [],
            thumbnailURL: nil,
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
