//
//  HealthMonitorDataService.swift
//  Pulsar
//

import Foundation

protocol HealthMonitorSummaryProviding {
    func healthMonitorSummary(
        profile: UserProfile,
        date: Date,
        calendar: Calendar,
        refreshedAt: Date,
        sleep: SleepSummary,
        history: [DailyStrainRecord]
    ) async -> HealthMonitorSummary
}

struct HealthMonitorDataService: HealthMonitorSummaryProviding {
    static let baselineWindowDays = 14

    var healthKit: HealthKitGateway
    var classifier: HealthMetricStatusClassifier

    init(healthKit: HealthKitGateway = HealthKitGateway(), classifier: HealthMetricStatusClassifier = HealthMetricStatusClassifier()) {
        self.healthKit = healthKit
        self.classifier = classifier
    }

    func healthMonitorSummary(
        profile: UserProfile,
        date: Date,
        calendar: Calendar,
        refreshedAt: Date,
        sleep: SleepSummary,
        history: [DailyStrainRecord]
    ) async -> HealthMonitorSummary {
        async let biometricsTask = healthKit.fetchDailyBiometrics(date: date, calendar: calendar)
        async let baselineTask = baselineDays(before: date, calendar: calendar)

        let (biometrics, baselineDays) = await (biometricsTask, baselineTask)
        let day = calendar.startOfDay(for: date)
        let sleepHistory = history
            .filter { calendar.startOfDay(for: $0.date) < day }
            .sorted { $0.date > $1.date }
            .compactMap(\.sleepMinutes)
            .map(Double.init)

        let metrics = [
            makeRespiratoryRateMetric(biometrics: biometrics, baselineDays: baselineDays, refreshedAt: refreshedAt),
            makeRestingHeartRateMetric(biometrics: biometrics, baselineDays: baselineDays, refreshedAt: refreshedAt),
            makeHRVMetric(biometrics: biometrics, baselineDays: baselineDays, refreshedAt: refreshedAt),
            makeOxygenMetric(biometrics: biometrics, baselineDays: baselineDays, refreshedAt: refreshedAt),
            makeTemperatureMetric(biometrics: biometrics, baselineDays: baselineDays, refreshedAt: refreshedAt),
            makeSleepMetric(profile: profile, sleep: sleep, sleepHistory: sleepHistory, refreshedAt: refreshedAt)
        ]

        return HealthMonitorSummary(
            date: day,
            metrics: metrics,
            lastUpdated: refreshedAt,
            baselineWindowDays: Self.baselineWindowDays,
            sourceBadges: SourceResolver.uniqueSourceBadges(metrics.flatMap(\.sourceBadges))
        )
    }

    private func baselineDays(before date: Date, calendar: Calendar) async -> [DailyBiometrics] {
        var days: [DailyBiometrics] = []
        for offset in 1...Self.baselineWindowDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { continue }
            days.append(await healthKit.fetchDailyBiometrics(date: day, calendar: calendar))
        }
        return days
    }

    private func makeRespiratoryRateMetric(biometrics: DailyBiometrics, baselineDays: [DailyBiometrics], refreshedAt: Date) -> HealthMetricModel {
        let assessment = classifier.respiratoryRate(
            current: biometrics.respiratoryRate,
            baseline: baselineDays.compactMap(\.respiratoryRate)
        )
        return HealthMetricModel(
            kind: .respiratoryRate,
            value: biometrics.respiratoryRate,
            status: assessment.status,
            baselineValue: assessment.referenceValue,
            comparisonText: assessment.comparisonText,
            sourceBadges: [biometrics.provenance["respiratory"]].compactMap { $0 },
            lastUpdated: refreshedAt
        )
    }

    private func makeRestingHeartRateMetric(biometrics: DailyBiometrics, baselineDays: [DailyBiometrics], refreshedAt: Date) -> HealthMetricModel {
        let assessment = classifier.restingHeartRate(
            current: biometrics.restingHeartRateBPM,
            baseline: baselineDays.compactMap(\.restingHeartRateBPM)
        )
        return HealthMetricModel(
            kind: .restingHeartRate,
            value: biometrics.restingHeartRateBPM,
            status: assessment.status,
            baselineValue: assessment.referenceValue,
            comparisonText: assessment.comparisonText,
            sourceBadges: [biometrics.provenance["rhr"]].compactMap { $0 },
            lastUpdated: refreshedAt
        )
    }

    private func makeHRVMetric(biometrics: DailyBiometrics, baselineDays: [DailyBiometrics], refreshedAt: Date) -> HealthMetricModel {
        let assessment = classifier.hrv(
            current: biometrics.hrvSDNNMilliseconds,
            baseline: baselineDays.compactMap(\.hrvSDNNMilliseconds)
        )
        return HealthMetricModel(
            kind: .hrv,
            value: biometrics.hrvSDNNMilliseconds,
            status: assessment.status,
            baselineValue: assessment.referenceValue,
            comparisonText: assessment.comparisonText,
            sourceBadges: [biometrics.provenance["hrv"]].compactMap { $0 },
            lastUpdated: refreshedAt
        )
    }

    private func makeOxygenMetric(biometrics: DailyBiometrics, baselineDays: [DailyBiometrics], refreshedAt: Date) -> HealthMetricModel {
        let assessment = classifier.oxygenSaturation(
            current: biometrics.oxygenSaturation,
            baseline: baselineDays.compactMap(\.oxygenSaturation)
        )
        return HealthMetricModel(
            kind: .oxygenSaturation,
            value: biometrics.oxygenSaturation,
            status: assessment.status,
            baselineValue: assessment.referenceValue,
            comparisonText: assessment.comparisonText,
            sourceBadges: [biometrics.provenance["oxygen"]].compactMap { $0 },
            lastUpdated: refreshedAt
        )
    }

    private func makeTemperatureMetric(biometrics: DailyBiometrics, baselineDays: [DailyBiometrics], refreshedAt: Date) -> HealthMetricModel {
        let assessment = classifier.wristTemperature(
            current: biometrics.wristTemperatureDeviationCelsius,
            baseline: baselineDays.compactMap(\.wristTemperatureDeviationCelsius)
        )
        return HealthMetricModel(
            kind: .wristTemperature,
            value: biometrics.wristTemperatureDeviationCelsius,
            status: assessment.status,
            baselineValue: assessment.referenceValue,
            comparisonText: assessment.comparisonText,
            sourceBadges: [biometrics.provenance["wristTemperature"]].compactMap { $0 },
            lastUpdated: refreshedAt
        )
    }

    private func makeSleepMetric(profile: UserProfile, sleep: SleepSummary, sleepHistory: [Double], refreshedAt: Date) -> HealthMetricModel {
        let sleepMinutes = sleep.totalSleepMinutes > 0 ? sleep.totalSleepMinutes : nil
        let assessment = classifier.sleepDuration(
            current: sleepMinutes,
            baseline: sleepHistory,
            targetMinutes: Double(profile.sleepSchedule.targetSleepDurationMinutes)
        )
        return HealthMetricModel(
            kind: .sleep,
            value: sleepMinutes,
            status: assessment.status,
            baselineValue: assessment.referenceValue,
            comparisonText: assessment.comparisonText,
            sourceBadges: sleep.sourceBadges,
            lastUpdated: refreshedAt
        )
    }
}

struct HealthMetricAssessment: Equatable {
    var status: HealthMetricStatus
    var referenceValue: Double?
    var comparisonText: String
}

struct HealthMetricStatusClassifier {
    let minimumBaselineSamples: Int

    init(minimumBaselineSamples: Int = 5) {
        self.minimumBaselineSamples = minimumBaselineSamples
    }

    func respiratoryRate(current: Double?, baseline: [Double]) -> HealthMetricAssessment {
        evaluateWithBaseline(
            current: current,
            baselineValues: baseline,
            higher: { value, reference in value >= reference + 1.5 && value >= reference * 1.08 },
            lower: { value, reference in value <= reference - 1.5 && value <= reference * 0.92 },
            fallback: { value in
                if value > 20 { return .higher }
                if value < 12 { return .lower }
                return .normal
            },
            fallbackText: generalRangeText
        )
    }

    func restingHeartRate(current: Double?, baseline: [Double]) -> HealthMetricAssessment {
        evaluateWithBaseline(
            current: current,
            baselineValues: baseline,
            higher: { value, reference in value >= reference + 6 && value >= reference * 1.08 },
            lower: { value, reference in value <= reference - 6 && value <= reference * 0.92 },
            fallback: { value in
                if value > 80 { return .higher }
                if value < 45 { return .lower }
                return .normal
            },
            fallbackText: generalRangeText
        )
    }

    func hrv(current: Double?, baseline: [Double]) -> HealthMetricAssessment {
        evaluateWithBaseline(
            current: current,
            baselineValues: baseline,
            higher: { value, reference in value >= reference + 12 && value >= reference * 1.12 },
            lower: { value, reference in value <= reference - 12 && value <= reference * 0.88 },
            fallback: { value in
                if value > 80 { return .higher }
                if value < 20 { return .lower }
                return .normal
            },
            fallbackText: generalRangeText
        )
    }

    func oxygenSaturation(current: Double?, baseline: [Double]) -> HealthMetricAssessment {
        evaluateWithBaseline(
            current: current,
            baselineValues: baseline,
            higher: { _, _ in false },
            lower: { value, reference in value < reference - 0.02 || value < 0.95 },
            fallback: { value in value < 0.95 ? .lower : .normal },
            fallbackText: generalRangeText
        )
    }

    func wristTemperature(current: Double?, baseline: [Double]) -> HealthMetricAssessment {
        evaluateWithBaseline(
            current: current,
            baselineValues: baseline,
            higher: { value, reference in value > reference + 0.3 },
            lower: { value, reference in value < reference - 0.3 },
            fallback: { value in
                if value > 0.3 { return .higher }
                if value < -0.3 { return .lower }
                return .normal
            },
            fallbackText: generalRangeText
        )
    }

    func sleepDuration(current: Double?, baseline: [Double], targetMinutes: Double) -> HealthMetricAssessment {
        guard let current, current.isFinite else {
            return .init(status: .noData, referenceValue: nil, comparisonText: noDataText)
        }

        if let reference = baselineValue(from: baseline) {
            let status = sleepStatus(current: current, reference: reference)
            return .init(status: status, referenceValue: reference, comparisonText: baselineText(for: status))
        }

        let status = sleepStatus(current: current, reference: targetMinutes)
        return .init(status: status, referenceValue: targetMinutes, comparisonText: targetText(for: status))
    }

    private func evaluateWithBaseline(
        current: Double?,
        baselineValues: [Double],
        higher: (Double, Double) -> Bool,
        lower: (Double, Double) -> Bool,
        fallback: (Double) -> HealthMetricStatus,
        fallbackText: (HealthMetricStatus) -> String
    ) -> HealthMetricAssessment {
        guard let current, current.isFinite else {
            return .init(status: .noData, referenceValue: nil, comparisonText: noDataText)
        }

        if let reference = baselineValue(from: baselineValues) {
            let status: HealthMetricStatus
            if higher(current, reference) {
                status = .higher
            } else if lower(current, reference) {
                status = .lower
            } else {
                status = .normal
            }
            return .init(status: status, referenceValue: reference, comparisonText: baselineText(for: status))
        }

        let status = fallback(current)
        return .init(status: status, referenceValue: nil, comparisonText: fallbackText(status))
    }

    private func sleepStatus(current: Double, reference: Double) -> HealthMetricStatus {
        if current >= reference + 45 && current >= reference * 1.08 {
            return .higher
        }
        if current <= reference - 45 && current <= reference * 0.92 {
            return .lower
        }
        return .normal
    }

    private func baselineValue(from values: [Double]) -> Double? {
        let cleaned = values.filter { $0.isFinite }
        guard cleaned.count >= minimumBaselineSamples else { return nil }
        return cleaned.median
    }

    private func baselineText(for status: HealthMetricStatus) -> String {
        switch status {
        case .normal:
            "Close to your recent baseline."
        case .higher:
            "Higher than your recent baseline."
        case .lower:
            "Lower than your recent baseline."
        case .noData:
            noDataText
        }
    }

    private func targetText(for status: HealthMetricStatus) -> String {
        switch status {
        case .normal:
            "Close to your current sleep target."
        case .higher:
            "Higher than your current sleep target."
        case .lower:
            "Lower than your current sleep target."
        case .noData:
            noDataText
        }
    }

    private func generalRangeText(for status: HealthMetricStatus) -> String {
        switch status {
        case .normal:
            "Within a conservative general range."
        case .higher:
            "Above a conservative general range."
        case .lower:
            "Below a conservative general range."
        case .noData:
            noDataText
        }
    }

    private var noDataText: String {
        "No HealthKit data was available for this metric on the selected day."
    }
}

private extension Array where Element == Double {
    var median: Double? {
        guard !isEmpty else { return nil }
        let sorted = self.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
