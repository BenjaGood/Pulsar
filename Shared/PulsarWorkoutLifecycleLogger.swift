//
//  PulsarWorkoutLifecycleLogger.swift
//  Pulsar
//

import Foundation
import os

enum PulsarWorkoutLifecycleEvent: String {
    case stateTransition
    case wcSend
    case wcReceive
    case wcAck
    case finishRequested
    case finishCompleted
    case finishFallback
    case workoutStartRequested
    case workoutStartValidated
    case workoutStartRejectedDuplicate
    case workoutHealthKitSessionCreated
    case workoutBuilderStarted
    case workoutWatchSyncRequested
    case workoutWatchSyncSucceeded
    case workoutWatchSyncFailed
    case workoutActivated
    case workoutStartFailed
    case workoutSessionCleanedUp
    case watchLaunchRequestSubmitted
    case watchLaunchRequestFailed
    case watchLaunchDecision
    case watchPrelaunchDurablyQueued
    case watchRecoveryAttempt
    case watchStartVerified
    case watchHealthKitMirroringStarted
    case watchHealthKitActivityStarted
    case watchAppHandlerInvoked
    case watchWorkoutSessionCreated
    case watchWorkoutSessionPrepared
    case watchWorkoutSessionRunning
    case watchAcknowledgementReceived
    case mirroredSessionReceived
    case firstHeartRateSampleReceived
    case routineSnapshotReceived
    case workoutStartTimedOut
    case summaryPresentationAttempted
    case summaryPresentationBlocked
    case staleFinishedIgnored
    case staleAcknowledgementIgnored
}

enum PulsarWorkoutLifecycleLogger {
    private static let logger = Logger(subsystem: "tech.aetherial.pulsar", category: "WorkoutLifecycle")

    static func log(
        _ event: PulsarWorkoutLifecycleEvent,
        sessionID: UUID? = nil,
        requestID: UUID? = nil,
        workoutType: String? = nil,
        source: String? = nil,
        detail: String? = nil,
        device: String? = nil,
        timestamp: Date = Date(),
        previousState: String? = nil,
        nextState: String? = nil,
        reachability: String? = nil,
        messageType: String? = nil,
        ackStatus: String? = nil,
        error: String? = nil,
        healthKitState: String? = nil,
        watchConnectivityState: String? = nil,
        transport: String? = nil,
        retryAttempt: Int? = nil,
        latencyMilliseconds: Int? = nil,
        role: String? = nil
    ) {
        var parts: [String] = [
            "event=\(event.rawValue)",
            "timestamp=\(timestamp.timeIntervalSince1970)"
        ]
        if let sessionID {
            parts.append("workoutID=\(sessionID.uuidString)")
        }
        if let requestID {
            parts.append("requestID=\(requestID.uuidString)")
        }
        if let workoutType, !workoutType.isEmpty {
            parts.append("type=\(workoutType)")
        }
        if let source, !source.isEmpty {
            parts.append("source=\(source)")
        }
        if let role, !role.isEmpty {
            parts.append("role=\(role)")
        }
        if let detail, !detail.isEmpty {
            parts.append("detail=\(detail)")
        }
        if let device, !device.isEmpty {
            parts.append("device=\(device)")
        }
        if let previousState, !previousState.isEmpty {
            parts.append("previousState=\(previousState)")
        }
        if let nextState, !nextState.isEmpty {
            parts.append("nextState=\(nextState)")
        }
        if let reachability, !reachability.isEmpty {
            parts.append("reachability=\(reachability)")
        }
        if let messageType, !messageType.isEmpty {
            parts.append("messageType=\(messageType)")
        }
        if let ackStatus, !ackStatus.isEmpty {
            parts.append("ackStatus=\(ackStatus)")
        }
        if let error, !error.isEmpty {
            parts.append("error=\(error)")
        }
        if let healthKitState, !healthKitState.isEmpty {
            parts.append("hkState=\(healthKitState)")
        }
        if let watchConnectivityState, !watchConnectivityState.isEmpty {
            parts.append("wcState=\(watchConnectivityState)")
        }
        if let transport, !transport.isEmpty {
            parts.append("transport=\(transport)")
        }
        if let retryAttempt {
            parts.append("retry=\(retryAttempt)")
        }
        if let latencyMilliseconds {
            parts.append("latencyMs=\(latencyMilliseconds)")
        }
        logger.log("\(parts.joined(separator: " "), privacy: .public)")
    }
}
