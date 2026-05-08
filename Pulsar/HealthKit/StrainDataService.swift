//
//  StrainDataService.swift
//  Pulsar
//

import Foundation
import HealthKit

protocol StrainSummaryProviding {
    func strainSummary(profile: UserProfile, date: Date, calendar: Calendar, refreshedAt: Date) async throws -> StrainSummary
}

struct StrainDataService: StrainSummaryProviding {
    var healthKit: HealthKitGateway

    init(healthKit: HealthKitGateway = HealthKitGateway()) {
        self.healthKit = healthKit
    }

    func strainSummary(profile: UserProfile, date: Date, calendar: Calendar, refreshedAt: Date) async throws -> StrainSummary {
        let interval = queryInterval(for: date, calendar: calendar, refreshedAt: refreshedAt)
        async let activity = healthKit.fetchActivity(start: interval.start, end: interval.end)
        async let workouts = healthKit.fetchWorkouts(start: interval.start, end: interval.end)
        async let heartSamples = healthKit.fetchHeartRateSamples(start: interval.start, end: interval.end)
        async let biometrics = healthKit.fetchDailyBiometrics(date: date, calendar: calendar)
        async let recentLoads = recentMovementLoads(end: interval.end, calendar: calendar)
        let values = await (activity, workouts, heartSamples, biometrics, recentLoads)
        PulsarSyncDebugLogger.log("samples loaded for strain: workouts=\(values.1.count) heartSamples=\(values.2.count) steps=\(Int(values.0.steps.rounded())) activeEnergy=\(Int(values.0.activeEnergyKilocalories.rounded())) recentLoads=\(values.4.count)")
        let recent = values.4
        let input = DailyStrainInput(
            date: date,
            maxHeartRate: profile.resolvedMaxHeartRate(on: date, calendar: calendar)?.value,
            workouts: values.1,
            activity: values.0,
            recentRawLoads: recent,
            sevenDayRawLoad: recent.suffix(7).reduce(0, +),
            twentyEightDayRawLoad: recent.reduce(0, +)
        )
        let analysis = StrainAnalysisInput(
            strainInput: input,
            biometrics: values.3,
            dayHeartRateSamples: values.2,
            queryInterval: interval,
            refreshedAt: refreshedAt
        )
        var summary = StrainAnalyzer().analyze(analysis)
        if let sharedMetric = sharedStrainMetric(activity: values.0, workouts: values.1, heartSamples: values.2, restingHeartRate: values.3.restingHeartRateBPM, maxHeartRate: profile.resolvedMaxHeartRate(on: date, calendar: calendar)?.value, recentRawLoads: recent, computedAt: refreshedAt) {
            summary = summary.applying(sharedMetric: sharedMetric)
            PulsarSyncDebugLogger.log("canonical Strain payload built score=\(sharedMetric.score) dateKey=\(PulsarDailyMetricsDateKey.dateKey(for: date, calendar: calendar))")
        } else {
            PulsarSyncDebugLogger.log("invalid or empty canonical Strain result ignored dateKey=\(PulsarDailyMetricsDateKey.dateKey(for: date, calendar: calendar))")
        }
        PulsarSyncDebugLogger.log("calculated Strain value=\(summary.score) confidence=\(summary.confidence.rawValue) rawLoad=\(summary.rawLoad)")
        if summary.analyzedSampleCount == 0 && summary.workouts.isEmpty && summary.steps == 0 && summary.exerciseMinutes == 0 && (summary.activeEnergyKilocalories ?? 0) == 0 {
            return summary.withDetailsDate(date, interval: interval, refreshedAt: refreshedAt)
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

    private func recentMovementLoads(end: Date, calendar: Calendar) async -> [Double] {
        guard let start = calendar.date(byAdding: .day, value: -28, to: end) else { return [] }
        let values = await healthKit.dailyStatisticsCollection(
            identifier: .activeEnergyBurned,
            unit: .kilocalorie(),
            start: start,
            end: end,
            calendar: calendar
        )
        return values.map { max(0, $0.1 / 8) }
    }

    private func sharedStrainMetric(activity: DailyActivityInput, workouts: [WorkoutLoadInput], heartSamples: [HeartRateSample], restingHeartRate: Double?, maxHeartRate: Double?, recentRawLoads: [Double], computedAt: Date) -> PulsarStrainSyncMetric? {
        let heartContext = PulsarSharedMetricCalculator.heartRateContext(
            samples: heartSamples.map {
                PulsarSharedHeartRateSample(start: $0.start, end: $0.end, bpm: $0.bpm)
            },
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate
        )
        return PulsarSharedMetricCalculator.makeStrainMetric(
            activity: PulsarSharedActivityInput(
                steps: activity.steps,
                activeEnergyKilocalories: activity.activeEnergyKilocalories,
                basalEnergyKilocalories: activity.basalEnergyKilocalories,
                distanceMeters: activity.distanceMeters,
                exerciseMinutes: activity.exerciseMinutes,
                elevatedHeartRateMinutes: heartContext.elevatedMinutes,
                moderateHeartRateMinutes: heartContext.moderateMinutes,
                vigorousHeartRateMinutes: heartContext.vigorousMinutes,
                zone1Minutes: heartContext.zone1Minutes,
                zone2Minutes: heartContext.zone2Minutes,
                zone3Minutes: heartContext.zone3Minutes,
                zone4Minutes: heartContext.zone4Minutes,
                zone5Minutes: heartContext.zone5Minutes,
                averageElevatedHeartRate: heartContext.averageElevatedHeartRate,
                peakHeartRate: heartContext.peakHeartRate,
                restingHeartRate: restingHeartRate,
                maxHeartRate: maxHeartRate
            ),
            workouts: workouts.map { workout in
                let heartRates = workout.heartRateSamples.map(\.bpm).filter { $0 > 0 }
                return PulsarSharedWorkoutInput(
                    type: workout.type,
                    durationMinutes: workout.durationMinutes,
                    activeEnergyKilocalories: workout.activeEnergyKilocalories,
                    distanceMeters: workout.distanceMeters,
                    averageHeartRate: heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count),
                    peakHeartRate: heartRates.max(),
                    sourceName: workout.provenance.displayName
                )
            },
            recentRawLoads: recentRawLoads,
            computedAt: computedAt
        )
    }
}

private extension StrainSummary {
    func applying(sharedMetric: PulsarStrainSyncMetric) -> StrainSummary {
        var copy = self
        copy.score = sharedMetric.score
        copy.confidence = sharedMetric.confidence.appConfidence
        copy.rawLoad = sharedMetric.rawLoad
        copy.workoutLoad = sharedMetric.workoutLoad
        copy.movementLoad = sharedMetric.movementLoad
        copy.steps = max(copy.steps, sharedMetric.steps)
        copy.activeEnergyKilocalories = sharedMetric.activeEnergyKilocalories ?? copy.activeEnergyKilocalories
        copy.exerciseMinutes = max(copy.exerciseMinutes, sharedMetric.exerciseMinutes)
        copy.workoutMinutes = max(copy.workoutMinutes, sharedMetric.workoutMinutes)
        copy.averageActiveHeartRate = sharedMetric.averageActiveHeartRate ?? copy.averageActiveHeartRate
        copy.peakHeartRate = sharedMetric.peakHeartRate ?? copy.peakHeartRate
        copy.lastUpdated = sharedMetric.computedAt
        return copy
    }

    func withDetailsDate(_ date: Date, interval: DateInterval, refreshedAt: Date) -> StrainSummary {
        var copy = self
        copy.date = date
        copy.queryStart = interval.start
        copy.queryEnd = interval.end
        copy.lastUpdated = refreshedAt
        return copy
    }
}
