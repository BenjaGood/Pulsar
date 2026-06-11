//
//  PulsarLiveWorkoutDashboardModels.swift
//  Pulsar
//

import SwiftUI
import UIKit

enum PulsarLiveWorkoutDashboardPhase: String, Hashable {
    case preparing
    case running
    case paused
    case finishing
    case finished

    var controlTitle: String {
        switch self {
        case .paused: "Resume"
        case .preparing, .running, .finishing, .finished: "Pause"
        }
    }

    var controlSymbolName: String {
        switch self {
        case .paused: "play.fill"
        case .preparing, .running, .finishing, .finished: "pause.fill"
        }
    }

    var statusText: String {
        switch self {
        case .preparing: "READY"
        case .running: "LIVE"
        case .paused: "PAUSED"
        case .finishing: "SAVING"
        case .finished: "DONE"
        }
    }
}

struct PulsarHeartRateZone: Identifiable, Equatable {
    var id: Int { number }
    var number: Int
    var title: String
    var detail: String
    var lowerPercent: Double
    var upperPercent: Double
    var lowerBound: Double?
    var upperBound: Double?
    var color: Color

    var percentRangeText: String {
        "\(Int((lowerPercent * 100).rounded()))-\(Int((upperPercent * 100).rounded()))%"
    }

    var rangeText: String {
        guard let lowerBound, let upperBound else {
            return percentRangeText
        }
        return "\(Int(lowerBound.rounded()))-\(Int(upperBound.rounded())) bpm"
    }
}

struct PulsarHeartRateZoneProfile: Equatable {
    enum MaxHeartRateSource: Equatable {
        case manual
        case ageFormula
        case unavailable

        var displayText: String {
            switch self {
            case .manual: "User max HR"
            case .ageFormula: "220 - age"
            case .unavailable: "Max HR Missing"
            }
        }
    }

    var maxHeartRate: Double?
    var maxHeartRateSource: MaxHeartRateSource
    var zones: [PulsarHeartRateZone]

    init(profile: UserProfile, date: Date = .now, calendar: Calendar = .current) {
        if let manualMaxHeartRate = profile.manualMaxHeartRate,
           manualMaxHeartRate.isFinite,
           manualMaxHeartRate > 0 {
            self.init(maxHeartRate: manualMaxHeartRate, source: .manual)
            return
        }

        if let age = profile.age(on: date, calendar: calendar), age > 0 {
            self.init(maxHeartRate: max(80, 220 - Double(age)), source: .ageFormula)
            return
        }

        self.init(maxHeartRate: nil, source: .unavailable)
    }

    init(maxHeartRate: Double? = nil, source: MaxHeartRateSource = .unavailable) {
        let resolvedMax = maxHeartRate.flatMap { value -> Double? in
            guard value.isFinite, value > 0 else { return nil }
            return min(max(value, 80), 240)
        }

        self.maxHeartRate = resolvedMax
        self.maxHeartRateSource = resolvedMax == nil ? .unavailable : source

        let definitions: [(Int, String, String, Double, Double, Color)] = [
            (1, "Recovery", "Light effort", 0.50, 0.60, Color(red: 0.22, green: 0.74, blue: 0.92)),
            (2, "Endurance", "Aerobic base", 0.60, 0.70, Color(red: 0.35, green: 0.84, blue: 0.39)),
            (3, "Aerobic", "Productive tempo", 0.70, 0.80, Color(red: 1.00, green: 0.58, blue: 0.10)),
            (4, "Threshold", "Hard effort", 0.80, 0.90, Color(red: 1.00, green: 0.35, blue: 0.18)),
            (5, "Peak", "Maximum effort", 0.90, 1.00, Color(red: 0.96, green: 0.16, blue: 0.31))
        ]

        self.zones = definitions.map { number, title, detail, lower, upper, color in
            PulsarHeartRateZone(
                number: number,
                title: title,
                detail: detail,
                lowerPercent: lower,
                upperPercent: upper,
                lowerBound: resolvedMax.map { $0 * lower },
                upperBound: resolvedMax.map { $0 * upper },
                color: color
            )
        }
    }

    func zone(for heartRate: Double?) -> PulsarHeartRateZone? {
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

    func percentOfMax(for heartRate: Double?) -> Double? {
        guard let heartRate,
              heartRate.isFinite,
              heartRate > 0,
              let maxHeartRate,
              maxHeartRate > 0 else {
            return nil
        }
        return min(max(heartRate / maxHeartRate, 0), 1.2)
    }

    var maxHeartRateText: String {
        guard let maxHeartRate else { return "Set max HR or birthday in Settings" }
        return "\(Int(maxHeartRate.rounded())) bpm \(maxHeartRateSource.displayText)"
    }
}

struct PulsarNowPlayingTrack {
    var title: String?
    var artist: String?
    var albumTitle: String?
    var artworkImage: UIImage?
    var isPlaying: Bool
    var progress: Double?
    var statusText: String
    var unavailableReason: String?

    var isAvailable: Bool {
        title != nil
    }

    var displayTitle: String {
        title ?? statusText
    }

    var displaySubtitle: String {
        if let artist, let albumTitle, !albumTitle.isEmpty {
            return "\(artist) - \(albumTitle)"
        }
        if let artist {
            return artist
        }
        if let unavailableReason {
            return unavailableReason
        }
        return "Apple Music"
    }

    static func unavailable(
        _ statusText: String = "Now Playing unavailable",
        reason: String? = nil
    ) -> PulsarNowPlayingTrack {
        PulsarNowPlayingTrack(
            title: nil,
            artist: nil,
            albumTitle: nil,
            artworkImage: nil,
            isPlaying: false,
            progress: nil,
            statusText: statusText,
            unavailableReason: reason
        )
    }

    #if DEBUG
    static let preview = PulsarNowPlayingTrack(
        title: "Higher Ground",
        artist: "ODESZA",
        albumTitle: "A Moment Apart",
        artworkImage: nil,
        isPlaying: true,
        progress: 0.42,
        statusText: "Now Playing",
        unavailableReason: nil
    )
    #endif
}

struct PulsarLiveWorkoutMetric: Identifiable {
    var id: String { title }
    var title: String
    var value: String
    var unit: String?
    var symbolName: String
    var tint: Color

    init(title: String, value: String, unit: String? = nil, symbolName: String, tint: Color) {
        self.title = title
        self.value = value
        self.unit = unit
        self.symbolName = symbolName
        self.tint = tint
    }
}

struct PulsarLiveWorkoutBanner: Identifiable {
    let id: String
    var title: String
    var message: String?
    var symbolName: String
    var tint: Color
}

enum PulsarLiveWorkoutDashboardPresentationStyle: Hashable {
    case classic
    case premiumNonGPS
}

struct PulsarLiveWorkoutDashboardState {
    var title: String
    var subtitle: String
    var symbolName: String
    var tint: Color
    var glowColor: Color
    var phase: PulsarLiveWorkoutDashboardPhase
    var statusText: String
    var recorderStatusText: String
    var recorderStatusSymbolName: String
    var primaryMetricTitle: String
    var primaryMetricValue: String
    var primaryMetricSubtitle: String
    var elapsedTime: TimeInterval
    var currentHeartRate: Double?
    var heartRateZone: PulsarHeartRateZone?
    var zoneProfile: PulsarHeartRateZoneProfile
    var insightTitle: String = "Workout Intensity"
    var intensityTitle: String
    var intensitySubtitle: String
    var nowPlaying: PulsarNowPlayingTrack
    var metrics: [PulsarLiveWorkoutMetric]
    var banners: [PulsarLiveWorkoutBanner] = []
    var controlsDisabled = false
    var musicControlsDisabled = false
    var presentationStyle: PulsarLiveWorkoutDashboardPresentationStyle = .classic

    var isPaused: Bool { phase == .paused }
    var isFinishing: Bool { phase == .finishing || phase == .finished }
    var isPremiumNonGPS: Bool { presentationStyle == .premiumNonGPS }

    var activeZoneColor: Color {
        heartRateZone?.color ?? tint
    }

    var heartRateDisplayText: String {
        guard let currentHeartRate, currentHeartRate > 0 else {
            return "No Heart Rate Available"
        }
        return "\(Int(currentHeartRate.rounded()))"
    }

    var heartRatePlaceholderText: String {
        if recorderStatusSymbolName == "applewatch" {
            return "Waiting for Apple Watch..."
        }
        return "Waiting for heart rate..."
    }

    var heartRateUnitText: String {
        guard currentHeartRate != nil else { return "" }
        return "bpm"
    }

    var percentOfMaxText: String {
        guard let percent = zoneProfile.percentOfMax(for: currentHeartRate) else {
            return zoneProfile.maxHeartRate == nil ? "Max HR unavailable" : "Waiting for live HR"
        }
        return "\(Int((percent * 100).rounded()))% max HR"
    }

    var zoneTitleText: String {
        guard let heartRateZone else {
            return currentHeartRate == nil ? "No Zone" : "Zone unavailable"
        }
        return "Zone \(heartRateZone.number)"
    }

    var zoneDetailText: String {
        guard let heartRateZone else {
            return currentHeartRate == nil ? "Waiting for heart rate" : zoneProfile.maxHeartRateText
        }
        return "\(heartRateZone.title) - \(heartRateZone.percentRangeText)"
    }

    var activeZoneTargetText: String {
        guard let heartRateZone else {
            return "Target: --"
        }
        return "Target: \(heartRateZone.rangeText)"
    }

    var activeZoneDescriptionText: String {
        guard let heartRateZone else {
            return currentHeartRate == nil ? "Waiting for heart rate" : "Set max HR to unlock zones"
        }
        return "You're in \(heartRateZone.title) Zone"
    }
}
