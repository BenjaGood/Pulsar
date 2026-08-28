//
//  NutritionHealthActivityAnalyzer.swift
//  Pulsar
//

import Foundation
import HealthKit

struct NutritionHealthActivityAnalysis: Equatable {
    var summary: HealthActivitySummary
    var latestWeightKilograms: Double?
    var latestBodyFatPercentage: Double?
}

protocol NutritionHealthActivityAnalyzing {
    func analyze(
        profileWeightKilograms: Double?,
        restingEnergyKilocalories: Double?,
        plannedWeeklySessions: Int,
        age: Int
    ) async -> NutritionHealthActivityAnalysis
}

extension NutritionHealthActivityAnalyzing {
    func analyze(profileWeightKilograms: Double?) async -> NutritionHealthActivityAnalysis {
        await analyze(
            profileWeightKilograms: profileWeightKilograms,
            restingEnergyKilocalories: nil,
            plannedWeeklySessions: 0,
            age: 30
        )
    }
}

struct NutritionHealthActivityAnalyzer: NutritionHealthActivityAnalyzing {
    var healthKit: HealthKitGateway
    var calendar: Calendar
    var nowProvider: () -> Date

    init(
        healthKit: HealthKitGateway = HealthKitGateway(),
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.healthKit = healthKit
        self.calendar = calendar
        self.nowProvider = nowProvider
    }

    func analyze(
        profileWeightKilograms: Double?,
        restingEnergyKilocalories: Double?,
        plannedWeeklySessions: Int,
        age: Int
    ) async -> NutritionHealthActivityAnalysis {
        guard await healthKit.isAvailable else {
            return NutritionHealthActivityAnalysis(
                summary: .unavailable,
                latestWeightKilograms: nil,
                latestBodyFatPercentage: nil
            )
        }

        try? await healthKit.requestAuthorization()
        let end = calendar.startOfDay(for: nowProvider())
        let start = calendar.date(byAdding: .day, value: -28, to: end) ?? end.addingTimeInterval(-28 * 86_400)

        async let steps = healthKit.dailyStatisticsCollection(
            identifier: .stepCount,
            unit: .count(),
            start: start,
            end: end,
            calendar: calendar
        )
        async let activeEnergy = healthKit.dailyStatisticsCollection(
            identifier: .activeEnergyBurned,
            unit: .kilocalorie(),
            start: start,
            end: end,
            calendar: calendar
        )
        async let basalEnergy = healthKit.dailyStatisticsCollection(
            identifier: .basalEnergyBurned,
            unit: .kilocalorie(),
            start: start,
            end: end,
            calendar: calendar
        )
        async let exercise = healthKit.dailyStatisticsCollection(
            identifier: .appleExerciseTime,
            unit: .minute(),
            start: start,
            end: end,
            calendar: calendar
        )
        async let distance = healthKit.dailyStatisticsCollection(
            identifier: .distanceWalkingRunning,
            unit: .meter(),
            start: start,
            end: end,
            calendar: calendar
        )
        async let workouts = healthKit.fetchWorkouts(start: start, end: end)
        async let weight = healthKit.fetchMostRecentQuantitySample(
            identifier: .bodyMass,
            unit: .gramUnit(with: .kilo),
            start: start,
            end: end
        )
        async let bodyFat = healthKit.fetchMostRecentQuantitySample(
            identifier: .bodyFatPercentage,
            unit: .percent(),
            start: start,
            end: end
        )
        async let weightSamples = healthKit.fetchQuantitySamples(
            identifier: .bodyMass,
            unit: .gramUnit(with: .kilo),
            start: start,
            end: end
        )
        let values = await (steps, activeEnergy, basalEnergy, exercise, distance, workouts, weight, bodyFat, weightSamples)

        let stepCoverage = coverageDays(values.0)
        let activeCoverage = coverageDays(values.1)
        let basalCoverage = coverageDays(values.2)
        let exerciseCoverage = coverageDays(values.3)
        let observedDays = Set(values.0.map { calendar.startOfDay(for: $0.0) }
            + values.1.map { calendar.startOfDay(for: $0.0) }
            + values.2.map { calendar.startOfDay(for: $0.0) }).count

        let restingEnergy = restingEnergyKilocalories ?? 1_600
        let dailyEnergyTotals = buildDailyEnergyTotals(
            basal: values.2,
            active: values.1,
            restingEnergy: restingEnergy
        )
        let validEnergyDays = dailyEnergyTotals.filter(\.isValid)
        let robustMedian = NutritionHealthKitCalibration.winsorizedMedian(
            validEnergyDays.map(\.totalEnergy)
        )

        let deduplicatedWorkouts = NutritionWorkoutTypeMapper.deduplicatedWorkouts(values.5)
        let workoutDays = Set(deduplicatedWorkouts.map { calendar.startOfDay(for: $0.start) }).count
        let workoutMinutes = deduplicatedWorkouts.reduce(0) { $0 + $1.durationMinutes }
        let workoutEnergy = deduplicatedWorkouts.reduce(0) { $0 + ($1.activeEnergyKilocalories ?? 0) }
        let weeklyWorkoutMinutes = workoutMinutes / max(28.0 / 7.0, 1)
        let weeklyWorkoutEnergy = workoutEnergy / max(28.0 / 7.0, 1)
        let observedAggregates = NutritionWorkoutTypeMapper.observedAggregates(
            workouts: deduplicatedWorkouts,
            windowDays: 28,
            age: age
        )
        let heartRateWorkouts = deduplicatedWorkouts.filter { !$0.heartRateSamples.isEmpty }.count
        let heartRateCoverage = deduplicatedWorkouts.isEmpty ? 0 : Double(heartRateWorkouts) / Double(deduplicatedWorkouts.count)

        let latestWeight = values.6?.value
        let weightTrend = NutritionWeightTrendCalculator.slopeKilogramsPerWeek(
            measurements: values.8.map { ($0.date, $0.value) }
        )

        var flags: [String] = []
        var anomalyCodes: [NutritionHealthAnomalyCode] = []
        if validEnergyDays.count < 7 {
            flags.append("Fewer than 7 valid energy days were available; confidence is low.")
            anomalyCodes.append(.sparseEnergyCoverage)
        } else if validEnergyDays.count < 14 {
            flags.append("Fewer than 14 valid energy days were available; wearable calibration was not applied.")
            anomalyCodes.append(.sparseEnergyCoverage)
        }
        if deduplicatedWorkouts.isEmpty {
            flags.append("No workouts were found in the selected period.")
            anomalyCodes.append(.noWorkoutsObserved)
        } else if heartRateCoverage < 0.35 {
            anomalyCodes.append(.heartRateCoverageLow)
        }
        if let profileWeightKilograms, let latestWeight,
           abs(profileWeightKilograms - latestWeight) / max(profileWeightKilograms, 1) > 0.05 {
            flags.append("Profile and recent HealthKit weight differ by more than 5%; confirm the weight used below.")
            anomalyCodes.append(.profileWeightMismatch)
        }
        if weightTrend == nil {
            anomalyCodes.append(.weightTrendUnavailable)
        }

        let observedWeeklySessions = Double(deduplicatedWorkouts.count) / (28.0 / 7.0)
        if plannedWeeklySessions == 0 && observedWeeklySessions >= 1 {
            flags.append("HealthKit shows workouts but the manual plan lists none.")
            anomalyCodes.append(.planWorkoutConflict)
        } else if plannedWeeklySessions > 0,
                  abs(observedWeeklySessions - Double(plannedWeeklySessions)) <= max(1, Double(plannedWeeklySessions) * 0.35) {
            flags.append("Recent HealthKit workouts broadly match the planned routine.")
            anomalyCodes.append(.planWorkoutConfirmed)
        } else if plannedWeeklySessions > 0 {
            flags.append("Recent HealthKit workouts differ from the planned routine.")
            anomalyCodes.append(.planWorkoutConflict)
        }

        if flags.isEmpty {
            flags.append("Recent activity coverage is suitable for bounded wearable calibration.")
        }

        let confidence: NutritionDataConfidence
        if validEnergyDays.count >= 21 { confidence = .high }
        else if validEnergyDays.count >= 7 || observedDays >= 7 { confidence = .moderate }
        else { confidence = .low }

        let summary = HealthActivitySummary(
            startDate: start,
            endDate: end,
            requestedDayCount: 28,
            observedDayCount: min(observedDays, 28),
            validEnergyDayCount: validEnergyDays.count,
            basalEnergyCoverageDays: basalCoverage,
            activeEnergyCoverageDays: activeCoverage,
            stepCoverageDays: stepCoverage,
            workoutCoverageDays: workoutDays,
            averageSteps: average(values.0, coverageDays: stepCoverage),
            averageActiveEnergyKilocalories: average(values.1, coverageDays: activeCoverage),
            averageBasalEnergyKilocalories: average(values.2, coverageDays: basalCoverage),
            averageExerciseMinutes: average(values.3, coverageDays: exerciseCoverage),
            averageDistanceMeters: average(values.4, coverageDays: stepCoverage),
            workoutCount: deduplicatedWorkouts.count,
            workoutMinutes: workoutMinutes,
            workoutEnergyKilocalories: workoutEnergy,
            weeklyWorkoutMinutes: weeklyWorkoutMinutes,
            weeklyObservedWorkoutEnergyKilocalories: weeklyWorkoutEnergy,
            robustMedianDailyEnergyKilocalories: robustMedian,
            observedWorkoutAggregates: observedAggregates,
            workoutHeartRateCoverageFraction: heartRateCoverage,
            latestWeightKilograms: latestWeight,
            latestBodyFatPercentage: values.7.map { $0.value * 100 },
            weightTrendKilogramsPerWeek: weightTrend,
            confidence: confidence,
            flags: flags,
            anomalyCodes: anomalyCodes
        )
        return NutritionHealthActivityAnalysis(
            summary: summary,
            latestWeightKilograms: latestWeight,
            latestBodyFatPercentage: values.7.map { $0.value * 100 }
        )
    }

    private struct DailyEnergyTotal {
        var totalEnergy: Double
        var isValid: Bool
    }

    private func buildDailyEnergyTotals(
        basal: [(Date, Double)],
        active: [(Date, Double)],
        restingEnergy: Double
    ) -> [DailyEnergyTotal] {
        var basalByDay: [Date: Double] = [:]
        var activeByDay: [Date: Double] = [:]
        for (date, value) in basal where value.isFinite {
            basalByDay[calendar.startOfDay(for: date), default: 0] += max(0, value)
        }
        for (date, value) in active where value.isFinite {
            activeByDay[calendar.startOfDay(for: date), default: 0] += max(0, value)
        }
        let days = Set(basalByDay.keys).union(activeByDay.keys)
        return days.map { day in
            let basalValue = basalByDay[day] ?? 0
            let activeValue = activeByDay[day] ?? 0
            let total = basalValue + activeValue
            let isValid = NutritionHealthKitCalibration.isValidEnergyDay(
                basalEnergy: basalValue,
                activeEnergy: activeValue,
                restingEnergy: restingEnergy
            )
            return DailyEnergyTotal(totalEnergy: total, isValid: isValid)
        }
    }

    private func coverageDays(_ series: [(Date, Double)]) -> Int {
        Set(series.filter { $0.1 > 0 }.map { calendar.startOfDay(for: $0.0) }).count
    }

    private func average(_ values: [(Date, Double)], coverageDays: Int) -> Double {
        guard coverageDays > 0 else { return 0 }
        return values.reduce(0) { $0 + max(0, $1.1) } / Double(coverageDays)
    }
}
