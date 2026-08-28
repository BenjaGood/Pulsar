//
//  WatchRunAppDelegate.swift
//  Pulsar Watch App Watch App
//

import HealthKit
import WatchKit

final class WatchRunAppDelegate: NSObject, WKApplicationDelegate {
    private let healthStore = HKHealthStore()

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            let destination = destination(for: workoutConfiguration)
            let managerName = destination == .gym ? "WatchGymSessionManager" : "WatchRunSessionManager"
            PulsarWorkoutStartupTrace.watch(
                "handle configuration activity=\(workoutConfiguration.activityType.rawValue) location=\(workoutConfiguration.locationType.rawValue) handler=WatchRunAppDelegate manager=\(managerName) selected=\(destination == .gym ? "gym" : "run")"
            )
            PulsarWorkoutStartupTrace.diag(
                "[HandleConfiguration] activity=\(workoutConfiguration.activityType.rawValue) destination=\(destination == .gym ? "gym" : "run") \(PulsarWorkoutStartupTrace.threadTag())"
            )
            PulsarWorkoutLifecycleLogger.log(
                .watchAppHandlerInvoked,
                source: "WatchRunAppDelegate.handle",
                detail: "activity=\(workoutConfiguration.activityType.rawValue) manager=\(managerName)",
                role: "watch"
            )
            switch destination {
            case .gym:
                await WatchGymSessionManager.shared.startFromCompanion(configuration: workoutConfiguration)
            case .run:
                await WatchRunSessionManager.shared.startRunFromCompanion(configuration: workoutConfiguration)
            }
        }
    }

    func handleActiveWorkoutRecovery() {
        PulsarWorkoutStartupTrace.watch("recovery invoked source=handleActiveWorkoutRecovery")
        healthStore.recoverActiveWorkoutSession { recoveredSession, error in
            Task { @MainActor in
                if let error {
                    PulsarWorkoutStartupTrace.watch("recovery failed error=\(error.localizedDescription)")
                    PulsarSyncDebugLogger.log("Watch active workout recovery failed error=\(error.localizedDescription)")
                    return
                }

                guard let recoveredSession else {
                    PulsarWorkoutStartupTrace.watch("recovery returned no session")
                    PulsarSyncDebugLogger.log("Watch active workout recovery returned no session")
                    return
                }

                let destination = self.destination(for: recoveredSession.workoutConfiguration)
                PulsarWorkoutStartupTrace.watch(
                    "recovery session object=\(String(describing: ObjectIdentifier(recoveredSession))) activity=\(recoveredSession.workoutConfiguration.activityType.rawValue) manager=\(destination == .gym ? "WatchGymSessionManager" : "WatchRunSessionManager")"
                )
                switch destination {
                case .gym:
                    WatchGymSessionManager.shared.recoverActiveWorkoutSession(recoveredSession)
                case .run:
                    WatchRunSessionManager.shared.recoverActiveWorkoutSession(recoveredSession)
                }
            }
        }
    }

    private enum WorkoutDestination {
        case run
        case gym
    }

    @MainActor
    private func destination(for configuration: HKWorkoutConfiguration) -> WorkoutDestination {
        let inferredKind = PulsarOutdoorWorkoutKind(
            activityType: configuration.activityType,
            locationType: configuration.locationType
        )
        // HealthKit's launch configuration is authoritative. WatchConnectivity
        // state may be delayed or stale during a cold companion launch.
        return inferredKind == .strength ? .gym : .run
    }
}
