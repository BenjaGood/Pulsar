//
//  RecoveryScoringEngine.swift
//  Pulsar
//

import Foundation

struct RecoveryScoringEngine {
    func score(today: DailyBiometrics, baselineDays: [DailyBiometrics]) -> RecoverySummary {
        let hrvBaseline = baselineDays.compactMap(\.hrvSDNNMilliseconds).filter(validHRV)
        let rhrBaseline = baselineDays.compactMap(\.restingHeartRateBPM).filter(validHeartRate)
        let respiratoryBaseline = baselineDays.compactMap(\.respiratoryRate).filter(validRespiratoryRate)

        let hrv = today.hrvSDNNMilliseconds.flatMap { readinessHigherIsBetter(value: $0, baseline: hrvBaseline, valid: validHRV) }
        let rhr = today.restingHeartRateBPM.flatMap { readinessLowerIsBetter(value: $0, baseline: rhrBaseline, valid: validHeartRate) }
        let respiratory = today.respiratoryRate.flatMap { stabilityScore(value: $0, baseline: respiratoryBaseline, valid: validRespiratoryRate) }
        let sleep = today.sleepPerformance.map { ScoreMath.clamp($0) }
        let carryOver = today.priorDayStrain.map { ScoreMath.clamp(1 - $0) }

        let availableWeights: [(Double, Double?)] = [
            (0.35, hrv),
            (0.20, rhr),
            (0.10, respiratory),
            (0.25, sleep),
            (0.10, carryOver)
        ]
        let weightSum = availableWeights.compactMap { $0.1 == nil ? nil : $0.0 }.reduce(0, +)
        guard weightSum > 0 else { return .missing }
        let weighted = availableWeights.reduce(0.0) { partial, pair in
            guard let value = pair.1 else { return partial }
            return partial + value * pair.0
        } / weightSum

        let confidence = confidenceGrade(
            validHRVDays: hrvBaseline.count,
            validRHRDays: rhrBaseline.count,
            validRespiratoryDays: respiratoryBaseline.count,
            availableContributorCount: availableWeights.filter { $0.1 != nil }.count
        )
        let sourceBadges = SourceResolver.uniqueSourceBadges(Array(today.provenance.values))

        let score = ScoreMath.roundedScore(weighted)
        return RecoverySummary(
            date: today.date,
            score: score,
            confidence: confidence,
            status: status(for: score, confidence: confidence),
            hrvSDNN: today.hrvSDNNMilliseconds,
            hrvBaseline: average(hrvBaseline),
            restingHeartRate: today.restingHeartRateBPM,
            restingHeartRateBaseline: average(rhrBaseline),
            sleepDuration: nil,
            sleepEfficiency: nil,
            deepSleep: nil,
            remSleep: nil,
            strainScore: today.priorDayStrain.map { $0 * 100 },
            respiratoryRate: today.respiratoryRate,
            oxygenSaturation: today.oxygenSaturation,
            wristTemperatureDeviation: today.wristTemperatureDeviationCelsius,
            hrvReadiness: hrv ?? 0,
            restingHeartRateReadiness: rhr ?? 0,
            respiratoryStability: respiratory ?? 0,
            sleepContribution: sleep ?? 0,
            strainPenalty: 1 - (carryOver ?? 1),
            components: [],
            trend: [],
            analyzedSampleCount: analyzedSampleCount(today: today),
            queryStart: nil,
            queryEnd: nil,
            lastUpdated: nil,
            baselineWindowDays: baselineDays.count,
            explanation: explanation(hrv: hrv, rhr: rhr, respiratory: respiratory, sleep: sleep, carryOver: carryOver),
            sourceBadges: sourceBadges,
            notes: notes(confidence: confidence, hrvBaselineDays: hrvBaseline.count)
        )
    }

    private func readinessHigherIsBetter(value: Double, baseline: [Double], valid: (Double) -> Bool) -> Double? {
        guard valid(value), baseline.count >= 7, let z = ScoreMath.robustZScore(value: value, baseline: baseline) else { return nil }
        return ScoreMath.clamp(0.50 + z * 0.15)
    }

    private func readinessLowerIsBetter(value: Double, baseline: [Double], valid: (Double) -> Bool) -> Double? {
        guard valid(value), baseline.count >= 7, let z = ScoreMath.robustZScore(value: value, baseline: baseline) else { return nil }
        return ScoreMath.clamp(0.50 - z * 0.15)
    }

    private func stabilityScore(value: Double, baseline: [Double], valid: (Double) -> Bool) -> Double? {
        guard valid(value), baseline.count >= 7, let z = ScoreMath.robustZScore(value: value, baseline: baseline) else { return nil }
        return ScoreMath.clamp(1 - abs(z) * 0.18)
    }

    private func validHRV(_ value: Double) -> Bool { (5...250).contains(value) }
    private func validHeartRate(_ value: Double) -> Bool { (30...120).contains(value) }
    private func validRespiratoryRate(_ value: Double) -> Bool { (6...30).contains(value) }

    private func confidenceGrade(validHRVDays: Int, validRHRDays: Int, validRespiratoryDays: Int, availableContributorCount: Int) -> ConfidenceGrade {
        if validHRVDays >= 21 && validRHRDays >= 21 && validRespiratoryDays >= 14 && availableContributorCount >= 4 { return .high }
        if validHRVDays >= 10 && validRHRDays >= 10 && availableContributorCount >= 3 { return .moderate }
        if availableContributorCount > 0 { return .low }
        return .missing
    }

    private func status(for score: Int, confidence: ConfidenceGrade) -> RecoveryStatus {
        guard confidence != .missing, score > 0 else { return .unknown }
        if confidence == .low { return .needsAttention }
        switch score {
        case 85...100: return .excellent
        case 70..<85: return .balanced
        case 55..<70: return .moderate
        default: return .low
        }
    }

    private func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private func analyzedSampleCount(today: DailyBiometrics) -> Int {
        [today.hrvSDNNMilliseconds, today.restingHeartRateBPM, today.respiratoryRate, today.oxygenSaturation, today.wristTemperatureDeviationCelsius].compactMap { $0 }.count
            + (today.sleepPerformance == nil ? 0 : 1)
            + (today.priorDayStrain == nil ? 0 : 1)
    }

    private func explanation(hrv: Double?, rhr: Double?, respiratory: Double?, sleep: Double?, carryOver: Double?) -> String {
        var drivers: [String] = []
        if let hrv { drivers.append(hrv >= 0.55 ? "HRV was above baseline" : "HRV was below baseline") }
        if let rhr { drivers.append(rhr >= 0.55 ? "resting heart rate was favorable" : "resting heart rate was elevated") }
        if let respiratory { drivers.append(respiratory >= 0.75 ? "respiratory rate was stable" : "respiratory rate moved away from baseline") }
        if let sleep { drivers.append(sleep >= 0.75 ? "sleep supported recovery" : "sleep limited recovery") }
        if let carryOver { drivers.append(carryOver >= 0.70 ? "prior strain was manageable" : "prior strain carried fatigue forward") }
        return drivers.isEmpty ? "Recovery could not be scored from available HealthKit data." : drivers.joined(separator: "; ") + "."
    }

    private func notes(confidence: ConfidenceGrade, hrvBaselineDays: Int) -> [String] {
        var notes = ["Recovery is baseline-relative and not a medical diagnosis."]
        if hrvBaselineDays < 21 {
            notes.append("Full-confidence HRV readiness needs more valid nights in the 28-day baseline.")
        }
        if confidence == .low {
            notes.append("Scores are degraded until HealthKit has sufficient consistent overnight signals.")
        }
        return notes
    }
}
