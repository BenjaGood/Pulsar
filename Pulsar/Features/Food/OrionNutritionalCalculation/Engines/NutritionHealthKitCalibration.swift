//
//  NutritionHealthKitCalibration.swift
//  Pulsar
//

import Foundation

struct NutritionHealthKitCalibrationResult: Equatable {
    var validDayCount: Int
    var calibrationWeight: Double
    var robustMedianDailyEnergy: Double?
    var modeledMaintenance: Double
    var calibratedMaintenance: Double
    var finalMaintenance: Double
    var usedWearableEvidence: Bool
    var rationale: String
}

struct NutritionHealthKitCalibration {
    func calibrate(
        summary: HealthActivitySummary?,
        restingEnergy: Double,
        modeledMaintenance: Double
    ) -> NutritionHealthKitCalibrationResult {
        let validDayCount = summary?.validEnergyDayCount ?? 0
        let calibrationWeight = weight(for: validDayCount)
        let robustMedian = summary?.robustMedianDailyEnergyKilocalories

        guard calibrationWeight > 0, let robustMedian, modeledMaintenance > 0 else {
            return NutritionHealthKitCalibrationResult(
                validDayCount: validDayCount,
                calibrationWeight: 0,
                robustMedianDailyEnergy: robustMedian,
                modeledMaintenance: modeledMaintenance,
                calibratedMaintenance: modeledMaintenance,
                finalMaintenance: modeledMaintenance,
                usedWearableEvidence: false,
                rationale: "Wearable calibration was not applied because fewer than 14 valid energy days were available."
            )
        }

        let calibrated = modeledMaintenance + calibrationWeight * (robustMedian - modeledMaintenance)
        let lower = modeledMaintenance * 0.90
        let upper = modeledMaintenance * 1.10
        let final = min(max(calibrated, lower), upper)

        return NutritionHealthKitCalibrationResult(
            validDayCount: validDayCount,
            calibrationWeight: calibrationWeight,
            robustMedianDailyEnergy: robustMedian,
            modeledMaintenance: modeledMaintenance,
            calibratedMaintenance: calibrated,
            finalMaintenance: final,
            usedWearableEvidence: true,
            rationale: "Wearable evidence contributed \(Int((calibrationWeight * 100).rounded()))% toward maintenance and was clamped to ±10% of the modeled estimate."
        )
    }

    func weight(for validDayCount: Int) -> Double {
        switch validDayCount {
        case ..<14: 0
        case 14...20: 0.15
        default: 0.25
        }
    }

    static func winsorizedMedian(_ values: [Double], lowerPercentile: Double = 0.10, upperPercentile: Double = 0.90) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let lowerIndex = max(0, Int((Double(sorted.count - 1) * lowerPercentile).rounded(.down)))
        let upperIndex = min(sorted.count - 1, Int((Double(sorted.count - 1) * upperPercentile).rounded(.up)))
        let lowerBound = sorted[lowerIndex]
        let upperBound = sorted[upperIndex]
        let winsorized = sorted.map { min(max($0, lowerBound), upperBound) }
        let midpoint = winsorized.count / 2
        if winsorized.count.isMultiple(of: 2) {
            return (winsorized[midpoint - 1] + winsorized[midpoint]) / 2
        }
        return winsorized[midpoint]
    }

    static func isValidEnergyDay(
        basalEnergy: Double,
        activeEnergy: Double,
        restingEnergy: Double
    ) -> Bool {
        guard basalEnergy.isFinite, activeEnergy.isFinite, restingEnergy > 0 else { return false }
        guard basalEnergy >= 0, activeEnergy >= 0 else { return false }
        let total = basalEnergy + activeEnergy
        let basalWithinRange = basalEnergy >= restingEnergy * 0.75 && basalEnergy <= restingEnergy * 1.35
        let totalWithinRange = total >= restingEnergy && total <= restingEnergy * 2.5
        return basalWithinRange && totalWithinRange
    }
}
