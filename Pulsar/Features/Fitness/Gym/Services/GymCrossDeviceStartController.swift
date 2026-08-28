//
//  GymCrossDeviceStartController.swift
//  Pulsar
//

import Combine
import HealthKit
import SwiftUI

enum GymCrossDeviceStartPresentationPhase: Equatable {
    case idle
    case preparing
    case launchingWatch
    case waitingForWatchAcknowledgement
    case watchSessionRunning
    case mirroring
    case recovering
    case checkingWatch
    case active
    case failed(GymCrossDeviceStartError, canRetry: Bool)
    case cancelled

    var statusMessage: String {
        switch self {
        case .idle, .cancelled:
            ""
        case .preparing:
            "Preparing gym workout..."
        case .launchingWatch:
            "Opening Pulsar on Apple Watch..."
        case .waitingForWatchAcknowledgement:
            "Waiting for Apple Watch to confirm recording..."
        case .watchSessionRunning:
            "Apple Watch is recording."
        case .mirroring:
            "Mirroring live workout to iPhone..."
        case .recovering:
            "Reconnecting to Apple Watch..."
        case .checkingWatch:
            "Checking Apple Watch..."
        case .active:
            "Apple Watch gym workout active"
        case .failed(let error, _):
            error.userFacingMessage
        }
    }
}

@MainActor
final class GymCrossDeviceStartController: ObservableObject {
    @Published private(set) var phase: GymCrossDeviceStartPresentationPhase = .idle
    @Published private(set) var currentRequest: GymWorkoutStartRequest?
    @Published private(set) var pendingRoutine: PulsarRoutine?
    @Published private(set) var lastError: GymCrossDeviceStartError?

    private let healthStore = HKHealthStore()
    private let syncStore: PulsarWatchConnectivitySyncStore
    private var acknowledgementWaitTask: Task<Void, Never>?
    private var lastAckMirroringState: GymWorkoutMirroringState?
    private var syncCancellables = Set<AnyCancellable>()
    private weak var routineStore: PulsarRoutineStore?
    private var retainedStartContext: ActiveGymWorkoutState?
    private var didAttemptRemoteQuery = false
    private var didAttemptRecoveryLaunch = false

    var hasLiveMirroredSession: Bool {
        GymMirroredSessionBridge.shared.snapshot.hasAttachedLiveMirror
    }

    init(syncStore: PulsarWatchConnectivitySyncStore? = nil) {
        self.syncStore = syncStore ?? .shared
        self.syncStore.registerGymStartAcknowledgementHandler { [weak self] acknowledgement, reason in
            self?.handleWatchAcknowledgement(acknowledgement, source: reason)
        }
        self.syncStore.$activeGymState
            .compactMap { $0 }
            .sink { [weak self] state in
                self?.markLiveFromWatchStateIfEligible(state)
            }
            .store(in: &syncCancellables)
        GymMirroredSessionBridge.shared.bind(controller: self)
    }

    deinit {
        acknowledgementWaitTask?.cancel()
    }

    func start(
        routine: PulsarRoutine,
        workoutKind: PulsarGymWorkoutKind,
        availability: PulsarWatchRecorderAvailabilitySnapshot,
        routineStore: PulsarRoutineStore
    ) async throws {
        guard PulsarGymCrossDeviceStartFeature.isEnabled else {
            throw GymCrossDeviceStartError.unknown
        }

        guard availability.canAttemptWatchAppLaunch else {
            throw mapFallbackReason(availability.fallbackReason ?? .notReachable)
        }

        pendingRoutine = routine
        self.routineStore = routineStore
        lastError = nil
        didAttemptRemoteQuery = false
        didAttemptRecoveryLaunch = false

        let configuration = PulsarWorkoutCatalog.gymWorkoutConfiguration
        let coordinator = PulsarWorkoutStartCoordinator.shared
        if coordinator.phase.blocksNewWatchPrimaryIdentity,
           let transaction = coordinator.currentTransaction {
            PulsarWorkoutStartupTrace.phone(
                "Start tapped blocked new identity existing \(PulsarWorkoutStartupTrace.identity(workoutID: transaction.sessionID, requestID: transaction.requestID)) phase=\(coordinator.phase.name)"
            )
            let reused = GymWorkoutStartRequest(
                requestID: transaction.requestID ?? UUID(),
                candidateSessionID: transaction.sessionID,
                idempotencyKey: transaction.idempotencyKey,
                routineID: routine.id,
                routineRevision: routineStore.routinesRevision,
                workoutKind: workoutKind,
                activityTypeRawValue: configuration.activityType.rawValue,
                locationTypeRawValue: configuration.locationType.rawValue
            )
            currentRequest = reused
            phase = .checkingWatch
            await queryWatchAndReconcile(for: reused, allowLaunchRetry: true)
            if isVerifiedForPresentation || phase == .active {
                return
            }
            if case .failed = coordinator.phase {
                syncPhaseFromLifecycleAuthority()
                throw lastError ?? GymCrossDeviceStartError.existingWorkoutConflict
            }
            return
        }

        if let existing = liveWatchOwnedGymState() {
            PulsarWorkoutStartupTrace.phone(
                "Start tapped adopting existing Watch workout \(PulsarWorkoutStartupTrace.identity(workoutID: existing.sessionId, requestID: nil))"
            )
            await adoptLiveWatchGymState(existing, routine: routine, workoutKind: workoutKind, routineStore: routineStore)
            return
        }

        phase = .preparing
        let request = GymWorkoutStartRequest(
            routineID: routine.id,
            routineRevision: routineStore.routinesRevision,
            workoutKind: workoutKind,
            activityTypeRawValue: configuration.activityType.rawValue,
            locationTypeRawValue: configuration.locationType.rawValue
        )
        currentRequest = request
        PulsarWorkoutStartupTrace.phone(
            "Start tapped gym \(PulsarWorkoutStartupTrace.identity(workoutID: request.candidateSessionID, requestID: request.requestID))"
        )

        switch PulsarWorkoutStartCoordinator.shared.beginCrossDeviceGymStart(
            request: request,
            source: "GymCrossDeviceStartController"
        ) {
        case .granted:
            syncStore.prepareForNewGymStart(
                sessionID: request.candidateSessionID,
                reason: "GymCrossDeviceStartController"
            )
            break
        case .duplicateStart:
            phase = .waitingForWatchAcknowledgement
            return
        case .alreadyActive:
            phase = .active
            return
        case .rejectedConflict:
            phase = .failed(.existingWorkoutConflict, canRetry: false)
            throw GymCrossDeviceStartError.existingWorkoutConflict
        }

        PulsarWorkoutMirroringCoordinator.shared.setPendingGymMirroring(
            requestID: request.requestID,
            sessionID: request.candidateSessionID
        )

        let prelaunchState = makePrelaunchState(routine: routine, request: request, availability: availability)
        retainedStartContext = prelaunchState
        syncStore.storeActiveGymState(
            prelaunchState,
            broadcast: true,
            reason: "gymCrossDeviceStart.prelaunchState"
        )

        _ = syncStore.sendGymStartPrelaunchHint(request, reason: "gymCrossDeviceStart")
        if let snapshot = routineStore.makeImmutableSnapshot(for: routine, request: request) {
            syncStore.transferGymRoutineSnapshot(snapshot, reason: "gymCrossDeviceStart")
        }
        PulsarWorkoutLifecycleLogger.log(
            .watchLaunchDecision,
            sessionID: request.candidateSessionID,
            requestID: request.requestID,
            workoutType: workoutKind.rawValue,
            source: "GymCrossDeviceStartController",
            detail: "attemptWatchAppLaunch",
            watchConnectivityState: availability.derivedReachabilityDescription,
            transport: availability.isWatchInteractivelyReachable ? "healthKit+realtimeWC" : "healthKit+durableWC"
        )

        phase = .launchingWatch
        _ = PulsarWorkoutStartCoordinator.shared.markWatchLaunchSubmitted(
            requestID: request.requestID,
            source: "GymCrossDeviceStartController"
        )

        PulsarWorkoutLifecycleLogger.log(
            .workoutWatchSyncRequested,
            sessionID: request.candidateSessionID,
            requestID: request.requestID,
            workoutType: workoutKind.rawValue,
            source: "GymCrossDeviceStartController",
            watchConnectivityState: availability.derivedReachabilityDescription
        )

        let watchAppLaunchStartedAt = Date()
        do {
            PulsarWorkoutStartupTrace.phone(
                "startWatchApp begin gym \(PulsarWorkoutStartupTrace.identity(workoutID: request.candidateSessionID, requestID: request.requestID))"
            )
            PulsarWorkoutStartupTrace.diag(
                "[StartWatchApp] begin kind=gym \(PulsarWorkoutStartupTrace.identity(workoutID: request.candidateSessionID, requestID: request.requestID)) \(PulsarWorkoutStartupTrace.threadTag())"
            )
            try await healthStore.startWatchApp(toHandle: configuration)
            PulsarWorkoutStartupTrace.phone(
                "startWatchApp completion gym means=HealthKitAcceptedLaunchRequest not=WatchPrimaryCreated \(PulsarWorkoutStartupTrace.identity(workoutID: request.candidateSessionID, requestID: request.requestID))"
            )
            PulsarWorkoutStartupTrace.diag(
                "[StartWatchApp] completion kind=gym elapsedMs=\(PulsarWorkoutStartupTrace.elapsedMs(since: watchAppLaunchStartedAt)) \(PulsarWorkoutStartupTrace.identity(workoutID: request.candidateSessionID, requestID: request.requestID)) \(PulsarWorkoutStartupTrace.threadTag())"
            )
        } catch {
            PulsarWorkoutStartupTrace.diag(
                "[StartWatchApp] completion kind=gym elapsedMs=\(PulsarWorkoutStartupTrace.elapsedMs(since: watchAppLaunchStartedAt)) error=\(error.localizedDescription) \(PulsarWorkoutStartupTrace.identity(workoutID: request.candidateSessionID, requestID: request.requestID)) \(PulsarWorkoutStartupTrace.threadTag())"
            )
            _ = PulsarWorkoutStartCoordinator.shared.markWatchLaunchFailed(
                requestID: request.requestID,
                source: "GymCrossDeviceStartController",
                error: error.localizedDescription
            )
            PulsarWorkoutMirroringCoordinator.shared.clearPendingGymMirroring(requestID: request.requestID)
            abandonUnstartedCompanionGym(request: request, reason: "iPhoneGymWatchLaunchFailed")
            phase = .failed(.watchLaunchFailed, canRetry: true)
            lastError = .watchLaunchFailed
            throw error
        }

        _ = PulsarWorkoutStartCoordinator.shared.markWaitingForWatchAcknowledgement(
            requestID: request.requestID,
            source: "GymCrossDeviceStartController"
        )
        if PulsarWorkoutStartCoordinator.shared.isCrossDeviceGymStartVerified {
            if hasLiveMirroredSession {
                markMirroringVerified(for: request)
            } else {
                phase = .watchSessionRunning
            }
        } else {
            phase = .waitingForWatchAcknowledgement
            beginAcknowledgementWait(for: request)
        }
    }

    func retry(routineStore: PulsarRoutineStore) async throws {
        guard let routine = pendingRoutine else {
            throw GymCrossDeviceStartError.unknown
        }
        let workoutKind = PulsarGymWorkoutKind.inferred(
            routineName: routine.name,
            exerciseCount: routine.exercises.count
        )
        let availability = await syncStore.waitForWatchAppLaunchAvailability(
            reason: "GymCrossDeviceStartRetry.\(workoutKind.rawValue)"
        )
        try await start(
            routine: routine,
            workoutKind: workoutKind,
            availability: availability,
            routineStore: routineStore
        )
    }

    func chooseIPhoneOnlyFallback() {
        if let request = currentRequest {
            syncStore.sendGymAction(.finishWorkout(sessionId: request.candidateSessionID))
            PulsarWorkoutStartCoordinator.shared.markIPhoneFallbackChosen(
                requestID: request.requestID,
                source: "GymCrossDeviceStartController"
            )
            PulsarWorkoutMirroringCoordinator.shared.clearPendingGymMirroring(requestID: request.requestID)
            abandonUnstartedCompanionGym(request: request, reason: "iPhoneFallbackChosen")
        }
        acknowledgementWaitTask?.cancel()
        phase = .cancelled
    }

    func cancel() {
        if let request = currentRequest {
            syncStore.sendGymAction(.finishWorkout(sessionId: request.candidateSessionID))
            PulsarWorkoutStartCoordinator.shared.cancelCurrentStart(
                requestID: request.requestID,
                source: "GymCrossDeviceStartController"
            )
            PulsarWorkoutMirroringCoordinator.shared.clearPendingGymMirroring(requestID: request.requestID)
            abandonUnstartedCompanionGym(request: request, reason: "gymStartCancelled")
        }
        acknowledgementWaitTask?.cancel()
        phase = .cancelled
        currentRequest = nil
    }

    func attachMirroredSession(_ session: HKWorkoutSession) {
        PulsarWorkoutStartupTrace.phone(
            "gym controller attached object=\(PulsarWorkoutMirroringCoordinator.objectToken(session))"
        )
        guard let request = currentRequest else { return }
        markMirroringVerified(for: request)
        syncPhaseFromLifecycleAuthority()
        if PulsarWorkoutStartCoordinator.shared.isWatchStartVerified(
            requestID: request.requestID,
            candidateSessionID: request.candidateSessionID
        ) {
            acknowledgementWaitTask?.cancel()
            PulsarWorkoutLifecycleLogger.log(
                .watchStartVerified,
                sessionID: request.candidateSessionID,
                requestID: request.requestID,
                workoutType: request.workoutKind.rawValue,
                source: "GymCrossDeviceStartController",
                detail: "mirror"
            )
        }
        markLiveFromMirroredSessionIfEligible()
    }

    func markVerifiedActive() {
        guard let request = currentRequest else { return }
        let coordinator = PulsarWorkoutStartCoordinator.shared
        guard !coordinator.phase.isTerminal else {
            PulsarWorkoutStartupTrace.lifecycle(
                "[WorkoutReconcile] incomingWorkoutID=\(request.candidateSessionID.uuidString) canonicalWorkoutID=\(coordinator.currentTransaction?.sessionID.uuidString ?? "none") incomingRequestID=\(request.requestID.uuidString) canonicalRequestID=\(coordinator.currentTransaction?.requestID?.uuidString ?? "none") source=markVerifiedActive decision=rejectTerminal reason=phase.\(coordinator.phase.name)"
            )
            return
        }
        if phase == .active,
           coordinator.phase.name == "active",
           PulsarActiveWorkoutManager.shared.activeWorkoutSessionID == request.candidateSessionID {
            return
        }
        promoteCanonicalStartContextToLive(request: request)
        PulsarWorkoutStartupTrace.phone(
            "active runtime mirror ownedBy=GymMirroredSessionBridge session=\(request.candidateSessionID.uuidString)"
        )
        _ = PulsarActiveWorkoutManager.shared.reconcileVerifiedWatchGymWorkout(
            sessionID: request.candidateSessionID,
            phase: "active",
            reason: "gymAuthoritativeMirrorAttached"
        )
        PulsarWorkoutStartupTrace.phone("markActivated session=\(request.candidateSessionID.uuidString)")
        PulsarWorkoutStartCoordinator.shared.markActivated(
            sessionID: request.candidateSessionID,
            workoutType: request.workoutKind.rawValue,
            source: "GymCrossDeviceStartVerified"
        )
        phase = .active
    }

    func markLiveFromMirroredSessionIfEligible() {
        guard hasLiveMirroredSession, currentRequest != nil else { return }
        markVerifiedActive()
    }

    /// Keep the logical workout and presentation alive while HealthKit creates
    /// and delivers a replacement mirrored-session object.
    func authoritativeMirrorDidDisconnect() {
        guard currentRequest != nil else { return }
        phase = .recovering
    }

    var isVerifiedForPresentation: Bool {
        guard let request = currentRequest else { return false }
        return PulsarWorkoutStartCoordinator.shared.isWatchStartVerified(
            requestID: request.requestID,
            candidateSessionID: request.candidateSessionID
        )
    }

    var lifecyclePresentationPolicy: PulsarWorkoutPresentationPolicy {
        PulsarWorkoutStartCoordinator.shared.presentationPolicy
    }

    /// Maps coordinator lifecycle into local presentation phase when the
    /// controller still owns a matching in-flight request.
    func syncPhaseFromLifecycleAuthority() {
        let coordinator = PulsarWorkoutStartCoordinator.shared
        guard let request = currentRequest,
              let transaction = coordinator.currentTransaction,
              transaction.requestID == request.requestID ||
                transaction.sessionID == request.candidateSessionID else {
            return
        }

        switch coordinator.phase {
        case .preparing, .startRequested:
            phase = .preparing
        case .launchingWatch:
            phase = .launchingWatch
        case .waitingForWatchAcknowledgement, .watchSessionPreparing:
            phase = .waitingForWatchAcknowledgement
        case .watchSessionRunning:
            phase = .watchSessionRunning
        case .mirroring:
            phase = .mirroring
        case .recovering:
            phase = .recovering
        case .reconcilingRemote:
            phase = .checkingWatch
        case .active, .ending:
            phase = .active
        case .failed(_, let error):
            let mapped = GymCrossDeviceStartError(rawValue: error) ?? .unknown
            phase = .failed(mapped, canRetry: mapped != .existingWorkoutConflict)
            lastError = mapped
        case .cancelled:
            phase = .cancelled
        case .completed, .idle:
            break
        }
    }

    private func beginAcknowledgementWait(for request: GymWorkoutStartRequest, isRecoveryWait: Bool = false) {
        acknowledgementWaitTask?.cancel()
        PulsarWorkoutStartupTrace.phone("WorkoutTimeoutTask cancelled gym request=\(request.requestID.uuidString)")
        acknowledgementWaitTask = Task { [weak self] in
            PulsarWorkoutStartupTrace.phone("WorkoutTimeoutTask created gym recovery=\(isRecoveryWait) request=\(request.requestID.uuidString)")
            let duration: TimeInterval = isRecoveryWait ? 6 : PulsarWorkoutStartCoordinator.watchAcknowledgementTimeout
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            await self?.handleVerificationWaitExpiry(for: request)
        }
    }

    private func handleVerificationWaitExpiry(for request: GymWorkoutStartRequest) async {
        guard currentRequest?.requestID == request.requestID,
              !isVerifiedForPresentation else { return }

        if !didAttemptRemoteQuery {
            didAttemptRemoteQuery = true
            phase = .checkingWatch
            _ = PulsarWorkoutStartCoordinator.shared.markWatchStartRecovering(
                requestID: request.requestID,
                source: "GymCrossDeviceStartController.query"
            )
            await queryWatchAndReconcile(for: request, allowLaunchRetry: true)
            if isVerifiedForPresentation || phase == .active { return }
        }

        if !didAttemptRecoveryLaunch,
           liveWatchOwnedGymState() == nil {
            didAttemptRecoveryLaunch = true
            phase = .recovering
            _ = PulsarWorkoutStartCoordinator.shared.markWatchStartRecovering(
                requestID: request.requestID,
                source: "GymCrossDeviceStartController.recovery"
            )
            if let routineStore, let routine = pendingRoutine,
               let snapshot = routineStore.makeImmutableSnapshot(for: routine, request: request) {
                syncStore.transferGymRoutineSnapshot(snapshot, reason: "gymCrossDeviceStart.recovery")
            } else {
                _ = syncStore.sendGymStartPrelaunchHint(request, reason: "gymCrossDeviceStart.recovery.snapshotFallback")
            }
            do {
                let startedAt = Date()
                PulsarWorkoutStartupTrace.phone(
                    "startWatchApp begin gym recovery \(PulsarWorkoutStartupTrace.identity(workoutID: request.candidateSessionID, requestID: request.requestID))"
                )
                PulsarWorkoutStartupTrace.diag(
                    "[StartWatchApp] begin kind=gym.recovery \(PulsarWorkoutStartupTrace.identity(workoutID: request.candidateSessionID, requestID: request.requestID)) \(PulsarWorkoutStartupTrace.threadTag())"
                )
                try await healthStore.startWatchApp(toHandle: PulsarWorkoutCatalog.gymWorkoutConfiguration)
                PulsarWorkoutStartupTrace.phone(
                    "startWatchApp completion gym recovery means=HealthKitAcceptedLaunchRequest not=WatchPrimaryCreated \(PulsarWorkoutStartupTrace.identity(workoutID: request.candidateSessionID, requestID: request.requestID))"
                )
                PulsarWorkoutStartupTrace.diag(
                    "[StartWatchApp] completion kind=gym.recovery elapsedMs=\(PulsarWorkoutStartupTrace.elapsedMs(since: startedAt)) \(PulsarWorkoutStartupTrace.identity(workoutID: request.candidateSessionID, requestID: request.requestID)) \(PulsarWorkoutStartupTrace.threadTag())"
                )
            } catch {
                PulsarWorkoutLifecycleLogger.log(
                    .watchLaunchRequestFailed,
                    sessionID: request.candidateSessionID,
                    requestID: request.requestID,
                    workoutType: request.workoutKind.rawValue,
                    source: "GymCrossDeviceStartController.recovery",
                    error: error.localizedDescription,
                    retryAttempt: 1
                )
            }
            guard !isVerifiedForPresentation else { return }
            beginAcknowledgementWait(for: request, isRecoveryWait: true)
            return
        }

        _ = PulsarWorkoutStartCoordinator.shared.markWatchAcknowledgementTimedOut(
            requestID: request.requestID,
            source: "GymCrossDeviceStartController"
        )
        phase = .checkingWatch
        lastError = .watchAcknowledgementTimedOut
        PulsarWorkoutStartupTrace.phone(
            "timeout remote state unknown \(PulsarWorkoutStartupTrace.identity(workoutID: request.candidateSessionID, requestID: request.requestID))"
        )
        await queryWatchAndReconcile(for: request, allowLaunchRetry: false)
    }

    func handleWatchAcknowledgement(_ acknowledgement: GymWorkoutStartAcknowledgement, source: String) {
        if let request = currentRequest, request.requestID != acknowledgement.requestID {
            PulsarWorkoutStartupTrace.remoteConflict(
                expectedWorkoutID: request.candidateSessionID,
                expectedRequestID: request.requestID,
                watchWorkoutID: acknowledgement.authoritativeSessionID,
                watchRequestID: acknowledgement.requestID,
                watchHKState: acknowledgement.sessionState.rawValue,
                action: "reconcile"
            )
        }
        let coordinator = PulsarWorkoutStartCoordinator.shared
        let result = coordinator.receiveWatchAcknowledgement(acknowledgement, source: source)
        let duplicateIsVerified = coordinator.isWatchStartVerified(
            requestID: acknowledgement.requestID,
            candidateSessionID: acknowledgement.candidateSessionID
        )
        if Self.shouldCancelAcknowledgementWait(
            for: result,
            duplicateIsVerified: duplicateIsVerified
        ) {
            acknowledgementWaitTask?.cancel()
            acknowledgementWaitTask = nil
        }

        switch result {
        case .accepted:
            lastAckMirroringState = acknowledgement.mirroringState
            if hasLiveMirroredSession, acknowledgement.mirroringState != .unavailableWatchRecording {
                markMirroringVerified(for: currentRequest)
                markLiveFromMirroredSessionIfEligible()
            } else if acknowledgement.mirroringState == .unavailableWatchRecording {
                phase = .watchSessionRunning
                if let state = syncStore.activeGymState {
                    markLiveFromWatchStateIfEligible(state)
                }
            } else {
                phase = .watchSessionRunning
            }
            syncPhaseFromLifecycleAuthority()
            PulsarWorkoutLifecycleLogger.log(
                .watchStartVerified,
                sessionID: acknowledgement.authoritativeSessionID,
                requestID: acknowledgement.requestID,
                workoutType: acknowledgement.sessionState.rawValue,
                source: source,
                detail: "ack"
            )
        case .duplicate:
            syncPhaseFromLifecycleAuthority()
        case .stale, .lateAfterFallback, .rejectedNoMatchingRequest:
            PulsarWorkoutStartupTrace.phone(
                "ignored uncorrelated acknowledgement requestID=\(acknowledgement.requestID.uuidString) candidateWorkoutID=\(acknowledgement.candidateSessionID.uuidString) authoritativeWorkoutID=\(acknowledgement.authoritativeSessionID.uuidString) currentRequestID=\(currentRequest?.requestID.uuidString ?? "none") currentWorkoutID=\(currentRequest?.candidateSessionID.uuidString ?? "none")"
            )
        }
    }

    static func shouldCancelAcknowledgementWait(
        for result: PulsarWorkoutStartAckResult,
        duplicateIsVerified: Bool
    ) -> Bool {
        switch result {
        case .accepted:
            true
        case .duplicate:
            duplicateIsVerified
        case .stale, .lateAfterFallback, .rejectedNoMatchingRequest:
            false
        }
    }

    private func markLiveFromWatchStateIfEligible(_ state: ActiveGymWorkoutState) {
        guard let request = currentRequest else { return }
        let transaction = PulsarWorkoutStartCoordinator.shared.currentTransaction
        let canonicalSessionID = transaction?.authoritativeSessionID ?? request.candidateSessionID
        let matchesRequest = state.sessionId == canonicalSessionID || state.sessionId == request.candidateSessionID
        if !matchesRequest, syncStore.isRoutableActiveGymState(state) {
            let authorityDecision = PulsarWatchSynchronizedGymReconciliation.incomingAuthorityDecision(
                incoming: state,
                canonicalSessionID: canonicalSessionID,
                canonicalRequestID: transaction?.requestID ?? request.requestID,
                hasAuthoritativeMirror: hasLiveMirroredSession
            )
            PulsarWorkoutStartupTrace.remoteConflict(
                expectedWorkoutID: canonicalSessionID,
                expectedRequestID: request.requestID,
                watchWorkoutID: state.sessionId,
                watchRequestID: state.requestID,
                watchHKState: state.isFinished ? "finished" : "running",
                action: "reconcile"
            )
            switch authorityDecision {
            case .adopt:
                break
            case .rejectAdvisory(let reason):
                PulsarWorkoutStartupTrace.lifecycle(
                    "[WorkoutReconcile] incomingWorkoutID=\(state.sessionId.uuidString) canonicalWorkoutID=\(canonicalSessionID.uuidString) incomingRequestID=\(state.requestID?.uuidString ?? "none") canonicalRequestID=\(request.requestID.uuidString) source=watchActiveGymState decision=rejectAdvisory reason=\(reason)"
                )
                return
            case .competingWorkout(let reason):
                PulsarWorkoutStartupTrace.lifecycle(
                    "[WorkoutReconcile] incomingWorkoutID=\(state.sessionId.uuidString) canonicalWorkoutID=\(canonicalSessionID.uuidString) incomingRequestID=\(state.requestID?.uuidString ?? "none") canonicalRequestID=\(request.requestID.uuidString) source=watchActiveGymState decision=rejectConflict reason=\(reason)"
                )
                rejectConflictingWatchState(request: request, watchSessionID: state.sessionId, source: "watchActiveGymState")
                return
            }
        }
        guard matchesRequest else {
            return
        }
        guard lastAckMirroringState == .unavailableWatchRecording || PulsarWorkoutStartCoordinator.shared.phase.name == "reconcilingRemote" || PulsarWorkoutStartCoordinator.shared.phase.name == "recovering" else { return }
        guard matchesRequest, syncStore.isRoutableActiveGymState(state) else { return }
        markVerifiedActive()
    }

    private func promoteCanonicalStartContextToLive(request: GymWorkoutStartRequest) {
        let retained = retainedStartContext.flatMap { $0.sessionId == request.candidateSessionID ? $0 : nil }
        guard var state = syncStore.activeGymState?.sessionId == request.candidateSessionID
            ? syncStore.activeGymState
            : retained else {
            PulsarWorkoutStartupTrace.lifecycle(
                "[PulsarWorkoutRoutine] resolvedMode=unavailable reason=missingCanonicalContext workoutID=\(request.candidateSessionID.uuidString) requestID=\(request.requestID.uuidString) routineID=\(request.routineID.uuidString) snapshotAvailable=false activeGymStateAvailable=\(syncStore.activeGymState != nil)"
            )
            return
        }
        state.requestID = request.requestID
        state.routineId = request.routineID
        state.routineRevision = max(state.routineRevision ?? 0, request.routineRevision)
        state.workoutKind = request.workoutKind
        state.isLaunchPlaceholder = false
        state.healthKitStatusMessage = "Apple Watch recording"
        state.updatedAt = Date()
        retainedStartContext = state
        let didStoreCanonicalState = syncStore.storeActiveGymState(
            state,
            broadcast: false,
            reason: "gymAuthoritativeMirrorContextActivated"
        )
        guard didStoreCanonicalState,
              let canonicalState = syncStore.activeGymState,
              canonicalState.sessionId == request.candidateSessionID,
              canonicalState.requestID == request.requestID else {
            PulsarWorkoutStartupTrace.lifecycle(
                "[PulsarWorkoutRoutine] resolvedMode=unavailable reason=canonicalStoreRejected workoutID=\(request.candidateSessionID.uuidString) requestID=\(request.requestID.uuidString) routineID=\(request.routineID.uuidString) snapshotAvailable=\(!state.exercises.isEmpty) activeGymStateAvailable=\(syncStore.activeGymState != nil) exerciseCount=\(state.exercises.count) tombstoned=\(syncStore.isActiveWorkoutSessionTombstoned(request.candidateSessionID))"
            )
            return
        }
        PulsarWorkoutStartupTrace.lifecycle(
            "[PulsarWorkoutRoutine] resolvedMode=\(canonicalState.workoutKind == .freeWorkout ? "openGym" : "routine") reason=canonicalActiveGymState workoutID=\(canonicalState.sessionId.uuidString) requestID=\(canonicalState.requestID?.uuidString ?? "none") routineID=\(canonicalState.routineId.uuidString) snapshotAvailable=\(!canonicalState.exercises.isEmpty) activeGymStateAvailable=true exerciseCount=\(canonicalState.exercises.count)"
        )
    }

    private func markMirroringVerified(for request: GymWorkoutStartRequest?) {
        guard let request else { return }
        let result = PulsarWorkoutStartCoordinator.shared.markMirroredSessionReceived(
            sessionID: request.candidateSessionID,
            requestID: request.requestID,
            source: "GymCrossDeviceStartController"
        )
        if result == .applied {
            phase = .mirroring
        } else if result == .duplicate {
            syncPhaseFromLifecycleAuthority()
        }
    }

    private func liveWatchOwnedGymState() -> ActiveGymWorkoutState? {
        guard let state = syncStore.activeGymState,
              !state.isPrelaunchPlaceholder,
              syncStore.isRoutableActiveGymState(state),
              state.startedFrom?.isAppleWatchRecorder == true else {
            return nil
        }
        return state
    }

    private func rejectConflictingWatchState(
        request: GymWorkoutStartRequest,
        watchSessionID: UUID,
        source: String
    ) {
        PulsarWorkoutStartCoordinator.shared.markStartFailed(
            sessionID: request.candidateSessionID,
            workoutType: request.workoutKind.rawValue,
            source: source,
            error: GymCrossDeviceStartError.existingWorkoutConflict.rawValue
        )
        PulsarWorkoutMirroringCoordinator.shared.clearPendingGymMirroring(requestID: request.requestID)
        phase = .failed(.existingWorkoutConflict, canRetry: false)
        lastError = .existingWorkoutConflict
        PulsarSyncDebugLogger.log(
            "Rejected uncorrelated Watch gym during start expected=\(request.candidateSessionID.uuidString) watch=\(watchSessionID.uuidString) source=\(source) action=noop"
        )
    }

    private func adoptLiveWatchGymState(
        _ state: ActiveGymWorkoutState,
        routine: PulsarRoutine,
        workoutKind: PulsarGymWorkoutKind,
        routineStore: PulsarRoutineStore
    ) async {
        let request = GymWorkoutStartRequest(
            candidateSessionID: state.sessionId,
            routineID: routine.id,
            routineRevision: routineStore.routinesRevision,
            workoutKind: workoutKind,
            activityTypeRawValue: PulsarWorkoutCatalog.gymWorkoutConfiguration.activityType.rawValue,
            locationTypeRawValue: PulsarWorkoutCatalog.gymWorkoutConfiguration.locationType.rawValue
        )
        currentRequest = request
        switch PulsarWorkoutStartCoordinator.shared.beginCrossDeviceGymStart(
            request: request,
            source: "GymCrossDeviceStartController.adoptExisting"
        ) {
        case .granted, .duplicateStart, .alreadyActive:
            break
        case .rejectedConflict:
            _ = PulsarWorkoutStartCoordinator.shared.adoptRemoteWatchGymIdentity(
                sessionID: state.sessionId,
                requestID: request.requestID,
                source: "GymCrossDeviceStartController.adoptExisting"
            )
        }
        _ = PulsarWorkoutStartCoordinator.shared.adoptRemoteWatchGymIdentity(
            sessionID: state.sessionId,
            requestID: request.requestID,
            source: "GymCrossDeviceStartController.adoptExisting"
        )
        markVerifiedActive()
    }

    private func queryWatchAndReconcile(for request: GymWorkoutStartRequest, allowLaunchRetry: Bool) async {
        PulsarWorkoutStartupTrace.phone(
            "query Watch active gym \(PulsarWorkoutStartupTrace.identity(workoutID: request.candidateSessionID, requestID: request.requestID))"
        )
        syncStore.sendGymAction(.requestState())
        syncStore.sendGymAction(.requestState(sessionId: request.candidateSessionID))
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            if Task.isCancelled { return }
            if isVerifiedForPresentation || phase == .active { return }
            if let state = liveWatchOwnedGymState() {
                if state.sessionId == request.candidateSessionID {
                    PulsarWorkoutStartupTrace.phone(
                        "query matched same workout \(PulsarWorkoutStartupTrace.identity(workoutID: state.sessionId, requestID: request.requestID))"
                    )
                    _ = PulsarWorkoutStartCoordinator.shared.adoptRemoteWatchGymIdentity(
                        sessionID: state.sessionId,
                        requestID: request.requestID,
                        source: "queryWatch.same"
                    )
                    markVerifiedActive()
                    return
                }
                PulsarWorkoutStartupTrace.remoteConflict(
                    expectedWorkoutID: request.candidateSessionID,
                    expectedRequestID: request.requestID,
                    watchWorkoutID: state.sessionId,
                    watchHKState: "running",
                    action: "reject"
                )
                rejectConflictingWatchState(
                    request: request,
                    watchSessionID: state.sessionId,
                    source: "queryWatch.different"
                )
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard liveWatchOwnedGymState() == nil else { return }
        if allowLaunchRetry, !didAttemptRecoveryLaunch {
            PulsarWorkoutStartupTrace.phone(
                "query found no Watch gym, launch retry permitted \(PulsarWorkoutStartupTrace.identity(workoutID: request.candidateSessionID, requestID: request.requestID))"
            )
            return
        }
        let reachable = syncStore.watchRecorderAvailabilitySnapshot(reason: "queryWatch.absent").rawIsReachable
        guard reachable else {
            PulsarWorkoutStartupTrace.phone(
                "query inconclusive Watch unreachable \(PulsarWorkoutStartupTrace.identity(workoutID: request.candidateSessionID, requestID: request.requestID))"
            )
            return
        }
        _ = PulsarWorkoutStartCoordinator.shared.markRemoteWorkoutAbsent(
            requestID: request.requestID,
            source: "queryWatch.absent"
        )
        abandonUnstartedCompanionGym(request: request, reason: "queryWatch.absent")
        phase = .failed(.watchAcknowledgementTimedOut, canRetry: true)
        lastError = .watchAcknowledgementTimedOut
        PulsarWorkoutMirroringCoordinator.shared.clearPendingGymMirroring(requestID: request.requestID)
    }

    private func abandonUnstartedCompanionGym(request: GymWorkoutStartRequest, reason: String) {
        guard !hasLiveMirroredSession else { return }
        guard let state = syncStore.activeGymState,
              state.sessionId == request.candidateSessionID,
              !state.isFinished else {
            return
        }
        syncStore.clearActiveGymState(reason: reason, broadcastEndedState: true)
        PulsarSyncDebugLogger.log(
            "Abandoned unstarted companion gym session=\(request.candidateSessionID.uuidString) request=\(request.requestID.uuidString) reason=\(reason)"
        )
    }

    private func makePrelaunchState(
        routine: PulsarRoutine,
        request: GymWorkoutStartRequest,
        availability: PulsarWatchRecorderAvailabilitySnapshot
    ) -> ActiveGymWorkoutState {
        let now = Date()
        let routinePlan = WatchGymRoutinePlan(routine: routine)
        let exercises = routinePlan.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map(ActiveGymWorkoutExerciseState.init(routinePlan:))
        return ActiveGymWorkoutState(
            sessionId: request.candidateSessionID,
            routineId: routine.id,
            routineName: routine.name,
            routineEmoji: routine.emoji,
            workoutKind: request.workoutKind,
            startedFrom: .iPhoneRequestedWatchStart,
            startedAt: now,
            elapsedSeconds: 0,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: exercises.count,
            totalSets: exercises.reduce(0) { $0 + $1.sets.count },
            completedSets: 0,
            currentHeartRate: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            activeEnergyKilocalories: nil,
            restRemainingSeconds: nil,
            restTotalSeconds: nil,
            isHealthKitEnabled: true,
            healthKitStatusMessage: availability.isWatchInteractivelyReachable
                ? "Opening on Apple Watch..."
                : "Waiting for Apple Watch...",
            isFinished: false,
            updatedAt: now,
            exercises: exercises,
            requestID: request.requestID,
            routineRevision: request.routineRevision,
            lifecycleGeneration: 1,
            isLaunchPlaceholder: true
        )
    }

    private func mapFallbackReason(_ reason: PulsarWatchRecorderFallbackReason) -> GymCrossDeviceStartError {
        switch reason {
        case .noPairedWatch:
            .watchNotPaired
        case .watchAppNotInstalled:
            .watchAppNotInstalled
        case .activationPending, .unsupported:
            .watchConnectivityUnavailable
        case .notReachable:
            .watchNotReachable
        case .watchLaunchFailed:
            .watchLaunchFailed
        case .mirroringTimedOut:
            .watchAcknowledgementTimedOut
        }
    }

    func resetForNewFlow() {
        acknowledgementWaitTask?.cancel()
        phase = .idle
        currentRequest = nil
        pendingRoutine = nil
        retainedStartContext = nil
        lastError = nil
        lastAckMirroringState = nil
        routineStore = nil
        didAttemptRemoteQuery = false
        didAttemptRecoveryLaunch = false
        GymMirroredSessionBridge.shared.bind(controller: self)
    }
}
