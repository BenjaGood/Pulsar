//
//  PulsarRunSharedModels.swift
//  Pulsar
//

import Foundation

enum PulsarRunRecordingSource: String, Codable, Hashable {
    case appleWatch
    case iPhone

    var label: String {
        switch self {
        case .appleWatch: "Apple Watch"
        case .iPhone: "iPhone"
        }
    }
}

enum PulsarRunPhase: String, Codable, Hashable {
    case idle
    case requestingPermissions
    case countingDown
    case connectingToWatch
    case running
    case paused
    case finishing
    case finished
    case failed
}

struct PulsarRunOptions: Codable, Equatable {
    var prefersWatchRecorder: Bool
    var autoPauseEnabled: Bool
    var audioCuesEnabled: Bool

    static let `default` = PulsarRunOptions(
        prefersWatchRecorder: true,
        autoPauseEnabled: true,
        audioCuesEnabled: false
    )
}

struct PulsarRunCoordinate: Codable, Hashable, Identifiable {
    var id: String { "\(timestamp.timeIntervalSince1970)-\(latitude)-\(longitude)" }
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    var horizontalAccuracy: Double?
    var verticalAccuracy: Double?
    var timestamp: Date

    init(
        latitude: Double,
        longitude: Double,
        altitude: Double? = nil,
        horizontalAccuracy: Double? = nil,
        verticalAccuracy: Double? = nil,
        timestamp: Date = Date()
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.timestamp = timestamp
    }
}

struct PulsarRunMetricSnapshot: Codable, Equatable {
    var phase: PulsarRunPhase
    var source: PulsarRunRecordingSource
    var startedAt: Date?
    var endedAt: Date?
    var elapsedTime: TimeInterval
    var movingTime: TimeInterval
    var distanceMeters: Double
    var currentPaceSecondsPerKilometer: Double?
    var averagePaceSecondsPerKilometer: Double?
    var splitPaceSecondsPerKilometer: Double?
    var activeSplitIndex: Int
    var elevationGainMeters: Double
    var currentElevationMeters: Double?
    var activeEnergyKilocalories: Double?
    var currentHeartRate: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var stepCount: Int?
    var cadenceStepsPerMinute: Double?
    var runningPowerWatts: Double?
    var strideLengthMeters: Double?
    var groundContactTimeMilliseconds: Double?
    var verticalOscillationCentimeters: Double?
    var route: [PulsarRunCoordinate]
    var splits: [PulsarRunSplit]
    var statusMessage: String?

    static let empty = PulsarRunMetricSnapshot(
        phase: .idle,
        source: .iPhone,
        startedAt: nil,
        endedAt: nil,
        elapsedTime: 0,
        movingTime: 0,
        distanceMeters: 0,
        currentPaceSecondsPerKilometer: nil,
        averagePaceSecondsPerKilometer: nil,
        splitPaceSecondsPerKilometer: nil,
        activeSplitIndex: 1,
        elevationGainMeters: 0,
        currentElevationMeters: nil,
        activeEnergyKilocalories: nil,
        currentHeartRate: nil,
        averageHeartRate: nil,
        maxHeartRate: nil,
        stepCount: nil,
        cadenceStepsPerMinute: nil,
        runningPowerWatts: nil,
        strideLengthMeters: nil,
        groundContactTimeMilliseconds: nil,
        verticalOscillationCentimeters: nil,
        route: [],
        splits: [],
        statusMessage: nil
    )
}

struct PulsarRunSplit: Codable, Equatable, Identifiable {
    var id: Int { index }
    var index: Int
    var distanceMeters: Double
    var movingTime: TimeInterval
    var elevationGainMeters: Double
    var averageHeartRate: Double?

    var paceSecondsPerKilometer: Double? {
        guard distanceMeters > 0 else { return nil }
        return movingTime / (distanceMeters / 1_000)
    }
}

struct PulsarRunSummary: Codable, Equatable, Identifiable {
    var id: UUID
    var workoutUUID: UUID?
    var startedAt: Date
    var endedAt: Date
    var source: PulsarRunRecordingSource
    var distanceMeters: Double
    var elapsedTime: TimeInterval
    var movingTime: TimeInterval
    var activeEnergyKilocalories: Double?
    var elevationGainMeters: Double
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var steps: Int?
    var averageCadenceStepsPerMinute: Double?
    var route: [PulsarRunCoordinate]
    var splits: [PulsarRunSplit]

    var averagePaceSecondsPerKilometer: Double? {
        guard distanceMeters > 0 else { return nil }
        return movingTime / (distanceMeters / 1_000)
    }
}

enum PulsarRunControlCommand: String, Codable, Hashable {
    case pause
    case resume
    case finish
}

enum PulsarRunTransportEnvelope: Codable, Equatable {
    case options(PulsarRunOptions)
    case metrics(PulsarRunMetricSnapshot)
    case command(PulsarRunControlCommand)
    case summary(PulsarRunSummary)

    private enum CodingKeys: String, CodingKey {
        case kind
        case options
        case metrics
        case command
        case summary
    }

    private enum Kind: String, Codable {
        case options
        case metrics
        case command
        case summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .options:
            self = .options(try container.decode(PulsarRunOptions.self, forKey: .options))
        case .metrics:
            self = .metrics(try container.decode(PulsarRunMetricSnapshot.self, forKey: .metrics))
        case .command:
            self = .command(try container.decode(PulsarRunControlCommand.self, forKey: .command))
        case .summary:
            self = .summary(try container.decode(PulsarRunSummary.self, forKey: .summary))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .options(let options):
            try container.encode(Kind.options, forKey: .kind)
            try container.encode(options, forKey: .options)
        case .metrics(let metrics):
            try container.encode(Kind.metrics, forKey: .kind)
            try container.encode(metrics, forKey: .metrics)
        case .command(let command):
            try container.encode(Kind.command, forKey: .kind)
            try container.encode(command, forKey: .command)
        case .summary(let summary):
            try container.encode(Kind.summary, forKey: .kind)
            try container.encode(summary, forKey: .summary)
        }
    }
}

enum PulsarRunTransportCodec {
    static func encode(_ envelope: PulsarRunTransportEnvelope) -> Data? {
        try? JSONEncoder.pulsarRun.encode(envelope)
    }

    static func decode(_ data: Data) -> PulsarRunTransportEnvelope? {
        try? JSONDecoder.pulsarRun.decode(PulsarRunTransportEnvelope.self, from: data)
    }
}

enum PulsarRunFormatters {
    static func distance(_ meters: Double) -> String {
        let kilometers = max(0, meters) / 1_000
        if kilometers < 10 {
            return String(format: "%.2f km", kilometers)
        }
        return String(format: "%.1f km", kilometers)
    }

    static func compactDistance(_ meters: Double) -> String {
        String(format: "%.2f", max(0, meters) / 1_000)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let value = max(0, Int(interval.rounded()))
        let hours = value / 3_600
        let minutes = (value % 3_600) / 60
        let seconds = value % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func pace(_ secondsPerKilometer: Double?) -> String {
        guard let secondsPerKilometer, secondsPerKilometer.isFinite, secondsPerKilometer > 0 else {
            return "--"
        }
        let minutes = Int(secondsPerKilometer) / 60
        let seconds = Int(secondsPerKilometer.rounded()) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    static func heartRate(_ bpm: Double?) -> String {
        guard let bpm, bpm > 0 else { return "--" }
        return "\(Int(bpm.rounded()))"
    }

    static func calories(_ kilocalories: Double?) -> String {
        guard let kilocalories, kilocalories > 0 else { return "--" }
        return "\(Int(kilocalories.rounded()))"
    }

    static func elevation(_ meters: Double?) -> String {
        guard let meters else { return "--" }
        return "\(Int(meters.rounded())) m"
    }

    static func cadence(_ stepsPerMinute: Double?) -> String {
        guard let stepsPerMinute, stepsPerMinute > 0 else { return "--" }
        return "\(Int(stepsPerMinute.rounded())) spm"
    }
}

struct PulsarRunDerivedMetrics {
    static func averagePace(distanceMeters: Double, movingTime: TimeInterval) -> Double? {
        guard distanceMeters >= 10, movingTime > 0 else { return nil }
        return movingTime / (distanceMeters / 1_000)
    }

    static func splitIndex(distanceMeters: Double) -> Int {
        max(1, Int(distanceMeters / 1_000) + 1)
    }

    static func shouldAutoPause(speedMetersPerSecond: Double?, horizontalAccuracy: Double?) -> Bool {
        guard let speedMetersPerSecond else { return false }
        if let horizontalAccuracy, horizontalAccuracy > 35 { return false }
        return speedMetersPerSecond >= 0 && speedMetersPerSecond < 0.55
    }

    static func elevationGain(previousAltitude: Double?, nextAltitude: Double, verticalAccuracy: Double?) -> Double {
        guard let previousAltitude else { return 0 }
        if let verticalAccuracy, verticalAccuracy > 18 { return 0 }
        let delta = nextAltitude - previousAltitude
        return delta >= 1.5 ? delta : 0
    }
}

private extension JSONEncoder {
    static var pulsarRun: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var pulsarRun: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
