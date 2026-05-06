import Foundation

struct PulsarSharedWorkoutInput {
    var type: String
    var durationMinutes: Double
    var activeEnergyKilocalories: Double?
    var averageHeartRate: Double?
    var peakHeartRate: Double?
    var sourceName: String?
}

struct PulsarSharedActivityInput {
    var steps: Double
    var activeEnergyKilocalories: Double
    var exerciseMinutes: Double
}

struct PulsarSharedBiometricsDay {
    var date: Date
    var hrvSDNN: Double?
    var restingHeartRate: Double?
    var respiratoryRate: Double?
    var oxygenSaturation: Double?
    var wristTemperatureDeviation: Double?
    var sleepPerformance: Double?
    var strainScore: Double?
    var sourceNames: [String]
}

enum PulsarSharedMetricCalculator {
    nonisolated static func makeStrainMetric(
        activity: PulsarSharedActivityInput,
        workouts: [PulsarSharedWorkoutInput],
        recentRawLoads: [Double],
        computedAt: Date
    ) -> PulsarStrainSyncMetric? {
        let totalWorkoutLoad = workouts.reduce(0.0) { partial, workout in
            partial + workoutLoad(for: workout)
        }
        let movementLoad = movementLoad(activity: activity, workoutLoad: totalWorkoutLoad)
        let rawLoad = totalWorkoutLoad + movementLoad
        let normalized = normalizedDailyStrain(rawLoad: rawLoad, recentLoads: recentRawLoads)
        let score = PulsarMetricMath.roundedScore(normalized)
        let averageActiveHeartRate = average(workouts.compactMap(\.averageHeartRate))
        let peakHeartRate = workouts.compactMap { $0.peakHeartRate ?? $0.averageHeartRate }.max()
        let sourceNames = Array(Set(workouts.compactMap(\.sourceName))).sorted()
        let confidence: PulsarSyncConfidence

        if averageActiveHeartRate != nil || peakHeartRate != nil {
            confidence = .high
        } else if activity.steps > 0 || activity.exerciseMinutes > 0 || activity.activeEnergyKilocalories > 0 {
            confidence = .moderate
        } else {
            confidence = .missing
        }

        let metric = PulsarStrainSyncMetric(
            score: score,
            confidence: confidence,
            rawLoad: rawLoad,
            workoutLoad: totalWorkoutLoad,
            movementLoad: movementLoad,
            steps: Int(activity.steps.rounded()),
            activeEnergyKilocalories: activity.activeEnergyKilocalories > 0 ? activity.activeEnergyKilocalories : nil,
            exerciseMinutes: activity.exerciseMinutes,
            workoutMinutes: workouts.reduce(0) { $0 + $1.durationMinutes },
            averageActiveHeartRate: averageActiveHeartRate,
            peakHeartRate: peakHeartRate,
            sourceNames: sourceNames,
            computedAt: computedAt
        )
        return metric.isValid ? metric : nil
    }

    nonisolated static func makeRecoveryMetric(
        today: PulsarSharedBiometricsDay,
        baselineDays: [PulsarSharedBiometricsDay],
        computedAt: Date
    ) -> PulsarRecoverySyncMetric? {
        let hrvBaseline = baselineDays.compactMap(\.hrvSDNN).filter(validHRV)
        let rhrBaseline = baselineDays.compactMap(\.restingHeartRate).filter(validHeartRate)
        let respiratoryBaseline = baselineDays.compactMap(\.respiratoryRate).filter(validRespiratoryRate)

        let hrv = today.hrvSDNN.flatMap { readinessHigherIsBetter(value: $0, baseline: hrvBaseline, valid: validHRV) }
        let rhr = today.restingHeartRate.flatMap { readinessLowerIsBetter(value: $0, baseline: rhrBaseline, valid: validHeartRate) }
        let respiratory = today.respiratoryRate.flatMap { stabilityScore(value: $0, baseline: respiratoryBaseline, valid: validRespiratoryRate) }
        let sleep = today.sleepPerformance.map { PulsarMetricMath.clamp($0) }
        let carryOver = today.strainScore.map { PulsarMetricMath.clamp(1 - ($0 / 100)) }

        let contributors: [(Double, Double?)] = [
            (0.35, hrv),
            (0.20, rhr),
            (0.10, respiratory),
            (0.25, sleep),
            (0.10, carryOver)
        ]
        let weightSum = contributors.reduce(0.0) { partial, pair in
            partial + (pair.1 == nil ? 0 : pair.0)
        }
        guard weightSum > 0 else { return nil }

        let weighted = contributors.reduce(0.0) { partial, pair in
            guard let value = pair.1 else { return partial }
            return partial + value * pair.0
        } / weightSum
        let score = PulsarMetricMath.roundedScore(weighted)
        let confidence = recoveryConfidence(validHRVDays: hrvBaseline.count, validRHRDays: rhrBaseline.count, validRespiratoryDays: respiratoryBaseline.count, availableContributorCount: contributors.filter { $0.1 != nil }.count)
        let metric = PulsarRecoverySyncMetric(
            score: score,
            confidence: confidence,
            statusText: recoveryStatus(score: score, confidence: confidence),
            hrvSDNN: today.hrvSDNN,
            hrvBaseline: average(hrvBaseline),
            restingHeartRate: today.restingHeartRate,
            restingHeartRateBaseline: average(rhrBaseline),
            sleepDuration: nil,
            sleepEfficiency: nil,
            strainScore: today.strainScore,
            respiratoryRate: today.respiratoryRate,
            oxygenSaturation: today.oxygenSaturation,
            wristTemperatureDeviation: today.wristTemperatureDeviation,
            hrvReadiness: hrv ?? 0,
            restingHeartRateReadiness: rhr ?? 0,
            respiratoryStability: respiratory ?? 0,
            sleepContribution: sleep ?? 0,
            strainPenalty: 1 - (carryOver ?? 1),
            sourceNames: today.sourceNames.sorted(),
            computedAt: computedAt
        )
        return metric.isValid ? metric : nil
    }

    nonisolated private static func workoutLoad(for workout: PulsarSharedWorkoutInput) -> Double {
        let intensity = intensityMultiplier(averageHeartRate: workout.averageHeartRate, peakHeartRate: workout.peakHeartRate)
        let durationBased = workout.durationMinutes * intensity
        let energyBased = (workout.activeEnergyKilocalories ?? 0) / 8
        let fallback = max(max(durationBased, energyBased), workout.durationMinutes * 1.2)
        return min(120, fallback)
    }

    nonisolated private static func intensityMultiplier(averageHeartRate: Double?, peakHeartRate: Double?) -> Double {
        let reference = peakHeartRate ?? averageHeartRate ?? 0
        switch reference {
        case ..<95: return 0.9
        case ..<115: return 1.2
        case ..<135: return 1.7
        case ..<155: return 2.3
        default: return 2.9
        }
    }

    nonisolated private static func movementLoad(activity: PulsarSharedActivityInput, workoutLoad: Double) -> Double {
        let stepLoad = min(35, activity.steps / 1_000 * 1.2)
        let exerciseLoad = min(45, activity.exerciseMinutes * 1.5)
        let energyContext = min(20, activity.activeEnergyKilocalories / 50)
        let rawMovement = stepLoad + exerciseLoad + energyContext
        let cap = max(25, workoutLoad * 0.35 + 35)
        return min(rawMovement, cap)
    }

    nonisolated private static func normalizedDailyStrain(rawLoad: Double, recentLoads: [Double]) -> Double {
        guard recentLoads.count >= 10,
              let z = PulsarMetricMath.robustZScore(value: rawLoad, baseline: recentLoads, outlierLimit: 3) else {
            return PulsarMetricMath.clamp(rawLoad / 220)
        }
        return PulsarMetricMath.clamp(0.50 + z * 0.16)
    }

    nonisolated private static func readinessHigherIsBetter(value: Double, baseline: [Double], valid: (Double) -> Bool) -> Double? {
        guard valid(value), baseline.count >= 7,
              let z = PulsarMetricMath.robustZScore(value: value, baseline: baseline) else { return nil }
        return PulsarMetricMath.clamp(0.50 + z * 0.15)
    }

    nonisolated private static func readinessLowerIsBetter(value: Double, baseline: [Double], valid: (Double) -> Bool) -> Double? {
        guard valid(value), baseline.count >= 7,
              let z = PulsarMetricMath.robustZScore(value: value, baseline: baseline) else { return nil }
        return PulsarMetricMath.clamp(0.50 - z * 0.15)
    }

    nonisolated private static func stabilityScore(value: Double, baseline: [Double], valid: (Double) -> Bool) -> Double? {
        guard valid(value), baseline.count >= 7,
              let z = PulsarMetricMath.robustZScore(value: value, baseline: baseline) else { return nil }
        return PulsarMetricMath.clamp(1 - abs(z) * 0.18)
    }

    nonisolated private static func validHRV(_ value: Double) -> Bool { (5...250).contains(value) }
    nonisolated private static func validHeartRate(_ value: Double) -> Bool { (30...120).contains(value) }
    nonisolated private static func validRespiratoryRate(_ value: Double) -> Bool { (6...30).contains(value) }

    nonisolated private static func recoveryConfidence(validHRVDays: Int, validRHRDays: Int, validRespiratoryDays: Int, availableContributorCount: Int) -> PulsarSyncConfidence {
        if validHRVDays >= 21 && validRHRDays >= 21 && validRespiratoryDays >= 14 && availableContributorCount >= 4 { return .high }
        if validHRVDays >= 10 && validRHRDays >= 10 && availableContributorCount >= 3 { return .moderate }
        if availableContributorCount > 0 { return .low }
        return .missing
    }

    nonisolated private static func recoveryStatus(score: Int, confidence: PulsarSyncConfidence) -> String {
        guard confidence != .missing, score > 0 else { return "Not enough data" }
        if confidence == .low { return "Build more baseline data" }
        switch score {
        case 85...100: return "Ready to perform"
        case 70..<85: return "Balanced recovery"
        case 55..<70: return "Moderate recovery"
        default: return "Recovery is lower today"
        }
    }

    nonisolated private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

enum PulsarSharedSleepCalculator {
    nonisolated static let defaultTargetSleepHours = 8.0

    nonisolated static func makeSleepMetric(
        analysis: SleepAnalysisSummary,
        recentAnalyses: [SleepAnalysisSummary],
        targetSleepHours: Double?,
        computedAt: Date,
        calendar: Calendar
    ) -> PulsarSleepSyncMetric? {
        guard analysis.hasSamples,
              analysis.totalSleepMinutes > 0,
              let sleepStart = firstSleepStart(in: analysis),
              let sleepEnd = analysis.mergedIntervals.last?.end,
              sleepStart < sleepEnd else { return nil }

        let resolvedTargetSleepHours = validTargetSleepHours(targetSleepHours) ? targetSleepHours! : defaultTargetSleepHours
        let sleepMinutes = analysis.totalSleepMinutes
        let timeInBed = analysis.timeInBedMinutes
        let efficiency = timeInBed > 0 ? sleepMinutes / timeInBed : 0
        let durationAdequacy = PulsarMetricMath.clamp(sleepMinutes / (resolvedTargetSleepHours * 60))
        let regularity = sleepConsistency(for: recentAnalyses + [analysis], calendar: calendar)
        let continuity = PulsarMetricMath.clamp(1 - analysis.wasoMinutes / 90)
        let performance = PulsarMetricMath.clamp(
            durationAdequacy * 0.35 +
                efficiency * 0.25 +
                regularity * 0.25 +
                continuity * 0.15
        )
        let score = PulsarMetricMath.roundedScore(performance)
        let metric = PulsarSleepSyncMetric(
            score: score,
            confidence: confidence(for: analysis, sleepMinutes: sleepMinutes),
            sleepDateKey: SleepWindowResolver.sleepDateKey(forWakeUpDate: analysis.wakeUpDate, calendar: calendar),
            wakeUpDate: analysis.wakeUpDate,
            sleepStart: sleepStart,
            sleepEnd: sleepEnd,
            queryStart: analysis.queryStart,
            queryEnd: analysis.queryEnd,
            totalSleepMinutes: sleepMinutes,
            timeInBedMinutes: timeInBed,
            sleepEfficiency: PulsarMetricMath.clamp(efficiency),
            awakeMinutes: analysis.awakeMinutes,
            wasoMinutes: analysis.wasoMinutes,
            remMinutes: analysis.remMinutes,
            coreMinutes: analysis.coreMinutes,
            deepMinutes: analysis.deepMinutes,
            asleepUnspecifiedMinutes: analysis.asleepUnspecifiedMinutes,
            awakenings: analysis.awakenings,
            analyzedSampleCount: analysis.usedSampleCount,
            sleepConsistency: regularity,
            sleepPerformance: performance,
            durationAdequacy: durationAdequacy,
            regularity: regularity,
            continuity: continuity,
            targetSleepHours: resolvedTargetSleepHours,
            sourceNames: analysis.sourceNames,
            computedAt: computedAt
        )
        return metric.isValid ? metric : nil
    }

    nonisolated private static func validTargetSleepHours(_ value: Double?) -> Bool {
        guard let value else { return false }
        return value.isFinite && (4...14).contains(value)
    }

    nonisolated private static func confidence(for analysis: SleepAnalysisSummary, sleepMinutes: Double) -> PulsarSyncConfidence {
        guard sleepMinutes >= 120 else { return .low }
        if analysis.coreMinutes > 0 || analysis.deepMinutes > 0 || analysis.remMinutes > 0 { return .high }
        if analysis.asleepUnspecifiedMinutes > 0 { return .moderate }
        return .low
    }

    nonisolated private static func sleepConsistency(for analyses: [SleepAnalysisSummary], calendar: Calendar) -> Double {
        let validAnalyses = analyses
            .filter { firstSleepStart(in: $0) != nil && $0.totalSleepMinutes > 0 }
            .sorted { $0.wakeUpDate < $1.wakeUpDate }
        guard validAnalyses.count >= 3 else { return interimRegularity(for: validAnalyses, calendar: calendar) }
        guard validAnalyses.count >= 7 else { return interimRegularity(for: validAnalyses, calendar: calendar) }

        let sleepBins = validAnalyses.map { asleepBins(for: $0, calendar: calendar) }
        let pairScores = zip(sleepBins, sleepBins.dropFirst()).map { lhs, rhs in
            let overlap = lhs.intersection(rhs).count
            let union = lhs.union(rhs).count
            return union == 0 ? 0.0 : Double(overlap) / Double(union)
        }
        return PulsarMetricMath.clamp(pairScores.reduce(0, +) / max(1, Double(pairScores.count)))
    }

    nonisolated private static func asleepBins(for analysis: SleepAnalysisSummary, calendar: Calendar) -> Set<Int> {
        var bins = Set<Int>()
        for interval in analysis.mergedIntervals where interval.stage.isAsleep {
            let startMinutes = minutesFromNoon(interval.start, calendar: calendar)
            let endMinutes = minutesFromNoon(interval.end, calendar: calendar)
            let startBin = Int(startMinutes / 30)
            let endBin = Int(ceil(endMinutes / 30))
            for bin in startBin..<max(startBin + 1, endBin) {
                bins.insert((bin + 48) % 48)
            }
        }
        return bins
    }

    nonisolated private static func interimRegularity(for analyses: [SleepAnalysisSummary], calendar: Calendar) -> Double {
        guard analyses.count >= 2 else { return 0.55 }
        let bedtimes = analyses.compactMap { firstSleepStart(in: $0) }.map { minutesFromNoon($0, calendar: calendar) }
        let wakeTimes = analyses.compactMap { $0.mergedIntervals.last?.end }.map { minutesFromNoon($0, calendar: calendar) }
        guard bedtimes.count >= 2, wakeTimes.count >= 2 else { return 0.55 }
        let midpoints = zip(bedtimes, wakeTimes).map { pair in (pair.0 + pair.1) / 2 }
        let bedtimeScore = variabilityScore(values: bedtimes, toleratedMinutes: 60)
        let wakeScore = variabilityScore(values: wakeTimes, toleratedMinutes: 60)
        let midpointScore = variabilityScore(values: midpoints, toleratedMinutes: 45)
        return PulsarMetricMath.clamp(bedtimeScore * 0.35 + wakeScore * 0.35 + midpointScore * 0.30)
    }

    nonisolated private static func variabilityScore(values: [Double], toleratedMinutes: Double) -> Double {
        guard values.count >= 2, let median = PulsarMetricMath.median(values) else { return 0.55 }
        let deviations = values.map { abs($0 - median) }
        let averageDeviation = deviations.reduce(0, +) / Double(deviations.count)
        return PulsarMetricMath.clamp(1 - averageDeviation / toleratedMinutes)
    }

    nonisolated private static func minutesFromNoon(_ date: Date, calendar: Calendar) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
        return minutes >= 12 * 60 ? minutes - 12 * 60 : minutes + 12 * 60
    }

    nonisolated private static func firstSleepStart(in analysis: SleepAnalysisSummary) -> Date? {
        analysis.mergedIntervals.first(where: { $0.stage.isAsleep })?.start
    }
}

private enum PulsarMetricMath {
    nonisolated static func clamp(_ value: Double, _ lower: Double = 0, _ upper: Double = 1) -> Double {
        min(upper, max(lower, value))
    }

    nonisolated static func roundedScore(_ value: Double) -> Int {
        Int((clamp(value) * 100).rounded())
    }

    nonisolated static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    nonisolated static func medianAbsoluteDeviation(_ values: [Double], median: Double) -> Double? {
        self.median(values.map { abs($0 - median) })
    }

    nonisolated static func robustZScore(value: Double, baseline: [Double], outlierLimit: Double = 3) -> Double? {
        guard let median = median(baseline),
              let mad = medianAbsoluteDeviation(baseline, median: median) else { return nil }
        let robustSigma = max(1, mad * 1.4826)
        return clamp((value - median) / robustSigma, -outlierLimit, outlierLimit)
    }
}
