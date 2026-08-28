//
//  PulsarLiveWorkoutPresentation.swift
//  Pulsar
//

import Foundation

/// A UIKit-free, max-heart-rate percentage zone profile shared by live workout surfaces.
nonisolated struct PulsarLiveHeartRateZoneProfile: Equatable, Sendable {
    enum MaxHeartRateSource: Equatable, Sendable {
        case ageFormula
        case unavailable
    }

    struct Zone: Identifiable, Equatable, Sendable {
        var id: Int { number }
        var number: Int
        var title: String
        var lowerPercent: Double
        var upperPercent: Double
    }

    var maxHeartRate: Double?
    var maxHeartRateSource: MaxHeartRateSource
    var zones: [Zone]

    init(maxHeartRate: Double? = nil, source: MaxHeartRateSource = .unavailable) {
        let resolvedMaxHeartRate = maxHeartRate.flatMap { value -> Double? in
            guard value.isFinite, value > 0 else { return nil }
            return min(max(value, 80), 240)
        }
        self.maxHeartRate = resolvedMaxHeartRate
        self.maxHeartRateSource = resolvedMaxHeartRate == nil ? .unavailable : source
        self.zones = [
            Zone(number: 1, title: "Recovery", lowerPercent: 0.50, upperPercent: 0.60),
            Zone(number: 2, title: "Endurance", lowerPercent: 0.60, upperPercent: 0.70),
            Zone(number: 3, title: "Aerobic", lowerPercent: 0.70, upperPercent: 0.80),
            Zone(number: 4, title: "Threshold", lowerPercent: 0.80, upperPercent: 0.90),
            Zone(number: 5, title: "Peak", lowerPercent: 0.90, upperPercent: 1.00)
        ]
    }

    func zone(for heartRate: Double?) -> Zone? {
        guard let heartRate,
              heartRate.isFinite,
              heartRate > 0,
              let maxHeartRate,
              maxHeartRate > 0 else {
            return nil
        }
        let percent = heartRate / maxHeartRate
        if percent < 0.60 { return zones.first }
        return zones.last { percent >= $0.lowerPercent } ?? zones.first
    }
}

nonisolated enum PulsarLiveWorkoutMetricAccent: String, Equatable, Sendable {
    case activity
    case time
    case energy
    case heartRate
    case zone
    case distance
    case pace
    case cadence
}

nonisolated struct PulsarWatchLiveWorkoutMetric: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case value
        case heartRateZone(PulsarLiveHeartRateZoneProfile.Zone?)
    }

    var id: String { title }
    var title: String
    var value: String
    var unit: String?
    var symbolName: String
    var accent: PulsarLiveWorkoutMetricAccent
    var kind: Kind = .value
    var detail: String?
}

nonisolated struct PulsarWatchLiveWorkoutPresentation: Equatable, Sendable {
    enum TimerState: Equatable, Sendable {
        case active
        case paused
        case pending
    }

    var title: String
    var workoutSymbolName: String
    var elapsedTimeText: String
    var statusText: String
    var timerState: TimerState
    var metrics: [PulsarWatchLiveWorkoutMetric]
}

nonisolated enum PulsarWatchLiveWorkoutPresentationBuilder {
    static func make(
        snapshot: PulsarRunMetricSnapshot,
        heartRateZoneProfile: PulsarLiveHeartRateZoneProfile
    ) -> PulsarWatchLiveWorkoutPresentation {
        let kind = snapshot.workoutKind
        let zone = heartRateZoneProfile.zone(for: snapshot.currentHeartRate)
        return PulsarWatchLiveWorkoutPresentation(
            title: kind.outdoorTitle,
            workoutSymbolName: kind.systemImageName,
            elapsedTimeText: PulsarRunFormatters.duration(snapshot.elapsedTime),
            statusText: statusText(for: snapshot.phase),
            timerState: timerState(for: snapshot.phase),
            metrics: metrics(for: snapshot, zone: zone, maxHeartRateAvailable: heartRateZoneProfile.maxHeartRate != nil)
        )
    }

    private static func metrics(
        for snapshot: PulsarRunMetricSnapshot,
        zone: PulsarLiveHeartRateZoneProfile.Zone?,
        maxHeartRateAvailable: Bool
    ) -> [PulsarWatchLiveWorkoutMetric] {
        let zoneMetric = heartRateZoneMetric(
            heartRate: snapshot.currentHeartRate,
            zone: zone,
            maxHeartRateAvailable: maxHeartRateAvailable
        )
        let heartRateMetric = metric(
            title: "Heart Rate",
            value: PulsarRunFormatters.heartRate(snapshot.currentHeartRate),
            unit: snapshot.currentHeartRate.map { $0 > 0 ? "BPM" : nil } ?? nil,
            symbolName: "heart.fill",
            accent: .heartRate
        )
        let caloriesMetric = metric(
            title: "Calories",
            value: PulsarRunFormatters.calories(snapshot.activeEnergyKilocalories),
            unit: snapshot.activeEnergyKilocalories.map { $0 > 0 ? "CAL" : nil } ?? nil,
            symbolName: "flame.fill",
            accent: .energy
        )
        let averageHeartRateMetric = metric(
            title: "Avg HR",
            value: PulsarRunFormatters.heartRate(snapshot.averageHeartRate),
            unit: snapshot.averageHeartRate.map { $0 > 0 ? "BPM" : nil } ?? nil,
            symbolName: "heart.text.square.fill",
            accent: .heartRate
        )

        switch snapshot.workoutKind {
        case .running, .walking, .hiking:
            return [
                distanceMetric(snapshot.distanceMeters),
                paceMetric(snapshot),
                heartRateMetric,
                zoneMetric
            ]
        case .cycling:
            return [
                distanceMetric(snapshot.distanceMeters),
                speedMetric(snapshot),
                heartRateMetric,
                zoneMetric
            ]
        case .indoorRunning, .elliptical, .rowing, .stairClimber:
            return [
                caloriesMetric,
                snapshot.cadenceStepsPerMinute == nil ? averageHeartRateMetric : cadenceMetric(snapshot.cadenceStepsPerMinute),
                heartRateMetric,
                zoneMetric
            ]
        case .swimming:
            return [
                caloriesMetric,
                snapshot.distanceMeters > 0 ? distanceMetric(snapshot.distanceMeters) : averageHeartRateMetric,
                heartRateMetric,
                zoneMetric
            ]
        case .hiit, .strength, .yoga, .pilates, .dance, .boxing, .stretching, .core, .mobility, .cooldown, .other:
            return [caloriesMetric, averageHeartRateMetric, heartRateMetric, zoneMetric]
        }
    }

    private static func metric(
        title: String,
        value: String,
        unit: String?,
        symbolName: String,
        accent: PulsarLiveWorkoutMetricAccent
    ) -> PulsarWatchLiveWorkoutMetric {
        PulsarWatchLiveWorkoutMetric(
            title: title,
            value: value,
            unit: unit,
            symbolName: symbolName,
            accent: accent
        )
    }

    private static func distanceMetric(_ meters: Double) -> PulsarWatchLiveWorkoutMetric {
        metric(
            title: "Distance",
            value: PulsarRunFormatters.compactDistance(meters),
            unit: "KM",
            symbolName: "location.fill",
            accent: .distance
        )
    }

    private static func paceMetric(_ snapshot: PulsarRunMetricSnapshot) -> PulsarWatchLiveWorkoutMetric {
        metric(
            title: "Pace",
            value: PulsarRunFormatters.pace(snapshot.currentPaceSecondsPerKilometer).replacingOccurrences(of: " /km", with: ""),
            unit: "/KM",
            symbolName: "figure.run",
            accent: .pace
        )
    }

    private static func speedMetric(_ snapshot: PulsarRunMetricSnapshot) -> PulsarWatchLiveWorkoutMetric {
        let metersPerSecond = snapshot.currentPaceSecondsPerKilometer.map { 1_000 / $0 }
        return metric(
            title: "Speed",
            value: PulsarRunFormatters.speed(metersPerSecond).replacingOccurrences(of: " km/h", with: ""),
            unit: "KM/H",
            symbolName: "bicycle",
            accent: .pace
        )
    }

    private static func cadenceMetric(_ cadence: Double?) -> PulsarWatchLiveWorkoutMetric {
        metric(
            title: "Cadence",
            value: PulsarRunFormatters.cadence(cadence).replacingOccurrences(of: " spm", with: ""),
            unit: "SPM",
            symbolName: "metronome.fill",
            accent: .cadence
        )
    }

    private static func heartRateZoneMetric(
        heartRate: Double?,
        zone: PulsarLiveHeartRateZoneProfile.Zone?,
        maxHeartRateAvailable: Bool
    ) -> PulsarWatchLiveWorkoutMetric {
        let detail: String
        if let zone {
            detail = zone.title
        } else if heartRate == nil {
            detail = "Waiting for HR"
        } else if !maxHeartRateAvailable {
            detail = "Set max HR"
        } else {
            detail = "Unavailable"
        }
        return PulsarWatchLiveWorkoutMetric(
            title: "Zone",
            value: zone.map { "\($0.number)" } ?? "--",
            unit: nil,
            symbolName: "chart.bar.fill",
            accent: .zone,
            kind: .heartRateZone(zone),
            detail: detail
        )
    }

    private static func statusText(for phase: PulsarRunPhase) -> String {
        switch phase {
        case .running: "Live"
        case .paused: "Paused"
        case .finishing: "Saving"
        case .connectingToWatch, .requestingPermissions, .countingDown: "Starting"
        case .finished: "Finished"
        case .failed: "Unavailable"
        case .idle: "Ready"
        }
    }

    private static func timerState(for phase: PulsarRunPhase) -> PulsarWatchLiveWorkoutPresentation.TimerState {
        switch phase {
        case .running: .active
        case .paused: .paused
        case .idle, .requestingPermissions, .countingDown, .connectingToWatch, .finishing, .finished, .failed: .pending
        }
    }
}
