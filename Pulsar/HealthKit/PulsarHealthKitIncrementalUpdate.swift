//
//  PulsarHealthKitIncrementalUpdate.swift
//  Pulsar
//

import Foundation
import HealthKit

enum PulsarHealthKitLogger {
    nonisolated static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard isEnabled else { return }
        print("[PulsarHealthKit] \(message())")
        #endif
    }

    #if DEBUG
    private nonisolated static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["PULSAR_HEALTHKIT_DEBUG_LOGS"] == "1"
    }
    #endif
}

enum PulsarHealthKitIncrementalMetric {
    static func label(for sampleType: HKSampleType) -> String {
        label(forIdentifier: sampleType.identifier)
    }

    static func label(forIdentifier identifier: String) -> String {
        switch identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue:
            return "heartRate"
        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
            return "hrv"
        case HKQuantityTypeIdentifier.restingHeartRate.rawValue:
            return "restingHeartRate"
        case HKQuantityTypeIdentifier.respiratoryRate.rawValue:
            return "respiratoryRate"
        case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
            return "oxygenSaturation"
        case HKQuantityTypeIdentifier.stepCount.rawValue:
            return "steps"
        case HKQuantityTypeIdentifier.appleExerciseTime.rawValue:
            return "exerciseMinutes"
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
            return "activeEnergy"
        case HKQuantityTypeIdentifier.appleSleepingWristTemperature.rawValue:
            return "temperatureTrend"
        case HKCategoryTypeIdentifier.sleepAnalysis.rawValue:
            return "sleep"
        case HKObjectType.workoutType().identifier:
            return "workouts"
        default:
            return identifier
                .replacingOccurrences(of: "HKQuantityTypeIdentifier", with: "")
                .replacingOccurrences(of: "HKCategoryTypeIdentifier", with: "")
                .replacingOccurrences(of: "HKWorkoutTypeIdentifier", with: "")
        }
    }
}
