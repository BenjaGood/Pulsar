//
//  PulsarMirroredSessionIntake.swift
//  Pulsar
//

import Foundation
import HealthKit

/// Receives HealthKit mirrored sessions and installs a delegate before any
/// asynchronous routing hop. HealthKit can deliver data or disconnection
/// immediately; a received session must never sit delegate-less.
nonisolated final class PulsarMirroredSessionIntake: NSObject, HKWorkoutSessionDelegate, @unchecked Sendable {
    static let shared = PulsarMirroredSessionIntake()

    private let lock = NSLock()
    private var retainedSessions: [ObjectIdentifier: HKWorkoutSession] = [:]

    private override init() {
        super.init()
    }

    func accept(_ session: HKWorkoutSession) {
        let object = String(describing: ObjectIdentifier(session))
        let acceptedAt = Date()
        PulsarWorkoutStartupTrace.diag(
            "[MirrorIntake] received object=\(object) hkState=\(session.state.rawValue) \(PulsarWorkoutStartupTrace.threadTag())"
        )
        session.delegate = self
        lock.lock()
        retainedSessions[ObjectIdentifier(session)] = session
        lock.unlock()
        Task { @MainActor in
            PulsarWorkoutStartupTrace.diag(
                "[MirrorIntake] onMainActor object=\(object) hopMs=\(PulsarWorkoutStartupTrace.elapsedMs(since: acceptedAt)) hkState=\(session.state.rawValue) \(PulsarWorkoutStartupTrace.threadTag())"
            )
            PulsarWorkoutStartupTrace.phone("handler received mirror object=\(object) state=\(session.state.rawValue)")
            PulsarWorkoutStartupTrace.phone("provisional delegate installed object=\(object)")
            PulsarWorkoutMirroringCoordinator.shared.routeAcceptedSession(session)
        }
    }

    func relinquish(_ session: HKWorkoutSession) {
        lock.lock()
        retainedSessions[ObjectIdentifier(session)] = nil
        lock.unlock()
    }

    func retains(_ session: HKWorkoutSession) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return retainedSessions[ObjectIdentifier(session)] != nil
    }

    func resetForTesting() {
        lock.lock()
        retainedSessions.removeAll()
        lock.unlock()
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        let object = String(describing: ObjectIdentifier(workoutSession))
        Task { @MainActor in
            PulsarWorkoutStartupTrace.phone(
                "provisional delegate state changed object=\(object) from=\(fromState.rawValue) to=\(toState.rawValue)"
            )
            PulsarWorkoutMirroringCoordinator.shared.forwardIntakeStateChange(
                workoutSession,
                toState: toState,
                fromState: fromState,
                date: date
            )
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        let object = String(describing: ObjectIdentifier(workoutSession))
        Task { @MainActor in
            PulsarWorkoutStartupTrace.phone("provisional delegate failed object=\(object) error=\(error.localizedDescription)")
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didDisconnectFromRemoteDeviceWithError error: Error?
    ) {
        let object = String(describing: ObjectIdentifier(workoutSession))
        Task { @MainActor in
            PulsarWorkoutStartupTrace.phone(
                "provisional delegate disconnection object=\(object) error=\(error?.localizedDescription ?? "none")"
            )
            PulsarWorkoutMirroringCoordinator.shared.mirroredSessionDidDisconnect(
                workoutSession,
                error: error,
                source: "mirroredSessionIntake"
            )
        }
    }

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didReceiveDataFromRemoteWorkoutSession data: [Data]
    ) {
        let object = String(describing: ObjectIdentifier(workoutSession))
        Task { @MainActor in
            PulsarWorkoutStartupTrace.phone("provisional delegate received remote data object=\(object) count=\(data.count)")
            for (index, item) in data.enumerated() {
                if let acknowledgement = GymCrossDeviceCodec.decodeAcknowledgement(item) {
                    PulsarWorkoutStartupTrace.phone(
                        "remote payload object=\(object) index=\(index) messageType=gymStartAcknowledgement workoutID=\(acknowledgement.authoritativeSessionID.uuidString) requestID=\(acknowledgement.requestID.uuidString) candidate=\(acknowledgement.candidateSessionID.uuidString) sessionState=\(acknowledgement.sessionState.rawValue) source=healthKitRemote"
                    )
                } else if let snapshot = GymCrossDeviceCodec.decodeRoutineSnapshot(item) {
                    PulsarWorkoutStartupTrace.phone(
                        "remote payload object=\(object) index=\(index) messageType=gymRoutineSnapshotEnvelope workoutID=\(snapshot.sessionID.uuidString) requestID=\(snapshot.requestID.uuidString) source=healthKitRemote"
                    )
                } else {
                    PulsarWorkoutStartupTrace.phone(
                        "remote payload object=\(object) index=\(index) messageType=unknown byteCount=\(item.count) source=healthKitRemote"
                    )
                }
            }
            PulsarWorkoutMirroringCoordinator.shared.forwardIntakeRemoteData(workoutSession, data: data)
        }
    }
}
