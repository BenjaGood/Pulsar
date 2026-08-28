//
//  PulsarWorkoutSessionValidity.swift
//  Pulsar
//

import Foundation

nonisolated enum PulsarWorkoutSessionValidity {
    static let liveHeartbeatGraceInterval: TimeInterval = 15 * 60
    static let startingGraceInterval: TimeInterval = 2 * 60
    static let endedStateRetentionInterval: TimeInterval = 6 * 60 * 60
    private static let futureTimestampTolerance: TimeInterval = 30

    static func isRecent(_ date: Date, now: Date = Date(), interval: TimeInterval = liveHeartbeatGraceInterval) -> Bool {
        let age = now.timeIntervalSince(date)
        return age >= -futureTimestampTolerance && age <= interval
    }

    static func isPlausibleTimestamp(_ date: Date, now: Date = Date()) -> Bool {
        date.timeIntervalSince1970 > 0 &&
            now.timeIntervalSince(date) >= -futureTimestampTolerance
    }
}

extension PulsarActiveWorkoutSyncPhase {
    nonisolated var isActiveWorkoutPresentationPhase: Bool {
        switch self {
        case .active, .paused, .resumed:
            true
        case .starting, .ending, .ended, .failed, .cancelled:
            false
        }
    }
}

extension PulsarActiveWorkoutSyncState {
    nonisolated func isFreshRestoreConfirmation(now: Date = Date(), interval: TimeInterval = 90) -> Bool {
        guard phase.isActiveWorkoutPresentationPhase else { return false }
        return PulsarWorkoutSessionValidity.isRecent(updatedAt, now: now, interval: interval)
    }

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

    func isValidActiveWorkoutPresentationCandidate(now: Date = Date()) -> Bool {
        activeWorkoutPresentationRejectionReason(now: now) == nil
    }

    func activeWorkoutPresentationRejectionReason(now: Date = Date()) -> String? {
        if sessionId.uuidString == "00000000-0000-0000-0000-000000000000" {
            return "mock/default session"
        }
        if isEnded {
            return "phase \(phase.rawValue)"
        }
        if !phase.isActiveWorkoutPresentationPhase {
            return "phase \(phase.rawValue)"
        }
        guard PulsarWorkoutSessionValidity.isPlausibleTimestamp(startedAt, now: now),
              PulsarWorkoutSessionValidity.isPlausibleTimestamp(updatedAt, now: now) else {
            return "missing or invalid timestamp"
        }
        if updatedAt < startedAt.addingTimeInterval(-30) {
            return "updatedAt before startedAt"
        }
        guard PulsarWorkoutSessionValidity.isRecent(updatedAt, now: now) else {
            let age = Int(now.timeIntervalSince(updatedAt).rounded())
            return "stale updatedAt age=\(age)s"
        }
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedDisplayName.contains("mock") ||
            normalizedDisplayName.contains("demo") ||
            normalizedDisplayName.contains("preview") {
            return "mock/default session"
        }
        return nil
    }

    func staleRouteReason(now: Date = Date()) -> String? {
        if isEnded { return "ended" }
        if !phase.isRestoreEligible { return "nonRestorablePhase=\(phase.rawValue)" }
        guard !isValidLiveRouteCandidate(now: now) else { return nil }
        let heartbeatAge = Int(now.timeIntervalSince(updatedAt).rounded())
        let startAge = Int(now.timeIntervalSince(startedAt).rounded())
        return "stale heartbeatAge=\(heartbeatAge)s startAge=\(startAge)s"
    }
}

extension ActiveGymWorkoutState {
    nonisolated func isFreshRestoreConfirmation(now: Date = Date(), interval: TimeInterval = 90) -> Bool {
        guard !isFinished else { return false }
        return PulsarWorkoutSessionValidity.isRecent(updatedAt, now: now, interval: interval)
    }

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

    func isValidActiveWorkoutPresentationCandidate(now: Date = Date()) -> Bool {
        activeWorkoutPresentationRejectionReason(now: now) == nil
    }

    func activeWorkoutPresentationRejectionReason(now: Date = Date()) -> String? {
        if sessionId.uuidString == "00000000-0000-0000-0000-000000000000" {
            return "mock/default session"
        }
        if isPrelaunchPlaceholder {
            return "launch placeholder"
        }
        if isFinished {
            return "finished"
        }
        guard startedFrom != nil else {
            return "invalid source"
        }
        guard workoutKind != nil else {
            return "missing workout type"
        }
        guard !routineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "missing workout type"
        }
        guard PulsarWorkoutSessionValidity.isPlausibleTimestamp(startedAt, now: now),
              PulsarWorkoutSessionValidity.isPlausibleTimestamp(updatedAt, now: now) else {
            return "missing or invalid timestamp"
        }
        if updatedAt < startedAt.addingTimeInterval(-30) {
            return "updatedAt before startedAt"
        }
        guard PulsarWorkoutSessionValidity.isRecent(updatedAt, now: now) else {
            let age = Int(now.timeIntervalSince(updatedAt).rounded())
            return "stale updatedAt age=\(age)s"
        }
        guard totalExercises >= 0,
              totalSets >= 0,
              completedSets >= 0,
              currentExerciseIndex >= 0,
              currentSetIndex >= 0 else {
            return "invalid progress"
        }
        if totalSets > 0, completedSets > totalSets {
            return "invalid progress"
        }
        if totalExercises > 0, currentExerciseIndex >= totalExercises {
            return "invalid progress"
        }
        let normalizedName = routineName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedName.contains("mock") || normalizedName.contains("demo") || normalizedName.contains("preview") {
            return "mock/default session"
        }
        return nil
    }

    func staleRouteReason(now: Date = Date()) -> String? {
        if isFinished { return "finished" }
        guard !isValidLiveRouteCandidate(now: now) else { return nil }
        let heartbeatAge = Int(now.timeIntervalSince(updatedAt).rounded())
        let startAge = Int(now.timeIntervalSince(startedAt).rounded())
        return "stale heartbeatAge=\(heartbeatAge)s startAge=\(startAge)s"
    }
}
