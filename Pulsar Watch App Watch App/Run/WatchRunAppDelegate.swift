//
//  WatchRunAppDelegate.swift
//  Pulsar Watch App Watch App
//

import HealthKit
import WatchKit

final class WatchRunAppDelegate: NSObject, WKApplicationDelegate {
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
}
