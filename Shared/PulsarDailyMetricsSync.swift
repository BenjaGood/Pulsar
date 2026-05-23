import Foundation

enum PulsarSyncSourceDevice: String, Codable, Hashable {
    case iPhone
    case appleWatch
    case ouraRing

    nonisolated var sourceRouterLogName: String {
        switch self {
        case .iPhone, .appleWatch:
            return "appleWatchHealthKit"
        case .ouraRing:
            return "ouraRing"
        }
    }
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

    nonisolated static func date(from dateKey: String, calendar: Calendar = .current) -> Date? {
        let parts = dateKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.calendar = calendar
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return components.date.map { calendar.startOfDay(for: $0) }
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
    var analyzedSampleCount: Int? = nil
    var heartRateSampleCount: Int? = nil
    var workoutSampleCount: Int? = nil
    var activitySampleCount: Int? = nil

    nonisolated var isValid: Bool {
        guard (0...100).contains(score),
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
        for count in [analyzedSampleCount, heartRateSampleCount, workoutSampleCount, activitySampleCount].compactMap({ $0 }) {
            if count < 0 || count > 100_000 { return false }
        }
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

struct PulsarSleepStageSyncInterval: Codable, Equatable {
    var stage: String
    var start: Date
    var end: Date

    nonisolated var isValid: Bool {
        !stage.isEmpty &&
            start.timeIntervalSinceReferenceDate.isFinite &&
            end.timeIntervalSinceReferenceDate.isFinite &&
            start < end
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
    var stageIntervals: [PulsarSleepStageSyncInterval]? = nil

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
        if let stageIntervals,
           !stageIntervals.allSatisfy(\.isValid) {
            return false
        }
        return true
    }
}

struct PulsarStressSyncSample: Codable, Equatable {
    var timestamp: Date
    var score: Double
    var context: String?
}

struct PulsarStressSyncMetric: Codable, Equatable {
    var score: Int
    var confidence: PulsarSyncConfidence
    var levelText: String
    var driverInsights: [String]
    var hrvSDNN: Double?
    var hrvTimestamp: Date? = nil
    var hrvBaseline: Double? = nil
    var restingHeartRate: Double?
    var restingHeartRateBaseline: Double? = nil
    var respiratoryRate: Double?
    var recentHeartRate: Double?
    var heartRateTimestamp: Date? = nil
    var daytimeHeartRateBaseline: Double? = nil
    var heartRateDeviation: Double? = nil
    var hrvDeviation: Double? = nil
    var nonActivityStress: Double? = nil
    var activityAdjustedStress: Double? = nil
    var rawStressScore: Double? = nil
    var activityAdjustment: Double? = nil
    var smoothedStressScore: Double? = nil
    var movementState: String? = nil
    var recentSteps: Double? = nil
    var recentActiveEnergyKilocalories: Double? = nil
    var isWorkoutActive: Bool = false
    var lastWorkoutEnd: Date? = nil
    var cooldownActive: Bool = false
    var calculationState: String? = nil
    var appliedAdjustments: [String] = []
    var sleepDurationMinutes: Double?
    var strainScore: Double?
    var availableSignalCount: Int
    var baselineWindowDays: Int
    var timelineSamples: [PulsarStressSyncSample]
    var sourceNames: [String]
    var computedAt: Date

    nonisolated var isValid: Bool {
        guard (0...100).contains(score),
              !levelText.isEmpty,
              availableSignalCount >= 0,
              baselineWindowDays >= 0,
              computedAt.timeIntervalSinceReferenceDate.isFinite else { return false }
        if let hrvSDNN, !(5...250).contains(hrvSDNN) { return false }
        if let hrvTimestamp, !hrvTimestamp.timeIntervalSinceReferenceDate.isFinite { return false }
        if let hrvBaseline, !(5...250).contains(hrvBaseline) { return false }
        if let restingHeartRate, !(30...160).contains(restingHeartRate) { return false }
        if let restingHeartRateBaseline, !(30...160).contains(restingHeartRateBaseline) { return false }
        if let respiratoryRate, !(6...35).contains(respiratoryRate) { return false }
        if let recentHeartRate, !(30...240).contains(recentHeartRate) { return false }
        if let heartRateTimestamp, !heartRateTimestamp.timeIntervalSinceReferenceDate.isFinite { return false }
        if let daytimeHeartRateBaseline, !(30...200).contains(daytimeHeartRateBaseline) { return false }
        if let heartRateDeviation, !heartRateDeviation.isFinite { return false }
        if let hrvDeviation, !hrvDeviation.isFinite { return false }
        if let nonActivityStress, !(0...100).contains(nonActivityStress) { return false }
        if let activityAdjustedStress, !(0...100).contains(activityAdjustedStress) { return false }
        if let rawStressScore, !(0...100).contains(rawStressScore) { return false }
        if let activityAdjustment, !activityAdjustment.isFinite { return false }
        if let smoothedStressScore, !(0...100).contains(smoothedStressScore) { return false }
        if let recentSteps, !recentSteps.isFinite || recentSteps < 0 || recentSteps > 20_000 { return false }
        if let recentActiveEnergyKilocalories, !recentActiveEnergyKilocalories.isFinite || recentActiveEnergyKilocalories < 0 || recentActiveEnergyKilocalories > 3_000 { return false }
        if let lastWorkoutEnd, !lastWorkoutEnd.timeIntervalSinceReferenceDate.isFinite { return false }
        if let sleepDurationMinutes, !sleepDurationMinutes.isFinite || sleepDurationMinutes < 0 || sleepDurationMinutes > 1_440 { return false }
        if let strainScore, !(0...100).contains(strainScore) { return false }
        return timelineSamples.allSatisfy { sample in
            sample.timestamp.timeIntervalSinceReferenceDate.isFinite &&
                sample.score.isFinite &&
                (0...100).contains(sample.score)
        }
    }

    nonisolated var sharedCalculationState: PulsarSharedStressCalculationState {
        calculationState.flatMap(PulsarSharedStressCalculationState.init(rawValue:)) ??
            (cooldownActive ? .cooldownPaused : (isWorkoutActive ? .workoutPaused : .measuring))
    }

    nonisolated var isPaused: Bool {
        sharedCalculationState.isPaused
    }
}

enum PulsarHealthMetricSyncKind: String, Codable, CaseIterable {
    case respiratoryRate
    case restingHeartRate
    case hrv
    case oxygenSaturation
    case wristTemperature
    case sleep
}

enum PulsarHealthMetricSyncStatus: String, Codable {
    case normal = "Normal"
    case higher = "Higher"
    case lower = "Lower"
    case noData = "No data"
}

struct PulsarHealthMetricSyncValue: Codable, Equatable {
    var kind: PulsarHealthMetricSyncKind
    var value: Double?
    var status: PulsarHealthMetricSyncStatus
    var baselineValue: Double?
    var comparisonText: String
    var sourceNames: [String]

    nonisolated var isValid: Bool {
        guard !comparisonText.isEmpty else { return false }
        if let value {
            guard value.isFinite else { return false }
            switch kind {
            case .respiratoryRate:
                guard (4...40).contains(value) else { return false }
            case .restingHeartRate:
                guard (25...160).contains(value) else { return false }
            case .hrv:
                guard (5...250).contains(value) else { return false }
            case .oxygenSaturation:
                guard (0.5...1).contains(value) else { return false }
            case .wristTemperature:
                guard abs(value) <= 10 else { return false }
            case .sleep:
                guard (0...1_440).contains(value) else { return false }
            }
        } else if status != .noData {
            return false
        }
        if let baselineValue, !baselineValue.isFinite {
            return false
        }
        return true
    }
}

struct PulsarHealthMonitorSyncMetric: Codable, Equatable {
    var metrics: [PulsarHealthMetricSyncValue]
    var baselineWindowDays: Int
    var sourceNames: [String]
    var computedAt: Date

    nonisolated var isValid: Bool {
        guard baselineWindowDays >= 0,
              computedAt.timeIntervalSinceReferenceDate.isFinite,
              !metrics.isEmpty,
              Set(metrics.map(\.kind)).count == metrics.count,
              metrics.allSatisfy(\.isValid),
              metrics.contains(where: { $0.value != nil }) else { return false }
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
    var stress: PulsarStressSyncMetric? = nil
    var healthMonitor: PulsarHealthMonitorSyncMetric? = nil
    var syncSessionID: UUID? = nil
    var dataFingerprint: String? = nil
    var validityFlag: Bool? = nil

    nonisolated var hasValidData: Bool {
        hasCompleteDailyScores || hasValidRecovery || hasValidStrain || hasValidSleep || hasValidStress || hasValidHealthMonitor
    }

    nonisolated var hasCompleteDailyScores: Bool {
        strain?.isValid == true && recovery?.isValid == true
    }

    nonisolated var hasPartialDailyScores: Bool {
        (strain != nil || recovery != nil) && !hasCompleteDailyScores
    }

    nonisolated var hasValidRecovery: Bool {
        recovery?.isValid == true
    }

    nonisolated var hasValidStrain: Bool {
        strain?.isValid == true
    }

    nonisolated var hasValidSleep: Bool {
        sleep?.isValid == true
    }

    nonisolated var hasValidStress: Bool {
        stress?.isValid == true
    }

    nonisolated var hasValidHealthMonitor: Bool {
        healthMonitor?.isValid == true
    }

    nonisolated var dailyMetricsComputedAt: Date? {
        guard let strain, let recovery, strain.isValid, recovery.isValid else { return nil }
        return max(strain.computedAt, recovery.computedAt)
    }

    nonisolated var sleepComputedAt: Date? {
        guard let sleep, sleep.isValid else { return nil }
        return sleep.computedAt
    }

    nonisolated var stressComputedAt: Date? {
        guard let stress, stress.isValid else { return nil }
        return stress.computedAt
    }

    nonisolated var healthMonitorComputedAt: Date? {
        guard let healthMonitor, healthMonitor.isValid else { return nil }
        return healthMonitor.computedAt
    }

    nonisolated var resolvedDateKey: String {
        if let dateKey, !dateKey.isEmpty { return dateKey }
        return ""
    }

    nonisolated var isValidPayload: Bool {
        guard validityFlag ?? true,
              hasValidData,
              syncSessionID != nil,
              !resolvedDateKey.isEmpty,
              date.timeIntervalSinceReferenceDate.isFinite,
              syncedAt.timeIntervalSinceReferenceDate.isFinite else { return false }
        return !resolvedDataFingerprint.isEmpty
    }

    nonisolated var resolvedDataFingerprint: String {
        if let dataFingerprint, !dataFingerprint.isEmpty { return dataFingerprint }
        return Self.makeFingerprint(dateKey: resolvedDateKey, sourceDevice: sourceDevice, strain: strain, recovery: recovery, sleep: sleep, stress: stress, healthMonitor: healthMonitor)
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
        let strainSource = Self.newerMetricSource(lhs: self, rhs: other, timestamp: \.strainComputedAt, isPresent: \.hasValidStrain)
        let recoverySource = Self.newerMetricSource(lhs: self, rhs: other, timestamp: \.recoveryComputedAt, isPresent: \.hasValidRecovery)
        let sleepSource = Self.newerMetricSource(lhs: self, rhs: other, timestamp: \.sleepComputedAt, isPresent: \.hasValidSleep)
        let stressSource = Self.newerMetricSource(lhs: self, rhs: other, timestamp: \.stressComputedAt, isPresent: \.hasValidStress)
        let healthMonitorSource = Self.newerMetricSource(lhs: self, rhs: other, timestamp: \.healthMonitorComputedAt, isPresent: \.hasValidHealthMonitor)

        let merged = PulsarDailyMetricsSyncPayload(
            date: newer.date,
            dateKey: newer.resolvedDateKey,
            syncedAt: newer.syncedAt,
            sourceDevice: newer.sourceDevice,
            strain: dailySource?.strain ?? strainSource?.strain,
            recovery: dailySource?.recovery ?? recoverySource?.recovery,
            sleep: sleepSource?.sleep,
            stress: stressSource?.stress,
            healthMonitor: healthMonitorSource?.healthMonitor,
            syncSessionID: newer.syncSessionID,
            dataFingerprint: nil,
            validityFlag: true
        )
        let sanitized = merged.sanitizedForDeclaredSource()
        guard sanitized.resolvedDataFingerprint != resolvedDataFingerprint else { return self }
        return sanitized
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

    nonisolated var strainComputedAt: Date? {
        guard let strain, strain.isValid else { return nil }
        return strain.computedAt
    }

    nonisolated var recoveryComputedAt: Date? {
        guard let recovery, recovery.isValid else { return nil }
        return recovery.computedAt
    }

    nonisolated func sanitizedForDeclaredSource() -> PulsarDailyMetricsSyncPayload {
        var copy = self
        copy.dataFingerprint = nil

        if let strain, !Self.sourceNamesMatch(strain.sourceNames, sourceDevice: sourceDevice) {
            Self.logInvalidSourceMix(metric: "strain", currentSource: sourceDevice, displayedSourceNames: strain.sourceNames)
            copy.strain = nil
        }

        if let recovery, !Self.sourceNamesMatch(recovery.sourceNames, sourceDevice: sourceDevice) {
            Self.logInvalidSourceMix(metric: "recovery", currentSource: sourceDevice, displayedSourceNames: recovery.sourceNames)
            copy.recovery = nil
        }

        if let sleep, !Self.sourceNamesMatch(sleep.sourceNames, sourceDevice: sourceDevice) {
            Self.logInvalidSourceMix(metric: "sleep", currentSource: sourceDevice, displayedSourceNames: sleep.sourceNames)
            copy.sleep = nil
        }

        if let stress, !Self.sourceNamesMatch(stress.sourceNames, sourceDevice: sourceDevice) {
            Self.logInvalidSourceMix(metric: "stress", currentSource: sourceDevice, displayedSourceNames: stress.sourceNames)
            copy.stress = nil
        }

        if let healthMonitor {
            let filteredMetrics = healthMonitor.metrics.filter { metric in
                if metric.value == nil, metric.status == .noData, metric.sourceNames.isEmpty {
                    return false
                }
                let matches = Self.sourceNamesMatch(metric.sourceNames, sourceDevice: sourceDevice)
                if !matches {
                    Self.logInvalidSourceMix(
                        metric: "healthMonitor.\(metric.kind.rawValue)",
                        currentSource: sourceDevice,
                        displayedSourceNames: metric.sourceNames
                    )
                }
                return matches
            }

            let sourceNames = Self.sourceNamesMatch(healthMonitor.sourceNames, sourceDevice: sourceDevice)
                ? healthMonitor.sourceNames
                : Array(Set(filteredMetrics.flatMap(\.sourceNames))).sorted()

            let sanitizedHealthMonitor = PulsarHealthMonitorSyncMetric(
                metrics: filteredMetrics,
                baselineWindowDays: healthMonitor.baselineWindowDays,
                sourceNames: sourceNames,
                computedAt: healthMonitor.computedAt
            )
            copy.healthMonitor = sanitizedHealthMonitor.isValid ? sanitizedHealthMonitor : nil
        }

        copy.validityFlag = copy.validityFlag ?? true
        return copy
    }

    private nonisolated static func makeFingerprint(dateKey: String, sourceDevice: PulsarSyncSourceDevice, strain: PulsarStrainSyncMetric?, recovery: PulsarRecoverySyncMetric?, sleep: PulsarSleepSyncMetric?, stress: PulsarStressSyncMetric? = nil, healthMonitor: PulsarHealthMonitorSyncMetric? = nil) -> String {
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
                strain.confidence.rawValue,
                "\(strain.analyzedSampleCount ?? 0)",
                "\(strain.heartRateSampleCount ?? 0)",
                "\(strain.workoutSampleCount ?? 0)",
                "\(strain.activitySampleCount ?? 0)"
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
        } else {
            if let strain, strain.isValid {
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
                    strain.confidence.rawValue,
                    "\(strain.analyzedSampleCount ?? 0)",
                    "\(strain.heartRateSampleCount ?? 0)",
                    "\(strain.workoutSampleCount ?? 0)",
                    "\(strain.activitySampleCount ?? 0)"
                ].joined(separator: ":"))
            }
            if let recovery, recovery.isValid {
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
                rounded(sleep.targetSleepHours),
                sleep.stageIntervals?.prefix(24).map { interval in
                    [
                        interval.stage,
                        rounded(interval.start.timeIntervalSinceReferenceDate),
                        rounded(interval.end.timeIntervalSinceReferenceDate)
                    ].joined(separator: "/")
                }.joined(separator: ",") ?? "no-intervals"
            ].joined(separator: ":"))
        }
        if let stress, stress.isValid {
            let samples = stress.timelineSamples.prefix(12).map { sample in
                [
                    rounded(sample.timestamp.timeIntervalSinceReferenceDate),
                    rounded(sample.score),
                    sample.context ?? "none"
                ].joined(separator: "/")
            }.joined(separator: ",")
            parts.append([
                "stress",
                "\(stress.score)",
                stress.confidence.rawValue,
                stress.levelText,
                stress.driverInsights.prefix(2).joined(separator: ","),
                rounded(stress.hrvSDNN),
                rounded(stress.hrvBaseline),
                rounded(stress.restingHeartRate),
                rounded(stress.restingHeartRateBaseline),
                rounded(stress.respiratoryRate),
                rounded(stress.recentHeartRate),
                rounded(stress.daytimeHeartRateBaseline),
                rounded(stress.heartRateDeviation),
                rounded(stress.hrvDeviation),
                rounded(stress.nonActivityStress),
                rounded(stress.activityAdjustedStress),
                rounded(stress.rawStressScore),
                rounded(stress.activityAdjustment),
                stress.movementState ?? "nil",
                rounded(stress.recentSteps),
                rounded(stress.recentActiveEnergyKilocalories),
                stress.isWorkoutActive ? "workout" : "noWorkout",
                stress.cooldownActive ? "cooldown" : "noCooldown",
                stress.calculationState ?? "nil",
                rounded(stress.sleepDurationMinutes),
                rounded(stress.strainScore),
                "\(stress.availableSignalCount)",
                "\(stress.baselineWindowDays)",
                samples
            ].joined(separator: ":"))
        }
        if let healthMonitor, healthMonitor.isValid {
            let metrics = healthMonitor.metrics
                .sorted { $0.kind.rawValue < $1.kind.rawValue }
                .map { metric in
                    [
                        metric.kind.rawValue,
                        rounded(metric.value),
                        metric.status.rawValue,
                        rounded(metric.baselineValue),
                        metric.comparisonText,
                        "source=\(sourceIDFingerprint(for: metric.sourceNames, fallback: sourceDevice))",
                        "fallback=false",
                        metric.sourceNames.joined(separator: ",")
                    ].joined(separator: ":")
                }
                .joined(separator: "|")
            parts.append([
                "health-monitor",
                "\(healthMonitor.baselineWindowDays)",
                metrics
            ].joined(separator: ":"))
        }
        return parts.joined(separator: "|")
    }

    private nonisolated static func rounded(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "nil" }
        return String(format: "%.3f", value)
    }

    private nonisolated static func sourceNamesMatch(_ sourceNames: [String], sourceDevice: PulsarSyncSourceDevice) -> Bool {
        let joined = sourceNames.joined(separator: " ").lowercased()
        guard !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch sourceDevice {
        case .ouraRing:
            return joined.contains("oura")
        case .appleWatch:
            return joined.contains("apple") ||
                joined.contains("watch") ||
                joined.contains("healthkit") ||
                joined.contains("health")
        case .iPhone:
            return joined.contains("iphone") ||
                joined.contains("apple") ||
                joined.contains("watch") ||
                joined.contains("healthkit") ||
                joined.contains("health")
        }
    }

    private nonisolated static func sourceIDFingerprint(for sourceNames: [String], fallback sourceDevice: PulsarSyncSourceDevice) -> String {
        let joined = sourceNames.joined(separator: " ").lowercased()
        guard !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "unknown" }
        if joined.contains("oura") { return "ouraRing" }
        if joined.contains("apple") || joined.contains("watch") || joined.contains("healthkit") || joined.contains("health") {
            return "appleWatchHealthKit"
        }
        if joined.contains("iphone") { return "iPhoneSensors" }
        return sourceDevice.sourceRouterLogName
    }

    private nonisolated static func logInvalidSourceMix(
        metric: String,
        currentSource: PulsarSyncSourceDevice,
        displayedSourceNames: [String]
    ) {
        #if DEBUG
        let displayedSource = sourceIDFingerprint(for: displayedSourceNames, fallback: currentSource)
        print("[PulsarSourceRouter] Invalid source mix metric=\(metric) currentSource=\(currentSource.sourceRouterLogName) displayedSource=\(displayedSource) fallback=false")
        #endif
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
