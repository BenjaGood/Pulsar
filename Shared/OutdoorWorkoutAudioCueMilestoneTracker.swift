//
//  OutdoorWorkoutAudioCueMilestoneTracker.swift
//  Pulsar
//

import Foundation

/// A completed kilometer that is eligible for an audio or haptic cue.
nonisolated struct OutdoorWorkoutAudioCueEvent: Equatable, Sendable {
    let kilometer: Int
    let paceSecondsPerKilometer: Double?
}

/// Tracks which kilometer milestones have already been consumed so cues are never repeated.
///
/// Split pace uses the same moving-time basis as `PulsarRunSplit` / live outdoor metrics.
nonisolated struct OutdoorWorkoutAudioCueMilestoneTracker: Equatable, Sendable {
    private(set) var lastAnnouncedKilometer: Int = 0

    mutating func reset() {
        lastAnnouncedKilometer = 0
    }

    /// Seeds the tracker after restoring a live workout so prior kilometers are not re-announced.
    mutating func restore(completedKilometerCount: Int) {
        lastAnnouncedKilometer = max(0, completedKilometerCount)
    }

    /// Seeds from distance when full split history is not yet available.
    mutating func restore(distanceMeters: Double) {
        guard distanceMeters.isFinite, distanceMeters >= 0 else { return }
        lastAnnouncedKilometer = max(lastAnnouncedKilometer, Int(distanceMeters / 1_000))
    }

    /// Consumes newly completed splits.
    ///
    /// Always advances `lastAnnouncedKilometer`, even when `shouldAnnounce` is false, so toggling
    /// cues back on mid-workout does not dump a backlog of missed announcements.
    mutating func consume(
        completedSplits: [PulsarRunSplit],
        shouldAnnounce: Bool
    ) -> [OutdoorWorkoutAudioCueEvent] {
        let newSplits = completedSplits
            .filter { $0.index > lastAnnouncedKilometer }
            .sorted { $0.index < $1.index }
        guard let newest = newSplits.last else { return [] }

        lastAnnouncedKilometer = newest.index
        guard shouldAnnounce else { return [] }

        return newSplits.compactMap { split in
            let pace = Self.validPaceSecondsPerKilometer(for: split)
            guard pace != nil || split.movingTime > 0 else { return nil }
            return OutdoorWorkoutAudioCueEvent(
                kilometer: split.index,
                paceSecondsPerKilometer: pace
            )
        }
    }

    /// Distance-based fallback when split objects are unavailable (for example sync restore).
    mutating func consume(
        distanceMeters: Double,
        shouldAnnounce: Bool
    ) -> [Int] {
        guard distanceMeters.isFinite, distanceMeters >= 0 else { return [] }
        let completed = Int(distanceMeters / 1_000)
        guard completed > lastAnnouncedKilometer else { return [] }

        let kilometers = Array((lastAnnouncedKilometer + 1)...completed)
        lastAnnouncedKilometer = completed
        return shouldAnnounce ? kilometers : []
    }

    private static func validPaceSecondsPerKilometer(for split: PulsarRunSplit) -> Double? {
        guard split.distanceMeters > 0,
              split.movingTime > 0,
              let pace = split.paceSecondsPerKilometer,
              pace.isFinite,
              pace > 0 else {
            return nil
        }
        return pace
    }
}

/// Persists the outdoor workout audio-cues preference across launches.
enum OutdoorWorkoutAudioCueSettings {
    private static let audioCuesEnabledKey = "pulsar.outdoor.audioCuesEnabled.v1"

    static var audioCuesEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: audioCuesEnabledKey) != nil else {
                return PulsarRunOptions.default.audioCuesEnabled
            }
            return UserDefaults.standard.bool(forKey: audioCuesEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: audioCuesEnabledKey)
        }
    }

    static func applyPersistedPreference(to options: inout PulsarRunOptions) {
        options.audioCuesEnabled = audioCuesEnabled
    }

    static func persist(_ options: PulsarRunOptions) {
        audioCuesEnabled = options.audioCuesEnabled
    }
}
