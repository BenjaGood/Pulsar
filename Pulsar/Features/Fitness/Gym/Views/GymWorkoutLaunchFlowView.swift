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
    @ObservedObject private var routineStore = PulsarRoutineStore.shared
    private let historyStore = PulsarGymWorkoutHistoryStore.shared
    @StateObject private var gymSettingsStore = GymSettingsStore()
    private let watchSyncStore = PulsarWatchConnectivitySyncStore.shared
    @State private var step: Step = .intro
    @State private var builderReturnTarget: BuilderReturnTarget = .choice
    @State private var watchFallbackPrompt: PulsarWatchRecorderFallbackPrompt?
    @State private var pendingWatchFallbackRoutine: PulsarRoutine?
    @State private var isGymStartInFlight = false
    @State private var stepBeforeWatchLaunch: Step?
    @StateObject private var crossDeviceStartController = GymCrossDeviceStartController()

    private let healthStore = HKHealthStore()

    var appUnitPreference: UnitPreference = .metric
    var profile: UserProfile = .empty

    var body: some View {
        let _ = PulsarWorkoutStartupTrace.count("[RenderRate] GymLaunchFlow")
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

            case .watchWorkoutSession(let expectedSessionID):
                GymWatchMirroredWorkoutView(
                    syncStore: watchSyncStore,
                    expectedSessionID: expectedSessionID,
                    profile: profile,
                    diagnosticHost: "launchCover",
                    crossDevicePhase: crossDeviceStartController.phase,
                    onMinimize: {
                        activeWorkoutManager.minimizeWatchGymWorkout(sessionID: expectedSessionID)
                        dismiss()
                    },
                    onSummaryDone: {
                        dismissWatchGymCompletion(
                            sessionID: expectedSessionID,
                            source: "watchGymLaunchSummaryDone"
                        )
                        dismiss()
                    },
                    onRetry: {
                        retryWatchGymStart()
                    },
                    onUseIPhoneOnly: {
                        startPendingGymWorkoutOnIPhone()
                    },
                    onCancel: {
                        crossDeviceStartController.cancel()
                        activeWorkoutManager.endLaunchCoverOwnership(
                            reason: "watchGymLaunchCancelled"
                        )
                        stepBeforeWatchLaunch = nil
                        step = .routineChoice
                    }
                )
                .environmentObject(completionPresentationStore)
                .transition(.opacity.combined(with: .scale(scale: 0.99)))
            }
        }
        .background(GymGlassBackground().ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .pulsarFitnessMonochromeAppearance()
        .animation(.smooth(duration: 0.36), value: step)
        .onChange(of: crossDeviceStartController.currentRequest?.candidateSessionID) { _, sessionID in
            guard GymLaunchWatchSessionPresentation.shouldFollowCrossDeviceStart(
                isFallbackPromptVisible: watchFallbackPrompt != nil
            ) else { return }
            guard let sessionID else { return }
            revealWatchWorkoutSessionIfNeeded(sessionID)
        }
        .onChange(of: crossDeviceStartController.phase) { _, phase in
            if let sessionID = crossDeviceStartController.currentRequest?.candidateSessionID,
               GymLaunchWatchSessionPresentation.shouldRevealWatchSession(
                   phase: phase,
                   isFallbackPromptVisible: watchFallbackPrompt != nil
               ) {
                revealWatchWorkoutSessionIfNeeded(sessionID)
            }
            guard case .watchWorkoutSession(let sessionID) = step, phase == .active else { return }
            _ = activeWorkoutManager.reconcileVerifiedWatchGymWorkout(
                sessionID: sessionID,
                phase: "active",
                reason: "GymCrossDeviceMirrorBecameLive"
            )
        }
        .alert(
            watchFallbackPrompt?.title ?? "Apple Watch not connected",
            isPresented: isWatchFallbackPromptPresented,
            presenting: watchFallbackPrompt
        ) { _ in
            Button("Try Again") {
                retryWatchGymStart()
            }
            Button("Use iPhone Only") {
                startPendingGymWorkoutOnIPhone()
            }
            Button("Cancel", role: .cancel) {
                cancelPendingWatchGymStart()
            }
        } message: { prompt in
            Text(prompt.message)
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
        PulsarWorkoutStartupTrace.phone("Start tapped gym forceIPhone=\(forceIPhone) routine=\(routine.name)")

        if !forceIPhone {
            let workoutKind = PulsarGymWorkoutKind.inferred(
                routineName: routine.name,
                exerciseCount: routine.exercises.count
            )
            let availability = await watchSyncStore.waitForWatchAppLaunchAvailability(
                reason: "iPhoneGymStart.\(workoutKind.rawValue)"
            )
            if availability.canAttemptWatchAppLaunch {
                if PulsarGymCrossDeviceStartFeature.isEnabled {
                    do {
                        try await startGymWorkoutOnWatchUsingCrossDeviceFlow(
                            routine,
                            workoutKind: workoutKind,
                            availability: availability
                        )
                        return
                    } catch {
                        revertWatchLaunchPresentationIfNeeded()
                        activeWorkoutManager.endLaunchCoverOwnership(
                            reason: "crossDeviceWatchStartFailed"
                        )
                        pendingWatchFallbackRoutine = routine
                        let fallbackReason: PulsarWatchRecorderFallbackReason =
                            (error as? GymCrossDeviceStartError) == .watchAcknowledgementTimedOut
                            ? .mirroringTimedOut
                            : .watchLaunchFailed
                        watchFallbackPrompt = availability.fallbackPrompt(
                            workoutName: workoutKind.displayName,
                            reason: fallbackReason,
                            errorMessage: error.localizedDescription
                        )
                        return
                    }
                }
                do {
                    try await startGymWorkoutOnWatchLegacy(
                        routine,
                        workoutKind: workoutKind,
                        availability: availability
                    )
                    return
                } catch {
                    revertWatchLaunchPresentationIfNeeded()
                    activeWorkoutManager.endLaunchCoverOwnership(
                        reason: "legacyWatchStartFailed"
                    )
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
        step = .workoutSession(routine)
        let weightUnit = gymSettingsStore.resolvedWeightUnit(appUnits: appUnitPreference)
        Task { @MainActor in
            // Commit the lightweight preparing route before historical strength
            // analytics constructs the live session model.
            await Task.yield()
            activeWorkoutManager.startGymWorkout(
                routine: routine,
                workoutWeightUnit: weightUnit,
                historyStore: historyStore
            )
        }
    }

    private func startGymWorkoutOnWatchUsingCrossDeviceFlow(
        _ routine: PulsarRoutine,
        workoutKind: PulsarGymWorkoutKind,
        availability: PulsarWatchRecorderAvailabilitySnapshot
    ) async throws {
        activeWorkoutManager.beginLaunchCoverOwnership(
            reason: "crossDeviceWatchGymLaunchCover"
        )
        crossDeviceStartController.resetForNewFlow()
        try await crossDeviceStartController.start(
            routine: routine,
            workoutKind: workoutKind,
            availability: availability,
            routineStore: routineStore
        )

        guard let request = crossDeviceStartController.currentRequest else {
            throw GymCrossDeviceStartError.unknown
        }

        revealWatchWorkoutSessionIfNeeded(request.candidateSessionID)

        let maximumVerificationPolls = Int((PulsarWorkoutStartCoordinator.watchAcknowledgementTimeout + 6) * 10)
        for _ in 0..<maximumVerificationPolls {
            if crossDeviceStartController.isVerifiedForPresentation {
                break
            }
            if case .failed = crossDeviceStartController.phase {
                throw crossDeviceStartController.lastError ?? GymCrossDeviceStartError.watchAcknowledgementTimedOut
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        guard crossDeviceStartController.isVerifiedForPresentation else {
            if PulsarWorkoutStartCoordinator.shared.phase.blocksNewWatchPrimaryIdentity {
                PulsarWorkoutStartupTrace.phone(
                    "Watch launch poll ended with remote state unknown \(PulsarWorkoutStartupTrace.identity(workoutID: request.candidateSessionID, requestID: request.requestID)) phase=\(PulsarWorkoutStartCoordinator.shared.phase.name)"
                )
                let waitingSessionID = PulsarWorkoutStartCoordinator.shared.currentTransaction?.authoritativeSessionID
                    ?? request.candidateSessionID
                revealWatchWorkoutSessionIfNeeded(waitingSessionID)
                return
            }
            throw GymCrossDeviceStartError.watchAcknowledgementTimedOut
        }

        guard PulsarWorkoutStartCoordinator.shared.isCrossDeviceGymStartVerified else {
            throw GymCrossDeviceStartError.watchAcknowledgementTimedOut
        }

        let authoritativeSessionID = PulsarWorkoutStartCoordinator.shared.currentTransaction?.authoritativeSessionID
            ?? request.candidateSessionID
        revealWatchWorkoutSessionIfNeeded(authoritativeSessionID)
    }

    private func startGymWorkoutOnWatchLegacy(
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
            activeWorkoutManager.beginLaunchCoverOwnership(
                reason: "legacyWatchGymLaunchCover"
            )
            watchSyncStore.prepareForNewGymStart(
                sessionID: sessionId,
                reason: "iPhoneRequestedWatchGymStart"
            )
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

        watchSyncStore.storeActiveGymState(state, broadcast: true, reason: "iPhoneRequestedWatchGymStart")
        PulsarWorkoutLifecycleLogger.log(
            .workoutWatchSyncRequested,
            sessionID: sessionId,
            workoutType: workoutKind.rawValue,
            source: "iPhoneRequestedWatchGymStart"
        )
        let configuration = Self.gymWorkoutConfiguration
        PulsarSyncDebugLogger.log("Gym start selectedType=\(workoutKind.rawValue) hkType=\(configuration.activityType.rawValue) session=\(sessionId.uuidString) startedFrom=\(PulsarWorkoutStartedFrom.iPhoneRequestedWatchStart.rawValue) selectedRecorder=AppleWatch activation=\(availability.activationStateDescription) paired=\(availability.isPaired) rawInstalled=\(availability.rawIsWatchAppInstalled) rawReachable=\(availability.rawIsReachable) lastWatchSeenAt=\(availability.lastWatchSeenAt?.description ?? "none") derivedInstalled=\(availability.isWatchAppInstalled) derivedReachable=\(availability.derivedReachabilityDescription)")

        do {
            let startedAt = Date()
            PulsarWorkoutStartupTrace.diag(
                "[StartWatchApp] begin kind=gym.legacy session=\(sessionId.uuidString) \(PulsarWorkoutStartupTrace.threadTag())"
            )
            try await healthStore.startWatchApp(toHandle: configuration)
            PulsarWorkoutStartupTrace.diag(
                "[StartWatchApp] completion kind=gym.legacy elapsedMs=\(PulsarWorkoutStartupTrace.elapsedMs(since: startedAt)) session=\(sessionId.uuidString) \(PulsarWorkoutStartupTrace.threadTag())"
            )
        } catch {
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

        step = .watchWorkoutSession(sessionId)
    }

    private func watchStartStatusMessage(for availability: PulsarWatchRecorderAvailabilitySnapshot) -> String {
        availability.rawIsReachable ? "Opening on Apple Watch..." : "Waiting for Apple Watch..."
    }

    private var isWatchFallbackPromptPresented: Binding<Bool> {
        Binding(
            get: { watchFallbackPrompt != nil },
            set: { isPresented in
                if !isPresented {
                    watchFallbackPrompt = nil
                }
            }
        )
    }

    private func retryWatchGymStart() {
        guard let routine = pendingWatchFallbackRoutine else { return }
        Task { await beginGymWorkout(routine) }
    }

    private func startPendingGymWorkoutOnIPhone() {
        guard let routine = pendingWatchFallbackRoutine else { return }
        if PulsarGymCrossDeviceStartFeature.isEnabled {
            crossDeviceStartController.chooseIPhoneOnlyFallback()
        }
        activeWorkoutManager.endLaunchCoverOwnership(
            reason: "selectedIPhoneFallback"
        )
        pendingWatchFallbackRoutine = nil
        Task { await beginGymWorkout(routine, forceIPhone: true) }
    }

    private func cancelPendingWatchGymStart() {
        pendingWatchFallbackRoutine = nil
        watchFallbackPrompt = nil
        crossDeviceStartController.cancel()
        revertWatchLaunchPresentationIfNeeded()
        activeWorkoutManager.endLaunchCoverOwnership(
            reason: "watchGymFallbackCancelled"
        )
        stepBeforeWatchLaunch = nil
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

    private func revealWatchWorkoutSessionIfNeeded(_ sessionID: UUID) {
        if case .watchWorkoutSession(let current) = step, current == sessionID {
            return
        }
        if case .watchWorkoutSession = step {
            applyWatchWorkoutSessionStep(sessionID)
            return
        }
        guard crossDeviceStartController.currentRequest?.candidateSessionID == sessionID
            || PulsarWorkoutStartCoordinator.shared.currentTransaction?.authoritativeSessionID == sessionID else {
            return
        }
        stepBeforeWatchLaunch = step
        applyWatchWorkoutSessionStep(sessionID)
    }

    private func applyWatchWorkoutSessionStep(_ sessionID: UUID) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            step = .watchWorkoutSession(sessionID)
        }
        PulsarWorkoutStartupTrace.diag(
            "[WorkoutUI] launchCoverPresentedWatchSession session=\(sessionID.uuidString) phase=\(crossDeviceStartController.phase.statusMessage) \(PulsarWorkoutStartupTrace.threadTag())"
        )
    }

    private func revertWatchLaunchPresentationIfNeeded() {
        guard case .watchWorkoutSession = step else { return }
        let restored = stepBeforeWatchLaunch ?? .routineChoice
        stepBeforeWatchLaunch = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            step = restored
        }
    }

    private static var gymWorkoutConfiguration: HKWorkoutConfiguration {
        PulsarWorkoutCatalog.gymWorkoutConfiguration
    }
}

enum GymLaunchWatchSessionPresentation {
    static func shouldFollowCrossDeviceStart(
        isFallbackPromptVisible: Bool
    ) -> Bool {
        !isFallbackPromptVisible
    }

    static func shouldRevealWatchSession(
        phase: GymCrossDeviceStartPresentationPhase,
        isFallbackPromptVisible: Bool = false
    ) -> Bool {
        guard shouldFollowCrossDeviceStart(isFallbackPromptVisible: isFallbackPromptVisible) else {
            return false
        }
        switch phase {
        case .idle, .cancelled:
            return false
        case .preparing, .launchingWatch, .waitingForWatchAcknowledgement,
             .watchSessionRunning, .mirroring, .recovering, .checkingWatch,
             .active, .failed:
            return true
        }
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
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
            Button("Retry Start", action: onRetry)
                .pulsarTextStyle(.buttonTitle)
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
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

    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 42
    private let heroIconDiameter: CGFloat = 64

    var body: some View {
        GeometryReader { proxy in
            let metrics = GymSessionChoiceLayoutMetrics(availableHeight: proxy.size.height)

            ScrollView {
                PulsarGlassEffectGroup(spacing: 8) {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: metrics.topSpacing)
                            .accessibilityHidden(true)

                        GymSessionIconGlass(
                            symbolName: "dumbbell.fill",
                            diameter: heroIconDiameter,
                            symbolSize: 24
                        )
                        .accessibilityHidden(true)

                        Text("Choose your\ngym session")
                            .font(.system(size: titleSize, weight: .regular, design: .serif))
                            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(-4)
                            .lineLimit(2)
                            .minimumScaleFactor(0.80)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, metrics.titleSpacing)

                        Text("Start from a saved plan, build a new routine,\nor jump into open gym tracking.")
                            .font(.subheadline)
                            .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                            .padding(.top, metrics.subtitleSpacing)

                        VStack(spacing: 10) {
                            GymSessionActionCard(
                                title: "My Routines",
                                subtitle: savedRoutineCount == 0 ? "Create and save your first lift plan" : "\(savedRoutineCount) saved \(savedRoutineCount == 1 ? "routine" : "routines") ready",
                                symbolName: "rectangle.stack.fill",
                                prominence: .secondary,
                                action: onShowSavedRoutines
                            )

                            GymSessionActionCard(
                                title: "Create Routine",
                                subtitle: "Choose exercises from the Pulsar catalog",
                                symbolName: "sparkles",
                                prominence: .primary,
                                action: onCreateRoutine
                            )

                            GymSessionActionCard(
                                title: "Start Free Workout",
                                subtitle: "Track a freestyle gym session",
                                symbolName: "timer",
                                prominence: .secondary,
                                action: onStartEmptyWorkout
                            )
                        }
                        .padding(.top, metrics.cardsSpacing)

                        Spacer(minLength: metrics.cancelSpacing)

                        GymSessionCancelButton(action: onCancel)

                        Color.clear
                            .frame(height: metrics.bottomSpacing)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    .padding(.horizontal, 28)
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}

private struct GymSessionActionCard: View {
    enum Prominence {
        case primary
        case secondary
    }

    var title: String
    var subtitle: String
    var symbolName: String
    var prominence: Prominence
    var action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let minimumHeight: CGFloat = 86
    private let iconDiameter: CGFloat = 50

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: prominence == .primary ? .medium : .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 13) {
                GymSessionIconGlass(
                    symbolName: symbolName,
                    diameter: iconDiameter,
                    symbolSize: 18,
                    interactive: false
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.84)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
                .layoutPriority(1)

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.regular))
                    .foregroundStyle(PulsarFitnessMonochromeDesign.tertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .modifier(GymSessionCardGlassModifier(cornerRadius: 28))
        }
        .buttonStyle(GymSessionPressButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
        .accessibilityAddTraits(.isButton)
    }
}

private struct GymSessionIconGlass: View {
    var symbolName: String
    var diameter: CGFloat
    var symbolSize: CGFloat
    var interactive = false

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: symbolSize, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
            .frame(width: diameter, height: diameter)
            .modifier(GymSessionCircleGlassModifier(interactive: interactive))
    }
}

private struct GymSessionCancelButton: View {
    var action: () -> Void

    private let diameter: CGFloat = 46

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "xmark")
                    .font(.system(.body, design: .default, weight: .medium))
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                    .frame(width: diameter, height: diameter)
                    .modifier(GymSessionCircleGlassModifier(interactive: true))

                Text("Cancel")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(GymSessionPressButtonStyle())
        .accessibilityLabel("Cancel")
        .accessibilityHint("Dismisses the gym session picker")
    }
}

private struct GymSessionChoiceLayoutMetrics {
    let topSpacing: CGFloat
    let titleSpacing: CGFloat
    let subtitleSpacing: CGFloat
    let cardsSpacing: CGFloat
    let cancelSpacing: CGFloat
    let bottomSpacing: CGFloat

    init(availableHeight: CGFloat) {
        let expansion = min(max((availableHeight - 700) / 160, 0), 1)
        topSpacing = 18 + (14 * expansion)
        titleSpacing = 14 + (6 * expansion)
        subtitleSpacing = 6 + (3 * expansion)
        cardsSpacing = 16 + (8 * expansion)
        cancelSpacing = 16 + (18 * expansion)
        bottomSpacing = 8 + (10 * expansion)
    }
}

private struct GymSessionCardGlassModifier: ViewModifier {
    var cornerRadius: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if reduceTransparency {
            content
                .background(Color.white, in: shape)
                .overlay {
                    shape.strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.045), radius: 14, y: 6)
        } else if #available(iOS 26.0, *) {
            content
                .background(Color.white.opacity(0.18), in: shape)
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.96), .black.opacity(0.055)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
                    )
                }
                .shadow(color: .black.opacity(0.032), radius: 14, y: 6)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.88), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.045), radius: 14, y: 6)
        }
    }
}

private struct GymSessionCircleGlassModifier: ViewModifier {
    var interactive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color.white, in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.035), radius: 9, y: 4)
        } else if #available(iOS 26.0, *) {
            content
                .background(Color.white.opacity(0.16), in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.90), lineWidth: 0.7)
                }
                .shadow(color: .black.opacity(0.025), radius: 9, y: 4)
                .glassEffect(.regular.interactive(interactive), in: .circle)
        } else {
            content
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.88), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.035), radius: 9, y: 4)
        }
    }
}

private struct GymSessionPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.992 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct GymGlassBackground: View {
    var body: some View {
        ZStack {
            PulsarFitnessMonochromeBackground()

            VStack(spacing: 20) {
                ForEach(0..<12, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(.black.opacity(index.isMultiple(of: 3) ? 0.026 : 0.012))
                        .frame(height: 1)
                        .offset(x: index.isMultiple(of: 2) ? -26 : 34)
                }
            }
            .rotationEffect(.degrees(-11))
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

#Preview("Gym Session Picker - Small", traits: .fixedLayout(width: 375, height: 667)) {
    GymRoutineChoiceView(
        savedRoutineCount: 4,
        onShowSavedRoutines: {},
        onCreateRoutine: {},
        onStartEmptyWorkout: {},
        onCancel: {}
    )
    .pulsarFitnessMonochromeAppearance()
}

#Preview("Gym Session Picker - Standard", traits: .fixedLayout(width: 393, height: 852)) {
    GymRoutineChoiceView(
        savedRoutineCount: 4,
        onShowSavedRoutines: {},
        onCreateRoutine: {},
        onStartEmptyWorkout: {},
        onCancel: {}
    )
    .pulsarFitnessMonochromeAppearance()
}

#Preview("Gym Session Picker - Pro Max", traits: .fixedLayout(width: 430, height: 932)) {
    GymRoutineChoiceView(
        savedRoutineCount: 4,
        onShowSavedRoutines: {},
        onCreateRoutine: {},
        onStartEmptyWorkout: {},
        onCancel: {}
    )
    .pulsarFitnessMonochromeAppearance()
}

#Preview("Gym Session Picker - Accessibility", traits: .fixedLayout(width: 390, height: 844)) {
    GymRoutineChoiceView(
        savedRoutineCount: 12,
        onShowSavedRoutines: {},
        onCreateRoutine: {},
        onStartEmptyWorkout: {},
        onCancel: {}
    )
    .environment(\.dynamicTypeSize, .accessibility2)
    .pulsarFitnessMonochromeAppearance()
}

#Preview {
    GymWorkoutLaunchFlowView()
        .environmentObject(PulsarActiveWorkoutManager())
        .environmentObject(WorkoutCompletionPresentationStore())
}
