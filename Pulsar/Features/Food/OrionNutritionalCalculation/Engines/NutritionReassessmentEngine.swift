//
//  NutritionReassessmentEngine.swift
//  Pulsar
//

import Foundation

enum NutritionReassessmentEligibility: Equatable {
    case eligible
    case insufficientWeightHistory
    case noSavedTarget
    case safetyExclusion
}

struct NutritionReassessmentProposal: Equatable {
    var eligibility: NutritionReassessmentEligibility
    var currentTargetCalories: Double
    var proposedTargetCalories: Double
    var adjustmentCalories: Double
    var cumulativeAdjustmentFromOriginal: Double
    var weightTrendKilogramsPerWeek: Double?
    var rationale: String
    var requiresConfirmation: Bool
}

struct NutritionReassessmentEngine {
    static let maximumSingleAdjustment = 100.0
    static let maximumCumulativeAdjustment = 200.0

    func evaluate(
        goal: NutritionCalculationGoal,
        currentTarget: Double,
        originalModeledTarget: Double,
        cumulativeAdjustment: Double,
        weightTrendKilogramsPerWeek: Double?,
        expectedWeeklyChangeKilograms: Double,
        adherenceConfirmed: Bool,
        safetyBlocked: Bool
    ) -> NutritionReassessmentProposal {
        guard !safetyBlocked else {
            return ineligible(
                reason: .safetyExclusion,
                currentTarget: currentTarget,
                cumulativeAdjustment: cumulativeAdjustment,
                weightTrend: weightTrendKilogramsPerWeek,
                rationale: "A safety exclusion is active, so reassessment is paused."
            )
        }
        guard adherenceConfirmed else {
            return ineligible(
                reason: .noSavedTarget,
                currentTarget: currentTarget,
                cumulativeAdjustment: cumulativeAdjustment,
                weightTrend: weightTrendKilogramsPerWeek,
                rationale: "Reassessment requires confirmation that you followed the target on most days."
            )
        }
        guard let weightTrendKilogramsPerWeek else {
            return ineligible(
                reason: .insufficientWeightHistory,
                currentTarget: currentTarget,
                cumulativeAdjustment: cumulativeAdjustment,
                weightTrend: nil,
                rationale: "At least three weight measurements across 14 days are required before reassessment."
            )
        }

        let tolerance = max(abs(expectedWeeklyChangeKilograms) * 0.35, 0.10)
        let adjustment: Double
        let rationale: String
        if abs(weightTrendKilogramsPerWeek - expectedWeeklyChangeKilograms) <= tolerance {
            adjustment = 0
            rationale = "Observed weight trend is within the expected range for the selected goal."
        } else if weightTrendKilogramsPerWeek > expectedWeeklyChangeKilograms + tolerance {
            switch goal {
            case .fatLoss:
                adjustment = -Self.maximumSingleAdjustment
                rationale = "Weight change is slower than intended for fat loss; a conservative -100 kcal/day correction is proposed."
            case .muscleGain:
                adjustment = Self.maximumSingleAdjustment
                rationale = "Weight change is slower than intended for muscle gain; a conservative +100 kcal/day correction is proposed."
            default:
                adjustment = 0
                rationale = "Observed trend differs from expectation, but the selected goal does not support an automatic calorie correction."
            }
        } else {
            switch goal {
            case .fatLoss:
                adjustment = Self.maximumSingleAdjustment
                rationale = "Weight change is faster than intended for fat loss; a conservative +100 kcal/day correction is proposed."
            case .muscleGain:
                adjustment = -Self.maximumSingleAdjustment
                rationale = "Weight change is faster than intended for muscle gain; a conservative -100 kcal/day correction is proposed."
            default:
                adjustment = 0
                rationale = "Observed trend differs from expectation, but the selected goal does not support an automatic calorie correction."
            }
        }

        let cappedAdjustment = capped(
            proposed: adjustment,
            currentCumulative: cumulativeAdjustment,
            originalModeledTarget: originalModeledTarget,
            currentTarget: currentTarget
        )
        let proposedTarget = currentTarget + cappedAdjustment
        return NutritionReassessmentProposal(
            eligibility: .eligible,
            currentTargetCalories: currentTarget,
            proposedTargetCalories: proposedTarget,
            adjustmentCalories: cappedAdjustment,
            cumulativeAdjustmentFromOriginal: cumulativeAdjustment + cappedAdjustment,
            weightTrendKilogramsPerWeek: weightTrendKilogramsPerWeek,
            rationale: rationale,
            requiresConfirmation: cappedAdjustment != 0
        )
    }

    private func capped(
        proposed: Double,
        currentCumulative: Double,
        originalModeledTarget: Double,
        currentTarget: Double
    ) -> Double {
        guard proposed != 0 else { return 0 }
        let signed = proposed > 0 ? 1.0 : -1.0
        let magnitude = min(abs(proposed), Self.maximumSingleAdjustment)
        let tentative = currentCumulative + signed * magnitude
        let cappedCumulative = min(max(tentative, -Self.maximumCumulativeAdjustment), Self.maximumCumulativeAdjustment)
        let allowedDelta = cappedCumulative - currentCumulative
        let proposedTarget = currentTarget + allowedDelta
        let minimumTarget = max(originalModeledTarget - Self.maximumCumulativeAdjustment, 1_000)
        let maximumTarget = originalModeledTarget + Self.maximumCumulativeAdjustment
        if proposedTarget < minimumTarget {
            return minimumTarget - currentTarget
        }
        if proposedTarget > maximumTarget {
            return maximumTarget - currentTarget
        }
        return allowedDelta
    }

    private func ineligible(
        reason: NutritionReassessmentEligibility,
        currentTarget: Double,
        cumulativeAdjustment: Double,
        weightTrend: Double?,
        rationale: String
    ) -> NutritionReassessmentProposal {
        NutritionReassessmentProposal(
            eligibility: reason,
            currentTargetCalories: currentTarget,
            proposedTargetCalories: currentTarget,
            adjustmentCalories: 0,
            cumulativeAdjustmentFromOriginal: cumulativeAdjustment,
            weightTrendKilogramsPerWeek: weightTrend,
            rationale: rationale,
            requiresConfirmation: false
        )
    }
}

enum NutritionWeightTrendCalculator {
    static func slopeKilogramsPerWeek(
        measurements: [(date: Date, kilograms: Double)],
        minimumSpanDays: Int = 14,
        minimumMeasurements: Int = 3
    ) -> Double? {
        guard measurements.count >= minimumMeasurements else { return nil }
        let sorted = measurements.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        let spanDays = last.date.timeIntervalSince(first.date) / 86_400
        guard spanDays >= Double(minimumSpanDays) else { return nil }

        let reference = first.date.timeIntervalSinceReferenceDate
        let xs = sorted.map { ($0.date.timeIntervalSinceReferenceDate - reference) / 86_400 }
        let ys = sorted.map(\.kilograms)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        let numerator = zip(xs, ys).reduce(0) { $0 + (($1.0 - meanX) * ($1.1 - meanY)) }
        let denominator = xs.reduce(0) { $0 + pow($1 - meanX, 2) }
        guard denominator > 0 else { return nil }
        let slopePerDay = numerator / denominator
        return slopePerDay * 7
    }
}
