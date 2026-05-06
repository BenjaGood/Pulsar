import Foundation

enum PulsarSyncSourceDevice: String, Codable {
    case iPhone
    case appleWatch
}

enum PulsarSyncConfidence: String, Codable {
    case high
    case moderate
    case low
    case missing
}

enum PulsarDailyMetricsDateKey {
    nonisolated static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        guard let year = components.year,
              let month = components.month,
              let dayNumber = components.day else { return "" }
        return String(format: "%04d-%02d-%02d", year, month, dayNumber)
    }
}

struct PulsarStrainSyncMetric: Codable, Equatable {
    var score: Int
    var confidence: PulsarSyncConfidence
    var rawLoad: Double
    var workoutLoad: Double
    var movementLoad: Double
    var steps: Int
    var activeEnergyKilocalories: Double?
    var exerciseMinutes: Double
    var workoutMinutes: Double
    var averageActiveHeartRate: Double?
    var peakHeartRate: Double?
    var sourceNames: [String]
    var computedAt: Date

    nonisolated var isValid: Bool {
        guard (1...100).contains(score),
              rawLoad.isFinite,
              workoutLoad.isFinite,
              movementLoad.isFinite,
              rawLoad >= 0,
              workoutLoad >= 0,
              movementLoad >= 0,
              steps >= 0,
              exerciseMinutes.isFinite,
              workoutMinutes.isFinite,
              exerciseMinutes >= 0,
              workoutMinutes >= 0,
              exerciseMinutes <= 1_440,
              workoutMinutes <= 1_440,
              computedAt.timeIntervalSinceReferenceDate.isFinite else { return false }
        if let activeEnergyKilocalories, (!activeEnergyKilocalories.isFinite || activeEnergyKilocalories < 0 || activeEnergyKilocalories > 20_000) { return false }
        if let averageActiveHeartRate, !(30...240).contains(averageActiveHeartRate) { return false }
        if let peakHeartRate, !(30...260).contains(peakHeartRate) { return false }
        return true
    }
}

struct PulsarRecoverySyncMetric: Codable, Equatable {
    var score: Int
    var confidence: PulsarSyncConfidence
    var statusText: String
    var hrvSDNN: Double?
    var hrvBaseline: Double?
    var restingHeartRate: Double?
    var restingHeartRateBaseline: Double?
    var sleepDuration: TimeInterval?
    var sleepEfficiency: Double?
    var strainScore: Double?
    var respiratoryRate: Double?
    var oxygenSaturation: Double?
    var wristTemperatureDeviation: Double?
    var hrvReadiness: Double
    var restingHeartRateReadiness: Double
    var respiratoryStability: Double
    var sleepContribution: Double
    var strainPenalty: Double
    var sourceNames: [String]
    var computedAt: Date

    nonisolated var isValid: Bool {
        guard (1...100).contains(score),
              hrvReadiness.isFinite,
              restingHeartRateReadiness.isFinite,
              respiratoryStability.isFinite,
              sleepContribution.isFinite,
              strainPenalty.isFinite,
              (0...1).contains(hrvReadiness),
              (0...1).contains(restingHeartRateReadiness),
              (0...1).contains(respiratoryStability),
              (0...1).contains(sleepContribution),
              (0...1).contains(strainPenalty),
              computedAt.timeIntervalSinceReferenceDate.isFinite else { return false }
        if let hrvSDNN, !(5...250).contains(hrvSDNN) { return false }
        if let hrvBaseline, !(5...250).contains(hrvBaseline) { return false }
        if let restingHeartRate, !(30...120).contains(restingHeartRate) { return false }
        if let restingHeartRateBaseline, !(30...120).contains(restingHeartRateBaseline) { return false }
        if let sleepDuration, !sleepDuration.isFinite || sleepDuration < 0 || sleepDuration > 86_400 { return false }
        if let sleepEfficiency, !(0...1).contains(sleepEfficiency) { return false }
        if let strainScore, !(0...100).contains(strainScore) { return false }
        if let respiratoryRate, !(6...30).contains(respiratoryRate) { return false }
        if let oxygenSaturation, !(0.5...1).contains(oxygenSaturation) { return false }
        if let wristTemperatureDeviation, !wristTemperatureDeviation.isFinite || abs(wristTemperatureDeviation) > 10 { return false }
        return true
    }
}

struct PulsarSleepSyncMetric: Codable, Equatable {
    var score: Int
    var confidence: PulsarSyncConfidence
    var sleepDateKey: String
    var wakeUpDate: Date
    var sleepStart: Date
    var sleepEnd: Date
    var queryStart: Date
    var queryEnd: Date
    var totalSleepMinutes: Double
    var timeInBedMinutes: Double
    var sleepEfficiency: Double
    var awakeMinutes: Double
    var wasoMinutes: Double
    var remMinutes: Double
    var coreMinutes: Double
    var deepMinutes: Double
    var asleepUnspecifiedMinutes: Double
    var awakenings: Int
    var analyzedSampleCount: Int
    var sleepConsistency: Double
    var sleepPerformance: Double
    var durationAdequacy: Double
    var regularity: Double
    var continuity: Double
    var targetSleepHours: Double
    var sourceNames: [String]
    var computedAt: Date

    nonisolated var isValid: Bool {
        guard (1...100).contains(score),
              !sleepDateKey.isEmpty,
              wakeUpDate.timeIntervalSinceReferenceDate.isFinite,
              sleepStart.timeIntervalSinceReferenceDate.isFinite,
              sleepEnd.timeIntervalSinceReferenceDate.isFinite,
              queryStart.timeIntervalSinceReferenceDate.isFinite,
              queryEnd.timeIntervalSinceReferenceDate.isFinite,
              computedAt.timeIntervalSinceReferenceDate.isFinite,
              sleepStart < sleepEnd,
              queryStart < queryEnd,
              queryStart <= sleepStart,
              sleepEnd <= queryEnd,
              totalSleepMinutes.isFinite,
              timeInBedMinutes.isFinite,
              sleepEfficiency.isFinite,
              awakeMinutes.isFinite,
              wasoMinutes.isFinite,
              remMinutes.isFinite,
              coreMinutes.isFinite,
              deepMinutes.isFinite,
              asleepUnspecifiedMinutes.isFinite,
              sleepConsistency.isFinite,
              sleepPerformance.isFinite,
              durationAdequacy.isFinite,
              regularity.isFinite,
              continuity.isFinite,
              targetSleepHours.isFinite,
              totalSleepMinutes > 0,
              timeInBedMinutes > 0,
              totalSleepMinutes <= 1_440,
              timeInBedMinutes <= 1_440,
              (0...1).contains(sleepEfficiency),
              (0...1).contains(sleepConsistency),
              (0...1).contains(sleepPerformance),
              (0...1).contains(durationAdequacy),
              (0...1).contains(regularity),
              (0...1).contains(continuity),
              awakeMinutes >= 0,
              wasoMinutes >= 0,
              remMinutes >= 0,
              coreMinutes >= 0,
              deepMinutes >= 0,
              asleepUnspecifiedMinutes >= 0,
              awakenings >= 0,
              analyzedSampleCount > 0,
              (4...14).contains(targetSleepHours) else { return false }
        return true
    }
}

struct PulsarDailyMetricsSyncPayload: Codable, Equatable {
    var date: Date
    var dateKey: String? = nil
    var syncedAt: Date
    var sourceDevice: PulsarSyncSourceDevice
    var strain: PulsarStrainSyncMetric?
    var recovery: PulsarRecoverySyncMetric?
    var sleep: PulsarSleepSyncMetric? = nil
    var syncSessionID: UUID? = nil
    var dataFingerprint: String? = nil
    var validityFlag: Bool? = nil

    nonisolated var hasValidData: Bool {
        hasCompleteDailyScores || hasValidSleep
    }

    nonisolated var hasCompleteDailyScores: Bool {
        strain?.isValid == true && recovery?.isValid == true
    }

    nonisolated var hasPartialDailyScores: Bool {
        (strain != nil || recovery != nil) && !hasCompleteDailyScores
    }

    nonisolated var hasValidSleep: Bool {
        sleep?.isValid == true
    }

    nonisolated var dailyMetricsComputedAt: Date? {
        guard let strain, let recovery, strain.isValid, recovery.isValid else { return nil }
        return max(strain.computedAt, recovery.computedAt)
    }

    nonisolated var sleepComputedAt: Date? {
        guard let sleep, sleep.isValid else { return nil }
        return sleep.computedAt
    }

    nonisolated var resolvedDateKey: String {
        if let dateKey, !dateKey.isEmpty { return dateKey }
        return ""
    }

    nonisolated var isValidPayload: Bool {
        guard validityFlag ?? true,
              hasValidData,
              !hasPartialDailyScores,
              syncSessionID != nil,
              !resolvedDateKey.isEmpty,
              date.timeIntervalSinceReferenceDate.isFinite,
              syncedAt.timeIntervalSinceReferenceDate.isFinite else { return false }
        return !resolvedDataFingerprint.isEmpty
    }

    nonisolated var resolvedDataFingerprint: String {
        if let dataFingerprint, !dataFingerprint.isEmpty { return dataFingerprint }
        return Self.makeFingerprint(dateKey: resolvedDateKey, strain: strain, recovery: recovery, sleep: sleep)
    }

    nonisolated func applies(to day: Date, calendar: Calendar = .current) -> Bool {
        resolvedDateKey == PulsarDailyMetricsDateKey.dateKey(for: day, calendar: calendar)
    }

    nonisolated func merged(with other: PulsarDailyMetricsSyncPayload, calendar: Calendar = .current) -> PulsarDailyMetricsSyncPayload {
        guard other.isValidPayload else { return self }
        guard isValidPayload else { return other }
        let lhsKey = resolvedDateKey
        let rhsKey = other.resolvedDateKey
        guard lhsKey == rhsKey else { return syncedAt >= other.syncedAt ? self : other }

        let newer = syncedAt >= other.syncedAt ? self : other
        let dailySource = Self.newerMetricSource(lhs: self, rhs: other, timestamp: \.dailyMetricsComputedAt, isPresent: \.hasCompleteDailyScores)
        let sleepSource = Self.newerMetricSource(lhs: self, rhs: other, timestamp: \.sleepComputedAt, isPresent: \.hasValidSleep)

        let merged = PulsarDailyMetricsSyncPayload(
            date: newer.date,
            dateKey: newer.resolvedDateKey,
            syncedAt: newer.syncedAt,
            sourceDevice: newer.sourceDevice,
            strain: dailySource?.strain,
            recovery: dailySource?.recovery,
            sleep: sleepSource?.sleep,
            syncSessionID: newer.syncSessionID,
            dataFingerprint: nil,
            validityFlag: true
        )
        guard merged.resolvedDataFingerprint != resolvedDataFingerprint else { return self }
        return merged
    }

    private nonisolated static func newerMetricSource(
        lhs: PulsarDailyMetricsSyncPayload,
        rhs: PulsarDailyMetricsSyncPayload,
        timestamp: KeyPath<PulsarDailyMetricsSyncPayload, Date?>,
        isPresent: KeyPath<PulsarDailyMetricsSyncPayload, Bool>
    ) -> PulsarDailyMetricsSyncPayload? {
        guard lhs[keyPath: isPresent] || rhs[keyPath: isPresent] else { return nil }
        guard lhs[keyPath: isPresent] else { return rhs }
        guard rhs[keyPath: isPresent] else { return lhs }
        let lhsTimestamp = lhs[keyPath: timestamp] ?? lhs.syncedAt
        let rhsTimestamp = rhs[keyPath: timestamp] ?? rhs.syncedAt
        return lhsTimestamp >= rhsTimestamp ? lhs : rhs
    }

    private nonisolated static func makeFingerprint(dateKey: String, strain: PulsarStrainSyncMetric?, recovery: PulsarRecoverySyncMetric?, sleep: PulsarSleepSyncMetric?) -> String {
        var parts: [String] = []
        if !dateKey.isEmpty {
            parts.append("date:\(dateKey)")
        }
        if let strain, let recovery, strain.isValid, recovery.isValid {
            parts.append([
                "strain",
                "\(strain.score)",
                rounded(strain.rawLoad),
                rounded(strain.workoutLoad),
                rounded(strain.movementLoad),
                "\(strain.steps)",
                rounded(strain.activeEnergyKilocalories),
                rounded(strain.exerciseMinutes),
                rounded(strain.workoutMinutes),
                rounded(strain.averageActiveHeartRate),
                rounded(strain.peakHeartRate),
                strain.confidence.rawValue
            ].joined(separator: ":"))
            parts.append([
                "recovery",
                "\(recovery.score)",
                recovery.confidence.rawValue,
                recovery.statusText,
                rounded(recovery.hrvSDNN),
                rounded(recovery.hrvBaseline),
                rounded(recovery.restingHeartRate),
                rounded(recovery.restingHeartRateBaseline),
                rounded(recovery.sleepDuration),
                rounded(recovery.sleepEfficiency),
                rounded(recovery.strainScore),
                rounded(recovery.respiratoryRate),
                rounded(recovery.oxygenSaturation),
                rounded(recovery.wristTemperatureDeviation),
                rounded(recovery.hrvReadiness),
                rounded(recovery.restingHeartRateReadiness),
                rounded(recovery.respiratoryStability),
                rounded(recovery.sleepContribution),
                rounded(recovery.strainPenalty)
            ].joined(separator: ":"))
        }
        if let sleep, sleep.isValid {
            parts.append([
                "sleep",
                "\(sleep.score)",
                sleep.confidence.rawValue,
                sleep.sleepDateKey,
                rounded(sleep.sleepStart.timeIntervalSinceReferenceDate),
                rounded(sleep.sleepEnd.timeIntervalSinceReferenceDate),
                rounded(sleep.queryStart.timeIntervalSinceReferenceDate),
                rounded(sleep.queryEnd.timeIntervalSinceReferenceDate),
                rounded(sleep.totalSleepMinutes),
                rounded(sleep.timeInBedMinutes),
                rounded(sleep.sleepEfficiency),
                rounded(sleep.awakeMinutes),
                rounded(sleep.wasoMinutes),
                rounded(sleep.remMinutes),
                rounded(sleep.coreMinutes),
                rounded(sleep.deepMinutes),
                rounded(sleep.asleepUnspecifiedMinutes),
                "\(sleep.awakenings)",
                "\(sleep.analyzedSampleCount)",
                rounded(sleep.sleepConsistency),
                rounded(sleep.sleepPerformance),
                rounded(sleep.durationAdequacy),
                rounded(sleep.regularity),
                rounded(sleep.continuity),
                rounded(sleep.targetSleepHours)
            ].joined(separator: ":"))
        }
        return parts.joined(separator: "|")
    }

    private nonisolated static func rounded(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "nil" }
        return String(format: "%.3f", value)
    }
}

enum PulsarSyncPayloadCodec {
    static let payloadKey = "pulsar.dailyMetricsPayload"

    static func encode(_ payload: PulsarDailyMetricsSyncPayload) -> Data? {
        try? JSONEncoder().encode(payload)
    }

    static func decode(data: Data) -> PulsarDailyMetricsSyncPayload? {
        try? JSONDecoder().decode(PulsarDailyMetricsSyncPayload.self, from: data)
    }
}

enum PulsarSyncDebugLogger {
    nonisolated static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[PulsarSync] \(message())")
        #endif
    }
}
