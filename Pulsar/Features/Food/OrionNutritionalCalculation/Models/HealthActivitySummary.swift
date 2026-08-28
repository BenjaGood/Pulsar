//
//  HealthActivitySummary.swift
//  Pulsar
//

import Foundation

enum NutritionDataConfidence: String, Codable, CaseIterable, Hashable {
    case high
    case moderate
    case low

    var title: String { rawValue.capitalized }
}

enum NutritionHealthAnomalyCode: String, Codable, CaseIterable, Hashable {
    case sparseEnergyCoverage
    case sparseWorkoutCoverage
    case profileWeightMismatch
    case planWorkoutConflict
    case planWorkoutConfirmed
    case noWorkoutsObserved
    case heartRateCoverageLow
    case weightTrendUnavailable
}

struct HealthActivitySummary: Codable, Equatable, Hashable {
    var startDate: Date
    var endDate: Date
    var requestedDayCount: Int
    var observedDayCount: Int
    var validEnergyDayCount: Int
    var basalEnergyCoverageDays: Int
    var activeEnergyCoverageDays: Int
    var stepCoverageDays: Int
    var workoutCoverageDays: Int
    var averageSteps: Double
    var averageActiveEnergyKilocalories: Double
    var averageBasalEnergyKilocalories: Double
    var averageExerciseMinutes: Double
    var averageDistanceMeters: Double
    var workoutCount: Int
    var workoutMinutes: Double
    var workoutEnergyKilocalories: Double
    var weeklyWorkoutMinutes: Double
    var weeklyObservedWorkoutEnergyKilocalories: Double
    var robustMedianDailyEnergyKilocalories: Double?
    var observedWorkoutAggregates: [NutritionObservedWorkoutAggregate]
    var workoutHeartRateCoverageFraction: Double
    var latestWeightKilograms: Double?
    var latestBodyFatPercentage: Double?
    var weightTrendKilogramsPerWeek: Double?
    var confidence: NutritionDataConfidence
    var flags: [String]
    var anomalyCodes: [NutritionHealthAnomalyCode]

    var coverage: Double {
        guard requestedDayCount > 0 else { return 0 }
        return min(max(Double(observedDayCount) / Double(requestedDayCount), 0), 1)
    }

    var measuredDailyEnergyExpenditure: Double? {
        let total = averageBasalEnergyKilocalories + averageActiveEnergyKilocalories
        return averageBasalEnergyKilocalories > 0 && total > 0 ? total : nil
    }

    static let unavailable = HealthActivitySummary(
        startDate: .now,
        endDate: .now,
        requestedDayCount: 28,
        observedDayCount: 0,
        validEnergyDayCount: 0,
        basalEnergyCoverageDays: 0,
        activeEnergyCoverageDays: 0,
        stepCoverageDays: 0,
        workoutCoverageDays: 0,
        averageSteps: 0,
        averageActiveEnergyKilocalories: 0,
        averageBasalEnergyKilocalories: 0,
        averageExerciseMinutes: 0,
        averageDistanceMeters: 0,
        workoutCount: 0,
        workoutMinutes: 0,
        workoutEnergyKilocalories: 0,
        weeklyWorkoutMinutes: 0,
        weeklyObservedWorkoutEnergyKilocalories: 0,
        robustMedianDailyEnergyKilocalories: nil,
        observedWorkoutAggregates: [],
        workoutHeartRateCoverageFraction: 0,
        latestWeightKilograms: nil,
        latestBodyFatPercentage: nil,
        weightTrendKilogramsPerWeek: nil,
        confidence: .low,
        flags: ["Health activity history is unavailable; the estimate uses profile and workout-plan inputs."],
        anomalyCodes: [.sparseEnergyCoverage]
    )
}

extension HealthActivitySummary {
    enum CodingKeys: String, CodingKey {
        case startDate
        case endDate
        case requestedDayCount
        case observedDayCount
        case validEnergyDayCount
        case basalEnergyCoverageDays
        case activeEnergyCoverageDays
        case stepCoverageDays
        case workoutCoverageDays
        case averageSteps
        case averageActiveEnergyKilocalories
        case averageBasalEnergyKilocalories
        case averageExerciseMinutes
        case averageDistanceMeters
        case workoutCount
        case workoutMinutes
        case workoutEnergyKilocalories
        case weeklyWorkoutMinutes
        case weeklyObservedWorkoutEnergyKilocalories
        case robustMedianDailyEnergyKilocalories
        case observedWorkoutAggregates
        case workoutHeartRateCoverageFraction
        case latestWeightKilograms
        case latestBodyFatPercentage
        case weightTrendKilogramsPerWeek
        case confidence
        case flags
        case anomalyCodes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        requestedDayCount = try container.decode(Int.self, forKey: .requestedDayCount)
        observedDayCount = try container.decode(Int.self, forKey: .observedDayCount)
        validEnergyDayCount = try container.decodeIfPresent(Int.self, forKey: .validEnergyDayCount) ?? observedDayCount
        basalEnergyCoverageDays = try container.decodeIfPresent(Int.self, forKey: .basalEnergyCoverageDays) ?? observedDayCount
        activeEnergyCoverageDays = try container.decodeIfPresent(Int.self, forKey: .activeEnergyCoverageDays) ?? observedDayCount
        stepCoverageDays = try container.decodeIfPresent(Int.self, forKey: .stepCoverageDays) ?? observedDayCount
        workoutCoverageDays = try container.decodeIfPresent(Int.self, forKey: .workoutCoverageDays) ?? 0
        averageSteps = try container.decode(Double.self, forKey: .averageSteps)
        averageActiveEnergyKilocalories = try container.decode(Double.self, forKey: .averageActiveEnergyKilocalories)
        averageBasalEnergyKilocalories = try container.decode(Double.self, forKey: .averageBasalEnergyKilocalories)
        averageExerciseMinutes = try container.decode(Double.self, forKey: .averageExerciseMinutes)
        averageDistanceMeters = try container.decode(Double.self, forKey: .averageDistanceMeters)
        workoutCount = try container.decode(Int.self, forKey: .workoutCount)
        workoutMinutes = try container.decode(Double.self, forKey: .workoutMinutes)
        workoutEnergyKilocalories = try container.decode(Double.self, forKey: .workoutEnergyKilocalories)
        weeklyWorkoutMinutes = try container.decodeIfPresent(Double.self, forKey: .weeklyWorkoutMinutes) ?? (workoutMinutes / max(Double(requestedDayCount) / 7, 1))
        weeklyObservedWorkoutEnergyKilocalories = try container.decodeIfPresent(Double.self, forKey: .weeklyObservedWorkoutEnergyKilocalories) ?? (workoutEnergyKilocalories / max(Double(requestedDayCount) / 7, 1))
        robustMedianDailyEnergyKilocalories = try container.decodeIfPresent(Double.self, forKey: .robustMedianDailyEnergyKilocalories)
        observedWorkoutAggregates = try container.decodeIfPresent([NutritionObservedWorkoutAggregate].self, forKey: .observedWorkoutAggregates) ?? []
        workoutHeartRateCoverageFraction = try container.decodeIfPresent(Double.self, forKey: .workoutHeartRateCoverageFraction) ?? 0
        latestWeightKilograms = try container.decodeIfPresent(Double.self, forKey: .latestWeightKilograms)
        latestBodyFatPercentage = try container.decodeIfPresent(Double.self, forKey: .latestBodyFatPercentage)
        weightTrendKilogramsPerWeek = try container.decodeIfPresent(Double.self, forKey: .weightTrendKilogramsPerWeek)
        confidence = try container.decode(NutritionDataConfidence.self, forKey: .confidence)
        flags = try container.decode([String].self, forKey: .flags)
        anomalyCodes = try container.decodeIfPresent([NutritionHealthAnomalyCode].self, forKey: .anomalyCodes) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(requestedDayCount, forKey: .requestedDayCount)
        try container.encode(observedDayCount, forKey: .observedDayCount)
        try container.encode(validEnergyDayCount, forKey: .validEnergyDayCount)
        try container.encode(basalEnergyCoverageDays, forKey: .basalEnergyCoverageDays)
        try container.encode(activeEnergyCoverageDays, forKey: .activeEnergyCoverageDays)
        try container.encode(stepCoverageDays, forKey: .stepCoverageDays)
        try container.encode(workoutCoverageDays, forKey: .workoutCoverageDays)
        try container.encode(averageSteps, forKey: .averageSteps)
        try container.encode(averageActiveEnergyKilocalories, forKey: .averageActiveEnergyKilocalories)
        try container.encode(averageBasalEnergyKilocalories, forKey: .averageBasalEnergyKilocalories)
        try container.encode(averageExerciseMinutes, forKey: .averageExerciseMinutes)
        try container.encode(averageDistanceMeters, forKey: .averageDistanceMeters)
        try container.encode(workoutCount, forKey: .workoutCount)
        try container.encode(workoutMinutes, forKey: .workoutMinutes)
        try container.encode(workoutEnergyKilocalories, forKey: .workoutEnergyKilocalories)
        try container.encode(weeklyWorkoutMinutes, forKey: .weeklyWorkoutMinutes)
        try container.encode(weeklyObservedWorkoutEnergyKilocalories, forKey: .weeklyObservedWorkoutEnergyKilocalories)
        try container.encodeIfPresent(robustMedianDailyEnergyKilocalories, forKey: .robustMedianDailyEnergyKilocalories)
        try container.encode(observedWorkoutAggregates, forKey: .observedWorkoutAggregates)
        try container.encode(workoutHeartRateCoverageFraction, forKey: .workoutHeartRateCoverageFraction)
        try container.encodeIfPresent(latestWeightKilograms, forKey: .latestWeightKilograms)
        try container.encodeIfPresent(latestBodyFatPercentage, forKey: .latestBodyFatPercentage)
        try container.encodeIfPresent(weightTrendKilogramsPerWeek, forKey: .weightTrendKilogramsPerWeek)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(flags, forKey: .flags)
        try container.encode(anomalyCodes, forKey: .anomalyCodes)
    }
}
