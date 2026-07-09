//
//  PulsarHealthKitWorkoutSessionTeardown.swift
//  Pulsar
//

import Foundation
import HealthKit

enum PulsarHealthKitWorkoutSessionTeardown {
    static func stopAndEnd(
        _ session: HKWorkoutSession?,
        at date: Date = Date(),
        reason: String
    ) {
        guard let session else { return }

        switch session.state {
        case .running, .paused:
            session.stopActivity(with: date)
        case .notStarted, .prepared:
            break
        case .stopped, .ended:
            session.end()
            PulsarWorkoutLifecycleLogger.log(
                .workoutSessionCleanedUp,
                detail: "reason=\(reason) state=alreadyTerminal"
            )
            return
        @unknown default:
            break
        }

        session.end()
        PulsarWorkoutLifecycleLogger.log(
            .workoutSessionCleanedUp,
            detail: "reason=\(reason) state=\(describe(session.state))"
        )
    }

    private static func describe(_ state: HKWorkoutSessionState) -> String {
        switch state {
        case .notStarted:
            "notStarted"
        case .prepared:
            "prepared"
        case .running:
            "running"
        case .paused:
            "paused"
        case .stopped:
            "stopped"
        case .ended:
            "ended"
        @unknown default:
            "unknown(\(state.rawValue))"
        }
    }
}
