//
//  PulsarWorkoutSessionValidity.swift
//  Pulsar
//

import Foundation

enum PulsarWorkoutSessionValidity {
    static let liveHeartbeatGraceInterval: TimeInterval = 15 * 60
    static let startingGraceInterval: TimeInterval = 2 * 60
    static let endedStateRetentionInterval: TimeInterval = 6 * 60 * 60

    static func isRecent(_ date: Date, now: Date = Date(), interval: TimeInterval = liveHeartbeatGraceInterval) -> Bool {
        let age = now.timeIntervalSince(date)
        return age >= -30 && age <= interval
    }
}

extension PulsarActiveWorkoutSyncState {
    func isValidLiveRouteCandidate(now: Date = Date()) -> Bool {
        guard phase.isLive else { return false }
        if PulsarWorkoutSessionValidity.isRecent(updatedAt, now: now) {
            return true
        }
        if phase == .starting,
           PulsarWorkoutSessionValidity.isRecent(startedAt, now: now, interval: PulsarWorkoutSessionValidity.startingGraceInterval) {
            return true
        }
        return false
    }

    func staleRouteReason(now: Date = Date()) -> String? {
        if isEnded { return "ended" }
        guard !isValidLiveRouteCandidate(now: now) else { return nil }
        let heartbeatAge = Int(now.timeIntervalSince(updatedAt).rounded())
        let startAge = Int(now.timeIntervalSince(startedAt).rounded())
        return "stale heartbeatAge=\(heartbeatAge)s startAge=\(startAge)s"
    }
}

extension ActiveGymWorkoutState {
    func isValidLiveRouteCandidate(now: Date = Date()) -> Bool {
        guard !isFinished else { return false }
        if PulsarWorkoutSessionValidity.isRecent(updatedAt, now: now) {
            return true
        }
        if PulsarWorkoutSessionValidity.isRecent(startedAt, now: now, interval: PulsarWorkoutSessionValidity.startingGraceInterval) {
            return true
        }
        return false
    }

    func staleRouteReason(now: Date = Date()) -> String? {
        if isFinished { return "finished" }
        guard !isValidLiveRouteCandidate(now: now) else { return nil }
        let heartbeatAge = Int(now.timeIntervalSince(updatedAt).rounded())
        let startAge = Int(now.timeIntervalSince(startedAt).rounded())
        return "stale heartbeatAge=\(heartbeatAge)s startAge=\(startAge)s"
    }
}
