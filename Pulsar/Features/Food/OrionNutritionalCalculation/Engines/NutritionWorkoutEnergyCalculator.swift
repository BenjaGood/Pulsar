//
//  NutritionWorkoutEnergyCalculator.swift
//  Pulsar
//

import Foundation

struct NutritionWorkoutEnergySummary: Equatable {
    var weeklyNetWorkoutKilocalories: Double
    var weeklyWorkoutPALContribution: Double
    var routineAdjustmentKilocaloriesPerDay: Double
    var plannedWeeklyMinutes: Int
    var observedWeeklyMinutes: Double
}

struct NutritionWorkoutEnergyCalculator {
    func weeklyNetWorkoutKilocalories(
        plan: NutritionWorkoutPlan,
        bodyWeightKilograms: Double
    ) -> Double {
        plan.sessions.reduce(0) { partial, entry in
            let met = NutritionMETCompendium.metValue(for: entry.workoutType, intensity: entry.intensity)
            let sessionKcal = NutritionMETCompendium.netWorkoutKilocalories(
                met: met.met,
                bodyWeightKilograms: bodyWeightKilograms,
                minutes: Double(entry.minutesPerSession)
            )
            return partial + sessionKcal * Double(entry.weeklySessions)
        }
    }

    func weeklyWorkoutPALContribution(
        weeklyNetWorkoutKilocalories: Double,
        restingEnergy: Double
    ) -> Double {
        guard restingEnergy > 0 else { return 0 }
        return weeklyNetWorkoutKilocalories / (7 * restingEnergy)
    }

    func summarize(
        input: NutritionCalculationInput,
        restingEnergy: Double,
        modeledMaintenance: Double
    ) -> NutritionWorkoutEnergySummary {
        let plannedWeeklyKcal = weeklyNetWorkoutKilocalories(
            plan: input.workoutPlan,
            bodyWeightKilograms: input.weightKilograms
        )
        let plannedPAL = weeklyWorkoutPALContribution(
            weeklyNetWorkoutKilocalories: plannedWeeklyKcal,
            restingEnergy: restingEnergy
        )

        let observedWeeklyKcal = input.healthActivity?.weeklyObservedWorkoutEnergyKilocalories ?? 0
        let routineAdjustment: Double
        if input.workoutPlan.basis == .newOrIncreasedRoutine {
            let difference = plannedWeeklyKcal - observedWeeklyKcal
            let dailyDifference = difference / 7
            let cap = max(modeledMaintenance * 0.15, 0)
            routineAdjustment = min(max(dailyDifference, -cap), cap)
        } else {
            routineAdjustment = 0
        }

        return NutritionWorkoutEnergySummary(
            weeklyNetWorkoutKilocalories: plannedWeeklyKcal,
            weeklyWorkoutPALContribution: plannedPAL,
            routineAdjustmentKilocaloriesPerDay: routineAdjustment,
            plannedWeeklyMinutes: input.workoutPlan.totalMinutesPerWeek,
            observedWeeklyMinutes: input.healthActivity?.weeklyWorkoutMinutes ?? 0
        )
    }
}
