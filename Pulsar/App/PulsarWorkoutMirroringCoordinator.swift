//
//  PulsarWorkoutMirroringCoordinator.swift
//  Pulsar
//

import Foundation
import HealthKit

enum PulsarMirroredWorkoutDestination: Equatable {
    case run(PulsarOutdoorWorkoutKind)
    case gym(requestID: UUID?, sessionID: UUID?)
    case unknown
}

enum PulsarMirrorAttachmentDecision: Equatable {
    case attach
    case duplicate
    case replace(previous: ObjectIdentifier)
}

@MainActor
protocol PulsarMirroredWorkoutSessionConsumer: AnyObject {
    func attachMirroredWorkoutSession(_ session: HKWorkoutSession, destination: PulsarMirroredWorkoutDestination)
    func rejectMirroredWorkoutSession(_ session: HKWorkoutSession, reason: String)
    func handleMirroredRemoteData(_ session: HKWorkoutSession, data: [Data])
    func handleMirroredStateChange(
        _ session: HKWorkoutSession,
        toState: HKWorkoutSessionState,
        fromState: HKWorkoutSessionState,
        date: Date
    )
}

extension PulsarMirroredWorkoutSessionConsumer {
    func handleMirroredRemoteData(_ session: HKWorkoutSession, data: [Data]) {}
    func handleMirroredStateChange(
        _ session: HKWorkoutSession,
        toState: HKWorkoutSessionState,
        fromState: HKWorkoutSessionState,
        date: Date
    ) {}
}

@MainActor
final class PulsarWorkoutMirroringCoordinator {
    static let shared = PulsarWorkoutMirroringCoordinator()

    static let unmatchedMirrorRetentionTimeout: TimeInterval = 45

    private let healthStore = HKHealthStore()
    private weak var runConsumer: PulsarMirroredWorkoutSessionConsumer?
    private weak var gymConsumer: PulsarMirroredWorkoutSessionConsumer?

    private var pendingGymRequestID: UUID?
    private var pendingGymSessionID: UUID?
    private var pendingGymMirroredSession: HKWorkoutSession?
    private var pendingGymMirroredDestination: PulsarMirroredWorkoutDestination?
    private var pendingRunMirroredSession: HKWorkoutSession?
    private var pendingRunMirroredDestination: PulsarMirroredWorkoutDestination?
    private var pendingUnknownMirroredSession: HKWorkoutSession?
    private var unmatchedRetentionTimeoutTask: Task<Void, Never>?
    private var attachedMirroredSessionIDs = Set<ObjectIdentifier>()
    private var authoritativeGymMirrorID: ObjectIdentifier?
    private var authoritativeRunMirrorID: ObjectIdentifier?
    private var didRegisterHandler = false

    private init() {}

    static func objectToken(_ session: HKWorkoutSession) -> String {
        String(describing: ObjectIdentifier(session))
    }

    static func attachmentDecision(
        existingAuthoritative: ObjectIdentifier?,
        incoming: ObjectIdentifier
    ) -> PulsarMirrorAttachmentDecision {
        guard let existingAuthoritative else { return .attach }
        if existingAuthoritative == incoming { return .duplicate }
        return .replace(previous: existingAuthoritative)
    }

    static func isTerminalMirroredSessionState(_ state: HKWorkoutSessionState) -> Bool {
        switch state {
        case .stopped, .ended:
            true
        case .notStarted, .prepared, .running, .paused:
            false
        @unknown default:
            false
        }
    }

    func initializeAtLaunch() {
        guard !didRegisterHandler else { return }
        didRegisterHandler = true
        healthStore.workoutSessionMirroringStartHandler = { mirroredSession in
            PulsarMirroredSessionIntake.shared.accept(mirroredSession)
        }
        PulsarSyncDebugLogger.log("PulsarWorkoutMirroringCoordinator registered workoutSessionMirroringStartHandler")
    }

    func registerRunConsumer(_ consumer: PulsarMirroredWorkoutSessionConsumer) {
        runConsumer = consumer
        if let pendingRunMirroredSession,
           let pendingRunMirroredDestination {
            deliverToRunConsumer(pendingRunMirroredSession, destination: pendingRunMirroredDestination)
            self.pendingRunMirroredSession = nil
            self.pendingRunMirroredDestination = nil
            cancelUnmatchedRetentionTimeoutIfIdle()
        }
    }

    func registerGymConsumer(_ consumer: PulsarMirroredWorkoutSessionConsumer) {
        gymConsumer = consumer
        if let pendingGymMirroredSession,
           let pendingGymMirroredDestination {
            deliverToGymConsumer(pendingGymMirroredSession, destination: pendingGymMirroredDestination)
            self.pendingGymMirroredSession = nil
            self.pendingGymMirroredDestination = nil
            cancelUnmatchedRetentionTimeoutIfIdle()
        }
    }

    func setPendingGymMirroring(requestID: UUID, sessionID: UUID) {
        pendingGymRequestID = requestID
        pendingGymSessionID = sessionID
    }

    func clearPendingGymMirroring(requestID: UUID? = nil) {
        if let requestID, pendingGymRequestID != requestID { return }
        pendingGymRequestID = nil
        pendingGymSessionID = nil
    }

    func routeAcceptedSession(_ session: HKWorkoutSession) {
        routeMirroredSession(session)
    }

    /// HealthKit invalidates a mirrored session after a remote disconnect and
    /// reconnects by delivering a new object through the start handler.
    func mirroredSessionDidDisconnect(
        _ session: HKWorkoutSession,
        error: Error?,
        source: String
    ) {
        releaseMirroredSession(session, reason: "\(source).disconnected")
        PulsarWorkoutStartupTrace.phone(
            "mirrored session invalidated after remote disconnect object=\(Self.objectToken(session)) source=\(source) error=\(error?.localizedDescription ?? "none")"
        )
    }

    func forwardIntakeRemoteData(_ session: HKWorkoutSession, data: [Data]) {
        consumer(for: session)?.handleMirroredRemoteData(session, data: data)
    }

    func forwardIntakeStateChange(
        _ session: HKWorkoutSession,
        toState: HKWorkoutSessionState,
        fromState: HKWorkoutSessionState,
        date: Date
    ) {
        consumer(for: session)?.handleMirroredStateChange(
            session,
            toState: toState,
            fromState: fromState,
            date: date
        )
        if Self.isTerminalMirroredSessionState(toState) {
            releaseMirroredSession(session, reason: "healthKitState.\(toState.rawValue)")
        }
    }

    private func routeMirroredSession(_ session: HKWorkoutSession) {
        let sessionIdentifier = ObjectIdentifier(session)
        let object = Self.objectToken(session)
        let destination = resolveDestination(for: session.workoutConfiguration)
        let isRepeatCallback = attachedMirroredSessionIDs.contains(sessionIdentifier)
        let workoutID = pendingGymSessionID ?? destinationSessionID(destination)
        let requestID = pendingGymRequestID ?? destinationRequestID(destination)
        PulsarWorkoutStartupTrace.phone(
            "[MirrorReceived] mirroredObject=\(object) workoutID=\(workoutID?.uuidString ?? "none") requestID=\(requestID?.uuidString ?? "none") activity=\(session.workoutConfiguration.activityType.rawValue) destination=\(Self.destinationLabel(destination)) repeat=\(isRepeatCallback)"
        )
        PulsarWorkoutStartupTrace.diag(
            "[MirrorReceived] object=\(object) workoutID=\(workoutID?.uuidString ?? "none") requestID=\(requestID?.uuidString ?? "none") destination=\(Self.destinationLabel(destination)) repeat=\(isRepeatCallback) hkState=\(session.state.rawValue) \(PulsarWorkoutStartupTrace.threadTag())"
        )

        PulsarWorkoutLifecycleLogger.log(
            .mirroredSessionReceived,
            sessionID: pendingGymSessionID ?? destinationSessionID(destination),
            requestID: pendingGymRequestID ?? destinationRequestID(destination),
            source: "workoutSessionMirroringStartHandler",
            detail: isRepeatCallback ? "repeatCallback object=\(object)" : "firstCallback object=\(object)",
            healthKitState: "\(session.state.rawValue)",
            transport: "healthKit"
        )

        switch destination {
        case .run(let workoutKind):
            if let transaction = PulsarWorkoutStartCoordinator.shared.currentTransaction {
                _ = PulsarWorkoutStartCoordinator.shared.markMirroredSessionReceived(
                    sessionID: transaction.authoritativeSessionID ?? transaction.sessionID,
                    requestID: transaction.requestID,
                    source: "mirroringCoordinator"
                )
            }
            if runConsumer != nil {
                deliverToRunConsumer(session, destination: .run(workoutKind))
            } else {
                retainUnmatchedSession(
                    session,
                    destination: .run(workoutKind),
                    kind: .run
                )
            }
        case .gym(let requestID, let sessionID):
            if let transaction = PulsarWorkoutStartCoordinator.shared.currentTransaction {
                _ = PulsarWorkoutStartCoordinator.shared.markMirroredSessionReceived(
                    sessionID: sessionID ?? transaction.sessionID,
                    requestID: requestID ?? transaction.requestID,
                    source: "mirroringCoordinator"
                )
            }
            if gymConsumer != nil {
                deliverToGymConsumer(
                    session,
                    destination: .gym(requestID: requestID, sessionID: sessionID)
                )
            } else if runConsumer != nil, isOutdoorConfiguration(session.workoutConfiguration) {
                let workoutKind = PulsarOutdoorWorkoutKind(
                    activityType: session.workoutConfiguration.activityType,
                    locationType: session.workoutConfiguration.locationType
                )
                deliverToRunConsumer(session, destination: .run(workoutKind))
            } else {
                retainUnmatchedSession(
                    session,
                    destination: .gym(requestID: requestID, sessionID: sessionID),
                    kind: .gym
                )
            }
        case .unknown:
            retainUnmatchedSession(session, destination: .unknown, kind: .unknown)
        }
    }

    private func deliverToGymConsumer(
        _ session: HKWorkoutSession,
        destination: PulsarMirroredWorkoutDestination
    ) {
        let incoming = ObjectIdentifier(session)
        let object = Self.objectToken(session)
        let decision = Self.attachmentDecision(
            existingAuthoritative: authoritativeGymMirrorID,
            incoming: incoming
        )
        if decision == .duplicate {
            PulsarWorkoutStartupTrace.phone(
                "duplicate gym mirror callback ignored object=\(object)"
            )
            PulsarMirroredSessionIntake.shared.relinquish(session)
            return
        }
        guard let gymConsumer else { return }
        if case .replace(let previous) = decision {
            attachedMirroredSessionIDs.remove(previous)
            PulsarWorkoutStartupTrace.phone(
                "replacement gym mirror accepted previous=\(String(describing: previous)) incoming=\(object)"
            )
        }
        PulsarWorkoutStartupTrace.phone("mirror routed gym object=\(object)")
        gymConsumer.attachMirroredWorkoutSession(session, destination: destination)
        attachedMirroredSessionIDs.insert(incoming)
        authoritativeGymMirrorID = incoming
        if case .gym(let requestID, let sessionID) = destination,
           (requestID == nil || requestID == pendingGymRequestID),
           (sessionID == nil || sessionID == pendingGymSessionID) {
            clearPendingGymMirroring(requestID: requestID)
        }
        PulsarMirroredSessionIntake.shared.relinquish(session)
    }

    private func deliverToRunConsumer(
        _ session: HKWorkoutSession,
        destination: PulsarMirroredWorkoutDestination
    ) {
        let incoming = ObjectIdentifier(session)
        let object = Self.objectToken(session)
        let decision = Self.attachmentDecision(
            existingAuthoritative: authoritativeRunMirrorID,
            incoming: incoming
        )
        if decision == .duplicate {
            PulsarWorkoutStartupTrace.phone(
                "duplicate run mirror callback ignored object=\(object)"
            )
            PulsarMirroredSessionIntake.shared.relinquish(session)
            return
        }
        guard let runConsumer else { return }
        if case .replace(let previous) = decision {
            attachedMirroredSessionIDs.remove(previous)
            PulsarWorkoutStartupTrace.phone(
                "replacement run mirror accepted previous=\(String(describing: previous)) incoming=\(object)"
            )
        }
        PulsarWorkoutStartupTrace.phone("mirror routed run object=\(object)")
        runConsumer.attachMirroredWorkoutSession(session, destination: destination)
        attachedMirroredSessionIDs.insert(incoming)
        authoritativeRunMirrorID = incoming
        PulsarMirroredSessionIntake.shared.relinquish(session)
    }

    func releaseMirroredSession(_ session: HKWorkoutSession, reason: String) {
        let identifier = ObjectIdentifier(session)
        let object = Self.objectToken(session)
        var releasedDestination = "unmatched"

        if authoritativeGymMirrorID == identifier {
            authoritativeGymMirrorID = nil
            releasedDestination = "gym"
        }
        if authoritativeRunMirrorID == identifier {
            authoritativeRunMirrorID = nil
            releasedDestination = "run"
        }
        attachedMirroredSessionIDs.remove(identifier)
        PulsarMirroredSessionIntake.shared.relinquish(session)
        PulsarWorkoutStartupTrace.phone(
            "authoritative mirror released destination=\(releasedDestination) object=\(object) reason=\(reason)"
        )
    }

    private func consumer(for session: HKWorkoutSession) -> PulsarMirroredWorkoutSessionConsumer? {
        let identifier = ObjectIdentifier(session)
        if identifier == authoritativeGymMirrorID {
            return gymConsumer
        }
        if identifier == authoritativeRunMirrorID {
            return runConsumer
        }
        return gymConsumer ?? runConsumer
    }

    private enum PendingMirrorKind {
        case run
        case gym
        case unknown
    }

    private func retainUnmatchedSession(
        _ session: HKWorkoutSession,
        destination: PulsarMirroredWorkoutDestination,
        kind: PendingMirrorKind
    ) {
        let object = Self.objectToken(session)
        switch kind {
        case .run:
            if let pendingRunMirroredSession, pendingRunMirroredSession !== session {
                PulsarWorkoutStartupTrace.phone(
                    "pending run mirror kept previous object=\(Self.objectToken(pendingRunMirroredSession)) incoming=\(object)"
                )
            } else {
                pendingRunMirroredSession = session
                pendingRunMirroredDestination = destination
            }
        case .gym:
            if let pendingGymMirroredSession, pendingGymMirroredSession !== session {
                PulsarWorkoutStartupTrace.phone(
                    "pending gym mirror kept previous object=\(Self.objectToken(pendingGymMirroredSession)) incoming=\(object)"
                )
            } else {
                pendingGymMirroredSession = session
                pendingGymMirroredDestination = destination
            }
        case .unknown:
            if let pendingUnknownMirroredSession, pendingUnknownMirroredSession !== session {
                PulsarWorkoutStartupTrace.phone(
                    "pending unknown mirror kept previous object=\(Self.objectToken(pendingUnknownMirroredSession)) incoming=\(object)"
                )
            } else {
                pendingUnknownMirroredSession = session
            }
        }

        PulsarWorkoutStartupTrace.phone("mirrored session retained pendingRoute object=\(object) kind=\(String(describing: kind))")
        PulsarSyncDebugLogger.log(
            "Mirrored session retained until consumer/policy resolves kind=\(String(describing: kind)) session=\(destinationSessionID(destination)?.uuidString ?? "none") object=\(object)"
        )
        scheduleUnmatchedRetentionTimeoutIfNeeded()
    }

    private func scheduleUnmatchedRetentionTimeoutIfNeeded() {
        guard unmatchedRetentionTimeoutTask == nil else { return }
        unmatchedRetentionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(Self.unmatchedMirrorRetentionTimeout * 1_000_000_000)
            )
            await MainActor.run {
                self?.expireUnmatchedRetainedSessions()
            }
        }
    }

    private func cancelUnmatchedRetentionTimeoutIfIdle() {
        guard pendingRunMirroredSession == nil,
              pendingGymMirroredSession == nil,
              pendingUnknownMirroredSession == nil else { return }
        unmatchedRetentionTimeoutTask?.cancel()
        unmatchedRetentionTimeoutTask = nil
    }

    private func expireUnmatchedRetainedSessions() {
        unmatchedRetentionTimeoutTask = nil

        if let pendingGymMirroredSession {
            let destination = pendingGymMirroredDestination
            let requestID = destinationRequestID(destination) ?? pendingGymRequestID
            let sessionID = destinationSessionID(destination) ?? pendingGymSessionID
            PulsarWorkoutLifecycleLogger.log(
                .workoutSessionCleanedUp,
                sessionID: sessionID,
                requestID: requestID,
                source: "mirroringCoordinator.retentionTimeout",
                detail: "unclaimedGymMirror"
            )
            if GymMirroredSessionBridge.shouldEndMirroredSession(
                reason: "timeout",
                requestID: requestID,
                sessionID: sessionID
            ) {
                PulsarHealthKitWorkoutSessionTeardown.stopAndEnd(
                    pendingGymMirroredSession,
                    reason: "unclaimedGymMirrorTimeout"
                )
            }
            PulsarMirroredSessionIntake.shared.relinquish(pendingGymMirroredSession)
            self.pendingGymMirroredSession = nil
            self.pendingGymMirroredDestination = nil
        }

        if let pendingRunMirroredSession {
            PulsarWorkoutLifecycleLogger.log(
                .workoutSessionCleanedUp,
                source: "mirroringCoordinator.retentionTimeout",
                detail: "unclaimedRunMirror"
            )
            PulsarHealthKitWorkoutSessionTeardown.stopAndEnd(
                pendingRunMirroredSession,
                reason: "unclaimedRunMirrorTimeout"
            )
            PulsarMirroredSessionIntake.shared.relinquish(pendingRunMirroredSession)
            self.pendingRunMirroredSession = nil
            self.pendingRunMirroredDestination = nil
        }

        if let pendingUnknownMirroredSession {
            PulsarWorkoutLifecycleLogger.log(
                .workoutSessionCleanedUp,
                source: "mirroringCoordinator.retentionTimeout",
                detail: "unknownMirrorDeferred"
            )
            PulsarHealthKitWorkoutSessionTeardown.stopAndEnd(
                pendingUnknownMirroredSession,
                reason: "unknownMirrorTimeout"
            )
            PulsarMirroredSessionIntake.shared.relinquish(pendingUnknownMirroredSession)
            self.pendingUnknownMirroredSession = nil
        }
    }

    private func resolveDestination(for configuration: HKWorkoutConfiguration) -> PulsarMirroredWorkoutDestination {
        let inferredOutdoor = PulsarOutdoorWorkoutKind(
            activityType: configuration.activityType,
            locationType: configuration.locationType
        )

        if inferredOutdoor != .strength {
            return .run(inferredOutdoor)
        }

        if let pendingGymRequestID, let pendingGymSessionID {
            return .gym(requestID: pendingGymRequestID, sessionID: pendingGymSessionID)
        }

        let workoutLifecycle = PulsarWorkoutStartCoordinator.shared
        if workoutLifecycle.phase.isInProgress,
           let transaction = workoutLifecycle.currentTransaction,
           transaction.kind == .watchGym {
            return .gym(
                requestID: transaction.requestID,
                sessionID: transaction.authoritativeSessionID ?? transaction.sessionID
            )
        }

        return .gym(requestID: nil, sessionID: nil)
    }

    private func isOutdoorConfiguration(_ configuration: HKWorkoutConfiguration) -> Bool {
        PulsarOutdoorWorkoutKind(
            activityType: configuration.activityType,
            locationType: configuration.locationType
        ) != .strength
    }

    private func destinationRequestID(_ destination: PulsarMirroredWorkoutDestination?) -> UUID? {
        guard case .gym(let requestID, _) = destination else { return nil }
        return requestID
    }

    private func destinationSessionID(_ destination: PulsarMirroredWorkoutDestination?) -> UUID? {
        guard case .gym(_, let sessionID) = destination else { return nil }
        return sessionID
    }

    private static func destinationLabel(_ destination: PulsarMirroredWorkoutDestination) -> String {
        switch destination {
        case .gym:
            "gym"
        case .run(let workoutKind):
            "run.\(workoutKind.rawValue)"
        case .unknown:
            "unknown"
        }
    }

    func resetForTesting() {
        unmatchedRetentionTimeoutTask?.cancel()
        unmatchedRetentionTimeoutTask = nil
        attachedMirroredSessionIDs = []
        authoritativeGymMirrorID = nil
        authoritativeRunMirrorID = nil
        pendingGymRequestID = nil
        pendingGymSessionID = nil
        pendingGymMirroredSession = nil
        pendingGymMirroredDestination = nil
        pendingRunMirroredSession = nil
        pendingRunMirroredDestination = nil
        pendingUnknownMirroredSession = nil
        PulsarMirroredSessionIntake.shared.resetForTesting()
    }
}
