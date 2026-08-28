//
//  GymMirroredSessionBridge.swift
//  Pulsar
//

import Combine
import Foundation
import HealthKit

struct GymMirroredSessionSnapshot: Equatable, Sendable {
    var isAttached: Bool = false
    var isLive: Bool = false
    var sessionID: UUID?
    var startedAt: Date?
    var currentHeartRate: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var activeEnergyKilocalories: Double?

    static let empty = GymMirroredSessionSnapshot()

    var hasAttachedLiveMirror: Bool { isAttached && isLive }
}

/// App-lifetime gym mirror consumer. Survives LaunchFlow dismissal so mirrored
/// sessions are never ended solely because a transient start controller died.
/// Owns the iPhone mirrored `HKWorkoutSession` and its delegate. The Watch
/// remains the only workout builder/recording owner; app-specific live metrics
/// arrive through the existing workout transports.
@MainActor
final class GymMirroredSessionBridge: NSObject, ObservableObject, PulsarMirroredWorkoutSessionConsumer {
    static let shared = GymMirroredSessionBridge()

    @Published private(set) var snapshot = GymMirroredSessionSnapshot.empty

    private weak var activeController: GymCrossDeviceStartController?
    private var retainedSession: HKWorkoutSession?
    private var retainedDestination: PulsarMirroredWorkoutDestination?
    private var retentionTimeoutTask: Task<Void, Never>?
    private var didRegister = false

    static let pendingMirrorRetentionTimeout: TimeInterval = 45

    private override init() {
        super.init()
    }

    func initializeAtLaunch() {
        guard !didRegister else { return }
        didRegister = true
        PulsarWorkoutMirroringCoordinator.shared.registerGymConsumer(self)
        PulsarSyncDebugLogger.log("GymMirroredSessionBridge registered as app-lifetime gym mirror consumer")
    }

    func bind(controller: GymCrossDeviceStartController) {
        activeController = controller
        flushRetainedSessionIfPossible()
    }

    func unbind(controller: GymCrossDeviceStartController) {
        guard activeController === controller else { return }
        activeController = nil
    }

    func attachMirroredWorkoutSession(_ session: HKWorkoutSession, destination: PulsarMirroredWorkoutDestination) {
        guard case .gym = destination else {
            rejectMirroredWorkoutSession(session, reason: "unexpectedDestination")
            return
        }

        let object = PulsarWorkoutMirroringCoordinator.objectToken(session)
        if let retainedSession, retainedSession !== session {
            PulsarWorkoutStartupTrace.phone(
                "gym authoritative mirror replaced previous=\(PulsarWorkoutMirroringCoordinator.objectToken(retainedSession)) incoming=\(object)"
            )
            clearRetainedSession()
        }

        bindHealthKit(session, destination: destination)
        PulsarWorkoutStartupTrace.phone("gym authoritative mirror attached object=\(object)")
        PulsarMirroredSessionIntake.shared.relinquish(session)
        retentionTimeoutTask?.cancel()
        retentionTimeoutTask = nil

        if let activeController {
            activeController.attachMirroredSession(session)
            return
        }

        scheduleRetentionTimeout(for: session, destination: destination)
        PulsarSyncDebugLogger.log(
            "Gym mirrored session retained by app bridge until a start controller binds session=\(sessionID(for: destination)?.uuidString ?? "none") object=\(object)"
        )
    }

    func rejectMirroredWorkoutSession(_ session: HKWorkoutSession, reason: String) {
        let destination = retainedDestination
        let requestID = requestID(for: destination)
        let sessionID = sessionID(for: destination)

        guard Self.shouldEndMirroredSession(
            reason: reason,
            requestID: requestID,
            sessionID: sessionID
        ) else {
            PulsarWorkoutLifecycleLogger.log(
                .mirroredSessionReceived,
                sessionID: sessionID,
                requestID: requestID,
                source: "GymMirroredSessionBridge.reject",
                detail: "rejectDeferred reason=\(reason)",
                healthKitState: "\(session.state.rawValue)",
                transport: "healthKit"
            )
            PulsarSyncDebugLogger.log("Gym mirrored session reject deferred reason=\(reason)")
            return
        }

        PulsarHealthKitWorkoutSessionTeardown.stopAndEnd(session, reason: "gymMirrorRejected.\(reason)")
        if retainedSession === session {
            PulsarWorkoutMirroringCoordinator.shared.releaseMirroredSession(
                session,
                reason: "gymBridge.rejected.\(reason)"
            )
            clearRetainedSession()
        }
        PulsarSyncDebugLogger.log("Gym mirrored session rejected reason=\(reason)")
    }

    func handleMirroredRemoteData(_ session: HKWorkoutSession, data: [Data]) {
        guard retainedSession === session || retainedSession == nil else { return }
        for item in data {
            if let acknowledgement = GymCrossDeviceCodec.decodeAcknowledgement(item) {
                activeController?.handleWatchAcknowledgement(
                    acknowledgement,
                    source: "healthKitRemoteAcknowledgement"
                )
            } else if let metrics = GymCrossDeviceCodec.decodeMirroredMetrics(item),
                      snapshot.sessionID == nil || snapshot.sessionID == metrics.sessionID {
                snapshot.currentHeartRate = metrics.currentHeartRate
                snapshot.averageHeartRate = metrics.averageHeartRate
                snapshot.maxHeartRate = metrics.maxHeartRate
                snapshot.activeEnergyKilocalories = metrics.activeEnergyKilocalories
                PulsarWorkoutStartupTrace.count("[PublishRate] mirroredSnapshot")
                if metrics.currentHeartRate != nil {
                    PulsarWorkoutStartupTrace.count("[PublishRate] heartRate")
                }
            }
        }
    }

    func handleMirroredStateChange(
        _ session: HKWorkoutSession,
        toState: HKWorkoutSessionState,
        fromState: HKWorkoutSessionState,
        date: Date
    ) {
        applyMirroredStateChange(session, toState: toState, fromState: fromState, date: date)
    }

    func resetForTesting() {
        retentionTimeoutTask?.cancel()
        retentionTimeoutTask = nil
        activeController = nil
        retainedSession = nil
        retainedDestination = nil
        snapshot = .empty
        didRegister = false
    }

    private func bindHealthKit(_ session: HKWorkoutSession, destination: PulsarMirroredWorkoutDestination) {
        let object = PulsarWorkoutMirroringCoordinator.objectToken(session)
        if let existing = retainedSession, existing !== session {
            PulsarWorkoutStartupTrace.phone(
                "gym bind refused to replace authoritative object=\(PulsarWorkoutMirroringCoordinator.objectToken(existing)) incoming=\(object)"
            )
            return
        }

        session.delegate = self
        PulsarWorkoutStartupTrace.phone("delegate assigned object=\(object)")
        PulsarWorkoutStartupTrace.phone("delegate installed gym mirrored session object=\(object)")

        retainedSession = session
        retainedDestination = destination
        snapshot = GymMirroredSessionSnapshot(
            isAttached: true,
            isLive: Self.isLiveSessionState(session.state),
            sessionID: sessionID(for: destination),
            startedAt: session.startDate,
            currentHeartRate: snapshot.currentHeartRate,
            averageHeartRate: snapshot.averageHeartRate,
            maxHeartRate: snapshot.maxHeartRate,
            activeEnergyKilocalories: snapshot.activeEnergyKilocalories
        )
        PulsarWorkoutStartupTrace.count("[PublishRate] mirroredSnapshot")
        PulsarWorkoutStartupTrace.phone("mirrored session retained gym live=\(snapshot.isLive) object=\(object)")
        PulsarSyncDebugLogger.log(
            "Gym mirrored session HealthKit bound state=\(session.state.rawValue) session=\(sessionID(for: destination)?.uuidString ?? "none")"
        )
        if snapshot.isLive {
            activeController?.markLiveFromMirroredSessionIfEligible()
        }
    }

    private func flushRetainedSessionIfPossible() {
        guard let activeController,
              let retainedSession,
              let retainedDestination else { return }
        retentionTimeoutTask?.cancel()
        retentionTimeoutTask = nil
        activeController.attachMirroredSession(retainedSession)
        PulsarSyncDebugLogger.log(
            "Gym mirrored session flushed from app bridge to start controller session=\(sessionID(for: retainedDestination)?.uuidString ?? "none")"
        )
    }

    private func scheduleRetentionTimeout(
        for session: HKWorkoutSession,
        destination: PulsarMirroredWorkoutDestination
    ) {
        retentionTimeoutTask?.cancel()
        let requestID = requestID(for: destination)
        let sessionID = sessionID(for: destination)
        guard Self.shouldEndMirroredSession(
            reason: "timeout",
            requestID: requestID,
            sessionID: sessionID
        ) else {
            PulsarSyncDebugLogger.log(
                "Gym mirrored session has no launch identity; retaining until HealthKit reports a terminal state object=\(PulsarWorkoutMirroringCoordinator.objectToken(session))"
            )
            return
        }
        retentionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(Self.pendingMirrorRetentionTimeout * 1_000_000_000)
            )
            await MainActor.run {
                guard let self,
                      self.retainedSession === session,
                      self.activeController == nil else { return }
                PulsarWorkoutLifecycleLogger.log(
                    .workoutSessionCleanedUp,
                    sessionID: sessionID,
                    requestID: requestID,
                    source: "GymMirroredSessionBridge.retentionTimeout",
                    detail: "unclaimedMirroredGymSession"
                )
                PulsarHealthKitWorkoutSessionTeardown.stopAndEnd(
                    session,
                    reason: "gymMirrorRetentionTimeout"
                )
                PulsarWorkoutMirroringCoordinator.shared.releaseMirroredSession(
                    session,
                    reason: "gymBridge.retentionTimeout"
                )
                self.clearRetainedSession()
            }
        }
    }

    private func clearRetainedSession() {
        retentionTimeoutTask?.cancel()
        retentionTimeoutTask = nil
        retainedSession = nil
        retainedDestination = nil
        snapshot = .empty
    }

    private func requestID(for destination: PulsarMirroredWorkoutDestination?) -> UUID? {
        guard case .gym(let requestID, _) = destination else { return nil }
        return requestID
    }

    private func sessionID(for destination: PulsarMirroredWorkoutDestination?) -> UUID? {
        guard case .gym(_, let sessionID) = destination else { return nil }
        return sessionID
    }

    private func applyMirroredStateChange(
        _ workoutSession: HKWorkoutSession,
        toState: HKWorkoutSessionState,
        fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard retainedSession === workoutSession else { return }
        snapshot.isLive = Self.isLiveSessionState(toState)
        PulsarWorkoutStartupTrace.phone(
            "mirrored state changed gym from=\(fromState.rawValue) to=\(toState.rawValue) object=\(PulsarWorkoutMirroringCoordinator.objectToken(workoutSession))"
        )
        if snapshot.startedAt == nil {
            snapshot.startedAt = workoutSession.startDate ?? date
        }
        if snapshot.isLive {
            activeController?.markLiveFromMirroredSessionIfEligible()
        }
        PulsarSyncDebugLogger.log(
            "Gym mirrored session state from=\(fromState.rawValue) to=\(toState.rawValue)"
        )
        if PulsarWorkoutMirroringCoordinator.isTerminalMirroredSessionState(toState) {
            let finishedSessionID = snapshot.sessionID ?? sessionID(for: retainedDestination)
            if let finishedSessionID {
                // Publish terminal truth while the authoritative mirror and its
                // last metrics are still attached. Cleanup must never be the
                // first observable consequence of a successful finish.
        PulsarWatchConnectivitySyncStore.shared.confirmGymFinishFromMirroredHealthKit(
            sessionID: finishedSessionID,
            healthKitSessionStateRawValue: toState.rawValue,
            confirmedAt: date,
            source: "gymMirroredHealthKit.\(toState.rawValue)"
        )
        PulsarWorkoutStartupTrace.diag(
            "[HealthKit] sessionEnded gym workoutID=\(finishedSessionID.uuidString) from=\(fromState.rawValue) to=\(toState.rawValue) \(PulsarWorkoutStartupTrace.threadTag())"
        )
            }
            PulsarWorkoutStartupTrace.phone(
                "gym mirrored session released after terminal state object=\(PulsarWorkoutMirroringCoordinator.objectToken(workoutSession))"
            )
            PulsarWorkoutMirroringCoordinator.shared.releaseMirroredSession(
                workoutSession,
                reason: "gymBridge.\(toState.rawValue)"
            )
            clearRetainedSession()
            if let finishedSessionID {
                PulsarWorkoutStartupTrace.lifecycle(
                    "[GymFinish] workoutID=\(finishedSessionID.uuidString) HKState=\(toState.rawValue) terminalKnown=true mirrorReleased=true finishResult=success presentation=terminal"
                )
            }
        }
    }

    private static func isLiveSessionState(_ state: HKWorkoutSessionState) -> Bool {
        switch state {
        case .running, .paused, .prepared, .notStarted:
            true
        case .stopped, .ended:
            false
        @unknown default:
            true
        }
    }

    /// Ends a mirrored session only when the reject is intentional and tied to
    /// a known launch attempt. Unmatched/unknown rejects are deferred.
    static func shouldEndMirroredSession(
        reason: String,
        requestID: UUID?,
        sessionID: UUID?
    ) -> Bool {
        let normalized = reason.lowercased()
        if normalized.contains("unexpecteddestination") {
            return false
        }
        if normalized.contains("timeout") || normalized.contains("explicit") {
            return requestID != nil || sessionID != nil
        }
        return requestID != nil || sessionID != nil
    }
}

extension GymMirroredSessionBridge: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            self.applyMirroredStateChange(workoutSession, toState: toState, fromState: fromState, date: date)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            PulsarSyncDebugLogger.log("Gym mirrored session failed error=\(error.localizedDescription)")
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didDisconnectFromRemoteDeviceWithError error: Error?
    ) {
        Task { @MainActor in
            guard self.retainedSession === workoutSession else { return }
            PulsarSyncDebugLogger.log(
                "Gym mirrored session disconnected error=\(error?.localizedDescription ?? "none") action=awaitReplacement"
            )
            PulsarWorkoutMirroringCoordinator.shared.mirroredSessionDidDisconnect(
                workoutSession,
                error: error,
                source: "gymMirrorOwner"
            )
            self.activeController?.authoritativeMirrorDidDisconnect()
            self.clearRetainedSession()
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didReceiveDataFromRemoteWorkoutSession data: [Data]
    ) {
        Task { @MainActor in
            self.handleMirroredRemoteData(workoutSession, data: data)
        }
    }
}
