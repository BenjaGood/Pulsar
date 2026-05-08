//
//  PulsarGymLiveActivityAttributes.swift
//  Pulsar
//

import ActivityKit
import Foundation

struct PulsarGymLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var routineName: String
        var currentExerciseName: String
        var progressText: String
        var exerciseProgressText: String
        var elapsedSeconds: Int
        var heartRate: Double?
        var activeEnergyKilocalories: Double?
        var restRemainingSeconds: Int?
        var isFinished: Bool
    }

    var sessionId: UUID
}
