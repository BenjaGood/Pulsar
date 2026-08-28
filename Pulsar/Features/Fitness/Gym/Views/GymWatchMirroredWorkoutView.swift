//
//  GymWatchMirroredWorkoutView.swift
//  Pulsar
//

import SwiftUI

enum GymWatchMirrorPresentationContent: Equatable {
    case active
    case failed
    case pending
    case finishedSummary
    case terminal
    case connecting
}

struct GymWatchMirroredWorkoutView: View {
    enum RoutineDisplayMode: Equatable {
        case openGym
        case routine
        case routinePending
    }

    @EnvironmentObject private var completionPresentationStore: WorkoutCompletionPresentationStore
    @ObservedObject var syncStore: PulsarWatchConnectivitySyncStore
    @ObservedObject var mirroredBridge: GymMirroredSessionBridge = .shared
    let expectedSessionID: UUID
    var profile: UserProfile = .empty
    var diagnosticHost: String = "unspecified"
    var crossDevicePhase: GymCrossDeviceStartPresentationPhase = .active
    var onMinimize: () -> Void
    var onSummaryDone: () -> Void
    var onRetry: (() -> Void)?
    var onUseIPhoneOnly: (() -> Void)?
    var onCancel: (() -> Void)?
    @State private var finishedSummary: PulsarGymWorkoutSummary?
    @State private var lastMirroredState: ActiveGymWorkoutState?
    @State private var isRequestingFinish = false
    @State private var finishDeliveryFailed = false
    @State private var didLogLiveUIPresentation = false
    @State private var lastRoutineResolutionLogKey = ""

    static func canPresentFinishedSummary(
        expectedSessionID: UUID,
        finishedSessionID: UUID,
        isSummaryEligible: Bool
    ) -> Bool {
        expectedSessionID == finishedSessionID && isSummaryEligible
    }

    /// Deterministic content selection used by UI and Phase 5 tests.
    /// Missing live state must never collapse into a finished/Done screen.
    /// A live mirrored HealthKit session can show chrome before WC gym sets arrive.
    static func presentationContent(
        hasMatchingLiveState: Bool,
        crossDevicePhase: GymCrossDeviceStartPresentationPhase,
        hasFinishedSummary: Bool,
        hasAttachedLiveMirror: Bool = false,
        hasConfirmedTerminal: Bool = false
    ) -> GymWatchMirrorPresentationContent {
        if hasConfirmedTerminal {
            return hasFinishedSummary ? .finishedSummary : .terminal
        }
        if hasMatchingLiveState || hasAttachedLiveMirror {
            return .active
        }
        if case .failed = crossDevicePhase {
            return .failed
        }
        switch crossDevicePhase {
        case .preparing, .launchingWatch, .waitingForWatchAcknowledgement,
             .watchSessionRunning, .mirroring, .recovering, .checkingWatch:
            return .pending
        default:
            break
        }
        if hasFinishedSummary {
            return .finishedSummary
        }
        return .connecting
    }

    static func overlayMirroredMetrics(
        _ state: ActiveGymWorkoutState,
        from snapshot: GymMirroredSessionSnapshot
    ) -> ActiveGymWorkoutState {
        var next = state
        if let heartRate = snapshot.currentHeartRate {
            next.currentHeartRate = heartRate
        }
        if let averageHeartRate = snapshot.averageHeartRate {
            next.averageHeartRate = averageHeartRate
        }
        if let maxHeartRate = snapshot.maxHeartRate {
            next.maxHeartRate = maxHeartRate
        }
        if let calories = snapshot.activeEnergyKilocalories {
            next.activeEnergyKilocalories = calories
        }
        if let startedAt = snapshot.startedAt {
            next.startedAt = startedAt
            next.elapsedSeconds = max(next.elapsedSeconds, Int(Date().timeIntervalSince(startedAt)))
        }
        return next
    }

    static func fallbackLiveState(
        sessionID: UUID,
        snapshot: GymMirroredSessionSnapshot,
        workoutKind: PulsarGymWorkoutKind = .routine
    ) -> ActiveGymWorkoutState {
        let startedAt = snapshot.startedAt ?? Date()
        let isFreeWorkout = workoutKind == .freeWorkout
        return ActiveGymWorkoutState(
            sessionId: sessionID,
            routineId: sessionID,
            routineName: isFreeWorkout ? PulsarGymWorkoutKind.freeWorkout.displayName : "Gym Workout",
            routineEmoji: "🏋️",
            workoutKind: workoutKind,
            startedFrom: .iPhoneRequestedWatchStart,
            startedAt: startedAt,
            elapsedSeconds: max(0, Int(Date().timeIntervalSince(startedAt))),
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: 0,
            totalSets: 0,
            completedSets: 0,
            currentHeartRate: snapshot.currentHeartRate,
            averageHeartRate: snapshot.averageHeartRate,
            maxHeartRate: snapshot.maxHeartRate,
            activeEnergyKilocalories: snapshot.activeEnergyKilocalories,
            restRemainingSeconds: nil,
            restTotalSeconds: nil,
            isHealthKitEnabled: true,
            healthKitStatusMessage: nil,
            isFinished: false,
            updatedAt: Date(),
            exercises: []
        )
    }

    static func routineDisplayMode(
        for state: ActiveGymWorkoutState?,
        expectedSessionID: UUID
    ) -> RoutineDisplayMode {
        guard let state, state.sessionId == expectedSessionID else {
            return .routinePending
        }
        if state.workoutKind == .freeWorkout {
            return .openGym
        }
        return state.exercises.isEmpty ? .routinePending : .routine
    }

    static func currentExerciseTitle(for state: ActiveGymWorkoutState) -> String {
        if let exerciseName = state.currentExercise?.exerciseName {
            return exerciseName
        }
        return state.workoutKind == .freeWorkout ? "Open Gym" : "Loading Routine…"
    }

    private var state: ActiveGymWorkoutState? {
        guard let state = syncStore.activeGymState,
              state.sessionId == expectedSessionID,
              syncStore.isRoutableActiveGymState(state) else { return nil }
        return state
    }

    private var displayState: ActiveGymWorkoutState? {
        if let state {
            return Self.overlayMirroredMetrics(state, from: mirroredBridge.snapshot)
        }
        if mirroredBridge.snapshot.hasAttachedLiveMirror {
            if let lastMirroredState, lastMirroredState.sessionId == expectedSessionID {
                return Self.overlayMirroredMetrics(lastMirroredState, from: mirroredBridge.snapshot)
            }
            return Self.fallbackLiveState(
                sessionID: expectedSessionID,
                snapshot: mirroredBridge.snapshot,
                workoutKind: resolvedFallbackWorkoutKind
            )
        }
        return nil
    }

    private var resolvedFallbackWorkoutKind: PulsarGymWorkoutKind {
        let placeholderKind = syncStore.activeGymState.flatMap { candidate in
            candidate.sessionId == expectedSessionID ? candidate.workoutKind : nil
        }
        let startTransaction = PulsarWorkoutStartCoordinator.shared.currentTransaction
        let matchingStartType: String?
        if let startTransaction,
           startTransaction.sessionID == expectedSessionID ||
            startTransaction.authoritativeSessionID == expectedSessionID {
            matchingStartType = startTransaction.workoutType
        } else {
            matchingStartType = nil
        }
        return GymFreeWorkoutTelemetry.resolvedFallbackWorkoutKind(
            placeholderKind: placeholderKind,
            startTransactionWorkoutType: matchingStartType
        )
    }

    var body: some View {
        let _ = PulsarPerformanceDiagnostics.event("workout.gymView.body")
        let _ = PulsarWorkoutStartupTrace.count("[RenderRate] GymLiveView")
        let _ = PulsarWorkoutStartupTrace.diagOnce(
            "workoutUI.init.\(diagnosticHost).\(expectedSessionID.uuidString)",
            "[WorkoutUI] workoutViewInit host=\(diagnosticHost) session=\(expectedSessionID.uuidString) \(PulsarWorkoutStartupTrace.threadTag())"
        )
        ZStack {
            Color.white
                .ignoresSafeArea()

            switch Self.presentationContent(
                hasMatchingLiveState: state != nil,
                crossDevicePhase: crossDevicePhase,
                hasFinishedSummary: finishedSummary != nil,
                hasAttachedLiveMirror: mirroredBridge.snapshot.hasAttachedLiveMirror,
                hasConfirmedTerminal: syncStore.hasConfirmedGymFinish(sessionID: expectedSessionID)
            ) {
            case .active:
                if let displayState {
                    activeWorkoutContent(displayState)
                } else {
                    missingLiveStateContent
                }
            case .failed:
                if case .failed(let error, let canRetry) = crossDevicePhase {
                    failureContent(error: error, canRetry: canRetry)
                } else {
                    missingLiveStateContent
                }
            case .pending:
                pendingCrossDeviceContent
            case .finishedSummary:
                if let finishedSummary {
                    GymWorkoutSummaryOverlay(summary: finishedSummary) {
                        onSummaryDone()
                    }
                } else {
                    terminalCompletionContent
                }
            case .terminal:
                terminalCompletionContent
            case .connecting:
                missingLiveStateContent
            }
        }
        .onAppear {
            PulsarWorkoutStartupTrace.diag(
                "[WorkoutUI] workoutViewOnAppear host=\(diagnosticHost) session=\(expectedSessionID.uuidString) \(PulsarWorkoutStartupTrace.threadTag())"
            )
            PulsarPerformanceDiagnostics.instanceMounted("workout.gymView")
            PulsarPerformanceDiagnostics.checkpoint("workout.gymView.appear")
            requestExpectedSessionState()
            logLiveUIPresentedIfNeeded()
            logRoutineResolution(state)
            if let activeGymState = syncStore.activeGymState,
               activeGymState.sessionId == expectedSessionID,
               activeGymState.isFinished {
                presentFinishedSummary(from: activeGymState)
                return
            }
            if syncStore.activeGymState == nil,
               let finishedState = syncStore.lastFinishedGymState,
               finishedState.sessionId == expectedSessionID {
                presentFinishedSummary(from: finishedState)
                return
            }
            guard let state else { return }
            completionPresentationStore.markEligibleForSummary(sessionID: state.sessionId)
            lastMirroredState = state
        }
        .onDisappear {
            PulsarWorkoutStartupTrace.diag(
                "[WorkoutUI] workoutViewOnDisappear host=\(diagnosticHost) session=\(expectedSessionID.uuidString) \(PulsarWorkoutStartupTrace.threadTag())"
            )
            PulsarPerformanceDiagnostics.instanceUnmounted("workout.gymView")
            PulsarPerformanceDiagnostics.checkpoint("workout.gymView.disappear")
        }
        .onChange(of: syncStore.activeGymState) { _, newState in
            PulsarPerformanceDiagnostics.event("workout.gymView.activeState")
            logRoutineResolution(newState)
            if let newState {
                guard newState.sessionId == expectedSessionID else {
                    logBlockedSummary(sessionID: newState.sessionId, reason: "activeStateSessionMismatch")
                    return
                }
                if newState.isFinished {
                    presentFinishedSummary(from: newState)
                } else if syncStore.isRoutableActiveGymState(newState) {
                    completionPresentationStore.markEligibleForSummary(sessionID: newState.sessionId)
                    lastMirroredState = newState
                }
            } else if finishedSummary == nil,
                      let finishedState = syncStore.lastFinishedGymState,
                      finishedState.sessionId == expectedSessionID {
                presentFinishedSummary(from: finishedState)
            } else if finishedSummary == nil,
                      let lastMirroredState,
                      lastMirroredState.isFinished {
                presentFinishedSummary(from: lastMirroredState)
            }
        }
        .onChange(of: mirroredBridge.snapshot.isLive) { _, _ in
            logLiveUIPresentedIfNeeded()
            logRoutineResolution(state)
        }
        .onChange(of: syncStore.lastConfirmedGymFinish) { _, confirmation in
            guard confirmation?.sessionID == expectedSessionID else { return }
            finishDeliveryFailed = false
            guard finishedSummary == nil else { return }
            if let finishedState = syncStore.lastFinishedGymState,
               finishedState.sessionId == expectedSessionID {
                presentFinishedSummary(from: finishedState)
            } else if var lastMirroredState,
                      lastMirroredState.sessionId == expectedSessionID {
                lastMirroredState.isFinished = true
                lastMirroredState.updatedAt = confirmation?.confirmedAt ?? Date()
                presentFinishedSummary(from: lastMirroredState)
            }
        }
        .alert("Couldn’t Send Finish Command", isPresented: $finishDeliveryFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Open Pulsar on Apple Watch and try ending the workout again.")
        }
        .preferredColorScheme(.light)
    }

    private func logLiveUIPresentedIfNeeded() {
        guard !didLogLiveUIPresentation else { return }
        let content = Self.presentationContent(
            hasMatchingLiveState: state != nil,
            crossDevicePhase: crossDevicePhase,
            hasFinishedSummary: finishedSummary != nil,
            hasAttachedLiveMirror: mirroredBridge.snapshot.hasAttachedLiveMirror,
            hasConfirmedTerminal: syncStore.hasConfirmedGymFinish(sessionID: expectedSessionID)
        )
        guard content == .active else { return }
        didLogLiveUIPresentation = true
        PulsarWorkoutStartupTrace.phone("live UI presented gym session=\(expectedSessionID.uuidString)")
    }

    private func logRoutineResolution(_ candidate: ActiveGymWorkoutState?) {
        let matchingState = candidate.flatMap { $0.sessionId == expectedSessionID ? $0 : nil }
        let displayMode = Self.routineDisplayMode(for: candidate, expectedSessionID: expectedSessionID)
        let resolvedMode: String
        let reason: String
        switch displayMode {
        case .openGym:
            resolvedMode = "openGym"
            reason = "explicitFreeWorkout"
        case .routine:
            resolvedMode = "routine"
            reason = "matchingCanonicalState"
        case .routinePending:
            resolvedMode = "routinePending"
            if let matchingState {
                reason = matchingState.isPrelaunchPlaceholder
                    ? "launchPlaceholder"
                    : "missingRoutineExercises"
            } else {
                reason = candidate == nil ? "missingActiveGymState" : "workoutIDMismatch"
            }
        }
        let requestID = matchingState?.requestID ?? candidate?.requestID
        let routineID = matchingState?.routineId ?? candidate?.routineId
        let key = [
            resolvedMode,
            reason,
            expectedSessionID.uuidString,
            requestID?.uuidString ?? "none",
            routineID?.uuidString ?? "none",
            String(matchingState?.exercises.count ?? 0)
        ].joined(separator: "|")
        guard key != lastRoutineResolutionLogKey else { return }
        lastRoutineResolutionLogKey = key
        PulsarWorkoutStartupTrace.lifecycle(
            "[PulsarWorkoutRoutine] resolvedMode=\(resolvedMode) reason=\(reason) workoutID=\(expectedSessionID.uuidString) requestID=\(requestID?.uuidString ?? "none") routineID=\(routineID?.uuidString ?? "none") snapshotAvailable=\((matchingState?.exercises.isEmpty == false)) activeGymStateAvailable=\(candidate != nil)"
        )
    }

    @ViewBuilder
    private func activeWorkoutContent(_ state: ActiveGymWorkoutState) -> some View {
        if GymFreeWorkoutTelemetry.usesDedicatedPresentation(state) {
            GymFreeWorkoutScreen(
                state: state,
                zoneProfile: PulsarHeartRateZoneProfile(profile: profile),
                isRequestingFinish: isRequestingFinish,
                onOpenAudio: openNowPlaying,
                onMinimize: onMinimize,
                onFinish: { requestFinish(for: state) }
            )
        } else {
            GymMirroredWorkoutScreen(
                syncStore: syncStore,
                state: state,
                expectedSessionID: expectedSessionID,
                statusMessage: crossDevicePhase == .active
                    ? "Mirroring live workout to iPhone…"
                    : crossDevicePhase.statusMessage,
                isRequestingFinish: isRequestingFinish,
                onOpenAudio: openNowPlaying,
                onMinimize: onMinimize,
                onCompleteSet: { completeCurrentSet(in: state) },
                onUpdateSet: { reps, weight in
                    guard let exercise = state.currentExercise,
                          let set = state.currentSet else { return }
                    updateCurrentSetValues(
                        state: state,
                        exercise: exercise,
                        set: set,
                        reps: reps,
                        weight: weight
                    )
                },
                onSkipRest: {
                    syncStore.sendGymAction(.skipRestTimer(sessionId: state.sessionId))
                },
                onFinish: { requestFinish(for: state) }
            )
        }
    }

    private var pendingCrossDeviceContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(PulsarFitnessMonochromeDesign.primaryText)
            Text(crossDevicePhase.statusMessage)
                .pulsarTextStyle(.sectionTitle)
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
                .multilineTextAlignment(.center)
            if let onCancel {
                Button("Cancel", action: onCancel)
                    .pulsarTextStyle(.buttonTitle)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
            }
        }
        .padding(24)
    }

    private func failureContent(error: GymCrossDeviceStartError, canRetry: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "applewatch.slash")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
            Text(error.userFacingMessage)
                .pulsarTextStyle(.screenSubtitle)
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                .multilineTextAlignment(.center)
            if canRetry, let onRetry {
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
            if let onUseIPhoneOnly {
                Button("Use iPhone Only", action: onUseIPhoneOnly)
                    .buttonStyle(.bordered)
            }
            if let onCancel {
                Button("Cancel", action: onCancel)
                    .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
            }
        }
        .padding(24)
    }

    private var missingLiveStateContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(PulsarFitnessMonochromeDesign.primaryText)
            Text("Connecting to Apple Watch...")
                .pulsarTextStyle(.sectionHeader)
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
            Text("Waiting for the current workout session. This can take a moment.")
                .pulsarTextStyle(.screenSubtitle)
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                .multilineTextAlignment(.center)
            Button("Retry Connection", action: requestExpectedSessionState)
                .buttonStyle(.borderedProminent)
            Button("Minimize", action: onMinimize)
                .buttonStyle(.bordered)
        }
        .padding(24)
    }

    private var terminalCompletionContent: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(PulsarFitnessMonochromeDesign.primaryText)
            Text("Finishing workout...")
                .pulsarTextStyle(.sectionHeader)
                .foregroundStyle(PulsarFitnessMonochromeDesign.primaryText)
            Text("Apple Watch finished recording. Saving your workout now.")
                .pulsarTextStyle(.screenSubtitle)
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    static func progressFraction(for state: ActiveGymWorkoutState) -> Double {
        guard state.totalSets > 0 else {
            return state.workoutKind == .freeWorkout ? 1 : 0
        }
        return min(max(Double(state.completedSets) / Double(state.totalSets), 0), 1)
    }

    private func openNowPlaying() {
        let urls = ["music://nowplaying", "music://"].compactMap(URL.init(string:))
        guard let url = urls.first else { return }
        UIApplication.shared.open(url)
    }

    private func requestExpectedSessionState() {
        syncStore.sendGymAction(.requestState(sessionId: expectedSessionID))
    }

    private func presentFinishedSummary(from state: ActiveGymWorkoutState) {
        PulsarWorkoutLifecycleLogger.log(
            .summaryPresentationAttempted,
            sessionID: state.sessionId,
            source: "GymWatchMirroredWorkoutView",
            detail: "expectedSessionID=\(expectedSessionID.uuidString)"
        )
        let isSummaryEligible = completionPresentationStore.isEligibleForSummary(sessionID: state.sessionId)
        guard Self.canPresentFinishedSummary(
            expectedSessionID: expectedSessionID,
            finishedSessionID: state.sessionId,
            isSummaryEligible: isSummaryEligible
        ) else {
            let reason = state.sessionId == expectedSessionID
                ? "sessionNeverObservedActive"
                : "finishedSessionMismatch"
            logBlockedSummary(sessionID: state.sessionId, reason: reason)
            return
        }
        guard completionPresentationStore.shouldAutoPresent(sessionID: state.sessionId) else {
            finishedSummary = nil
            isRequestingFinish = false
            return
        }
        var finishedState = state
        let endedAt = state.isFinished ? state.updatedAt : Date.now
        finishedState.isFinished = true
        finishedState.updatedAt = endedAt
        finishedState.elapsedSeconds = max(state.elapsedSeconds, Int(endedAt.timeIntervalSince(state.startedAt)))
        lastMirroredState = finishedState
        isRequestingFinish = false
        finishedSummary = PulsarGymWorkoutSummary(activeGymState: finishedState)
    }

    private func logBlockedSummary(sessionID: UUID, reason: String) {
        PulsarWorkoutLifecycleLogger.log(
            .summaryPresentationBlocked,
            sessionID: sessionID,
            source: "GymWatchMirroredWorkoutView",
            detail: "reason=\(reason) expectedSessionID=\(expectedSessionID.uuidString)"
        )
    }

    @discardableResult
    private func requestFinish(for state: ActiveGymWorkoutState) -> Bool {
        guard !isRequestingFinish else { return false }
        isRequestingFinish = true
        PulsarWorkoutStartupTrace.diag(
            "[WorkoutUI] finishTapped workoutID=\(state.sessionId.uuidString) requestID=\(state.requestID?.uuidString ?? "none") host=\(diagnosticHost) \(PulsarWorkoutStartupTrace.threadTag())"
        )
        PulsarWorkoutLifecycleLogger.log(
            .wcSend,
            sessionID: state.sessionId,
            workoutType: state.workoutKind?.rawValue,
            device: "iPhone",
            messageType: "finishWorkout"
        )
        PulsarWorkoutLifecycleLogger.log(
            .finishRequested,
            sessionID: state.sessionId,
            workoutType: state.workoutKind?.rawValue,
            device: "iPhone",
            previousState: "active",
            nextState: "finishing"
        )
        let acceptedForDelivery = syncStore.sendGymAction(.finishWorkout(sessionId: state.sessionId))
        guard acceptedForDelivery else {
            isRequestingFinish = false
            if !syncStore.hasConfirmedGymFinish(sessionID: state.sessionId) {
                finishDeliveryFailed = true
            }
            return false
        }
        _ = PulsarWorkoutStartCoordinator.shared.markSessionEnding(
            sessionID: state.sessionId,
            reason: "GymWatchMirroredWorkoutView"
        )
        return true
    }

    private func completeCurrentSet(in state: ActiveGymWorkoutState) {
        guard let exercise = state.currentExercise,
              let set = state.currentSet,
              !set.isCompleted else { return }
        syncStore.sendGymAction(
            .completeSet(
                sessionId: state.sessionId,
                exerciseId: exercise.id,
                setId: set.id,
                reps: set.completedReps ?? set.targetReps,
                weight: set.completedWeight ?? set.targetWeight
            )
        )
    }

    private func updateCurrentSetValues(
        state: ActiveGymWorkoutState,
        exercise: ActiveGymWorkoutExerciseState,
        set: ActiveGymWorkoutSetState,
        reps: Int? = nil,
        weight: Double? = nil
    ) {
        var nextState = state
        if let exerciseIndex = nextState.exercises.firstIndex(where: { $0.id == exercise.id }),
           let setIndex = nextState.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == set.id }) {
            if let reps {
                let nextReps = max(1, reps)
                nextState.exercises[exerciseIndex].sets[setIndex].targetReps = nextReps
                if nextState.exercises[exerciseIndex].sets[setIndex].isCompleted {
                    nextState.exercises[exerciseIndex].sets[setIndex].completedReps = nextReps
                }
            }
            if let weight {
                let nextWeight = max(0, weight)
                nextState.exercises[exerciseIndex].sets[setIndex].targetWeight = nextWeight
                if nextState.exercises[exerciseIndex].sets[setIndex].isCompleted {
                    nextState.exercises[exerciseIndex].sets[setIndex].completedWeight = nextWeight
                }
            }
            nextState.updatedAt = Date()
            syncStore.storeActiveGymState(nextState, broadcast: false, reason: "gymMirrorSetAdjusted")
        }

        syncStore.sendGymAction(
            .updateSetValues(
                sessionId: state.sessionId,
                exerciseId: exercise.id,
                setId: set.id,
                reps: reps,
                weight: weight
            )
        )
    }
}

#Preview {
    GymWatchMirroredWorkoutView(
        syncStore: .shared,
        expectedSessionID: UUID(),
        onMinimize: {},
        onSummaryDone: {}
    )
    .environmentObject(WorkoutCompletionPresentationStore())
}
