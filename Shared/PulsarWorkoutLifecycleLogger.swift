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
}

enum PulsarWorkoutLifecycleLogger {
    private static let logger = Logger(subsystem: "tech.aetherial.pulsar", category: "WorkoutLifecycle")

    static func log(
        _ event: PulsarWorkoutLifecycleEvent,
        sessionID: UUID? = nil,
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
        error: String? = nil
    ) {
        var parts: [String] = [
            "event=\(event.rawValue)",
            "timestamp=\(timestamp.timeIntervalSince1970)"
        ]
        if let sessionID {
            parts.append("workoutID=\(sessionID.uuidString)")
        }
        if let workoutType, !workoutType.isEmpty {
            parts.append("type=\(workoutType)")
        }
        if let source, !source.isEmpty {
            parts.append("source=\(source)")
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
        logger.log("\(parts.joined(separator: " "), privacy: .public)")
    }
}
