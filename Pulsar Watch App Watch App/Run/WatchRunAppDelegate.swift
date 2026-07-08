//
//  WatchRunAppDelegate.swift
//  Pulsar Watch App Watch App
//

import HealthKit
import WatchKit

final class WatchRunAppDelegate: NSObject, WKApplicationDelegate {
    private let healthStore = HKHealthStore()
    private let syncStore = PulsarWatchConnectivitySyncStore.shared

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            switch destination(for: workoutConfiguration) {
            case .gym:
                await WatchGymSessionManager.shared.startFromCompanion(configuration: workoutConfiguration)
            case .run:
                await WatchRunSessionManager.shared.startRunFromCompanion(configuration: workoutConfiguration)
            }
        }
    }

    func handleActiveWorkoutRecovery() {
        healthStore.recoverActiveWorkoutSession { recoveredSession, error in
            Task { @MainActor in
                if let error {
                    PulsarSyncDebugLogger.log("Watch active workout recovery failed error=\(error.localizedDescription)")
                    return
                }

                guard let recoveredSession else {
                    PulsarSyncDebugLogger.log("Watch active workout recovery returned no session")
                    return
                }

                switch self.destination(for: recoveredSession.workoutConfiguration) {
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

        if let activeRunState = syncStore.activeWorkoutState,
           activeRunState.kind.outdoorWorkoutKind == inferredKind,
           activeRunState.phase.isLive,
           !activeRunState.isEnded {
            return .run
        }

        if let activeGymState = syncStore.activeGymState,
           syncStore.isRoutableActiveGymState(activeGymState),
           !activeGymState.isFinished {
            return .gym
        }

        if inferredKind != .strength {
            return .run
        }

        return .gym
    }
}
