//
//  DailyStrainRecord.swift
//  Pulsar
//

import Foundation

struct DailyStrainRecord: Identifiable, Hashable, Codable {
    var id: String { dateKey }
    var dateKey: String
    var date: Date
    var sleepScore: Int?
    var sleepMinutes: Int?
    var recoveryScore: Int?
    var stressScore: Int?
    var stressTimelineSamples: [StressSample]
    var strainScore: Int
    var respiratoryRate: Double?
    var respiratoryRateStatus: HealthMetricStatus?
    var restingHeartRate: Double?
    var restingHeartRateStatus: HealthMetricStatus?
    var hrv: Double?
    var hrvStatus: HealthMetricStatus?
    var oxygenSaturation: Double?
    var oxygenSaturationStatus: HealthMetricStatus?
    var wristTemperatureDeviation: Double?
    var wristTemperatureStatus: HealthMetricStatus?
    var sleepDurationStatus: HealthMetricStatus?
    var workoutMinutes: Int
    var steps: Int
    var activeEnergyKilocalories: Int
    var confidence: ConfidenceGrade
    var sourceName: String
    var syncedAt: Date

    private enum CodingKeys: String, CodingKey {
        case dateKey
        case date
        case sleepScore
        case sleepMinutes
        case recoveryScore
        case stressScore
        case stressTimelineSamples
        case strainScore
        case respiratoryRate
        case respiratoryRateStatus
        case restingHeartRate
        case restingHeartRateStatus
        case hrv
        case hrvStatus
        case oxygenSaturation
        case oxygenSaturationStatus
        case wristTemperatureDeviation
        case wristTemperatureStatus
        case sleepDurationStatus
        case workoutMinutes
        case steps
        case activeEnergyKilocalories
        case confidence
        case sourceName
        case syncedAt
    }

    nonisolated init(
        date: Date,
        dateKey: String? = nil,
        calendar: Calendar = .current,
        sleepScore: Int? = nil,
        sleepMinutes: Int? = nil,
        recoveryScore: Int? = nil,
        stressScore: Int? = nil,
        stressTimelineSamples: [StressSample] = [],
        strainScore: Int,
        respiratoryRate: Double? = nil,
        respiratoryRateStatus: HealthMetricStatus? = nil,
        restingHeartRate: Double? = nil,
        restingHeartRateStatus: HealthMetricStatus? = nil,
        hrv: Double? = nil,
        hrvStatus: HealthMetricStatus? = nil,
        oxygenSaturation: Double? = nil,
        oxygenSaturationStatus: HealthMetricStatus? = nil,
        wristTemperatureDeviation: Double? = nil,
        wristTemperatureStatus: HealthMetricStatus? = nil,
        sleepDurationStatus: HealthMetricStatus? = nil,
        workoutMinutes: Int,
        steps: Int,
        activeEnergyKilocalories: Int,
        confidence: ConfidenceGrade,
        sourceName: String,
        syncedAt: Date = Date()
    ) {
        let day = calendar.startOfDay(for: date)
        self.dateKey = dateKey ?? PulsarDailyMetricsDateKey.dateKey(for: day, calendar: calendar)
        self.date = day
        self.sleepScore = Self.clampedOptionalScore(sleepScore)
        self.sleepMinutes = sleepMinutes.map { max(0, $0) }
        self.recoveryScore = Self.clampedOptionalScore(recoveryScore)
        self.stressScore = Self.clampedOptionalScore(stressScore)
        self.stressTimelineSamples = Self.validatedStressTimeline(stressTimelineSamples)
        self.strainScore = min(100, max(0, strainScore))
        self.respiratoryRate = Self.validatedMetricValue(respiratoryRate)
        self.respiratoryRateStatus = respiratoryRate == nil ? nil : respiratoryRateStatus
        self.restingHeartRate = Self.validatedMetricValue(restingHeartRate)
        self.restingHeartRateStatus = restingHeartRate == nil ? nil : restingHeartRateStatus
        self.hrv = Self.validatedMetricValue(hrv)
        self.hrvStatus = hrv == nil ? nil : hrvStatus
        self.oxygenSaturation = Self.validatedMetricValue(oxygenSaturation)
        self.oxygenSaturationStatus = oxygenSaturation == nil ? nil : oxygenSaturationStatus
        self.wristTemperatureDeviation = Self.validatedMetricValue(wristTemperatureDeviation)
        self.wristTemperatureStatus = wristTemperatureDeviation == nil ? nil : wristTemperatureStatus
        self.sleepDurationStatus = sleepMinutes == nil ? nil : sleepDurationStatus
        self.workoutMinutes = max(0, workoutMinutes)
        self.steps = max(0, steps)
        self.activeEnergyKilocalories = max(0, activeEnergyKilocalories)
        self.confidence = confidence
        self.sourceName = sourceName.isEmpty ? "HealthKit" : sourceName
        self.syncedAt = syncedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedDate = try container.decode(Date.self, forKey: .date)
        let decodedDateKey = try container.decodeIfPresent(String.self, forKey: .dateKey)
        self.init(
            date: decodedDate,
            dateKey: decodedDateKey,
            sleepScore: try container.decodeIfPresent(Int.self, forKey: .sleepScore),
            sleepMinutes: try container.decodeIfPresent(Int.self, forKey: .sleepMinutes),
            recoveryScore: try container.decodeIfPresent(Int.self, forKey: .recoveryScore),
            stressScore: try container.decodeIfPresent(Int.self, forKey: .stressScore),
            stressTimelineSamples: try container.decodeIfPresent([StressSample].self, forKey: .stressTimelineSamples) ?? [],
            strainScore: try container.decodeIfPresent(Int.self, forKey: .strainScore) ?? 0,
            respiratoryRate: try container.decodeIfPresent(Double.self, forKey: .respiratoryRate),
            respiratoryRateStatus: try container.decodeIfPresent(HealthMetricStatus.self, forKey: .respiratoryRateStatus),
            restingHeartRate: try container.decodeIfPresent(Double.self, forKey: .restingHeartRate),
            restingHeartRateStatus: try container.decodeIfPresent(HealthMetricStatus.self, forKey: .restingHeartRateStatus),
            hrv: try container.decodeIfPresent(Double.self, forKey: .hrv),
            hrvStatus: try container.decodeIfPresent(HealthMetricStatus.self, forKey: .hrvStatus),
            oxygenSaturation: try container.decodeIfPresent(Double.self, forKey: .oxygenSaturation),
            oxygenSaturationStatus: try container.decodeIfPresent(HealthMetricStatus.self, forKey: .oxygenSaturationStatus),
            wristTemperatureDeviation: try container.decodeIfPresent(Double.self, forKey: .wristTemperatureDeviation),
            wristTemperatureStatus: try container.decodeIfPresent(HealthMetricStatus.self, forKey: .wristTemperatureStatus),
            sleepDurationStatus: try container.decodeIfPresent(HealthMetricStatus.self, forKey: .sleepDurationStatus),
            workoutMinutes: try container.decodeIfPresent(Int.self, forKey: .workoutMinutes) ?? 0,
            steps: try container.decodeIfPresent(Int.self, forKey: .steps) ?? 0,
            activeEnergyKilocalories: try container.decodeIfPresent(Int.self, forKey: .activeEnergyKilocalories) ?? 0,
            confidence: try container.decodeIfPresent(ConfidenceGrade.self, forKey: .confidence) ?? .missing,
            sourceName: try container.decodeIfPresent(String.self, forKey: .sourceName) ?? "HealthKit",
            syncedAt: try container.decodeIfPresent(Date.self, forKey: .syncedAt) ?? decodedDate
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dateKey, forKey: .dateKey)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(sleepScore, forKey: .sleepScore)
        try container.encodeIfPresent(sleepMinutes, forKey: .sleepMinutes)
        try container.encodeIfPresent(recoveryScore, forKey: .recoveryScore)
        try container.encodeIfPresent(stressScore, forKey: .stressScore)
        try container.encode(stressTimelineSamples, forKey: .stressTimelineSamples)
        try container.encode(strainScore, forKey: .strainScore)
        try container.encodeIfPresent(respiratoryRate, forKey: .respiratoryRate)
        try container.encodeIfPresent(respiratoryRateStatus, forKey: .respiratoryRateStatus)
        try container.encodeIfPresent(restingHeartRate, forKey: .restingHeartRate)
        try container.encodeIfPresent(restingHeartRateStatus, forKey: .restingHeartRateStatus)
        try container.encodeIfPresent(hrv, forKey: .hrv)
        try container.encodeIfPresent(hrvStatus, forKey: .hrvStatus)
        try container.encodeIfPresent(oxygenSaturation, forKey: .oxygenSaturation)
        try container.encodeIfPresent(oxygenSaturationStatus, forKey: .oxygenSaturationStatus)
        try container.encodeIfPresent(wristTemperatureDeviation, forKey: .wristTemperatureDeviation)
        try container.encodeIfPresent(wristTemperatureStatus, forKey: .wristTemperatureStatus)
        try container.encodeIfPresent(sleepDurationStatus, forKey: .sleepDurationStatus)
        try container.encode(workoutMinutes, forKey: .workoutMinutes)
        try container.encode(steps, forKey: .steps)
        try container.encode(activeEnergyKilocalories, forKey: .activeEnergyKilocalories)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(sourceName, forKey: .sourceName)
        try container.encode(syncedAt, forKey: .syncedAt)
    }

    init?(payload: PulsarDailyMetricsSyncPayload, calendar: Calendar = .current) {
        guard payload.isValidPayload else { return nil }
        let dateKey = payload.resolvedDateKey
        let day = PulsarDailyMetricsDateKey.date(from: dateKey, calendar: calendar) ?? calendar.startOfDay(for: payload.date)
        let sourceNames = [
            payload.strain?.sourceNames,
            payload.recovery?.sourceNames,
            payload.sleep?.sourceNames,
            payload.stress?.sourceNames
        ]
            .compactMap { $0 }
            .flatMap { $0 }
        let confidence = [
            payload.strain?.confidence,
            payload.recovery?.confidence,
            payload.sleep?.confidence,
            payload.stress?.confidence
        ]
            .compactMap { $0?.appConfidence }
            .sorted(by: Self.confidenceSort)
            .first ?? .missing
        let latestMetricDate = [
            payload.strain?.computedAt,
            payload.recovery?.computedAt,
            payload.sleep?.computedAt,
            payload.stress?.computedAt,
            payload.healthMonitor?.computedAt,
            payload.syncedAt
        ]
            .compactMap { $0 }
            .max() ?? payload.syncedAt
        let metricLookup = Dictionary(uniqueKeysWithValues: (payload.healthMonitor?.metrics ?? []).map { ($0.kind.appKind, $0) })
        let sleepMetric = metricLookup[.sleep]

        self.init(
            date: day,
            dateKey: dateKey,
            calendar: calendar,
            sleepScore: payload.sleep?.score,
            sleepMinutes: payload.sleep.map { Int($0.totalSleepMinutes.rounded()) } ?? sleepMetric?.value.map { Int($0.rounded()) },
            recoveryScore: payload.recovery?.score,
            stressScore: payload.stress?.score,
            stressTimelineSamples: payload.stress?.timelineSamples.map {
                StressSample(
                    timestamp: $0.timestamp,
                    score: $0.score,
                    confidence: payload.stress?.confidence.appConfidence ?? .missing,
                    context: $0.context.flatMap(StressContext.init(rawValue:))
                )
            } ?? [],
            strainScore: payload.strain?.score ?? 0,
            respiratoryRate: metricLookup[.respiratoryRate]?.value,
            respiratoryRateStatus: metricLookup[.respiratoryRate]?.status.appStatus,
            restingHeartRate: metricLookup[.restingHeartRate]?.value,
            restingHeartRateStatus: metricLookup[.restingHeartRate]?.status.appStatus,
            hrv: metricLookup[.hrv]?.value,
            hrvStatus: metricLookup[.hrv]?.status.appStatus,
            oxygenSaturation: metricLookup[.oxygenSaturation]?.value,
            oxygenSaturationStatus: metricLookup[.oxygenSaturation]?.status.appStatus,
            wristTemperatureDeviation: metricLookup[.wristTemperature]?.value,
            wristTemperatureStatus: metricLookup[.wristTemperature]?.status.appStatus,
            sleepDurationStatus: sleepMetric?.status.appStatus,
            workoutMinutes: Int((payload.strain?.workoutMinutes ?? 0).rounded()),
            steps: payload.strain?.steps ?? 0,
            activeEnergyKilocalories: Int((payload.strain?.activeEnergyKilocalories ?? 0).rounded()),
            confidence: confidence,
            sourceName: sourceNames.first ?? payload.sourceDevice.displayName,
            syncedAt: latestMetricDate
        )
    }

    var normalizedScore: Double {
        min(1, max(0, Double(strainScore) / 100))
    }

    var hasRecordedData: Bool {
        sleepScore != nil ||
            recoveryScore != nil ||
            stressScore != nil ||
            !stressTimelineSamples.isEmpty ||
            strainScore > 0 ||
            workoutMinutes > 0 ||
            steps > 0 ||
            activeEnergyKilocalories > 0
    }

    var intensity: StrainIntensity {
        switch strainScore {
        case 1..<35: .low
        case 35..<70: .moderate
        case 70...100: .high
        default: .none
        }
    }
}

enum StrainIntensity: String, Codable {
    case none
    case low
    case moderate
    case high
}

enum MockStrainCalendarData {
    nonisolated static func runtimePlaceholderRecords(firstLaunchDate: Date, today: Date = Date(), calendar: Calendar = .current) -> [DailyStrainRecord] {
        // Runtime placeholder data must never imply history before install or after today.
        let start = calendar.startOfDay(for: firstLaunchDate)
        let end = calendar.startOfDay(for: today)
        guard start < end else { return [] }

        let recentOffsets = [3, 2, 1]
        return recentOffsets.compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end), date >= start else { return nil }
            return record(on: date, seed: calendar.component(.day, from: date), calendar: calendar)
        }
    }

    nonisolated static func previewRecords(around date: Date = .now, calendar: Calendar = .current) -> [DailyStrainRecord] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date),
               let range = calendar.range(of: .day, in: .month, for: date) else { return [] }

        return range.compactMap { day -> DailyStrainRecord? in
            guard day % 4 != 0,
                   let recordDate = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) else { return nil }
            return record(on: recordDate, seed: day, calendar: calendar)
        }
    }

    nonisolated private static func record(on date: Date, seed: Int, calendar: Calendar) -> DailyStrainRecord {
        let score = min(96, max(12, (seed * 11 + 23) % 101))
        return DailyStrainRecord(
            date: calendar.startOfDay(for: date),
            calendar: calendar,
            sleepScore: min(95, max(42, score - 5 + seed % 10)),
            sleepMinutes: 390 + seed % 80,
            recoveryScore: min(98, max(36, score + 8 - seed % 12)),
            stressScore: min(88, max(12, 100 - score + seed % 9)),
            strainScore: score,
            workoutMinutes: score > 65 ? 62 + seed % 20 : score > 35 ? 34 + seed % 16 : 12 + seed % 10,
            steps: 4_500 + seed * 347,
            activeEnergyKilocalories: 220 + score * 7,
            confidence: score > 70 ? .high : .moderate,
            sourceName: seed % 3 == 0 ? "Apple Watch" : "HealthKit"
        )
    }
}

extension DailyStrainRecord {
    func merged(with other: DailyStrainRecord, calendar: Calendar = .current) -> DailyStrainRecord {
        guard dateKey == other.dateKey else { return syncedAt >= other.syncedAt ? self : other }
        let preferOther = other.syncedAt >= syncedAt
        let mergedSource = sourceName == other.sourceName ? sourceName : [sourceName, other.sourceName].filter { !$0.isEmpty }.first ?? "HealthKit"
        let otherHasDailyStrain = other.recoveryScore != nil || other.strainScore > 0 || other.workoutMinutes > 0 || other.steps > 0 || other.activeEnergyKilocalories > 0
        return DailyStrainRecord(
            date: preferOther ? other.date : date,
            dateKey: dateKey,
            calendar: calendar,
            sleepScore: preferOther ? (other.sleepScore ?? sleepScore) : (sleepScore ?? other.sleepScore),
            sleepMinutes: preferOther ? (other.sleepMinutes ?? sleepMinutes) : (sleepMinutes ?? other.sleepMinutes),
            recoveryScore: preferOther ? (other.recoveryScore ?? recoveryScore) : (recoveryScore ?? other.recoveryScore),
            stressScore: preferOther ? (other.stressScore ?? stressScore) : (stressScore ?? other.stressScore),
            stressTimelineSamples: preferOther ? (!other.stressTimelineSamples.isEmpty ? other.stressTimelineSamples : stressTimelineSamples) : (!stressTimelineSamples.isEmpty ? stressTimelineSamples : other.stressTimelineSamples),
            strainScore: preferOther && otherHasDailyStrain ? other.strainScore : (strainScore > 0 ? strainScore : other.strainScore),
            respiratoryRate: preferOther ? (other.respiratoryRate ?? respiratoryRate) : (respiratoryRate ?? other.respiratoryRate),
            respiratoryRateStatus: preferOther ? (other.respiratoryRateStatus ?? respiratoryRateStatus) : (respiratoryRateStatus ?? other.respiratoryRateStatus),
            restingHeartRate: preferOther ? (other.restingHeartRate ?? restingHeartRate) : (restingHeartRate ?? other.restingHeartRate),
            restingHeartRateStatus: preferOther ? (other.restingHeartRateStatus ?? restingHeartRateStatus) : (restingHeartRateStatus ?? other.restingHeartRateStatus),
            hrv: preferOther ? (other.hrv ?? hrv) : (hrv ?? other.hrv),
            hrvStatus: preferOther ? (other.hrvStatus ?? hrvStatus) : (hrvStatus ?? other.hrvStatus),
            oxygenSaturation: preferOther ? (other.oxygenSaturation ?? oxygenSaturation) : (oxygenSaturation ?? other.oxygenSaturation),
            oxygenSaturationStatus: preferOther ? (other.oxygenSaturationStatus ?? oxygenSaturationStatus) : (oxygenSaturationStatus ?? other.oxygenSaturationStatus),
            wristTemperatureDeviation: preferOther ? (other.wristTemperatureDeviation ?? wristTemperatureDeviation) : (wristTemperatureDeviation ?? other.wristTemperatureDeviation),
            wristTemperatureStatus: preferOther ? (other.wristTemperatureStatus ?? wristTemperatureStatus) : (wristTemperatureStatus ?? other.wristTemperatureStatus),
            sleepDurationStatus: preferOther ? (other.sleepDurationStatus ?? sleepDurationStatus) : (sleepDurationStatus ?? other.sleepDurationStatus),
            workoutMinutes: preferOther && other.workoutMinutes > 0 ? other.workoutMinutes : max(workoutMinutes, other.workoutMinutes),
            steps: max(steps, other.steps),
            activeEnergyKilocalories: max(activeEnergyKilocalories, other.activeEnergyKilocalories),
            confidence: preferOther ? other.confidence : confidence,
            sourceName: mergedSource,
            syncedAt: max(syncedAt, other.syncedAt)
        )
    }

    private nonisolated static func clampedOptionalScore(_ score: Int?) -> Int? {
        score.map { min(100, max(0, $0)) }
    }

    private nonisolated static func validatedMetricValue(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private nonisolated static func validatedStressTimeline(_ samples: [StressSample]) -> [StressSample] {
        samples
            .filter { $0.timestamp.timeIntervalSinceReferenceDate.isFinite && $0.score.isFinite }
            .map { sample in
                var copy = sample
                copy.score = PulsarStressScale.clampedScore(sample.score)
                return copy
            }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private nonisolated static func confidenceSort(_ lhs: ConfidenceGrade, _ rhs: ConfidenceGrade) -> Bool {
        score(for: lhs) > score(for: rhs)
    }

    private nonisolated static func score(for confidence: ConfidenceGrade) -> Int {
        switch confidence {
        case .high:
            return 3
        case .moderate:
            return 2
        case .low:
            return 1
        case .missing:
            return 0
        }
    }
}

private extension PulsarSyncSourceDevice {
    var displayName: String {
        switch self {
        case .iPhone:
            return "iPhone"
        case .appleWatch:
            return "Apple Watch"
        case .ouraRing:
            return "Oura Ring"
        }
    }
}
