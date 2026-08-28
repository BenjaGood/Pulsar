//
//  HealthMonitorModels.swift
//  Pulsar
//

import Foundation

nonisolated enum HealthMetricStatus: String, Codable, Equatable, Hashable, CaseIterable, Identifiable, Sendable {
    case normal = "Normal"
    case higher = "Higher"
    case lower = "Lower"
    case noData = "No data"

    var id: String { rawValue }

    var systemImageName: String {
        switch self {
        case .normal:
            "checkmark.circle.fill"
        case .higher:
            "arrow.up.circle.fill"
        case .lower:
            "arrow.down.circle.fill"
        case .noData:
            "minus.circle.fill"
        }
    }
}

enum HealthMetricKind: String, Codable, Equatable, Hashable, CaseIterable, Identifiable {
    case respiratoryRate
    case restingHeartRate
    case hrv
    case oxygenSaturation
    case wristTemperature
    case sleep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .respiratoryRate:
            "Respiratory Rate"
        case .restingHeartRate:
            "Resting Heart Rate"
        case .hrv:
            "Heart Rate Variability"
        case .oxygenSaturation:
            "SpO2"
        case .wristTemperature:
            "Temperature Trend"
        case .sleep:
            "Sleep"
        }
    }

    var abbreviation: String {
        switch self {
        case .respiratoryRate:
            "RR"
        case .restingHeartRate:
            "RHR"
        case .hrv:
            "HRV"
        case .oxygenSaturation:
            "SpO₂"
        case .wristTemperature:
            "Temp"
        case .sleep:
            "Sleep"
        }
    }

    var systemImageName: String {
        switch self {
        case .respiratoryRate:
            "lungs.fill"
        case .restingHeartRate:
            "heart.fill"
        case .hrv:
            "waveform.path.ecg"
        case .oxygenSaturation:
            "drop.fill"
        case .wristTemperature:
            "thermometer.medium"
        case .sleep:
            "bed.double.fill"
        }
    }

    var unitText: String? {
        switch self {
        case .respiratoryRate:
            "rpm"
        case .restingHeartRate:
            "bpm"
        case .hrv:
            "ms"
        case .oxygenSaturation:
            "%"
        case .wristTemperature:
            "°C"
        case .sleep:
            nil
        }
    }

    var descriptionText: String {
        switch self {
        case .respiratoryRate:
            "Breaths per minute from HealthKit samples for the selected day."
        case .restingHeartRate:
            "Your resting heart rate for the selected day."
        case .hrv:
            "Heart rate variability measured in milliseconds."
        case .oxygenSaturation:
            "Blood oxygen saturation from supported HealthKit samples."
        case .wristTemperature:
            "Nighttime temperature variation compared with your personal baseline."
        case .sleep:
            "Total sleep duration for the selected day."
        }
    }

    var measurementMetricType: MeasurementHealthMetricType {
        switch self {
        case .respiratoryRate:
            return .respiratoryRate
        case .restingHeartRate:
            return .restingHeartRate
        case .hrv:
            return .hrv
        case .oxygenSaturation:
            return .oxygenSaturation
        case .wristTemperature:
            return .temperature
        case .sleep:
            return .sleep
        }
    }
}

struct HealthMetricModel: Identifiable, Codable, Equatable {
    var id: HealthMetricKind { kind }
    var kind: HealthMetricKind
    var value: Double?
    var status: HealthMetricStatus
    var baselineValue: Double?
    var comparisonText: String
    var sourceBadges: [SourceProvenance]
    var lastUpdated: Date?
    var sourceResolution: MetricSourceResolution?

    init(
        kind: HealthMetricKind,
        value: Double?,
        status: HealthMetricStatus,
        baselineValue: Double? = nil,
        comparisonText: String,
        sourceBadges: [SourceProvenance] = [],
        lastUpdated: Date? = nil,
        sourceResolution: MetricSourceResolution? = nil
    ) {
        self.kind = kind
        self.value = value
        self.status = value == nil ? .noData : status
        self.baselineValue = baselineValue
        self.comparisonText = comparisonText
        self.sourceBadges = SourceResolver.uniqueSourceBadges(sourceBadges)
        self.lastUpdated = lastUpdated
        self.sourceResolution = sourceResolution
    }

    static func noData(
        kind: HealthMetricKind,
        comparisonText: String = "No data was available for this metric on the selected day.",
        lastUpdated: Date? = nil,
        sourceResolution: MetricSourceResolution? = nil
    ) -> HealthMetricModel {
        HealthMetricModel(
            kind: kind,
            value: nil,
            status: .noData,
            baselineValue: nil,
            comparisonText: comparisonText,
            sourceBadges: [],
            lastUpdated: lastUpdated,
            sourceResolution: sourceResolution
        )
    }

    var hasData: Bool {
        value != nil
    }

    var title: String { kind.title }
    var abbreviation: String { kind.abbreviation }
    var systemImageName: String { kind.systemImageName }
    var unitText: String? { kind.unitText }
    var descriptionText: String { kind.descriptionText }

    var displayValueText: String {
        guard let value else { return "No data" }
        switch kind {
        case .respiratoryRate:
            return String(format: "%.1f", value)
        case .restingHeartRate, .hrv:
            return "\(Int(value.rounded()))"
        case .oxygenSaturation:
            return "\(Int((value * 100).rounded()))"
        case .wristTemperature:
            return value == 0 ? "0.0" : String(format: "%+.1f", value)
        case .sleep:
            return Self.durationText(minutes: value)
        }
    }

    var detailValueText: String {
        guard hasData else { return "No data" }
        if kind == .wristTemperature {
            return "\(displayValueText) °C vs baseline"
        }
        if let unitText {
            return "\(displayValueText) \(unitText)"
        }
        return displayValueText
    }

    var referenceValueText: String? {
        guard let baselineValue else { return nil }
        switch kind {
        case .respiratoryRate:
            return String(format: "Reference %.1f rpm", baselineValue)
        case .restingHeartRate:
            return "Reference \(Int(baselineValue.rounded())) bpm"
        case .hrv:
            return "Reference \(Int(baselineValue.rounded())) ms"
        case .oxygenSaturation:
            return "Reference \(Int((baselineValue * 100).rounded()))%"
        case .wristTemperature:
            let formatted = baselineValue == 0 ? "0.0" : String(format: "%+.1f", baselineValue)
            return "Nighttime temperature vs baseline \(formatted) °C"
        case .sleep:
            return "Reference \(Self.durationText(minutes: baselineValue))"
        }
    }

    var accessibilityLabel: String {
        let sourceText = sourceBadges.isEmpty ? "" : ", source \(sourceBadges.map(\.displayName).joined(separator: ", "))"
        return "\(title), \(detailValueText), \(status.rawValue)\(sourceText)"
    }

    private static func durationText(minutes: Double) -> String {
        let totalMinutes = max(0, Int(minutes.rounded()))
        let hours = totalMinutes / 60
        let remainder = totalMinutes % 60
        if hours > 0 && remainder > 0 {
            return "\(hours)h \(remainder)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(remainder)m"
    }
}

struct HealthMonitorSummary: Codable, Equatable {
    var date: Date?
    var metrics: [HealthMetricModel]
    var lastUpdated: Date?
    var baselineWindowDays: Int
    var sourceBadges: [SourceProvenance]

    init(
        date: Date?,
        metrics: [HealthMetricModel],
        lastUpdated: Date?,
        baselineWindowDays: Int,
        sourceBadges: [SourceProvenance]
    ) {
        self.date = date
        self.metrics = Self.ordered(metrics)
        self.lastUpdated = lastUpdated
        self.baselineWindowDays = max(0, baselineWindowDays)
        self.sourceBadges = SourceResolver.uniqueSourceBadges(sourceBadges)
    }

    static func missing(date: Date? = nil, lastUpdated: Date? = nil) -> HealthMonitorSummary {
        HealthMonitorSummary(
            date: date,
            metrics: HealthMetricKind.allCases.map { HealthMetricModel.noData(kind: $0, lastUpdated: lastUpdated) },
            lastUpdated: lastUpdated,
            baselineWindowDays: 0,
            sourceBadges: []
        )
    }

    var availableMetricCount: Int {
        metrics.filter { $0.hasData }.count
    }

    func metric(_ kind: HealthMetricKind) -> HealthMetricModel {
        metrics.first(where: { $0.kind == kind }) ?? .noData(kind: kind, lastUpdated: lastUpdated)
    }

    private static func ordered(_ metrics: [HealthMetricModel]) -> [HealthMetricModel] {
        let byKind = Dictionary(uniqueKeysWithValues: metrics.map { ($0.kind, $0) })
        return HealthMetricKind.allCases.map { byKind[$0] ?? .noData(kind: $0) }
    }
}
