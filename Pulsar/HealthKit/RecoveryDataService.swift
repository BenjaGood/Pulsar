//
//  RecoveryDataService.swift
//  Pulsar
//

import Foundation

protocol RecoverySummaryProviding {
    func recoverySummary(profile: UserProfile, date: Date, calendar: Calendar, refreshedAt: Date) async throws -> RecoverySummary
    func recoverySummary(profile: UserProfile, date: Date, calendar: Calendar, refreshedAt: Date, sleep: SleepSummary, strain: StrainSummary) async throws -> RecoverySummary
}

extension RecoverySummaryProviding {
    func recoverySummary(profile: UserProfile, date: Date, calendar: Calendar, refreshedAt: Date, sleep _: SleepSummary, strain _: StrainSummary) async throws -> RecoverySummary {
        try await recoverySummary(profile: profile, date: date, calendar: calendar, refreshedAt: refreshedAt)
    }
}

struct RecoveryDataService: RecoverySummaryProviding {
    var healthKit: HealthKitGateway
    var sleepDataService: SleepSummaryProviding
    var strainDataService: StrainSummaryProviding

    init(healthKit: HealthKitGateway = HealthKitGateway(), sleepDataService: SleepSummaryProviding? = nil, strainDataService: StrainSummaryProviding? = nil) {
        self.healthKit = healthKit
        self.sleepDataService = sleepDataService ?? SleepDataService(healthKit: healthKit)
        self.strainDataService = strainDataService ?? StrainDataService(healthKit: healthKit)
    }

    func recoverySummary(profile: UserProfile, date: Date, calendar: Calendar, refreshedAt: Date) async throws -> RecoverySummary {
        async let sleep = sleepDataService.sleepSummary(profile: profile, wakeUpDate: date, calendar: calendar, refreshedAt: refreshedAt)
        async let strain = strainDataService.strainSummary(profile: profile, date: date, calendar: calendar, refreshedAt: refreshedAt)
        let values = try await (sleep, strain)
        return try await recoverySummary(
            profile: profile,
            date: date,
            calendar: calendar,
            refreshedAt: refreshedAt,
            sleep: values.0,
            strain: values.1
        )
    }

    func recoverySummary(profile: UserProfile, date: Date, calendar: Calendar, refreshedAt: Date, sleep: SleepSummary, strain: StrainSummary) async throws -> RecoverySummary {
        let interval = queryInterval(for: date, calendar: calendar, refreshedAt: refreshedAt)
        async let biometrics = healthKit.fetchDailyBiometrics(date: date, calendar: calendar)
        async let baseline = baselineDays(before: interval.start, calendar: calendar)
        async let trend = trendDays(endingAt: interval.start, calendar: calendar)

        let values = await (biometrics, baseline, trend)
        PulsarSyncDebugLogger.log("samples loaded for recovery: baselineDays=\(values.1.count) trendDays=\(values.2.count) sleepScore=\(sleep.score) strainScore=\(strain.score) hrv=\(values.0.hrvSDNNMilliseconds.map { Int($0.rounded()) } ?? 0)")
        var summary = RecoveryAnalyzer().analyze(
            RecoveryAnalysisInput(
                date: date,
                biometrics: values.0,
                baselineDays: values.1,
                trendDays: values.2,
                sleep: sleep,
                strain: strain,
                queryInterval: interval,
                refreshedAt: refreshedAt
            )
        )
        if let sharedMetric = sharedRecoveryMetric(
            biometrics: values.0,
            baselineDays: values.1,
            sleep: sleep,
            strain: strain,
            computedAt: refreshedAt
        ) {
            summary = summary.applying(sharedMetric: sharedMetric)
            PulsarSyncDebugLogger.log("canonical Recovery payload built score=\(sharedMetric.score) dateKey=\(PulsarDailyMetricsDateKey.dateKey(for: date, calendar: calendar))")
        } else {
            PulsarSyncDebugLogger.log("invalid or empty canonical Recovery result ignored dateKey=\(PulsarDailyMetricsDateKey.dateKey(for: date, calendar: calendar))")
        }
        PulsarSyncDebugLogger.log("calculated Recovery value=\(summary.score) confidence=\(summary.confidence.rawValue) status=\(summary.status.label)")

        if summary.analyzedSampleCount == 0 && summary.score == 0 && summary.components.allSatisfy({ $0.contribution == nil }) {
            return .missing.withDetailsDate(date, interval: interval, refreshedAt: refreshedAt)
        }
        return summary
    }

    private func queryInterval(for date: Date, calendar: Calendar, refreshedAt: Date) -> DateInterval {
        let day = calendar.startOfDay(for: date)
        let dayInterval = calendar.dateInterval(of: .day, for: day) ?? DateInterval(start: day, duration: 86_400)
        if calendar.isDate(day, inSameDayAs: refreshedAt) {
            return DateInterval(start: dayInterval.start, end: min(refreshedAt, dayInterval.end))
        }
        return dayInterval
    }

    private func baselineDays(before date: Date, calendar: Calendar) async -> [DailyBiometrics] {
        var days: [DailyBiometrics] = []
        for offset in 1...28 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { continue }
            days.append(await healthKit.fetchDailyBiometrics(date: day, calendar: calendar))
        }
        return days
    }

    private func trendDays(endingAt date: Date, calendar: Calendar) async -> [DailyBiometrics] {
        var days: [DailyBiometrics] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { continue }
            days.append(await healthKit.fetchDailyBiometrics(date: day, calendar: calendar))
        }
        return days.sorted { $0.date < $1.date }
    }

    private func sharedRecoveryMetric(biometrics: DailyBiometrics, baselineDays: [DailyBiometrics], sleep: SleepSummary, strain: StrainSummary, computedAt: Date) -> PulsarRecoverySyncMetric? {
        let wristTemperatureDeviation = baselineRelativeTemperatureDeviation(
            current: biometrics.wristTemperatureDeviationCelsius,
            baselineSamples: baselineDays.compactMap(\.wristTemperatureDeviationCelsius)
        )
        return PulsarSharedMetricCalculator.makeRecoveryMetric(
            today: PulsarSharedBiometricsDay(
                date: biometrics.date,
                hrvSDNN: biometrics.hrvSDNNMilliseconds,
                restingHeartRate: biometrics.restingHeartRateBPM,
                respiratoryRate: biometrics.respiratoryRate,
                oxygenSaturation: biometrics.oxygenSaturation,
                wristTemperatureDeviation: wristTemperatureDeviation,
                sleepPerformance: sleep.sleepPerformance > 0 ? sleep.sleepPerformance : nil,
                strainScore: strain.score > 0 ? Double(strain.score) : nil,
                sourceNames: Array(biometrics.provenance.values.map(\.displayName))
            ),
            baselineDays: baselineDays.map { day in
                PulsarSharedBiometricsDay(
                    date: day.date,
                    hrvSDNN: day.hrvSDNNMilliseconds,
                    restingHeartRate: day.restingHeartRateBPM,
                    respiratoryRate: day.respiratoryRate,
                    oxygenSaturation: day.oxygenSaturation,
                    wristTemperatureDeviation: nil,
                    sleepPerformance: nil,
                    strainScore: nil,
                    sourceNames: Array(day.provenance.values.map(\.displayName))
                )
            },
            computedAt: computedAt
        )
    }

    private func baselineRelativeTemperatureDeviation(current: Double?, baselineSamples: [Double]) -> Double? {
        guard let current, current.isFinite else { return nil }
        let cleaned = baselineSamples.filter(\.isFinite)
        guard cleaned.count >= 5 else { return nil }
        let baseline = cleaned.reduce(0, +) / Double(cleaned.count)
        return current - baseline
    }
}

private extension RecoverySummary {
    func applying(sharedMetric: PulsarRecoverySyncMetric) -> RecoverySummary {
        var copy = self
        copy.score = sharedMetric.score
        copy.confidence = sharedMetric.confidence.appConfidence
        copy.status = recoveryStatus(from: sharedMetric.statusText)
        copy.hrvSDNN = sharedMetric.hrvSDNN ?? copy.hrvSDNN
        copy.hrvBaseline = sharedMetric.hrvBaseline ?? copy.hrvBaseline
        copy.restingHeartRate = sharedMetric.restingHeartRate ?? copy.restingHeartRate
        copy.restingHeartRateBaseline = sharedMetric.restingHeartRateBaseline ?? copy.restingHeartRateBaseline
        copy.strainScore = sharedMetric.strainScore ?? copy.strainScore
        copy.respiratoryRate = sharedMetric.respiratoryRate ?? copy.respiratoryRate
        copy.oxygenSaturation = sharedMetric.oxygenSaturation ?? copy.oxygenSaturation
        copy.wristTemperatureDeviation = sharedMetric.wristTemperatureDeviation ?? copy.wristTemperatureDeviation
        copy.hrvReadiness = sharedMetric.hrvReadiness
        copy.restingHeartRateReadiness = sharedMetric.restingHeartRateReadiness
        copy.respiratoryStability = sharedMetric.respiratoryStability
        copy.sleepContribution = sharedMetric.sleepContribution
        copy.strainPenalty = sharedMetric.strainPenalty
        copy.lastUpdated = sharedMetric.computedAt
        if copy.explanation.isEmpty || copy.explanation == RecoverySummary.missing.explanation {
            copy.explanation = sharedMetric.statusText
        }
        return copy
    }

    func withDetailsDate(_ date: Date, interval: DateInterval, refreshedAt: Date) -> RecoverySummary {
        var copy = self
        copy.date = date
        copy.queryStart = interval.start
        copy.queryEnd = interval.end
        copy.lastUpdated = refreshedAt
        return copy
    }

    func recoveryStatus(from label: String) -> RecoveryStatus {
        switch label {
        case RecoveryStatus.excellent.label: .excellent
        case RecoveryStatus.balanced.label: .balanced
        case RecoveryStatus.moderate.label: .moderate
        case RecoveryStatus.low.label: .low
        case RecoveryStatus.needsAttention.label: .needsAttention
        default: .unknown
        }
    }
}
