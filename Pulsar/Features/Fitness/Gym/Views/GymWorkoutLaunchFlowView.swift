//
//  GymWorkoutLaunchFlowView.swift
//  Pulsar
//

import HealthKit
import SwiftUI
import UIKit

struct GymWorkoutLaunchFlowView: View {
    private enum Step: Hashable {
        case intro
        case routineChoice
        case savedRoutines
        case routineBuilder(PulsarRoutine?)
        case workoutSession(PulsarRoutine)
        case watchWorkoutSession(UUID)
    }

    private enum BuilderReturnTarget {
        case choice
        case savedRoutines
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var activeWorkoutManager: PulsarActiveWorkoutManager
    @EnvironmentObject private var completionPresentationStore: WorkoutCompletionPresentationStore
    @StateObject private var routineStore = PulsarRoutineStore()
    @StateObject private var historyStore = PulsarGymWorkoutHistoryStore()
    @StateObject private var gymSettingsStore = GymSettingsStore()
    @ObservedObject private var watchSyncStore = PulsarWatchConnectivitySyncStore.shared
    @State private var step: Step = .intro
    @State private var builderReturnTarget: BuilderReturnTarget = .choice
    @State private var watchFallbackPrompt: PulsarWatchRecorderFallbackPrompt?
    @State private var pendingWatchFallbackRoutine: PulsarRoutine?
    @State private var isGymStartInFlight = false

    private let healthStore = HKHealthStore()

    var appUnitPreference: UnitPreference = .metric

    var body: some View {
        ZStack {
            switch step {
            case .intro:
                PersonalizedWorkoutStartView(
                    workout: .gym,
                    onStart: showRoutineChoice,
                    onCancel: { dismiss() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))

            case .routineChoice:
                GymRoutineChoiceView(
                    savedRoutineCount: routineStore.routines.count,
                    onShowSavedRoutines: showSavedRoutines,
                    onCreateRoutine: showRoutineBuilder,
                    onStartEmptyWorkout: startEmptyWorkout,
                    onCancel: { dismiss() }
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))

            case .savedRoutines:
                GymSavedRoutinesView(
                    routineStore: routineStore,
                    historyStore: historyStore,
                    onBack: showRoutineChoice,
                    onCreateRoutine: showRoutineBuilder,
                    onStartRoutine: startWorkout(from:),
                    onEditRoutine: editRoutine
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))

            case .routineBuilder(let routine):
                GymRoutineBuilderFlowView(
                    routineStore: routineStore,
                    initialRoutine: routine,
                    defaultWeightUnit: gymSettingsStore.resolvedWeightUnit(appUnits: appUnitPreference),
                    onCancel: returnFromBuilder,
                    onStartWorkout: startWorkout(from:)
                )
                .transition(.opacity.combined(with: .scale(scale: 1.01)))

            case .workoutSession(let routine):
                if let viewModel = activeWorkoutManager.gymSessionViewModel {
                    GymWorkoutSessionView(
                        viewModel: viewModel,
                        onMinimize: {
                            activeWorkoutManager.minimizeGymWorkout(sessionID: viewModel.session.id)
                            dismiss()
                        },
                        onFinish: {
                            dismissGymCompletion(sessionID: viewModel.session.id, source: "gymLaunchSummaryDone")
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.99)))
                } else {
                    GymWorkoutLaunchPreparingView(routineName: routine.name) {
                        startGymWorkoutOnIPhone(routine)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.99)))
                }

            case .watchWorkoutSession(_):
                GymWatchMirroredWorkoutView(
                    syncStore: watchSyncStore,
                    onMinimize: {
                        activeWorkoutManager.minimizeWatchGymWorkout(sessionID: watchSyncStore.activeGymState?.sessionId ?? watchSyncStore.lastFinishedGymState?.sessionId)
                        dismiss()
                    },
                    onSummaryDone: {
                        dismissWatchGymCompletion(
                            sessionID: watchSyncStore.lastFinishedGymState?.sessionId ?? watchSyncStore.activeGymState?.sessionId ?? activeWorkoutManager.activeWorkout?.sessionID,
                            source: "watchGymLaunchSummaryDone"
                        )
                        dismiss()
                    }
                )
                .environmentObject(completionPresentationStore)
                .transition(.opacity.combined(with: .scale(scale: 0.99)))
            }
        }
        .background(GymGlassBackground().ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .animation(.smooth(duration: 0.36), value: step)
        .alert(item: $watchFallbackPrompt) { prompt in
            Alert(
                title: Text(prompt.title),
                message: Text(prompt.message),
                primaryButton: .default(Text("Try Again")) {
                    retryWatchGymStart()
                },
                secondaryButton: .default(Text("Use iPhone Only")) {
                    startPendingGymWorkoutOnIPhone()
                }
            )
        }
    }

    private func showRoutineChoice() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        step = .routineChoice
    }

    private func showSavedRoutines() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        step = .savedRoutines
    }

    private func showRoutineBuilder() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        builderReturnTarget = .choice
        step = .routineBuilder(nil)
    }

    private func editRoutine(_ routine: PulsarRoutine) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        builderReturnTarget = .savedRoutines
        step = .routineBuilder(routine)
    }

    private func returnFromBuilder() {
        switch builderReturnTarget {
        case .choice:
            showRoutineChoice()
        case .savedRoutines:
            showSavedRoutines()
        }
    }

    private func startEmptyWorkout() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let routine = PulsarRoutine.emptyGymWorkout()
        Task { await beginGymWorkout(routine) }
    }

    private func startWorkout(from routine: PulsarRoutine) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { await beginGymWorkout(routine) }
    }

    private func beginGymWorkout(_ routine: PulsarRoutine, forceIPhone: Bool = false) async {
        guard !isGymStartInFlight else { return }
        isGymStartInFlight = true
        defer { isGymStartInFlight = false }

        if !forceIPhone {
            let workoutKind = PulsarGymWorkoutKind.inferred(
                routineName: routine.name,
                exerciseCount: routine.exercises.count
            )
            let availability = await watchSyncStore.waitForReachableWatchRecorder(
                reason: "iPhoneGymStart.\(workoutKind.rawValue)"
            )
            if availability.canStartOnWatch {
                do {
                    try await startGymWorkoutOnWatch(routine, workoutKind: workoutKind, availability: availability)
                    return
                } catch {
                    pendingWatchFallbackRoutine = routine
                    watchFallbackPrompt = availability.fallbackPrompt(
                        workoutName: workoutKind.displayName,
                        reason: .watchLaunchFailed,
                        errorMessage: error.localizedDescription
                    )
                    return
                }
            } else {
                pendingWatchFallbackRoutine = routine
                watchFallbackPrompt = availability.fallbackPrompt(workoutName: workoutKind.displayName)
                PulsarSyncDebugLogger.log("Gym recorder selected=iPhoneFallbackPrompt type=\(workoutKind.rawValue) reason=\(availability.fallbackReason?.logValue ?? "unknown") rawInstalled=\(availability.rawIsWatchAppInstalled) rawReachable=\(availability.rawIsReachable) lastWatchSeenAt=\(availability.lastWatchSeenAt?.description ?? "none") derivedInstalled=\(availability.isWatchAppInstalled) derivedReachable=\(availability.derivedReachabilityDescription)")
                return
            }
        }

        startGymWorkoutOnIPhone(routine)
    }

    private func startGymWorkoutOnIPhone(_ routine: PulsarRoutine) {
        activeWorkoutManager.startGymWorkout(
            routine: routine,
            workoutWeightUnit: gymSettingsStore.resolvedWeightUnit(appUnits: appUnitPreference),
            historyStore: historyStore
        )
        step = .workoutSession(routine)
    }

    private func startGymWorkoutOnWatch(
        _ routine: PulsarRoutine,
        workoutKind: PulsarGymWorkoutKind,
        availability: PulsarWatchRecorderAvailabilitySnapshot
    ) async throws {
        let sessionId = UUID()
        switch PulsarWorkoutStartCoordinator.shared.requestStart(
            sessionID: sessionId,
            kind: .watchGym,
            source: "iPhoneRequestedWatchGymStart",
            workoutType: workoutKind.rawValue
        ) {
        case .granted:
            break
        case .duplicateStart, .alreadyActive:
            step = .watchWorkoutSession(sessionId)
            return
        case .rejectedConflict:
            throw WorkoutStartConflictError.anotherWorkoutActive
        }

        let now = Date()
        let session = PulsarGymWorkoutSession(id: sessionId, routine: routine, startedAt: now)
        let state = activeGymState(
            from: session,
            startedFrom: .iPhoneRequestedWatchStart,
            healthKitStatusMessage: watchStartStatusMessage(for: availability)
        )

        watchSyncStore.storeActiveGymState(state, broadcast: false, reason: "iPhoneRequestedWatchGymStart")
        PulsarWorkoutLifecycleLogger.log(
            .workoutWatchSyncRequested,
            sessionID: sessionId,
            workoutType: workoutKind.rawValue,
            source: "iPhoneRequestedWatchGymStart"
        )
        await watchSyncStore.broadcastActiveStateAndAwaitDelivery(
            state,
            reason: "iPhoneRequestedWatchGymStart.prelaunch"
        )
        let configuration = Self.gymWorkoutConfiguration
        PulsarSyncDebugLogger.log("Gym start selectedType=\(workoutKind.rawValue) hkType=\(configuration.activityType.rawValue) session=\(sessionId.uuidString) startedFrom=\(PulsarWorkoutStartedFrom.iPhoneRequestedWatchStart.rawValue) selectedRecorder=AppleWatch activation=\(availability.activationStateDescription) paired=\(availability.isPaired) rawInstalled=\(availability.rawIsWatchAppInstalled) rawReachable=\(availability.rawIsReachable) lastWatchSeenAt=\(availability.lastWatchSeenAt?.description ?? "none") derivedInstalled=\(availability.isWatchAppInstalled) derivedReachable=\(availability.derivedReachabilityDescription)")

        do {
            try await healthStore.startWatchApp(toHandle: configuration)
            PulsarWorkoutLifecycleLogger.log(
                .workoutWatchSyncSucceeded,
                sessionID: sessionId,
                workoutType: workoutKind.rawValue,
                source: "iPhoneRequestedWatchGymStart"
            )
        } catch {
            if shouldKeepQueuedWatchStart(for: availability) {
                PulsarWorkoutLifecycleLogger.log(
                    .workoutWatchSyncSucceeded,
                    sessionID: sessionId,
                    workoutType: workoutKind.rawValue,
                    source: "iPhoneRequestedWatchGymStart.queued",
                    detail: error.localizedDescription
                )
                PulsarSyncDebugLogger.log("Gym Watch start queued after launch failure type=\(workoutKind.rawValue) session=\(sessionId.uuidString) rawReachable=\(availability.rawIsReachable) derivedReachable=\(availability.derivedReachabilityDescription) error=\(error.localizedDescription)")
            } else {
                watchSyncStore.clearActiveGymState(reason: "iPhoneGymWatchLaunchFailed", broadcastEndedState: false)
                PulsarWorkoutStartCoordinator.shared.markStartFailed(
                    sessionID: sessionId,
                    workoutType: workoutKind.rawValue,
                    source: "iPhoneRequestedWatchGymStart",
                    error: error.localizedDescription
                )
                PulsarWorkoutLifecycleLogger.log(
                    .workoutWatchSyncFailed,
                    sessionID: sessionId,
                    workoutType: workoutKind.rawValue,
                    source: "iPhoneRequestedWatchGymStart",
                    detail: error.localizedDescription
                )
                throw error
            }
        }

        activeWorkoutManager.reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: sessionId,
            phase: "starting",
            reason: "iPhoneRequestedWatchGymStart"
        )
        PulsarWorkoutStartCoordinator.shared.markActivated(
            sessionID: sessionId,
            workoutType: workoutKind.rawValue,
            source: "iPhoneRequestedWatchGymStart"
        )
        step = .watchWorkoutSession(sessionId)
    }

    private func watchStartStatusMessage(for availability: PulsarWatchRecorderAvailabilitySnapshot) -> String {
        availability.rawIsReachable ? "Opening on Apple Watch..." : "Waiting for Apple Watch..."
    }

    private func shouldKeepQueuedWatchStart(for availability: PulsarWatchRecorderAvailabilitySnapshot) -> Bool {
        availability.isPaired &&
            availability.isWatchAppInstalled &&
            availability.hasRecentWatchHeartbeat &&
            !availability.rawIsReachable
    }

    private func retryWatchGymStart() {
        guard let routine = pendingWatchFallbackRoutine else { return }
        Task { await beginGymWorkout(routine) }
    }

    private func startPendingGymWorkoutOnIPhone() {
        guard let routine = pendingWatchFallbackRoutine else { return }
        pendingWatchFallbackRoutine = nil
        Task { await beginGymWorkout(routine, forceIPhone: true) }
    }

    private func dismissGymCompletion(sessionID: UUID?, source: String) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let sessionID {
            completionPresentationStore.consume(sessionID: sessionID, reason: source)
            watchSyncStore.tombstoneActiveWorkoutSession(sessionID, reason: "completionConsumed.\(source)")
            watchSyncStore.clearFinishedGymPresentationState(sessionID: sessionID, reason: "completionConsumed.\(source)")
        }
        step = .routineChoice
        activeWorkoutManager.completeGymWorkout()
        dismiss()
    }

    private func dismissWatchGymCompletion(sessionID: UUID?, source: String) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if let sessionID {
            completionPresentationStore.consume(sessionID: sessionID, reason: source)
            watchSyncStore.tombstoneActiveWorkoutSession(sessionID, reason: "completionConsumed.\(source)")
            watchSyncStore.clearFinishedGymPresentationState(sessionID: sessionID, reason: "completionConsumed.\(source)")
        }
        activeWorkoutManager.clearWatchGymWorkout(
            sessionID: sessionID,
            phase: "finished",
            source: source,
            reason: "summaryDismissed"
        )
    }

    private func activeGymState(
        from session: PulsarGymWorkoutSession,
        startedFrom: PulsarWorkoutStartedFrom,
        healthKitStatusMessage: String?
    ) -> ActiveGymWorkoutState {
        let exercises = session.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { activeExerciseState($0, supersetGroups: session.supersetGroups) }
        let totalSets = exercises.reduce(0) { $0 + $1.sets.count }

        return ActiveGymWorkoutState(
            sessionId: session.id,
            routineId: session.routineId,
            routineName: session.routineName,
            routineEmoji: session.routineEmoji,
            workoutKind: session.workoutKind,
            startedFrom: startedFrom,
            startedAt: session.startedAt,
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
            healthKitStatusMessage: healthKitStatusMessage,
            isFinished: false,
            updatedAt: Date(),
            exercises: exercises
        )
    }

    private func activeExerciseState(
        _ exercise: PulsarGymWorkoutExerciseSession,
        supersetGroups: [PulsarSupersetGroup]
    ) -> ActiveGymWorkoutExerciseState {
        let group = exercise.supersetGroupId.flatMap { groupId in
            supersetGroups.first { $0.id == groupId }
        }
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
            supersetRestSeconds: exercise.supersetRestSeconds ?? group?.restTimeSeconds,
            supersetSharedSetCount: group?.sharedSetCount,
            seriesMemberCount: group?.exerciseIds.count,
            thumbnailURL: exercise.thumbnailURL,
            instructionsPreview: exercise.instructionsPreview,
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

    private static var gymWorkoutConfiguration: HKWorkoutConfiguration {
        PulsarWorkoutCatalog.gymWorkoutConfiguration
    }
}

private enum WorkoutStartConflictError: LocalizedError {
    case anotherWorkoutActive

    var errorDescription: String? {
        switch self {
        case .anotherWorkoutActive:
            "Another workout is already active. Finish it before starting a new one."
        }
    }
}

private struct GymWorkoutLaunchPreparingView: View {
    var routineName: String
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .tint(.white)
            Text("Preparing \(routineName)")
                .pulsarTextStyle(.sectionTitle)
                .foregroundStyle(.white)
            Button("Retry Start", action: onRetry)
                .pulsarTextStyle(.buttonTitle)
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GymRoutineChoiceView: View {
    var savedRoutineCount: Int
    var onShowSavedRoutines: () -> Void
    var onCreateRoutine: () -> Void
    var onStartEmptyWorkout: () -> Void
    var onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 54)

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(colorScheme == .dark ? 0.08 : 0.70))
                        .frame(width: 72, height: 72)
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(colorScheme == .dark ? 0.18 : 0.88), lineWidth: 1)
                        }

                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, Color(red: 0.76, green: 0.69, blue: 1.0))
                }

                Text("Choose your gym session")
                    .pulsarTextStyle(.screenTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Start from a saved plan, build a new routine, or jump into open gym tracking.")
                    .pulsarTextStyle(.screenSubtitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14)

            VStack(spacing: 12) {
                GymChoiceActionButton(
                    title: "My Routines",
                    subtitle: savedRoutineCount == 0 ? "Create and save your first lift plan" : "\(savedRoutineCount) saved \(savedRoutineCount == 1 ? "routine" : "routines") ready",
                    symbolName: "rectangle.stack.fill",
                    prominence: .secondary,
                    action: onShowSavedRoutines
                )

                GymChoiceActionButton(
                    title: "Create Routine",
                    subtitle: "Choose exercises from the Pulsar catalog",
                    symbolName: "sparkles",
                    prominence: .primary,
                    action: onCreateRoutine
                )

                GymChoiceActionButton(
                    title: "Start Free Workout",
                    subtitle: "Track a freestyle gym session",
                    symbolName: "timer",
                    prominence: .secondary,
                    action: onStartEmptyWorkout
                )

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onCancel()
                } label: {
                    Text("Cancel")
                        .pulsarTextStyle(.buttonTitle)
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white.opacity(0.055), in: Capsule(style: .continuous))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(.white.opacity(0.10), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 54)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GymSavedRoutinesView: View {
    @ObservedObject var routineStore: PulsarRoutineStore
    @ObservedObject var historyStore: PulsarGymWorkoutHistoryStore
    var onBack: () -> Void
    var onCreateRoutine: () -> Void
    var onStartRoutine: (PulsarRoutine) -> Void
    var onEditRoutine: (PulsarRoutine) -> Void

    @State private var routinePendingDeletion: PulsarRoutine?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if routineStore.routines.isEmpty {
                emptyState
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(routineStore.routines) { routine in
                            GymSavedRoutineCard(
                                routine: routine,
                                lastPerformed: lastPerformedDate(for: routine),
                                onStart: {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    onStartRoutine(routine)
                                },
                                onEdit: {
                                    onEditRoutine(routine)
                                },
                                onDuplicate: {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    _ = routineStore.duplicate(routine)
                                },
                                onDelete: {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    routinePendingDeletion = routine
                                }
                            )
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(
            "Delete routine?",
            isPresented: Binding(
                get: { routinePendingDeletion != nil },
                set: { if !$0 { routinePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Routine", role: .destructive) {
                if let routinePendingDeletion {
                    routineStore.delete(routinePendingDeletion)
                }
                routinePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                routinePendingDeletion = nil
            }
        } message: {
            Text("This only removes the saved routine. Completed workout history stays intact.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.08), in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.11), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 5) {
                Text("My Routines")
                    .pulsarTextStyle(.screenTitle)
                    .foregroundStyle(.white)

                Text("Saved lifting plans, ready when you are.")
                    .pulsarTextStyle(.screenSubtitle)
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer(minLength: 0)

            Button(action: onCreateRoutine) {
                Image(systemName: "plus")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(Color(red: 0.14, green: 0.09, blue: 0.22))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.96), in: Circle())
            }
            .buttonStyle(PulsarGymPressButtonStyle())
            .accessibilityLabel("Create routine")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 78, height: 78)
                Text("🏋️")
                    .font(.system(size: 36))
            }

            VStack(spacing: 6) {
                Text("No saved routines yet")
                    .pulsarTextStyle(.sectionTitle)
                    .foregroundStyle(.white)
                Text("Create your first routine and Pulsar will keep the plan here for faster gym starts.")
                    .pulsarTextStyle(.screenSubtitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onCreateRoutine) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Create your first routine")
                }
                .pulsarTextStyle(.buttonTitle)
                .foregroundStyle(Color(red: 0.14, green: 0.09, blue: 0.22))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [.white.opacity(0.98), Color(red: 0.84, green: 0.78, blue: 1.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Capsule(style: .continuous)
                )
            }
            .buttonStyle(PulsarGymPressButtonStyle())
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private func lastPerformedDate(for routine: PulsarRoutine) -> Date? {
        historyStore.sessions
            .filter { $0.routineId == routine.id && $0.finishedAt != nil }
            .map(\.startedAt)
            .max()
    }
}

private struct GymSavedRoutineCard: View {
    var routine: PulsarRoutine
    var lastPerformed: Date?
    var onStart: () -> Void
    var onEdit: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 13) {
                Text(routine.emoji)
                    .font(.system(size: 28))
                    .frame(width: 54, height: 54)
                    .background(.white.opacity(0.11), in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.14), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text(routine.name)
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(routineSubtitle)
                        .pulsarTextStyle(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Menu {
                    Button("Edit", systemImage: "pencil", action: onEdit)
                    Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .pulsarTextStyle(.label)
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.08), in: Circle())
                }
            }

            HStack(spacing: 8) {
                GymSavedRoutineChip(symbol: "figure.strengthtraining.traditional", text: routine.exerciseCountText)
                GymSavedRoutineChip(symbol: "clock.fill", text: estimatedDurationText)
                if let lastPerformed {
                    GymSavedRoutineChip(symbol: "calendar", text: "Last \(lastPerformed.formatted(date: .abbreviated, time: .omitted))")
                }
            }

            HStack(spacing: 10) {
                Button(action: onEdit) {
                    Text("Edit")
                        .pulsarTextStyle(.label)
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(.white.opacity(0.08), in: Capsule(style: .continuous))
                }
                .buttonStyle(PulsarGymPressButtonStyle())

                Button(action: onStart) {
                    HStack(spacing: 7) {
                        Text("Start")
                        Image(systemName: "arrow.right")
                    }
                    .pulsarTextStyle(.label)
                    .foregroundStyle(Color(red: 0.14, green: 0.09, blue: 0.22))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        LinearGradient(
                            colors: [.white.opacity(0.98), Color(red: 0.84, green: 0.78, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule(style: .continuous)
                    )
                }
                .buttonStyle(PulsarGymPressButtonStyle())
            }
        }
        .padding(15)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
    }

    private var routineSubtitle: String {
        let muscles = routine.mainMuscleGroupNames
        return muscles.isEmpty ? "Custom gym routine" : muscles.joined(separator: " / ")
    }

    private var estimatedDurationText: String {
        let minutes = max(1, Int((Double(routine.estimatedDurationSeconds) / 60).rounded()))
        return "~\(minutes) min"
    }

    private var cardBackground: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(0.105),
                Color(red: 0.58, green: 0.48, blue: 1.0).opacity(0.070),
                .white.opacity(0.045)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct GymSavedRoutineChip: View {
    var symbol: String
    var text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .pulsarTextStyle(.overline)
            Text(text)
                .pulsarTextStyle(.overline)
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.68))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.white.opacity(0.070), in: Capsule(style: .continuous))
    }
}

private struct GymChoiceActionButton: View {
    enum Prominence {
        case primary
        case secondary
    }

    var title: String
    var subtitle: String
    var symbolName: String
    var prominence: Prominence
    var action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: prominence == .primary ? .medium : .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbolName)
                    .pulsarTextStyle(.cardTitle)
                    .frame(width: 42, height: 42)
                    .background(iconBackground, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .pulsarTextStyle(.buttonTitle)
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)

                    Text(subtitle)
                        .pulsarTextStyle(.caption)
                        .foregroundStyle(subtitleColor)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(chevronColor)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(border, lineWidth: 1)
            }
            .shadow(color: shadowColor, radius: prominence == .primary ? 24 : 14, y: 12)
        }
        .buttonStyle(PulsarGymPressButtonStyle())
    }

    private var background: LinearGradient {
        switch prominence {
        case .primary:
            LinearGradient(
                colors: [
                    Color.white.opacity(0.96),
                    Color(red: 0.84, green: 0.78, blue: 1.0).opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .secondary:
            LinearGradient(
                colors: [
                    Color.white.opacity(0.14),
                    Color.white.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var border: LinearGradient {
        LinearGradient(
            colors: prominence == .primary
                ? [.white.opacity(0.86), Color(red: 0.70, green: 0.62, blue: 1.0).opacity(0.32)]
                : [.white.opacity(0.18), .white.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var iconBackground: Color {
        prominence == .primary
            ? Color(red: 0.18, green: 0.14, blue: 0.30).opacity(0.10)
            : Color(red: 0.74, green: 0.66, blue: 1.0).opacity(0.16)
    }

    private var titleColor: Color {
        prominence == .primary
            ? Color(red: 0.12, green: 0.08, blue: 0.20)
            : .white.opacity(0.94)
    }

    private var subtitleColor: Color {
        prominence == .primary
            ? Color(red: 0.32, green: 0.26, blue: 0.42)
            : .white.opacity(0.60)
    }

    private var chevronColor: Color {
        prominence == .primary
            ? Color(red: 0.22, green: 0.14, blue: 0.34).opacity(0.62)
            : .white.opacity(0.44)
    }

    private var shadowColor: Color {
        prominence == .primary
            ? Color(red: 0.72, green: 0.62, blue: 1.0).opacity(0.34)
            : .black.opacity(0.18)
    }
}

struct GymGlassBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.04, blue: 0.09),
                    Color(red: 0.13, green: 0.06, blue: 0.17),
                    Color(red: 0.02, green: 0.02, blue: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 20) {
                ForEach(0..<12, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(.white.opacity(index.isMultiple(of: 3) ? 0.035 : 0.018))
                        .frame(height: 1)
                        .offset(x: index.isMultiple(of: 2) ? -26 : 34)
                }
            }
            .rotationEffect(.degrees(-11))
            .blendMode(.screen)
            .padding(.horizontal, -40)
        }
    }
}

struct PulsarGymPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.972 : 1)
            .brightness(configuration.isPressed ? 0.035 : 0)
            .animation(.spring(response: 0.26, dampingFraction: 0.76), value: configuration.isPressed)
    }
}

#Preview {
    GymWorkoutLaunchFlowView()
        .environmentObject(PulsarActiveWorkoutManager())
        .environmentObject(WorkoutCompletionPresentationStore())
}
