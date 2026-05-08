//
//  WatchRunAppDelegate.swift
//  Pulsar Watch App Watch App
//

import HealthKit
import WatchKit

final class WatchRunAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await WatchRunSessionManager.shared.startRunFromCompanion(configuration: workoutConfiguration)
        }
    }
}
