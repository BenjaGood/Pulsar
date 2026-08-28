//
//  TotalEnergyExpenditureEstimator.swift
//  Pulsar
//

import Foundation

struct TotalEnergyExpenditureEstimate: Equatable {
    var calories: Double
    var range: ClosedRange<Double>
    var usedMeasuredActivity: Bool
    var rationale: String
    var modeledMaintenanceCalories: Double
    var healthKitCalibrationWeight: Double
    var combinedPAL: Double
    var primaryDrivers: [String]
    var appliedGuardrails: [String]
}

struct TotalEnergyExpenditureEstimator {
    private let eerCalculator = EstimatedEnergyRequirementCalculator()
    private let workoutCalculator = NutritionWorkoutEnergyCalculator()
    private let calibration = NutritionHealthKitCalibration()

    func estimate(
        restingEnergy: Double,
        input: NutritionCalculationInput,
        confidence: NutritionDataConfidence
    ) -> TotalEnergyExpenditureEstimate {
        let plannedWeeklyKcal = workoutCalculator.weeklyNetWorkoutKilocalories(
            plan: input.workoutPlan,
            bodyWeightKilograms: input.weightKilograms
        )
        let workoutPAL = workoutCalculator.weeklyWorkoutPALContribution(
            weeklyNetWorkoutKilocalories: plannedWeeklyKcal,
            restingEnergy: restingEnergy
        )
        let eerEstimate = eerCalculator.estimate(
            input: input,
            restingEnergy: restingEnergy,
            workoutPALContribution: workoutPAL
        )
        let workoutSummary = workoutCalculator.summarize(
            input: input,
            restingEnergy: restingEnergy,
            modeledMaintenance: eerEstimate.midpoint
        )
        var modeledMaintenance = eerEstimate.midpoint + workoutSummary.routineAdjustmentKilocaloriesPerDay
        var appliedGuardrails: [String] = []
        if workoutSummary.routineAdjustmentKilocaloriesPerDay > 0 {
            appliedGuardrails.append("New-routine adjustment capped to protect against abrupt plan changes.")
        }

        let calibrationResult = calibration.calibrate(
            summary: input.healthActivity,
            restingEnergy: restingEnergy,
            modeledMaintenance: modeledMaintenance
        )
        let maintenance = NutritionTargetStabilityGuard.roundToNearest25(calibrationResult.finalMaintenance)
        let maintenanceRange = NutritionTargetStabilityGuard.maintenanceConfidenceRange(
            maintenance: maintenance,
            confidence: confidence
        ).clampedRounded()

        var primaryDrivers = [
            "Resting energy estimate: \(Int(restingEnergy.rounded())) kcal/day (\(eerEstimate.equationUsed.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? "EER")).",
            "Daily activity level: \(input.workoutPlan.dailyActivityLevel.title) (PAL anchor \(String(format: "%.2f", eerEstimate.dailyLifePAL))).",
            "Planned weekly workout minutes: \(workoutSummary.plannedWeeklyMinutes).",
            "Combined PAL after workouts: \(String(format: "%.2f", eerEstimate.combinedPAL))."
        ]
        if calibrationResult.usedWearableEvidence {
            primaryDrivers.append("HealthKit calibration weight: \(Int((calibrationResult.calibrationWeight * 100).rounded()))%.")
        } else {
            primaryDrivers.append("HealthKit calibration weight: 0% (formula and workout plan only).")
        }

        return TotalEnergyExpenditureEstimate(
            calories: maintenance,
            range: maintenanceRange,
            usedMeasuredActivity: calibrationResult.usedWearableEvidence,
            rationale: "\(eerEstimate.rationale) \(calibrationResult.rationale)",
            modeledMaintenanceCalories: modeledMaintenance,
            healthKitCalibrationWeight: calibrationResult.calibrationWeight,
            combinedPAL: eerEstimate.combinedPAL,
            primaryDrivers: primaryDrivers,
            appliedGuardrails: appliedGuardrails
        )
    }
}

private extension ClosedRange where Bound == Double {
    func clampedRounded() -> ClosedRange<Double> {
        let roundedLowerBound = NutritionTargetStabilityGuard.roundToNearest25(lowerBound)
        let roundedUpperBound = NutritionTargetStabilityGuard.roundToNearest25(upperBound)
        return roundedLowerBound...roundedUpperBound
    }
}
