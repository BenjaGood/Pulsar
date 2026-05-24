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
            if workoutConfiguration.activityType == .traditionalStrengthTraining ||
                workoutConfiguration.activityType == .functionalStrengthTraining {
                await WatchGymSessionManager.shared.startFromCompanion(configuration: workoutConfiguration)
            } else {
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

                let activityType = recoveredSession.workoutConfiguration.activityType
                if activityType == .traditionalStrengthTraining ||
                    activityType == .functionalStrengthTraining {
                    WatchGymSessionManager.shared.recoverActiveWorkoutSession(recoveredSession)
                } else {
                    WatchRunSessionManager.shared.recoverActiveWorkoutSession(recoveredSession)
                }
            }
        }
    }
}
