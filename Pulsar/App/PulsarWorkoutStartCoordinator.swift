//
//  PulsarWorkoutStartCoordinator.swift
//  Pulsar
//

import Combine
import Foundation

struct PulsarWorkoutStartTransaction: Equatable, Sendable {
    var sessionID: UUID
    let kind: PulsarActiveWorkoutKind
    let source: String
    let workoutType: String
    let requestedAt: Date
    var requestID: UUID?
    var idempotencyKey: String?
    var authoritativeSessionID: UUID?
    var didReachActive: Bool = false
}

/// Immutable identity captured before app-entry reconciliation suspends. A
/// reconciliation task may only act on the same logical publication it saw at
/// capture time; workout state published while the task is suspended belongs
/// to a newer runtime and is handled by the live-state subscriptions.
struct PulsarRestoredWorkoutReconciliationSnapshot: Equatable, Sendable {
    struct GymIdentity: Equatable, Sendable {
        let sessionID: UUID
        let requestID: UUID?
        let routineID: UUID
        let routineRevision: Int?
        let lifecycleGeneration: Int?
        let startedAt: Date
        let workoutKind: PulsarGymWorkoutKind?
        let exerciseIDs: [UUID]

        nonisolated init(_ state: ActiveGymWorkoutState) {
            sessionID = state.sessionId
            requestID = state.requestID
            routineID = state.routineId
            routineRevision = state.routineRevision
            lifecycleGeneration = state.lifecycleGeneration
            startedAt = state.startedAt
            workoutKind = state.workoutKind
            exerciseIDs = state.exercises.map(\.id)
        }
    }

    let workoutState: PulsarActiveWorkoutSyncState?
    let gymIdentity: GymIdentity?

    init(
        workoutState: PulsarActiveWorkoutSyncState?,
        gymState: ActiveGymWorkoutState?
    ) {
        self.workoutState = workoutState
        gymIdentity = gymState.map(GymIdentity.init)
    }

    func stillMatches(
        workoutState currentWorkoutState: PulsarActiveWorkoutSyncState?,
        gymState currentGymState: ActiveGymWorkoutState?
    ) -> Bool {
        guard let expectedWorkoutState = workoutState,
              let currentWorkoutState,
              expectedWorkoutState.sessionId == currentWorkoutState.sessionId,
              expectedWorkoutState.sessionGeneration == currentWorkoutState.sessionGeneration,
              expectedWorkoutState.startedAt == currentWorkoutState.startedAt,
              expectedWorkoutState.kind == currentWorkoutState.kind else {
            return workoutState == nil && currentWorkoutState == nil
        }

        guard case .gym = expectedWorkoutState.kind else { return true }
        return gymIdentity == currentGymState.map(GymIdentity.init)
    }
}

enum PulsarWorkoutStartDecision: Equatable {
    case granted(PulsarWorkoutStartTransaction)
    case duplicateStart(PulsarWorkoutStartTransaction)
    case alreadyActive(UUID)
    case rejectedConflict(existingSessionID: UUID, requestedKind: PulsarActiveWorkoutKind)
}

enum PulsarWorkoutPresentationPolicy: Equatable, Sendable {
    case hidden
    case loading
    case live
    case summaryEligible
    case failed(String)
    case cancelled
}

enum PulsarWorkoutStartPhase: Equatable, Sendable {
    case idle
    case preparing(PulsarWorkoutStartTransaction)
    case startRequested(PulsarWorkoutStartTransaction)
    case launchingWatch(PulsarWorkoutStartTransaction)
    case waitingForWatchAcknowledgement(PulsarWorkoutStartTransaction, startedWaitingAt: Date)
    case watchSessionPreparing(PulsarWorkoutStartTransaction)
    case watchSessionRunning(PulsarWorkoutStartTransaction)
    case mirroring(PulsarWorkoutStartTransaction)
    case active(PulsarWorkoutStartTransaction)
    case recovering(PulsarWorkoutStartTransaction)
    case reconcilingRemote(PulsarWorkoutStartTransaction)
    case ending(PulsarWorkoutStartTransaction)
    case completed(PulsarWorkoutStartTransaction)
    case failed(PulsarWorkoutStartTransaction, error: String)
    case cancelled(PulsarWorkoutStartTransaction)

    var transaction: PulsarWorkoutStartTransaction? {
        switch self {
        case .idle:
            nil
        case .preparing(let transaction),
             .startRequested(let transaction),
             .launchingWatch(let transaction),
             .waitingForWatchAcknowledgement(let transaction, _),
             .watchSessionPreparing(let transaction),
             .watchSessionRunning(let transaction),
             .mirroring(let transaction),
             .active(let transaction),
             .recovering(let transaction),
             .reconcilingRemote(let transaction),
             .ending(let transaction),
             .completed(let transaction),
             .failed(let transaction, _),
             .cancelled(let transaction):
            transaction
        }
    }

    var isTerminal: Bool {
        switch self {
        case .idle, .completed, .failed, .cancelled:
            true
        default:
            false
        }
    }

    var isInProgress: Bool {
        switch self {
        case .idle, .completed, .failed, .cancelled:
            false
        default:
            true
        }
    }

    /// After HealthKit accepts `startWatchApp`, a new logical workout ID must
    /// not be minted until this start is active, cancelled, or Watch is known idle.
    var blocksNewWatchPrimaryIdentity: Bool {
        isInProgress
    }

    var isLoadingPresentation: Bool {
        switch self {
        case .preparing, .startRequested, .launchingWatch, .waitingForWatchAcknowledgement,
             .watchSessionPreparing, .watchSessionRunning, .mirroring, .recovering,
             .reconcilingRemote:
            true
        default:
            false
        }
    }

    var name: String {
        switch self {
        case .idle: "idle"
        case .preparing: "preparing"
        case .startRequested: "startRequested"
        case .launchingWatch: "launchingWatch"
        case .waitingForWatchAcknowledgement: "waitingForWatchAcknowledgement"
        case .watchSessionPreparing: "watchSessionPreparing"
        case .watchSessionRunning: "watchSessionRunning"
        case .mirroring: "mirroring"
        case .active: "active"
        case .recovering: "recovering"
        case .reconcilingRemote: "reconcilingRemote"
        case .ending: "ending"
        case .completed: "completed"
        case .failed: "failed"
        case .cancelled: "cancelled"
        }
    }
}

enum PulsarWorkoutStartTransitionResult: Equatable {
    case applied
    case duplicate
    case rejectedIllegalTransition(from: String, to: String)
    case rejectedStale(requestID: UUID)
    case rejectedLateAfterFallback(requestID: UUID)
    case rejectedConflict(existingSessionID: UUID)
}

enum PulsarWorkoutStartAckResult: Equatable {
    case accepted(PulsarWorkoutStartTransaction)
    case duplicate
    case stale(requestID: UUID)
    case lateAfterFallback(requestID: UUID)
    case rejectedNoMatchingRequest(requestID: UUID)
}

@MainActor
final class PulsarWorkoutStartCoordinator: ObservableObject {
    static let shared = PulsarWorkoutStartCoordinator()

    static let watchAcknowledgementTimeout: TimeInterval = 12

    @Published private(set) var phase: PulsarWorkoutStartPhase = .idle
    private var didChooseIPhoneFallback = false
    private var handledAcknowledgementRequestIDs = Set<UUID>()
    private var handledIdempotencyKeys = Set<String>()
    private var reachedActiveSessionIDs = Set<UUID>()
    private(set) var endTransactionID: UUID?

    var currentTransaction: PulsarWorkoutStartTransaction? {
        phase.transaction
    }

    func matchesCurrentInFlightSession(_ sessionID: UUID) -> Bool {
        guard phase.isInProgress, let transaction = phase.transaction else { return false }
        return transaction.sessionID == sessionID || transaction.authoritativeSessionID == sessionID
    }

    var didReachActive: Bool {
        guard let transaction = phase.transaction else { return false }
        return didReachActive(sessionID: transaction.sessionID)
    }

    var presentationPolicy: PulsarWorkoutPresentationPolicy {
        return switch phase {
        case .idle:
            .hidden
        case .preparing, .startRequested, .launchingWatch, .waitingForWatchAcknowledgement,
             .watchSessionPreparing, .watchSessionRunning, .mirroring, .recovering,
             .reconcilingRemote:
            .loading
        case .active, .ending:
            .live
        case .completed(let transaction):
            didReachActive(sessionID: transaction.sessionID) ? .summaryEligible : .hidden
        case .failed(_, let error):
            .failed(error)
        case .cancelled:
            .cancelled
        }
    }

    var isCrossDeviceGymStartVerified: Bool {
        return switch phase {
        case .watchSessionRunning, .mirroring, .active:
            true
        default:
            false
        }
    }

    /// Scene-phase Oura/HealthKit/Fitness refreshes must not run while a Watch
    /// start handshake is in flight. `startWatchApp` bounces the iPhone scene
    /// active and would otherwise start a second MainActor sync.
    var shouldDeferForegroundHealthRefresh: Bool {
        phase.isLoadingPresentation
    }

    /// Shared verification policy for gym and run Watch-first starts. Every
    /// accepted signal must still correlate to the pending request and session.
    func isWatchStartVerified(requestID: UUID, candidateSessionID: UUID) -> Bool {
        guard let transaction = phase.transaction,
              transaction.requestID == requestID,
              transaction.sessionID == candidateSessionID ||
                transaction.authoritativeSessionID == candidateSessionID else {
            return false
        }
        return switch phase {
        case .watchSessionRunning, .mirroring, .active:
            true
        default:
            false
        }
    }

    func didReachActive(sessionID: UUID) -> Bool {
        if reachedActiveSessionIDs.contains(sessionID) {
            return true
        }
        if let authoritative = phase.transaction?.authoritativeSessionID,
           authoritative == sessionID,
           reachedActiveSessionIDs.contains(phase.transaction?.sessionID ?? sessionID) {
            return true
        }
        if case .active(let transaction) = phase,
           transaction.sessionID == sessionID || transaction.authoritativeSessionID == sessionID {
            return true
        }
        return false
    }

    func canPresentSummary(sessionID: UUID) -> Bool {
        didReachActive(sessionID: sessionID)
    }

    /// Records that a session reached live recording, including Watch-originated
    /// sessions that never passed through iPhone `requestStart`.
    func markSessionReachedActive(sessionID: UUID, source: String) {
        let inserted = reachedActiveSessionIDs.insert(sessionID).inserted
        if case .active(var transaction) = phase,
           transaction.sessionID == sessionID || transaction.authoritativeSessionID == sessionID {
            transaction.didReachActive = true
            phase = .active(transaction)
        }
        guard inserted else { return }
        PulsarWorkoutLifecycleLogger.log(
            .workoutActivated,
            sessionID: sessionID,
            source: source,
            detail: "markSessionReachedActive",
            previousState: phase.name,
            nextState: phase.name
        )
    }

    func acknowledgeTerminal(sessionID: UUID, reason: String) {
        let previous = phase.name
        switch phase {
        case .completed(let transaction), .failed(let transaction, _), .cancelled(let transaction):
            guard transaction.sessionID == sessionID || transaction.authoritativeSessionID == sessionID else { return }
            phase = .idle
        case .idle:
            break
        default:
            break
        }
        reachedActiveSessionIDs.remove(sessionID)
        PulsarWorkoutLifecycleLogger.log(
            .workoutSessionCleanedUp,
            sessionID: sessionID,
            detail: "acknowledgeTerminal.\(reason)",
            previousState: previous,
            nextState: phase.name
        )
    }

    func requestStart(
        sessionID: UUID,
        kind: PulsarActiveWorkoutKind,
        source: String,
        workoutType: String
    ) -> PulsarWorkoutStartDecision {
        PulsarWorkoutLifecycleLogger.log(
            .workoutStartRequested,
            sessionID: sessionID,
            requestID: nil,
            workoutType: workoutType,
            source: source
        )

        switch phase {
        case .idle:
            return grantPreparingStart(
                sessionID: sessionID,
                kind: kind,
                source: source,
                workoutType: workoutType,
                previousStateName: "idle"
            )

        case .completed(let previous), .failed(let previous, _), .cancelled(let previous):
            let previousStateName = phase.name
            clearTerminalAuthority(for: previous, reason: "supersededByNewStart")
            return grantPreparingStart(
                sessionID: sessionID,
                kind: kind,
                source: source,
                workoutType: workoutType,
                previousStateName: previousStateName
            )

        case .preparing(let existing),
             .startRequested(let existing),
             .launchingWatch(let existing),
             .waitingForWatchAcknowledgement(let existing, _),
             .watchSessionPreparing(let existing),
             .watchSessionRunning(let existing),
             .mirroring(let existing),
             .recovering(let existing),
             .reconcilingRemote(let existing):
            if existing.sessionID == sessionID {
                PulsarWorkoutLifecycleLogger.log(
                    .workoutStartRejectedDuplicate,
                    sessionID: sessionID,
                    workoutType: workoutType,
                    source: source,
                    detail: "phase=\(phase.name)"
                )
                return .duplicateStart(existing)
            }
            PulsarWorkoutLifecycleLogger.log(
                .workoutStartRejectedDuplicate,
                sessionID: sessionID,
                workoutType: workoutType,
                source: source,
                detail: "conflictWithInProgress=\(existing.sessionID.uuidString)"
            )
            return .rejectedConflict(existingSessionID: existing.sessionID, requestedKind: kind)

        case .active(let existing), .ending(let existing):
            if existing.sessionID == sessionID {
                PulsarWorkoutLifecycleLogger.log(
                    .workoutStartRejectedDuplicate,
                    sessionID: sessionID,
                    workoutType: workoutType,
                    source: source,
                    detail: "phase=\(phase.name)"
                )
                return .alreadyActive(existing.sessionID)
            }
            PulsarWorkoutLifecycleLogger.log(
                .workoutStartRejectedDuplicate,
                sessionID: sessionID,
                workoutType: workoutType,
                source: source,
                detail: "conflictWithActive=\(existing.sessionID.uuidString)"
            )
            return .rejectedConflict(existingSessionID: existing.sessionID, requestedKind: kind)
        }
    }

    private func grantPreparingStart(
        sessionID: UUID,
        kind: PulsarActiveWorkoutKind,
        source: String,
        workoutType: String,
        previousStateName: String
    ) -> PulsarWorkoutStartDecision {
        let transaction = PulsarWorkoutStartTransaction(
            sessionID: sessionID,
            kind: kind,
            source: source,
            workoutType: workoutType,
            requestedAt: Date()
        )
        endTransactionID = nil
        phase = .preparing(transaction)
        PulsarWorkoutHandshakeLogGate.setSuppressNonWorkoutDiagnostics(true)
        PulsarWorkoutLifecycleLogger.log(
            .workoutStartValidated,
            sessionID: sessionID,
            workoutType: workoutType,
            source: source,
            previousState: previousStateName,
            nextState: phase.name
        )
        return .granted(transaction)
    }

    private func clearTerminalAuthority(for transaction: PulsarWorkoutStartTransaction, reason: String) {
        reachedActiveSessionIDs.remove(transaction.sessionID)
        if let authoritative = transaction.authoritativeSessionID {
            reachedActiveSessionIDs.remove(authoritative)
        }
        PulsarWorkoutLifecycleLogger.log(
            .workoutSessionCleanedUp,
            sessionID: transaction.sessionID,
            requestID: transaction.requestID,
            workoutType: transaction.workoutType,
            source: reason,
            detail: "clearTerminalAuthority",
            previousState: phase.name,
            nextState: phase.name
        )
    }

    @discardableResult
    func beginCrossDeviceGymStart(
        request: GymWorkoutStartRequest,
        source: String
    ) -> PulsarWorkoutStartDecision {
        if handledIdempotencyKeys.contains(request.idempotencyKey),
           let transaction = phase.transaction,
           transaction.requestID == request.requestID {
            return .duplicateStart(transaction)
        }

        switch requestStart(
            sessionID: request.candidateSessionID,
            kind: .watchGym,
            source: source,
            workoutType: request.workoutKind.rawValue
        ) {
        case .granted(var transaction):
            transaction.requestID = request.requestID
            transaction.idempotencyKey = request.idempotencyKey
            transaction.authoritativeSessionID = request.candidateSessionID
            handledIdempotencyKeys.insert(request.idempotencyKey)
            phase = .startRequested(transaction)
            return .granted(transaction)
        case .duplicateStart(let transaction):
            return .duplicateStart(transaction)
        case .alreadyActive(let sessionID):
            return .alreadyActive(sessionID)
        case .rejectedConflict(let existingSessionID, let requestedKind):
            return .rejectedConflict(existingSessionID: existingSessionID, requestedKind: requestedKind)
        }
    }

    @discardableResult
    func markWatchLaunchSubmitted(requestID: UUID, source: String) -> PulsarWorkoutStartTransitionResult {
        guard var transaction = phase.transaction else {
            return .rejectedIllegalTransition(from: phase.name, to: "launchingWatch")
        }
        guard transaction.requestID == requestID || transaction.requestID == nil else {
            return .rejectedStale(requestID: requestID)
        }
        transaction.requestID = requestID
        let previous = phase.name
        switch phase {
        case .preparing, .startRequested:
            phase = .launchingWatch(transaction)
            beginWatchStartExecutionAssertionIfShared(reason: source)
            PulsarWorkoutStartupTrace.phone("Watch launch submitted source=\(source) session=\(transaction.sessionID.uuidString)")
            PulsarWorkoutStartupTrace.phone("WorkoutStartTask created source=\(source)")
            PulsarWorkoutLifecycleLogger.log(
                .watchLaunchRequestSubmitted,
                sessionID: transaction.sessionID,
                requestID: requestID,
                workoutType: transaction.workoutType,
                source: source,
                previousState: previous,
                nextState: phase.name
            )
            return .applied
        case .launchingWatch(let existing) where existing.requestID == requestID:
            return .duplicate
        default:
            return .rejectedIllegalTransition(from: phase.name, to: "launchingWatch")
        }
    }

    @discardableResult
    func markWatchLaunchFailed(
        requestID: UUID,
        source: String,
        error: String
    ) -> PulsarWorkoutStartTransitionResult {
        guard let transaction = phase.transaction, transaction.requestID == requestID else {
            return .rejectedStale(requestID: requestID)
        }
        let previous = phase.name
        phase = .failed(transaction, error: error)
        endWatchStartExecutionAssertionIfShared(reason: "watchLaunchFailed")
        PulsarWorkoutLifecycleLogger.log(
            .watchLaunchRequestFailed,
            sessionID: transaction.sessionID,
            requestID: requestID,
            workoutType: transaction.workoutType,
            source: source,
            previousState: previous,
            nextState: phase.name,
            error: error
        )
        PulsarWorkoutLifecycleLogger.log(
            .workoutStartFailed,
            sessionID: transaction.sessionID,
            requestID: requestID,
            workoutType: transaction.workoutType,
            source: source,
            detail: error,
            previousState: previous,
            nextState: phase.name
        )
        return .applied
    }

    @discardableResult
    func markWaitingForWatchAcknowledgement(requestID: UUID, source: String) -> PulsarWorkoutStartTransitionResult {
        guard let transaction = phase.transaction, transaction.requestID == requestID else {
            return .rejectedStale(requestID: requestID)
        }
        switch phase {
        case .launchingWatch:
            phase = .waitingForWatchAcknowledgement(transaction, startedWaitingAt: Date())
            return .applied
        case .waitingForWatchAcknowledgement(let existing, _) where existing.requestID == requestID:
            return .duplicate
        default:
            return .rejectedIllegalTransition(from: phase.name, to: "waitingForWatchAcknowledgement")
        }
    }

    @discardableResult
    func markWatchStartRecovering(requestID: UUID, source: String) -> PulsarWorkoutStartTransitionResult {
        guard let transaction = phase.transaction, transaction.requestID == requestID else {
            return .rejectedStale(requestID: requestID)
        }
        let previous = phase.name
        switch phase {
        case .launchingWatch, .waitingForWatchAcknowledgement, .recovering, .reconcilingRemote:
            phase = .recovering(transaction)
            PulsarWorkoutLifecycleLogger.log(
                .watchRecoveryAttempt,
                sessionID: transaction.sessionID,
                requestID: requestID,
                workoutType: transaction.workoutType,
                source: source,
                previousState: previous,
                nextState: phase.name,
                retryAttempt: 1
            )
            return .applied
        default:
            return .rejectedIllegalTransition(from: phase.name, to: "recovering")
        }
    }

    func receiveWatchAcknowledgement(
        _ acknowledgement: GymWorkoutStartAcknowledgement,
        source: String
    ) -> PulsarWorkoutStartAckResult {
        if didChooseIPhoneFallback {
            PulsarWorkoutLifecycleLogger.log(
                .watchAcknowledgementReceived,
                sessionID: acknowledgement.authoritativeSessionID,
                requestID: acknowledgement.requestID,
                source: source,
                detail: "lateAfterFallback",
                previousState: phase.name,
                nextState: "rejected"
            )
            return .lateAfterFallback(requestID: acknowledgement.requestID)
        }

        guard let transaction = phase.transaction else {
            return .rejectedNoMatchingRequest(requestID: acknowledgement.requestID)
        }

        guard transaction.requestID == acknowledgement.requestID else {
            if handledAcknowledgementRequestIDs.contains(acknowledgement.requestID) {
                return .duplicate
            }
            PulsarWorkoutStartupTrace.remoteConflict(
                expectedWorkoutID: transaction.sessionID,
                expectedRequestID: transaction.requestID,
                watchWorkoutID: acknowledgement.authoritativeSessionID,
                watchRequestID: acknowledgement.requestID,
                watchHKState: acknowledgement.sessionState.rawValue,
                action: acknowledgement.isAuthoritativeWatchRunning ? "adopt" : "ignore"
            )
            return .stale(requestID: acknowledgement.requestID)
        }

        guard transaction.sessionID == acknowledgement.candidateSessionID else {
            return .stale(requestID: acknowledgement.requestID)
        }

        let canonicalSessionID = transaction.authoritativeSessionID ?? transaction.sessionID
        guard acknowledgement.authoritativeSessionID == canonicalSessionID else {
            PulsarWorkoutStartupTrace.remoteConflict(
                expectedWorkoutID: canonicalSessionID,
                expectedRequestID: transaction.requestID,
                watchWorkoutID: acknowledgement.authoritativeSessionID,
                watchRequestID: acknowledgement.requestID,
                watchHKState: acknowledgement.sessionState.rawValue,
                action: "rejectAuthoritativeIdentityReplacement"
            )
            return .stale(requestID: acknowledgement.requestID)
        }

        if handledAcknowledgementRequestIDs.contains(acknowledgement.requestID) {
            return .duplicate
        }

        switch phase {
        case .completed, .failed, .cancelled:
            PulsarWorkoutLifecycleLogger.log(
                .watchAcknowledgementReceived,
                sessionID: acknowledgement.authoritativeSessionID,
                requestID: acknowledgement.requestID,
                source: source,
                detail: "terminalNoop",
                previousState: phase.name,
                nextState: phase.name
            )
            return .duplicate
        default:
            break
        }

        guard acknowledgement.isAuthoritativeWatchRunning else {
            return .rejectedNoMatchingRequest(requestID: acknowledgement.requestID)
        }

        var nextTransaction = transaction
        nextTransaction.authoritativeSessionID = canonicalSessionID
        let previous = phase.name
        handledAcknowledgementRequestIDs.insert(acknowledgement.requestID)

        // Acknowledgements may arrive after the HealthKit mirror has already
        // made the workout authoritative. They can enrich identity, but must not
        // move an active/ending/completed transaction backwards to mirroring.
        switch phase {
        case .active:
            nextTransaction.didReachActive = true
            phase = .active(nextTransaction)
        case .ending:
            nextTransaction.didReachActive = true
            phase = .ending(nextTransaction)
        case .completed:
            nextTransaction.didReachActive = true
            phase = .completed(nextTransaction)
        default:
            switch acknowledgement.mirroringState {
            case .active:
                phase = .mirroring(nextTransaction)
            case .unavailableWatchRecording:
                phase = .watchSessionRunning(nextTransaction)
            default:
                phase = .watchSessionRunning(nextTransaction)
            }
        }

        PulsarWorkoutLifecycleLogger.log(
            .watchAcknowledgementReceived,
            sessionID: acknowledgement.authoritativeSessionID,
            requestID: acknowledgement.requestID,
            workoutType: transaction.workoutType,
            source: source,
            previousState: previous,
            nextState: phase.name,
            transport: "watchConnectivity"
        )
        PulsarWorkoutLifecycleLogger.log(
            .workoutWatchSyncSucceeded,
            sessionID: acknowledgement.authoritativeSessionID,
            requestID: acknowledgement.requestID,
            workoutType: transaction.workoutType,
            source: source,
            previousState: previous,
            nextState: phase.name
        )
        return .accepted(nextTransaction)
    }

    func receiveRunWatchAcknowledgement(
        _ acknowledgement: PulsarRunStartAcknowledgement,
        source: String
    ) -> PulsarWorkoutStartAckResult {
        if didChooseIPhoneFallback {
            return .lateAfterFallback(requestID: acknowledgement.requestID)
        }
        guard let transaction = phase.transaction,
              transaction.kind == .run(acknowledgement.workoutKind) else {
            return .rejectedNoMatchingRequest(requestID: acknowledgement.requestID)
        }
        guard transaction.requestID == acknowledgement.requestID,
              transaction.sessionID == acknowledgement.candidateSessionID else {
            return .stale(requestID: acknowledgement.requestID)
        }
        if handledAcknowledgementRequestIDs.contains(acknowledgement.requestID) {
            return .duplicate
        }
        guard acknowledgement.isAuthoritativeWatchRunning else {
            return .rejectedNoMatchingRequest(requestID: acknowledgement.requestID)
        }

        var nextTransaction = transaction
        nextTransaction.authoritativeSessionID = acknowledgement.authoritativeSessionID
        let previous = phase.name
        handledAcknowledgementRequestIDs.insert(acknowledgement.requestID)
        phase = .watchSessionRunning(nextTransaction)
        PulsarWorkoutLifecycleLogger.log(
            .watchAcknowledgementReceived,
            sessionID: acknowledgement.authoritativeSessionID,
            requestID: acknowledgement.requestID,
            workoutType: acknowledgement.workoutKind.rawValue,
            source: source,
            previousState: previous,
            nextState: phase.name,
            transport: "watchConnectivity"
        )
        return .accepted(nextTransaction)
    }

    @discardableResult
    func markMirroredSessionReceived(
        sessionID: UUID,
        requestID: UUID?,
        source: String
    ) -> PulsarWorkoutStartTransitionResult {
        guard var transaction = phase.transaction else {
            return .rejectedIllegalTransition(from: phase.name, to: "mirroring")
        }
        if let requestID, transaction.requestID != requestID {
            return .rejectedStale(requestID: requestID)
        }
        guard transaction.sessionID == sessionID || transaction.authoritativeSessionID == sessionID else {
            if let requestID {
                return .rejectedStale(requestID: requestID)
            }
            return .rejectedIllegalTransition(from: phase.name, to: "mirroring")
        }
        transaction.authoritativeSessionID = sessionID
        let previous = phase.name
        switch phase {
        case .launchingWatch, .waitingForWatchAcknowledgement, .watchSessionRunning, .mirroring, .recovering, .reconcilingRemote:
            phase = .mirroring(transaction)
            PulsarWorkoutLifecycleLogger.log(
                .mirroredSessionReceived,
                sessionID: sessionID,
                requestID: transaction.requestID,
                workoutType: transaction.workoutType,
                source: source,
                previousState: previous,
                nextState: phase.name
            )
            return .applied
        case .active(let existing) where existing.sessionID == sessionID || existing.authoritativeSessionID == sessionID:
            return .duplicate
        default:
            return .rejectedIllegalTransition(from: phase.name, to: "mirroring")
        }
    }

    func markActivated(sessionID: UUID, workoutType: String, source: String) {
        let previous = phase.name
        var didActivate = false
        switch phase {
        case .preparing(var transaction), .startRequested(var transaction):
            guard transaction.sessionID == sessionID else {
                PulsarWorkoutLifecycleLogger.log(
                    .workoutStartRejectedDuplicate,
                    sessionID: sessionID,
                    workoutType: workoutType,
                    source: source,
                    detail: "markActivatedSessionMismatch phase=\(previous)"
                )
                return
            }
            transaction.authoritativeSessionID = sessionID
            transaction.didReachActive = true
            phase = .active(transaction)
            didActivate = true
        case .watchSessionRunning(var transaction), .mirroring(var transaction), .recovering(var transaction), .reconcilingRemote(var transaction):
            guard transaction.sessionID == sessionID || transaction.authoritativeSessionID == sessionID else {
                PulsarWorkoutLifecycleLogger.log(
                    .workoutStartRejectedDuplicate,
                    sessionID: sessionID,
                    workoutType: workoutType,
                    source: source,
                    detail: "markActivatedSessionMismatch phase=\(previous)"
                )
                return
            }
            transaction.authoritativeSessionID = sessionID
            transaction.didReachActive = true
            phase = .active(transaction)
            didActivate = true
        case .active(var transaction) where transaction.sessionID == sessionID || transaction.authoritativeSessionID == sessionID:
            if !transaction.didReachActive {
                transaction.didReachActive = true
                phase = .active(transaction)
                didActivate = true
            }
        default:
            PulsarWorkoutLifecycleLogger.log(
                .workoutStartRejectedDuplicate,
                sessionID: sessionID,
                workoutType: workoutType,
                source: source,
                detail: "markActivatedIllegalTransition from=\(previous)"
            )
            return
        }

        if didActivate {
            markSessionReachedActive(sessionID: sessionID, source: source)
            if let authoritative = phase.transaction?.authoritativeSessionID,
               authoritative != sessionID {
                markSessionReachedActive(sessionID: authoritative, source: source)
            }
            endWatchStartExecutionAssertionIfShared(reason: "activated")
            PulsarWorkoutStartupTrace.phone("live UI requested session=\(sessionID.uuidString) source=\(source)")
        }

        PulsarWorkoutLifecycleLogger.log(
            .workoutActivated,
            sessionID: sessionID,
            requestID: phase.transaction?.requestID,
            workoutType: workoutType,
            source: source,
            previousState: previous,
            nextState: phase.name
        )
    }

    func markStartFailed(sessionID: UUID, workoutType: String, source: String, error: String) {
        let previous = phase.name
        if let transaction = phase.transaction, transaction.sessionID == sessionID || transaction.authoritativeSessionID == sessionID {
            // Retain .failed until UI acknowledges or a new start begins.
            phase = .failed(transaction, error: error)
        } else if case .preparing = phase {
            phase = .idle
        }
        endWatchStartExecutionAssertionIfShared(reason: "startFailed")
        PulsarWorkoutLifecycleLogger.log(
            .workoutStartFailed,
            sessionID: sessionID,
            requestID: phase.transaction?.requestID,
            workoutType: workoutType,
            source: source,
            detail: error,
            previousState: previous,
            nextState: phase.name
        )
    }

    @discardableResult
    func markWatchAcknowledgementTimedOut(requestID: UUID, source: String) -> PulsarWorkoutStartTransitionResult {
        guard let transaction = phase.transaction, transaction.requestID == requestID else {
            return .rejectedStale(requestID: requestID)
        }
        let previous = phase.name
        // A Watch launch was already submitted. Timeout only proves the iPhone
        // missed ack/mirror; the Watch may still be recording. Keep the same
        // identity and block minting a new workout until remote state is known.
        phase = .reconcilingRemote(transaction)
        PulsarWorkoutStartupTrace.phone(
            "watch acknowledgement timed out remote state unknown \(PulsarWorkoutStartupTrace.identity(workoutID: transaction.sessionID, requestID: requestID)) previous=\(previous)"
        )
        PulsarWorkoutStartupTrace.phone("WorkoutTimeoutTask cancelled reason=watchAcknowledgementTimedOut remoteState=unknown")
        PulsarWorkoutLifecycleLogger.log(
            .workoutStartTimedOut,
            sessionID: transaction.sessionID,
            requestID: requestID,
            workoutType: transaction.workoutType,
            source: source,
            previousState: previous,
            nextState: phase.name
        )
        return .applied
    }

    @discardableResult
    func adoptRemoteWatchGymIdentity(
        sessionID: UUID,
        requestID: UUID?,
        source: String
    ) -> PulsarWorkoutStartTransitionResult {
        guard var transaction = phase.transaction else {
            return .rejectedIllegalTransition(from: phase.name, to: "adoptRemote")
        }
        let previous = phase.name
        guard transaction.sessionID == sessionID else {
            PulsarWorkoutStartupTrace.remoteConflict(
                expectedWorkoutID: transaction.sessionID,
                expectedRequestID: transaction.requestID,
                watchWorkoutID: sessionID,
                watchRequestID: requestID,
                watchHKState: "running",
                action: "reject"
            )
            return .rejectedConflict(existingSessionID: transaction.sessionID)
        }
        if let requestID, transaction.requestID != requestID {
            PulsarWorkoutStartupTrace.remoteConflict(
                expectedWorkoutID: transaction.sessionID,
                expectedRequestID: transaction.requestID,
                watchWorkoutID: sessionID,
                watchRequestID: requestID,
                watchHKState: "running",
                action: "reject"
            )
            return .rejectedStale(requestID: requestID)
        }
        transaction.authoritativeSessionID = sessionID
        if let requestID {
            transaction.requestID = requestID
        }
        handledAcknowledgementRequestIDs.insert(transaction.requestID ?? sessionID)
        phase = .watchSessionRunning(transaction)
        PulsarWorkoutStartupTrace.phone(
            "adopted Watch workout \(PulsarWorkoutStartupTrace.identity(workoutID: sessionID, requestID: transaction.requestID)) source=\(source) previous=\(previous)"
        )
        PulsarWorkoutLifecycleLogger.log(
            .watchStartVerified,
            sessionID: sessionID,
            requestID: transaction.requestID,
            workoutType: transaction.workoutType,
            source: source,
            detail: "adoptRemoteWatchGymIdentity",
            previousState: previous,
            nextState: phase.name
        )
        return .applied
    }

    enum RemoteWorkoutAuthority: String, Sendable {
        case freshWatchConnectivity
        case mirroredHealthKit
        case existingCoordinator
    }

    /// Adopts a verified, currently recording Watch workout that arrived without
    /// an iPhone launch transaction (for example after HealthKit woke the app).
    /// A live Watch state is authoritative and must reuse its identity rather
    /// than create a second iPhone `HKWorkoutSession`.
    @discardableResult
    func adoptRemoteActiveWorkout(
        sessionID: UUID,
        kind: PulsarActiveWorkoutKind,
        workoutType: String,
        authority: RemoteWorkoutAuthority,
        source: String
    ) -> PulsarWorkoutStartTransitionResult {
        let previous = phase.name
        var correlatedTransaction: PulsarWorkoutStartTransaction?

        switch phase {
        case .active(let existing), .ending(let existing):
            if existing.sessionID == sessionID || existing.authoritativeSessionID == sessionID {
                return .duplicate
            }
            return .rejectedConflict(existingSessionID: existing.sessionID)

        case .completed(let existing), .failed(let existing, _), .cancelled(let existing):
            clearTerminalAuthority(for: existing, reason: "remoteActiveWorkout")

        case .idle:
            break

        case .watchSessionRunning(let existing),
             .mirroring(let existing):
            if existing.sessionID == sessionID || existing.authoritativeSessionID == sessionID {
                var correlated = existing
                correlated.authoritativeSessionID = sessionID
                correlated.didReachActive = true
                correlatedTransaction = correlated
            } else {
                PulsarWorkoutStartupTrace.remoteConflict(
                    expectedWorkoutID: existing.sessionID,
                    expectedRequestID: existing.requestID,
                    watchWorkoutID: sessionID,
                    watchRequestID: nil,
                    watchHKState: "running",
                    action: "adoptVerifiedRemoteActive"
                )
                return .rejectedConflict(existingSessionID: existing.sessionID)
            }

        case .preparing(let existing),
             .startRequested(let existing),
             .launchingWatch(let existing),
             .waitingForWatchAcknowledgement(let existing, _),
             .watchSessionPreparing(let existing),
             .recovering(let existing),
             .reconcilingRemote(let existing):
            guard existing.sessionID == sessionID || existing.authoritativeSessionID == sessionID else {
                return .rejectedConflict(existingSessionID: existing.sessionID)
            }
            // A matching payload is still only data until the Watch running
            // acknowledgement or mirrored HealthKit session verifies it.
            return .rejectedIllegalTransition(from: phase.name, to: "adoptRemoteActive")
        }

        var transaction = correlatedTransaction ?? PulsarWorkoutStartTransaction(
            sessionID: sessionID,
            kind: kind,
            source: source,
            workoutType: workoutType,
            requestedAt: Date()
        )
        transaction.authoritativeSessionID = sessionID
        transaction.didReachActive = true
        phase = .active(transaction)
        reachedActiveSessionIDs.insert(sessionID)
        endWatchStartExecutionAssertionIfShared(reason: "remoteActiveWorkoutAdopted")
        PulsarWorkoutStartupTrace.phone(
            "adopted verified remote active workout workoutID=\(sessionID.uuidString) type=\(workoutType) source=\(source) previous=\(previous)"
        )
        PulsarWorkoutLifecycleLogger.log(
            .workoutActivated,
            sessionID: sessionID,
            workoutType: workoutType,
            source: source,
            detail: "adoptRemoteActiveWorkout",
            previousState: previous,
            nextState: phase.name,
            transport: authority.rawValue
        )
        return .applied
    }

    @discardableResult
    func markRemoteWorkoutAbsent(requestID: UUID, source: String) -> PulsarWorkoutStartTransitionResult {
        guard let transaction = phase.transaction, transaction.requestID == requestID else {
            return .rejectedStale(requestID: requestID)
        }
        switch phase {
        case .recovering, .reconcilingRemote, .waitingForWatchAcknowledgement, .launchingWatch:
            let previous = phase.name
            phase = .failed(transaction, error: GymCrossDeviceStartError.watchAcknowledgementTimedOut.rawValue)
            endWatchStartExecutionAssertionIfShared(reason: "remoteWorkoutAbsent")
            PulsarWorkoutStartupTrace.phone(
                "Watch confirmed no live Pulsar gym \(PulsarWorkoutStartupTrace.identity(workoutID: transaction.sessionID, requestID: requestID)) source=\(source)"
            )
            PulsarWorkoutLifecycleLogger.log(
                .workoutStartTimedOut,
                sessionID: transaction.sessionID,
                requestID: requestID,
                workoutType: transaction.workoutType,
                source: source,
                detail: "remoteWorkoutAbsent",
                previousState: previous,
                nextState: phase.name
            )
            return .applied
        default:
            return .rejectedIllegalTransition(from: phase.name, to: "failed")
        }
    }

    func markIPhoneFallbackChosen(requestID: UUID?, source: String) {
        didChooseIPhoneFallback = true
        if let requestID,
           let transaction = phase.transaction,
           transaction.requestID == requestID {
            let previous = phase.name
            // Retain .cancelled until UI acknowledges or a new start begins.
            phase = .cancelled(transaction)
            endWatchStartExecutionAssertionIfShared(reason: "iPhoneFallbackChosen")
            PulsarWorkoutLifecycleLogger.log(
                .workoutStartFailed,
                sessionID: transaction.sessionID,
                requestID: requestID,
                workoutType: transaction.workoutType,
                source: source,
                detail: "iPhoneFallbackChosen",
                previousState: previous,
                nextState: phase.name
            )
        }
    }

    func ensureEndTransactionID(sessionID: UUID) -> UUID {
        if let endTransactionID {
            return endTransactionID
        }
        let created = UUID()
        endTransactionID = created
        PulsarWorkoutStartupTrace.diag(
            "[WorkoutLifecycle] endTransactionCreated workoutID=\(sessionID.uuidString) endTransactionID=\(created.uuidString)"
        )
        return created
    }

    func markSessionEnded(sessionID: UUID, reason: String) {
        let previous = phase.name
        switch phase {
        case .active(let transaction), .ending(let transaction), .mirroring(let transaction), .watchSessionRunning(let transaction), .recovering(let transaction), .reconcilingRemote(let transaction):
            if transaction.sessionID == sessionID || transaction.authoritativeSessionID == sessionID {
                var completed = transaction
                completed.didReachActive = completed.didReachActive || reachedActiveSessionIDs.contains(sessionID)
                phase = .completed(completed)
                let endTransactionID = ensureEndTransactionID(sessionID: sessionID)
                PulsarWorkoutStartupTrace.diag(
                    "[WorkoutLifecycle] terminalAccepted source=\(reason) phase=\(previous)->completed endTransactionID=\(endTransactionID.uuidString) workoutID=\(sessionID.uuidString) requestID=\(transaction.requestID?.uuidString ?? "none") accepted=true reason=canonicalEnded"
                )
            }
        case .preparing(let transaction), .startRequested(let transaction), .launchingWatch(let transaction), .waitingForWatchAcknowledgement(let transaction, _), .watchSessionPreparing(let transaction):
            if transaction.sessionID == sessionID || transaction.authoritativeSessionID == sessionID {
                phase = .idle
            }
        case .completed(let transaction):
            if transaction.sessionID == sessionID || transaction.authoritativeSessionID == sessionID {
                PulsarWorkoutStartupTrace.diag(
                    "[WorkoutLifecycle] terminalAccepted source=\(reason) phase=completed->completed endTransactionID=\(endTransactionID?.uuidString ?? "none") workoutID=\(sessionID.uuidString) requestID=\(transaction.requestID?.uuidString ?? "none") accepted=false reason=alreadyEnded"
                )
                return
            }
        case .failed, .cancelled, .idle:
            break
        }
        didChooseIPhoneFallback = false
        guard previous != phase.name else { return }
        PulsarWorkoutLifecycleLogger.log(
            .workoutSessionCleanedUp,
            sessionID: sessionID,
            requestID: phase.transaction?.requestID,
            detail: reason,
            previousState: previous,
            nextState: phase.name
        )
    }

    @discardableResult
    func markSessionEnding(sessionID: UUID, reason: String) -> PulsarWorkoutStartTransitionResult {
        let previous = phase.name
        let transaction: PulsarWorkoutStartTransaction
        switch phase {
        case .active(let current), .mirroring(let current), .watchSessionRunning(let current),
             .recovering(let current), .reconcilingRemote(let current):
            guard current.sessionID == sessionID || current.authoritativeSessionID == sessionID else {
                return .rejectedConflict(existingSessionID: current.sessionID)
            }
            transaction = current
        case .ending(let current):
            guard current.sessionID == sessionID || current.authoritativeSessionID == sessionID else {
                return .rejectedConflict(existingSessionID: current.sessionID)
            }
            PulsarWorkoutStartupTrace.diag(
                "[WorkoutLifecycle] endAccepted source=\(reason) phase=ending->ending endTransactionID=\(endTransactionID?.uuidString ?? "none") workoutID=\(sessionID.uuidString) requestID=\(current.requestID?.uuidString ?? "none") accepted=false reason=duplicate"
            )
            return .duplicate
        default:
            return .rejectedIllegalTransition(from: previous, to: "ending")
        }

        phase = .ending(transaction)
        let endTransactionID = ensureEndTransactionID(sessionID: sessionID)
        PulsarWorkoutStartupTrace.diag(
            "[WorkoutLifecycle] endAccepted source=\(reason) phase=\(previous)->ending endTransactionID=\(endTransactionID.uuidString) workoutID=\(sessionID.uuidString) requestID=\(transaction.requestID?.uuidString ?? "none") accepted=true"
        )
        PulsarWorkoutLifecycleLogger.log(
            .finishRequested,
            sessionID: sessionID,
            requestID: transaction.requestID,
            workoutType: transaction.workoutType,
            source: reason,
            previousState: previous,
            nextState: phase.name
        )
        return .applied
    }

    func cancelCurrentStart(requestID: UUID?, source: String) {
        guard let transaction = phase.transaction else { return }
        if let requestID, transaction.requestID != requestID { return }
        let previous = phase.name
        // Retain .cancelled until UI acknowledges or a new start begins.
        phase = .cancelled(transaction)
        endWatchStartExecutionAssertionIfShared(reason: "cancelled")
        PulsarWorkoutLifecycleLogger.log(
            .workoutStartFailed,
            sessionID: transaction.sessionID,
            requestID: transaction.requestID,
            workoutType: transaction.workoutType,
            source: source,
            detail: "cancelled",
            previousState: previous,
            nextState: phase.name
        )
    }

    func resetForTesting() {
        endWatchStartExecutionAssertionIfShared(reason: "resetForTesting")
        phase = .idle
        didChooseIPhoneFallback = false
        handledAcknowledgementRequestIDs = []
        handledIdempotencyKeys = []
        reachedActiveSessionIDs = []
        endTransactionID = nil
        PulsarWorkoutHandshakeLogGate.setSuppressNonWorkoutDiagnostics(false)
    }

    private func beginWatchStartExecutionAssertionIfShared(reason: String) {
        PulsarWorkoutHandshakeLogGate.setSuppressNonWorkoutDiagnostics(true)
        guard self === PulsarWorkoutStartCoordinator.shared else { return }
        PulsarWatchStartExecutionAssertion.shared.begin(reason: reason)
    }

    private func endWatchStartExecutionAssertionIfShared(reason: String) {
        PulsarWorkoutHandshakeLogGate.setSuppressNonWorkoutDiagnostics(phase.isLoadingPresentation)
        guard self === PulsarWorkoutStartCoordinator.shared else { return }
        PulsarWatchStartExecutionAssertion.shared.end(reason: reason)
    }
}
