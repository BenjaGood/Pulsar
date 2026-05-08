import Foundation

struct PulsarSharedWorkoutInput {
    var type: String
    var durationMinutes: Double
    var activeEnergyKilocalories: Double?
    var distanceMeters: Double? = nil
    var averageHeartRate: Double?
    var peakHeartRate: Double?
    var sourceName: String?
}

struct PulsarSharedActivityInput {
    var steps: Double
    var activeEnergyKilocalories: Double
    var basalEnergyKilocalories: Double? = nil
    var distanceMeters: Double = 0
    var exerciseMinutes: Double
    var elevatedHeartRateMinutes: Double = 0
    var moderateHeartRateMinutes: Double = 0
    var vigorousHeartRateMinutes: Double = 0
    var zone1Minutes: Double = 0
    var zone2Minutes: Double = 0
    var zone3Minutes: Double = 0
    var zone4Minutes: Double = 0
    var zone5Minutes: Double = 0
    var averageElevatedHeartRate: Double? = nil
    var peakHeartRate: Double? = nil
    var restingHeartRate: Double? = nil
    var maxHeartRate: Double? = nil
}

struct PulsarSharedHeartRateSample {
    var start: Date
    var end: Date
    var bpm: Double
}

struct PulsarSharedHeartRateContext {
    var elevatedMinutes: Double
    var moderateMinutes: Double
    var vigorousMinutes: Double
    var zone1Minutes: Double = 0
    var zone2Minutes: Double = 0
    var zone3Minutes: Double = 0
    var zone4Minutes: Double = 0
    var zone5Minutes: Double = 0
    var averageElevatedHeartRate: Double?
    var peakHeartRate: Double?
}

struct PulsarSharedStrainTargetRange: Codable, Equatable {
    var lowerBound: Int
    var upperBound: Int

    var midpoint: Int {
        Int((Double(lowerBound + upperBound) / 2).rounded())
    }

    var displayText: String {
        "\(lowerBound)-\(upperBound)"
    }

    func contains(_ score: Int) -> Bool {
        (lowerBound...upperBound).contains(score)
    }
}

struct PulsarSharedBiometricsDay {
    var date: Date
    var hrvSDNN: Double?
    var restingHeartRate: Double?
    var daytimeHeartRate: Double? = nil
    var respiratoryRate: Double?
    var oxygenSaturation: Double?
    var wristTemperatureDeviation: Double?
    var sleepPerformance: Double?
    var strainScore: Double?
    var sourceNames: [String]
}

struct PulsarSharedStressInput {
    var date: Date
    var hrvSDNN: Double?
    var hrvTimestamp: Date? = nil
    var restingHeartRate: Double?
    var respiratoryRate: Double?
    var recentHeartRate: Double?
    var heartRateTimestamp: Date? = nil
    var daytimeHeartRate: Double? = nil
    var sleepDurationMinutes: Double?
    var sleepPerformance: Double?
    var strainScore: Double?
    var recentWorkoutLoad: Double?
    var isWorkoutActive: Bool
    var lastWorkoutEnd: Date? = nil
    var recentSteps: Double? = nil
    var recentActiveEnergyKilocalories: Double? = nil
    var recentExerciseMinutes: Double? = nil
    var movementState: PulsarSharedStressMovementState = .unknown
    var previousScore: Int? = nil
    var sourceNames: [String]
}

enum PulsarSharedMetricCalculator {
    nonisolated static func makeStrainMetric(
        activity: PulsarSharedActivityInput,
        workouts: [PulsarSharedWorkoutInput],
        recentRawLoads: [Double],
        computedAt: Date
    ) -> PulsarStrainSyncMetric? {
        let workoutMinutes = workouts.reduce(0) { $0 + $1.durationMinutes }
        let workoutEnergy = workouts.reduce(0) { $0 + sanitizedWorkoutEnergy($1) }
        let activeLoad = workouts.reduce(0.0) { partial, workout in
            partial + workoutLoad(for: workout)
        }
        let movementLoad = movementLoad(activity: activity, workoutMinutes: workoutMinutes, workoutEnergy: workoutEnergy)
        let passiveHeartLoad = passiveHeartRateLoad(activity: activity, workoutMinutes: workoutMinutes)
        let passiveLoad = movementLoad + passiveHeartLoad
        let rawLoad = activeLoad + passiveLoad
        let progressiveScore = progressiveStrainScore(rawLoad: rawLoad)
        let safeguard = safeguardedCurrentStrainScore(
            progressiveScore: progressiveScore,
            activity: activity,
            workoutCount: workouts.count,
            workoutMinutes: workoutMinutes,
            activeLoad: activeLoad,
            passiveLoad: passiveLoad
        )
        let score = safeguard.score
        let averageActiveHeartRate = average(workouts.compactMap(\.averageHeartRate) + [activity.averageElevatedHeartRate].compactMap { $0 })
        let peakHeartRate = (workouts.compactMap { $0.peakHeartRate ?? $0.averageHeartRate } + [activity.peakHeartRate].compactMap { $0 }).max()
        let sourceNames = Array(Set(workouts.compactMap(\.sourceName))).sorted()
        let confidence: PulsarSyncConfidence

        if averageActiveHeartRate != nil || peakHeartRate != nil || passiveHeartLoad > 0 {
            confidence = .high
        } else if !workouts.isEmpty || activity.steps > 0 || activity.exerciseMinutes > 0 || activity.activeEnergyKilocalories > 0 {
            confidence = .moderate
        } else {
            confidence = .missing
        }

        let metric = PulsarStrainSyncMetric(
            score: score,
            confidence: confidence,
            rawLoad: rawLoad,
            workoutLoad: activeLoad,
            movementLoad: passiveLoad,
            steps: Int(activity.steps.rounded()),
            activeEnergyKilocalories: activity.activeEnergyKilocalories > 0 ? activity.activeEnergyKilocalories : nil,
            exerciseMinutes: activity.exerciseMinutes,
            workoutMinutes: workoutMinutes,
            averageActiveHeartRate: averageActiveHeartRate,
            peakHeartRate: peakHeartRate,
            sourceNames: sourceNames,
            computedAt: computedAt
        )
        logStrainInputs(
            activity: activity,
            workouts: workouts,
            rawLoad: rawLoad,
            activeLoad: activeLoad,
            movementLoad: movementLoad,
            passiveHeartLoad: passiveHeartLoad,
            progressiveScore: progressiveScore,
            safeguards: safeguard.reasons,
            score: score,
            computedAt: computedAt
        )
        return metric.isValid ? metric : nil
    }

    nonisolated static func heartRateContext(samples: [PulsarSharedHeartRateSample], restingHeartRate: Double?, maxHeartRate: Double? = nil) -> PulsarSharedHeartRateContext {
        let sortedSamples = samples
            .filter { $0.bpm.isFinite && (30...260).contains($0.bpm) }
            .sorted { $0.start < $1.start }
        guard !sortedSamples.isEmpty else {
            return PulsarSharedHeartRateContext(elevatedMinutes: 0, moderateMinutes: 0, vigorousMinutes: 0, averageElevatedHeartRate: nil, peakHeartRate: nil)
        }

        let resting = restingHeartRate.flatMap { validHeartRate($0) ? $0 : nil } ?? 65
        let elevatedThreshold = max(95, resting + 20)
        let moderateThreshold = max(115, resting + 35)
        let vigorousThreshold = max(140, resting + 55)
        let resolvedMaxHeartRate = maxHeartRate.flatMap { $0.isFinite && $0 > resting + 45 ? $0 : nil } ?? max(185, resting + 110)
        let reserve = max(80, resolvedMaxHeartRate - resting)
        let zone1Threshold = resting + reserve * 0.50
        let zone2Threshold = resting + reserve * 0.60
        let zone3Threshold = resting + reserve * 0.70
        let zone4Threshold = resting + reserve * 0.80
        let zone5Threshold = resting + reserve * 0.90
        var elevatedMinutes = 0.0
        var moderateMinutes = 0.0
        var vigorousMinutes = 0.0
        var zone1Minutes = 0.0
        var zone2Minutes = 0.0
        var zone3Minutes = 0.0
        var zone4Minutes = 0.0
        var zone5Minutes = 0.0
        var elevatedWeightedHeartRate = 0.0
        var elevatedWeightedMinutes = 0.0

        for index in sortedSamples.indices {
            let sample = sortedSamples[index]
            let nextStart = sortedSamples.index(after: index) < sortedSamples.endIndex ? sortedSamples[sortedSamples.index(after: index)].start : sample.start.addingTimeInterval(60)
            let measuredDuration = sample.end.timeIntervalSince(sample.start)
            let inferredDuration = nextStart.timeIntervalSince(sample.start)
            let duration = measuredDuration >= 10 ? measuredDuration : inferredDuration
            let minutes = min(5, max(0, duration / 60))
            guard minutes > 0 else { continue }

            if sample.bpm >= vigorousThreshold {
                vigorousMinutes += minutes
                moderateMinutes += minutes
                elevatedMinutes += minutes
            } else if sample.bpm >= moderateThreshold {
                moderateMinutes += minutes
                elevatedMinutes += minutes
            } else if sample.bpm >= elevatedThreshold {
                elevatedMinutes += minutes
            }

            if sample.bpm >= elevatedThreshold {
                elevatedWeightedHeartRate += sample.bpm * minutes
                elevatedWeightedMinutes += minutes
            }

            switch sample.bpm {
            case zone5Threshold...:
                zone5Minutes += minutes
            case zone4Threshold..<zone5Threshold:
                zone4Minutes += minutes
            case zone3Threshold..<zone4Threshold:
                zone3Minutes += minutes
            case zone2Threshold..<zone3Threshold:
                zone2Minutes += minutes
            case zone1Threshold..<zone2Threshold:
                zone1Minutes += minutes
            default:
                break
            }
        }

        return PulsarSharedHeartRateContext(
            elevatedMinutes: elevatedMinutes,
            moderateMinutes: moderateMinutes,
            vigorousMinutes: vigorousMinutes,
            zone1Minutes: zone1Minutes,
            zone2Minutes: zone2Minutes,
            zone3Minutes: zone3Minutes,
            zone4Minutes: zone4Minutes,
            zone5Minutes: zone5Minutes,
            averageElevatedHeartRate: elevatedWeightedMinutes > 0 ? elevatedWeightedHeartRate / elevatedWeightedMinutes : nil,
            peakHeartRate: sortedSamples.map(\.bpm).max()
        )
    }

    nonisolated static func recommendedStrainTarget(forRecoveryScore recoveryScore: Int?) -> Int? {
        recommendedStrainTargetRange(forRecoveryScore: recoveryScore)?.upperBound
    }

    nonisolated static func recommendedStrainTargetRange(forRecoveryScore recoveryScore: Int?, recentStrainScores: [Int] = []) -> PulsarSharedStrainTargetRange? {
        guard let recoveryScore, recoveryScore > 0 else { return nil }
        let base: ClosedRange<Int>
        switch recoveryScore {
        case 85...100:
            base = interpolatedTargetRange(score: recoveryScore, scoreRange: 85...100, lowerRange: 65...72, upperRange: 82...90)
        case 70..<85:
            base = interpolatedTargetRange(score: recoveryScore, scoreRange: 70...84, lowerRange: 55...62, upperRange: 70...78)
        case 50..<70:
            base = interpolatedTargetRange(score: recoveryScore, scoreRange: 50...69, lowerRange: 40...48, upperRange: 55...65)
        case 30..<50:
            base = interpolatedTargetRange(score: recoveryScore, scoreRange: 30...49, lowerRange: 25...32, upperRange: 40...48)
        default:
            base = interpolatedTargetRange(score: max(1, recoveryScore), scoreRange: 1...29, lowerRange: 10...16, upperRange: 22...32)
        }

        let recent = recentStrainScores
            .filter { (0...100).contains($0) }
            .suffix(7)
        let adjustment: Int
        if recent.count >= 3 {
            let average = Double(recent.reduce(0, +)) / Double(recent.count)
            let lastThree = recent.suffix(3)
            let prior = recent.dropLast(3).suffix(3)
            let recentAverage = Double(lastThree.reduce(0, +)) / Double(max(1, lastThree.count))
            let priorAverage = prior.isEmpty ? average : Double(prior.reduce(0, +)) / Double(prior.count)
            let trend = recentAverage - priorAverage
            var shift = 0
            if average >= 62 { shift += 5 }
            else if average >= 45 { shift += 3 }
            else if average < 20 { shift -= 5 }
            else if average < 35 { shift -= 2 }

            if trend > 14 { shift -= 4 }
            if trend < -12 && recoveryScore >= 70 { shift += 2 }
            if recoveryScore < 50 && average >= 60 { shift -= 5 }
            adjustment = shift
        } else {
            adjustment = 0
        }

        let lower = min(92, max(5, base.lowerBound + adjustment))
        let upper = min(95, max(lower + 8, base.upperBound + adjustment))
        return PulsarSharedStrainTargetRange(lowerBound: lower, upperBound: upper)
    }

    nonisolated static func strainGuidance(
        currentStrain: Int?,
        recommendedTarget: Int?,
        recoveryScore: Int?,
        workoutMinutes: Double,
        exerciseMinutes: Double,
        steps: Int,
        isEarlyDay: Bool
    ) -> String {
        strainGuidance(
            currentStrain: currentStrain,
            targetRange: recommendedTarget.map { PulsarSharedStrainTargetRange(lowerBound: max(0, $0 - 18), upperBound: $0) },
            recoveryScore: recoveryScore,
            activeStrain: nil,
            passiveStrain: nil,
            workoutMinutes: workoutMinutes,
            exerciseMinutes: exerciseMinutes,
            steps: steps,
            isEarlyDay: isEarlyDay
        )
    }

    nonisolated static func strainGuidance(
        currentStrain: Int?,
        targetRange: PulsarSharedStrainTargetRange?,
        recoveryScore: Int?,
        activeStrain: Double?,
        passiveStrain: Double?,
        workoutMinutes: Double,
        exerciseMinutes: Double,
        steps: Int,
        isEarlyDay: Bool
    ) -> String {
        guard let currentStrain else {
            return "Strain will update as workouts, movement, and heart-rate load accumulate."
        }

        if isEarlyDay && workoutMinutes <= 0 && exerciseMinutes < 10 && steps < 3_000 && currentStrain <= 10 {
            return "Your strain is low because the day has just started. It will increase as your activity and heart-rate load accumulate."
        }

        guard let targetRange else {
            if currentStrain <= 10 {
                return "Current strain is low because Pulsar has only seen light activity so far."
            }
            return "Current strain reflects today's accumulated activity and cardiovascular load."
        }

        if currentStrain > targetRange.upperBound {
            return "You've pushed beyond today's recovery-based target. Prioritize cooldown, hydration, and sleep."
        }

        if currentStrain >= Int((Double(targetRange.upperBound) * 0.88).rounded()),
           (recoveryScore ?? 100) < 50 {
            return "You're approaching today's recommended limit. Consider active recovery."
        }

        if currentStrain >= targetRange.lowerBound && currentStrain <= targetRange.upperBound {
            if let activeStrain, let passiveStrain {
                if activeStrain >= passiveStrain * 1.35 && workoutMinutes >= 15 {
                    return "Your strain is moderate today, mostly driven by your recorded workout."
                }
                if passiveStrain > activeStrain && steps >= 5_000 {
                    return "Your passive strain is normal. Most of today's load came from movement outside workouts."
                }
            }
            return "You are within today's recommended strain range."
        }

        if currentStrain <= 15 && targetRange.upperBound >= 70 {
            return "Your body is ready for more. You can safely build toward a higher strain today."
        }

        if currentStrain < targetRange.lowerBound {
            return "Your current strain is still low. You have room to build toward your target today."
        }

        return "You are approaching the top of today's target range. Consider recovery-focused activity."
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

    nonisolated static func makeStressMetric(
        today: PulsarSharedStressInput,
        baselineDays: [PulsarSharedBiometricsDay],
        sleep: PulsarSleepSyncMetric?,
        strain: PulsarStrainSyncMetric?,
        computedAt: Date
    ) -> PulsarStressSyncMetric? {
        let baselineHRV = metricBaseline(baselineDays.compactMap(\.hrvSDNN).filter(validHRV), minimumStandardDeviation: 4)
        let baselineRHR = metricBaseline(baselineDays.compactMap(\.restingHeartRate).filter(validHeartRate), minimumStandardDeviation: 2)
        let baselineDaytimeHR = metricBaseline(baselineDays.compactMap(\.daytimeHeartRate).filter(validRecentHeartRate), minimumStandardDeviation: 5)
        let movementState = resolvedStressMovementState(today: today, computedAt: computedAt)
        let cooldownMinutes = today.lastWorkoutEnd.map { max(0, computedAt.timeIntervalSince($0) / 60) }
        let cooldownActive = movementState == .cooldown && (cooldownMinutes ?? .infinity) <= 12
        let sourceNames = Array(Set(today.sourceNames + baselineDays.flatMap(\.sourceNames) + (sleep?.sourceNames ?? []) + (strain?.sourceNames ?? []))).sorted()
        let availableSignalCount = [
            today.hrvSDNN,
            today.restingHeartRate,
            today.respiratoryRate,
            today.recentHeartRate
        ].compactMap { $0 }.count

        if today.isWorkoutActive || movementState == .workout || cooldownActive {
            let state: PulsarSharedStressCalculationState = today.isWorkoutActive || movementState == .workout ? .workoutPaused : .cooldownPaused
            let message = state == .workoutPaused
                ? "Stress tracking is paused during workouts because exercise naturally raises heart rate."
                : "Stress is paused while your heart rate settles after activity."
            let metric = PulsarStressSyncMetric(
                score: 0,
                confidence: .low,
                levelText: state.displayText,
                driverInsights: [message],
                hrvSDNN: today.hrvSDNN,
                hrvTimestamp: today.hrvTimestamp,
                hrvBaseline: baselineHRV?.mean,
                restingHeartRate: today.restingHeartRate,
                restingHeartRateBaseline: baselineRHR?.mean,
                respiratoryRate: today.respiratoryRate,
                recentHeartRate: today.recentHeartRate,
                heartRateTimestamp: today.heartRateTimestamp,
                daytimeHeartRateBaseline: baselineDaytimeHR?.mean ?? today.daytimeHeartRate,
                nonActivityStress: nil,
                activityAdjustedStress: nil,
                rawStressScore: nil,
                activityAdjustment: nil,
                smoothedStressScore: nil,
                movementState: movementState.rawValue,
                recentSteps: today.recentSteps,
                recentActiveEnergyKilocalories: today.recentActiveEnergyKilocalories,
                isWorkoutActive: today.isWorkoutActive || movementState == .workout,
                lastWorkoutEnd: today.lastWorkoutEnd,
                cooldownActive: state == .cooldownPaused,
                calculationState: state.rawValue,
                appliedAdjustments: [state.displayText],
                sleepDurationMinutes: today.sleepDurationMinutes ?? sleep?.totalSleepMinutes,
                strainScore: today.strainScore ?? strain.map { Double($0.score) },
                availableSignalCount: availableSignalCount,
                baselineWindowDays: stressBaselineDayCount(baselineDays),
                timelineSamples: [PulsarStressSyncSample(timestamp: computedAt, score: 0, context: state == .workoutPaused ? "workout" : "recovery")],
                sourceNames: sourceNames,
                computedAt: computedAt
            )
            logStressCalculation(metric: metric, today: today, computedAt: computedAt)
            return metric.isValid ? metric : nil
        }

        let hrvAgeMinutes = today.hrvTimestamp.map { max(0, computedAt.timeIntervalSince($0) / 60) }
        let heartRateAgeMinutes = today.heartRateTimestamp.map { max(0, computedAt.timeIntervalSince($0) / 60) }
        let hrvFreshness = stressFreshnessMultiplier(ageMinutes: hrvAgeMinutes, freshMinutes: 360, staleMinutes: 1_080)
        let heartRateFreshness = stressFreshnessMultiplier(ageMinutes: heartRateAgeMinutes, freshMinutes: 8, staleMinutes: 35)
        let hrvIsStale = hrvAgeMinutes.map { $0 > 720 } ?? false
        let heartRateIsStale = heartRateAgeMinutes.map { $0 > 20 } ?? false

        let restingBaseline = baselineRHR?.mean ?? today.restingHeartRate
        let restingSpread = max(5, baselineRHR?.standardDeviation ?? 6)
        let daytimeBaseline = today.daytimeHeartRate ?? baselineDaytimeHR?.mean ?? restingBaseline.map { $0 + 12 }
        let hrvBaseline = baselineHRV?.mean
        let hrvSpread = max(4, baselineHRV?.standardDeviation ?? 8)

        let hrvDeviation = stressHRVDeviation(value: today.hrvSDNN, baseline: hrvBaseline, spread: hrvSpread, freshness: hrvFreshness)
        let nonActivityHeartDeviation = stressHeartRateDeviation(
            heartRate: today.recentHeartRate,
            expected: restingBaseline.map { $0 + 5 },
            spread: restingSpread,
            freshness: heartRateFreshness
        )
        let contextualHeartDeviation = stressHeartRateDeviation(
            heartRate: today.recentHeartRate,
            expected: expectedStressHeartRate(restingBaseline: restingBaseline, daytimeBaseline: daytimeBaseline, movementState: movementState),
            spread: stressHeartRateSpread(restingSpread: restingSpread, movementState: movementState),
            freshness: heartRateFreshness
        )

        guard hrvDeviation != nil || nonActivityHeartDeviation != nil || contextualHeartDeviation != nil else {
            return nil
        }

        var adjustments: [String] = []
        let nonActivityScore = physiologicalStressScore(
            heartDeviation: nonActivityHeartDeviation,
            hrvDeviation: hrvDeviation,
            hrvFreshness: hrvFreshness,
            heartRateFreshness: heartRateFreshness,
            isInactive: true,
            adjustments: &adjustments
        )
        var activityAdjustedScore = physiologicalStressScore(
            heartDeviation: contextualHeartDeviation,
            hrvDeviation: hrvDeviation,
            hrvFreshness: hrvFreshness,
            heartRateFreshness: heartRateFreshness,
            isInactive: movementState == .inactive || movementState == .unknown,
            adjustments: &adjustments
        )

        let movementDiscount = stressMovementDiscount(
            movementState: movementState,
            recentSteps: today.recentSteps,
            recentActiveEnergyKilocalories: today.recentActiveEnergyKilocalories,
            recentExerciseMinutes: today.recentExerciseMinutes,
            cooldownMinutes: cooldownMinutes
        )
        if movementDiscount > 0 {
            activityAdjustedScore = max(0, activityAdjustedScore - movementDiscount)
            adjustments.append("movement discount \(Int(movementDiscount.rounded()))")
        }

        let capped = safeguardedStressScore(
            score: activityAdjustedScore,
            nonActivityScore: nonActivityScore,
            heartDeviation: contextualHeartDeviation,
            hrvDeviation: hrvDeviation,
            movementState: movementState,
            hrvIsStale: hrvIsStale,
            heartRateIsStale: heartRateIsStale,
            adjustments: &adjustments
        )
        let smoothed = smoothedStressScore(current: capped, previous: today.previousScore, movementState: movementState)
        if today.previousScore != nil, abs(smoothed - capped) >= 0.5 {
            adjustments.append("short-window smoothing")
        }

        let score = PulsarStressScale.roundedScore(smoothed)
        let calculationState: PulsarSharedStressCalculationState = heartRateIsStale || hrvIsStale ? .lowConfidence : .measuring
        let confidence = stressConfidence(
            baselineDayCount: stressBaselineDayCount(baselineDays),
            hasHeartRate: contextualHeartDeviation != nil,
            hasHRV: hrvDeviation != nil,
            heartRateIsStale: heartRateIsStale,
            hrvIsStale: hrvIsStale,
            movementState: movementState,
            calculationState: calculationState
        )
        let drivers = stressDrivers(
            score: score,
            confidence: confidence,
            movementState: movementState,
            calculationState: calculationState,
            heartDeviation: contextualHeartDeviation,
            hrvDeviation: hrvDeviation,
            hrvIsStale: hrvIsStale,
            heartRateIsStale: heartRateIsStale
        )
        let sample = PulsarStressSyncSample(timestamp: today.heartRateTimestamp ?? computedAt, score: Double(score), context: stressTimelineContext(for: movementState))

        let metric = PulsarStressSyncMetric(
            score: score,
            confidence: confidence,
            levelText: stressLevelText(score: score),
            driverInsights: drivers,
            hrvSDNN: today.hrvSDNN,
            hrvTimestamp: today.hrvTimestamp,
            hrvBaseline: hrvBaseline,
            restingHeartRate: today.restingHeartRate,
            restingHeartRateBaseline: restingBaseline,
            respiratoryRate: today.respiratoryRate,
            recentHeartRate: today.recentHeartRate,
            heartRateTimestamp: today.heartRateTimestamp,
            daytimeHeartRateBaseline: daytimeBaseline,
            heartRateDeviation: contextualHeartDeviation,
            hrvDeviation: hrvDeviation,
            nonActivityStress: nonActivityScore,
            activityAdjustedStress: capped,
            rawStressScore: activityAdjustedScore,
            activityAdjustment: max(0, nonActivityScore - capped),
            smoothedStressScore: smoothed,
            movementState: movementState.rawValue,
            recentSteps: today.recentSteps,
            recentActiveEnergyKilocalories: today.recentActiveEnergyKilocalories,
            isWorkoutActive: false,
            lastWorkoutEnd: today.lastWorkoutEnd,
            cooldownActive: false,
            calculationState: calculationState.rawValue,
            appliedAdjustments: adjustments,
            sleepDurationMinutes: today.sleepDurationMinutes ?? sleep?.totalSleepMinutes,
            strainScore: today.strainScore ?? strain.map { Double($0.score) },
            availableSignalCount: availableSignalCount,
            baselineWindowDays: stressBaselineDayCount(baselineDays),
            timelineSamples: [sample],
            sourceNames: sourceNames,
            computedAt: computedAt
        )
        logStressCalculation(metric: metric, today: today, computedAt: computedAt)
        return metric.isValid ? metric : nil
    }

    nonisolated private static func stressBaselineDayCount(_ days: [PulsarSharedBiometricsDay]) -> Int {
        days.filter {
            $0.hrvSDNN != nil ||
                $0.restingHeartRate != nil ||
                $0.daytimeHeartRate != nil ||
                $0.respiratoryRate != nil
        }.count
    }

    nonisolated private static func resolvedStressMovementState(today: PulsarSharedStressInput, computedAt: Date) -> PulsarSharedStressMovementState {
        if today.isWorkoutActive { return .workout }
        if let lastWorkoutEnd = today.lastWorkoutEnd {
            let minutesSinceWorkout = computedAt.timeIntervalSince(lastWorkoutEnd) / 60
            if minutesSinceWorkout >= 0 && minutesSinceWorkout <= 12 {
                return .cooldown
            }
        }
        if today.movementState != .unknown {
            return today.movementState
        }

        let steps = today.recentSteps ?? 0
        let energy = today.recentActiveEnergyKilocalories ?? 0
        let exercise = today.recentExerciseMinutes ?? 0
        if exercise >= 2.5 || steps >= 350 || energy >= 18 {
            return .activeMovement
        }
        if exercise >= 0.5 || steps >= 80 || energy >= 6 {
            return .lightMovement
        }
        if steps > 0 || energy > 0 {
            return .lightMovement
        }
        return .inactive
    }

    nonisolated private static func stressFreshnessMultiplier(ageMinutes: Double?, freshMinutes: Double, staleMinutes: Double) -> Double {
        guard let ageMinutes, ageMinutes.isFinite else { return 0.86 }
        if ageMinutes <= freshMinutes { return 1 }
        if ageMinutes >= staleMinutes { return 0.20 }
        let progress = (ageMinutes - freshMinutes) / max(1, staleMinutes - freshMinutes)
        return PulsarMetricMath.clamp(1 - progress * 0.80, 0.20, 1)
    }

    nonisolated private static func stressHRVDeviation(value: Double?, baseline: Double?, spread: Double, freshness: Double) -> Double? {
        guard let value, validHRV(value), let baseline, baseline.isFinite else { return nil }
        let deviation = (baseline - value) / max(4, spread)
        return PulsarMetricMath.clamp(deviation * freshness, -2, 3)
    }

    nonisolated private static func stressHeartRateDeviation(heartRate: Double?, expected: Double?, spread: Double, freshness: Double) -> Double? {
        guard let heartRate, validRecentHeartRate(heartRate), let expected, expected.isFinite else { return nil }
        let deviation = (heartRate - expected) / max(5, spread)
        return PulsarMetricMath.clamp(deviation * freshness, -2.5, 3.2)
    }

    nonisolated private static func expectedStressHeartRate(restingBaseline: Double?, daytimeBaseline: Double?, movementState: PulsarSharedStressMovementState) -> Double? {
        guard let restingBaseline else { return daytimeBaseline }
        switch movementState {
        case .inactive:
            return restingBaseline + 5
        case .lightMovement:
            return daytimeBaseline ?? restingBaseline + 14
        case .activeMovement:
            return (daytimeBaseline ?? restingBaseline + 18) + 8
        case .cooldown:
            return (daytimeBaseline ?? restingBaseline + 16) + 8
        case .workout:
            return (daytimeBaseline ?? restingBaseline + 22) + 24
        case .unknown:
            return restingBaseline + 9
        }
    }

    nonisolated private static func stressHeartRateSpread(restingSpread: Double, movementState: PulsarSharedStressMovementState) -> Double {
        switch movementState {
        case .inactive:
            return max(6, restingSpread * 1.35)
        case .lightMovement:
            return max(9, restingSpread * 1.9)
        case .activeMovement:
            return max(12, restingSpread * 2.4)
        case .cooldown:
            return max(13, restingSpread * 2.5)
        case .workout:
            return max(18, restingSpread * 3)
        case .unknown:
            return max(8, restingSpread * 1.6)
        }
    }

    nonisolated private static func physiologicalStressScore(
        heartDeviation: Double?,
        hrvDeviation: Double?,
        hrvFreshness: Double,
        heartRateFreshness: Double,
        isInactive: Bool,
        adjustments: inout [String]
    ) -> Double {
        let heart = heartDeviation
        let hrv = hrvDeviation
        let positiveHeart = max(0, heart ?? 0)
        let positiveHRV = max(0, hrv ?? 0)

        var score = 22.0
        if heart != nil {
            score += positiveHeart * (isInactive ? 14.5 : 10.5)
            score += min(0, heart ?? 0) * 5.0
        }
        if hrv != nil {
            let hrvWeight = positiveHeart >= 0.35 ? 9.0 : 5.2
            score += positiveHRV * hrvWeight
            score += min(0, hrv ?? 0) * 4.2
        }

        if positiveHeart > 0.35 && positiveHRV > 0.45 {
            score += min(positiveHeart, positiveHRV) * (isInactive ? 14 : 9)
        }
        if positiveHeart > 1.5 && positiveHRV > 1.4 && isInactive {
            score += (min(positiveHeart, positiveHRV) - 1.35) * 16
        }

        if heart == nil, hrv != nil {
            score = min(score, positiveHRV >= 2.2 ? 56 : 50)
            adjustments.append("HRV-only cap")
        }
        if hrv == nil, heart != nil {
            score = min(score, positiveHeart >= 2.4 ? 68 : 60)
            adjustments.append("heart-rate-only cap")
        }
        if let heart, heart < 0.35, positiveHRV > 0 {
            score = min(score, positiveHRV >= 2.2 ? 56 : 50)
            adjustments.append("low-HRV without HR elevation cap")
        }
        if hrvFreshness < 0.55 {
            score = min(score, 62)
            adjustments.append("stale HRV cap")
        }
        if heartRateFreshness < 0.55 {
            score = min(score, 60)
            adjustments.append("stale HR cap")
        }

        return PulsarStressScale.clampedScore(score)
    }

    nonisolated private static func stressMovementDiscount(
        movementState: PulsarSharedStressMovementState,
        recentSteps: Double?,
        recentActiveEnergyKilocalories: Double?,
        recentExerciseMinutes: Double?,
        cooldownMinutes: Double?
    ) -> Double {
        let steps = recentSteps ?? 0
        let energy = recentActiveEnergyKilocalories ?? 0
        let exercise = recentExerciseMinutes ?? 0
        let movementEvidence = min(1, steps / 550) * 9 + min(1, energy / 22) * 8 + min(1, exercise / 4) * 7
        switch movementState {
        case .inactive, .unknown:
            return 0
        case .lightMovement:
            return max(5, min(14, movementEvidence * 0.65))
        case .activeMovement:
            return max(12, min(26, movementEvidence + 8))
        case .cooldown:
            let minutes = cooldownMinutes ?? 12
            let decay = PulsarMetricMath.clamp(1 - (minutes - 12) / 18, 0.15, 1)
            return 18 * decay
        case .workout:
            return 40
        }
    }

    nonisolated private static func safeguardedStressScore(
        score: Double,
        nonActivityScore: Double,
        heartDeviation: Double?,
        hrvDeviation: Double?,
        movementState: PulsarSharedStressMovementState,
        hrvIsStale: Bool,
        heartRateIsStale: Bool,
        adjustments: inout [String]
    ) -> Double {
        var capped = PulsarStressScale.clampedScore(score)
        let heart = heartDeviation ?? 0
        let hrv = hrvDeviation ?? 0
        let inactive = movementState == .inactive || movementState == .unknown

        if movementState == .lightMovement {
            let cap = max(48, min(64, nonActivityScore - 6))
            if capped > cap {
                capped = cap
                adjustments.append("light movement cap")
            }
        } else if movementState == .activeMovement {
            let cap = max(45, min(60, nonActivityScore - 10))
            if capped > cap {
                capped = cap
                adjustments.append("active movement cap")
            }
        }

        if capped > 75, !(inactive && heart >= 1.55 && hrv >= 1.25 && !hrvIsStale && !heartRateIsStale) {
            capped = 74
            adjustments.append("high-stress evidence cap")
        }
        if capped > 85, !(inactive && heart >= 2.25 && hrv >= 1.9 && !hrvIsStale && !heartRateIsStale) {
            capped = 85
            adjustments.append("very-high stress evidence cap")
        }
        if heart < 0.35 && hrv > 0 {
            let cap = hrv >= 2.3 ? 56.0 : 50.0
            if capped > cap {
                capped = cap
                adjustments.append("HRV-alone safeguard")
            }
        }
        return PulsarStressScale.clampedScore(capped)
    }

    nonisolated private static func smoothedStressScore(current: Double, previous: Int?, movementState: PulsarSharedStressMovementState) -> Double {
        guard let previous else { return current }
        let previousValue = Double(previous)
        if current >= previousValue {
            return previousValue * 0.30 + current * 0.70
        }
        let fallWeight = movementState == .inactive || movementState == .unknown ? 0.72 : 0.82
        return previousValue * (1 - fallWeight) + current * fallWeight
    }

    nonisolated private static func stressTimelineContext(for movementState: PulsarSharedStressMovementState) -> String {
        switch movementState {
        case .inactive:
            return "rest"
        case .lightMovement, .activeMovement:
            return "active"
        case .workout:
            return "workout"
        case .cooldown:
            return "recovery"
        case .unknown:
            return "unknown"
        }
    }

    nonisolated private static func logStressCalculation(metric: PulsarStressSyncMetric, today: PulsarSharedStressInput, computedAt: Date) {
        let heartAge = today.heartRateTimestamp.map { String(format: "%.1fm", max(0, computedAt.timeIntervalSince($0) / 60)) } ?? "nil"
        let hrvAge = today.hrvTimestamp.map { String(format: "%.1fm", max(0, computedAt.timeIntervalSince($0) / 60)) } ?? "nil"
        let adjustments = metric.appliedAdjustments.isEmpty ? "none" : metric.appliedAdjustments.joined(separator: ",")
        PulsarSyncDebugLogger.log("stress validation currentHR=\(metric.recentHeartRate.map { String(format: "%.1f", $0) } ?? "nil") HRTimestamp=\(today.heartRateTimestamp.map { "\($0)" } ?? "nil") HRAge=\(heartAge) HRV=\(metric.hrvSDNN.map { String(format: "%.1f", $0) } ?? "nil") HRVTimestamp=\(today.hrvTimestamp.map { "\($0)" } ?? "nil") HRVAge=\(hrvAge) restingHRBaseline=\(metric.restingHeartRateBaseline.map { String(format: "%.1f", $0) } ?? "nil") daytimeHRBaseline=\(metric.daytimeHeartRateBaseline.map { String(format: "%.1f", $0) } ?? "nil") HRVBaseline=\(metric.hrvBaseline.map { String(format: "%.1f", $0) } ?? "nil") HRDeviation=\(metric.heartRateDeviation.map { String(format: "%.2f", $0) } ?? "nil") HRVDeviation=\(metric.hrvDeviation.map { String(format: "%.2f", $0) } ?? "nil") movementState=\(metric.movementState ?? "nil") recentSteps=\(metric.recentSteps.map { String(format: "%.0f", $0) } ?? "nil") recentActiveEnergy=\(metric.recentActiveEnergyKilocalories.map { String(format: "%.1f", $0) } ?? "nil") workoutActive=\(metric.isWorkoutActive) lastWorkoutEnd=\(metric.lastWorkoutEnd.map { "\($0)" } ?? "nil") cooldownActive=\(metric.cooldownActive) rawStress=\(metric.rawStressScore.map { String(format: "%.1f", $0) } ?? "nil") activityAdjustment=\(metric.activityAdjustment.map { String(format: "%.1f", $0) } ?? "nil") smoothedStress=\(metric.smoothedStressScore.map { String(format: "%.1f", $0) } ?? "nil") finalStress=\(metric.score) label=\(metric.levelText) confidence=\(metric.confidence.rawValue) adjustments=\(adjustments)")
    }

    private enum WorkoutStrainCategory {
        case walking
        case strength
        case running
        case cycling
        case hiit
        case endurance
        case mobility
        case other

        nonisolated var durationFactor: Double {
            switch self {
            case .walking: 0.42
            case .strength: 0.70
            case .running: 1.02
            case .cycling: 0.82
            case .hiit: 1.12
            case .endurance: 0.92
            case .mobility: 0.32
            case .other: 0.62
            }
        }

        nonisolated var heartRateMultiplier: Double {
            switch self {
            case .strength: 0.48
            case .mobility: 0.35
            case .walking: 0.70
            case .hiit: 1.15
            default: 1.0
            }
        }

        nonisolated var energyDivisor: Double {
            switch self {
            case .walking: 28
            case .strength: 18
            case .running, .hiit: 13
            case .cycling, .endurance: 16
            case .mobility: 32
            case .other: 22
            }
        }

        nonisolated var energyCap: Double {
            switch self {
            case .walking: 9
            case .strength: 13
            case .running, .hiit: 22
            case .cycling, .endurance: 18
            case .mobility: 7
            case .other: 12
            }
        }

        nonisolated var longSessionBonusFactor: Double {
            switch self {
            case .walking: 0.10
            case .strength: 0.12
            case .running, .cycling, .endurance: 0.24
            case .hiit: 0.18
            case .mobility: 0.05
            case .other: 0.10
            }
        }

        nonisolated var singleWorkoutCap: Double {
            switch self {
            case .walking: 52
            case .strength: 62
            case .running, .cycling, .endurance: 88
            case .hiit: 92
            case .mobility: 34
            case .other: 68
            }
        }

        nonisolated var heartRateLoadCap: Double {
            switch self {
            case .strength:
                12
            default:
                26
            }
        }
    }

    nonisolated private static func workoutLoad(for workout: PulsarSharedWorkoutInput) -> Double {
        let duration = max(0, workout.durationMinutes)
        guard duration > 0 else { return 0 }
        let category = workoutCategory(for: workout.type)
        let durationComponent = duration * category.durationFactor
        let heartComponent = workoutHeartRateLoad(for: workout, category: category)
        let energyComponent = min(category.energyCap, sanitizedWorkoutEnergy(workout) / category.energyDivisor)
        let distanceComponent = workoutDistanceLoad(for: workout, category: category)
        let longSessionBonus = min(18, max(0, duration - 60) * category.longSessionBonusFactor)
        let load = durationComponent + heartComponent + energyComponent + distanceComponent + longSessionBonus
        return min(category.singleWorkoutCap, max(0, load))
    }

    nonisolated private static func workoutCategory(for type: String) -> WorkoutStrainCategory {
        let value = type.lowercased()
        if value.contains("strength") || value.contains("traditional") || value.contains("functional") || value.contains("core") {
            return .strength
        }
        if value.contains("walk") || value.contains("hike") {
            return .walking
        }
        if value.contains("run") {
            return .running
        }
        if value.contains("cycle") || value.contains("bike") || value.contains("cycling") {
            return .cycling
        }
        if value.contains("hiit") || value.contains("interval") || value.contains("cross") {
            return .hiit
        }
        if value.contains("row") || value.contains("swim") || value.contains("elliptical") || value.contains("stair") {
            return .endurance
        }
        if value.contains("yoga") || value.contains("pilates") || value.contains("flexibility") || value.contains("mind") {
            return .mobility
        }
        return .other
    }

    nonisolated private static func workoutHeartRateLoad(for workout: PulsarSharedWorkoutInput, category: WorkoutStrainCategory) -> Double {
        guard let average = workout.averageHeartRate, average.isFinite, average > 0 else {
            return workout.peakHeartRate.map { $0 >= 155 ? min(5, workout.durationMinutes * 0.08) : 0 } ?? 0
        }
        let duration = max(0, workout.durationMinutes)
        let baseRate: Double
        switch average {
        case ..<105:
            baseRate = 0
        case 105..<125:
            baseRate = 0.08
        case 125..<145:
            baseRate = 0.18
        case 145..<165:
            baseRate = 0.32
        default:
            baseRate = 0.48
        }
        let peakBonus: Double
        switch workout.peakHeartRate ?? average {
        case 170...:
            peakBonus = 5
        case 155..<170:
            peakBonus = 3
        case 140..<155:
            peakBonus = 1.5
        default:
            peakBonus = 0
        }
        let raw = duration * baseRate * category.heartRateMultiplier + peakBonus * category.heartRateMultiplier
        return min(category.heartRateLoadCap, raw)
    }

    nonisolated private static func movementLoad(activity: PulsarSharedActivityInput, workoutMinutes: Double, workoutEnergy: Double) -> Double {
        let activeEnergyForLoad = sanitizedDailyActiveEnergyForLoad(activity: activity, workoutEnergy: workoutEnergy)
        let nonWorkoutExercise = max(0, activity.exerciseMinutes - workoutMinutes)
        let nonWorkoutEnergy = max(0, activeEnergyForLoad - workoutEnergy * 0.85)
        let steps = max(0, activity.steps)
        let stepLoad = 23 * (1 - exp(-steps / 8_500))
        let distanceLoad = min(7, max(0, activity.distanceMeters) / 1_000 * 0.75)
        let exerciseLoad = min(14, nonWorkoutExercise * 0.45)
        let energyLoad = min(12, nonWorkoutEnergy / 60)
        return min(stepLoad + distanceLoad + exerciseLoad + energyLoad, workoutMinutes > 0 ? 30 : 36)
    }

    nonisolated private static func passiveHeartRateLoad(activity: PulsarSharedActivityInput, workoutMinutes: Double) -> Double {
        let elevated = max(0, activity.elevatedHeartRateMinutes - workoutMinutes * 0.75)
        let moderate = max(0, activity.moderateHeartRateMinutes - workoutMinutes * 0.55)
        let vigorous = max(0, activity.vigorousHeartRateMinutes - workoutMinutes * 0.35)
        let thresholdLoad = min(8, elevated * 0.10) + min(12, moderate * 0.22) + min(16, vigorous * 0.45)
        let zone2 = max(0, activity.zone2Minutes - workoutMinutes * 0.70)
        let zone3 = max(0, activity.zone3Minutes - workoutMinutes * 0.55)
        let zone4 = max(0, activity.zone4Minutes - workoutMinutes * 0.40)
        let zone5 = max(0, activity.zone5Minutes - workoutMinutes * 0.25)
        let zoneLoad = min(22, zone2 * 0.08 + zone3 * 0.18 + zone4 * 0.34 + zone5 * 0.52)
        return min(max(thresholdLoad, zoneLoad), workoutMinutes > 0 ? 18 : 28)
    }

    nonisolated private static func progressiveStrainScore(rawLoad: Double) -> Double {
        let base = 100 * (1 - exp(-max(0, rawLoad) / 74))
        guard base > 70 else { return base }
        let highAdjusted = 70 + pow((base - 70) / 30, 1.24) * 30
        guard highAdjusted > 85 else { return highAdjusted }
        return 85 + pow((highAdjusted - 85) / 15, 1.42) * 15
    }

    nonisolated private static func safeguardedCurrentStrainScore(
        progressiveScore: Double,
        activity: PulsarSharedActivityInput,
        workoutCount: Int,
        workoutMinutes: Double,
        activeLoad: Double,
        passiveLoad: Double
    ) -> (score: Int, reasons: [String]) {
        let hasWorkout = workoutCount > 0 && workoutMinutes >= 5
        let steps = max(0, activity.steps)
        let exerciseMinutes = max(0, activity.exerciseMinutes)
        let activeEnergy = sanitizedDailyActiveEnergyForLoad(activity: activity, workoutEnergy: 0)
        let sustainedElevatedHeartRate = activity.vigorousHeartRateMinutes >= 8 ||
            activity.moderateHeartRateMinutes >= 25 ||
            activity.elevatedHeartRateMinutes >= 45
        var cap = 100.0
        var reasons: [String] = []

        if !hasWorkout {
            if exerciseMinutes < 10 && steps < 3_000 {
                cap = min(cap, (activeEnergy >= 180 || sustainedElevatedHeartRate) ? 25 : 18)
                reasons.append("noWorkoutLowMovement")
            } else if exerciseMinutes < 20 && steps < 6_000 {
                cap = min(cap, (activeEnergy >= 350 || sustainedElevatedHeartRate) ? 35 : 30)
                reasons.append("noWorkoutModerateMovement")
            } else if exerciseMinutes < 30 && steps < 9_000 && !sustainedElevatedHeartRate {
                cap = min(cap, 45)
                reasons.append("passiveOnlyCeiling")
            }
        }

        let moderateStrengthDay = workoutCount == 1 &&
            workoutMinutes >= 35 &&
            workoutMinutes <= 55 &&
            steps < 7_500 &&
            activeLoad < 58 &&
            activity.vigorousHeartRateMinutes < 8
        if moderateStrengthDay {
            cap = min(cap, 64)
            reasons.append("moderateSingleWorkoutCeiling")
        }

        let strongExertion = (hasWorkout && (workoutMinutes >= 45 || activeLoad >= 56 || activeEnergy >= 620)) ||
            activeEnergy >= 800 ||
            exerciseMinutes >= 65 ||
            activity.vigorousHeartRateMinutes >= 12 ||
            activity.moderateHeartRateMinutes >= 35 ||
            passiveLoad >= 38
        if !strongExertion {
            cap = min(cap, 70)
            reasons.append("above70RequiresStrongEvidence")
        }

        let veryHardExertion = (hasWorkout && workoutMinutes >= 75 && (activeLoad >= 78 || activeEnergy >= 850 || activity.vigorousHeartRateMinutes >= 15 || activity.moderateHeartRateMinutes >= 55)) ||
            workoutCount >= 2 && workoutMinutes >= 70 ||
            activeEnergy >= 1_050 ||
            exerciseMinutes >= 105
        if !veryHardExertion {
            cap = min(cap, 88)
            reasons.append("above85RequiresHardWorkout")
        }

        let exceptionalLoad = (hasWorkout && workoutMinutes >= 120 && (activeLoad >= 125 || activeEnergy >= 1_250 || activity.vigorousHeartRateMinutes >= 28)) ||
            workoutCount >= 2 && workoutMinutes >= 120 && activeEnergy >= 1_100 ||
            exerciseMinutes >= 150 ||
            activeEnergy >= 1_500
        if !exceptionalLoad {
            cap = min(cap, 95)
            reasons.append("above95RequiresExceptionalLoad")
        }

        let score = Int(min(100, max(0, min(progressiveScore, cap))).rounded())
        return (score, reasons)
    }

    nonisolated private static func workoutDistanceLoad(for workout: PulsarSharedWorkoutInput, category: WorkoutStrainCategory) -> Double {
        let kilometers = max(0, workout.distanceMeters ?? 0) / 1_000
        guard kilometers > 0 else { return 0 }
        switch category {
        case .running:
            return min(12, kilometers * 1.35)
        case .walking:
            return min(8, kilometers * 0.72)
        case .cycling:
            return min(10, kilometers * 0.32)
        case .endurance:
            return min(9, kilometers * 0.55)
        default:
            return min(4, kilometers * 0.25)
        }
    }

    nonisolated private static func sanitizedWorkoutEnergy(_ workout: PulsarSharedWorkoutInput) -> Double {
        let energy = max(0, workout.activeEnergyKilocalories ?? 0)
        guard energy > 0 else { return 0 }
        let category = workoutCategory(for: workout.type)
        let maxPerMinute: Double
        switch category {
        case .walking, .mobility:
            maxPerMinute = 9
        case .strength:
            maxPerMinute = 14
        case .running, .hiit:
            maxPerMinute = 24
        case .cycling, .endurance:
            maxPerMinute = 20
        case .other:
            maxPerMinute = 16
        }
        return min(energy, max(60, workout.durationMinutes * maxPerMinute))
    }

    nonisolated private static func sanitizedDailyActiveEnergyForLoad(activity: PulsarSharedActivityInput, workoutEnergy: Double) -> Double {
        let activeEnergy = max(0, activity.activeEnergyKilocalories)
        guard activeEnergy > 0 else { return 0 }
        guard let basalEnergy = activity.basalEnergyKilocalories, basalEnergy > 0 else { return activeEnergy }
        let looksLikeTotalEnergy = activeEnergy > 900 && activeEnergy > basalEnergy * 0.85
        guard looksLikeTotalEnergy else { return activeEnergy }
        let movementEstimate = max(0, activity.steps) * 0.045
        let exerciseEstimate = max(0, activity.exerciseMinutes) * 5.0
        let conservativeEstimate = workoutEnergy + movementEstimate + exerciseEstimate
        return min(activeEnergy, max(0, conservativeEstimate))
    }

    nonisolated private static func interpolatedTarget(score: Int, scoreRange: ClosedRange<Int>, targetRange: ClosedRange<Int>) -> Int {
        let scoreSpan = max(1, scoreRange.upperBound - scoreRange.lowerBound)
        let progress = Double(score - scoreRange.lowerBound) / Double(scoreSpan)
        let target = Double(targetRange.lowerBound) + progress * Double(targetRange.upperBound - targetRange.lowerBound)
        return Int(target.rounded())
    }

    nonisolated private static func interpolatedTargetRange(score: Int, scoreRange: ClosedRange<Int>, lowerRange: ClosedRange<Int>, upperRange: ClosedRange<Int>) -> ClosedRange<Int> {
        let lower = interpolatedTarget(score: score, scoreRange: scoreRange, targetRange: lowerRange)
        let upper = interpolatedTarget(score: score, scoreRange: scoreRange, targetRange: upperRange)
        return lower...upper
    }

    nonisolated private static func logStrainInputs(
        activity: PulsarSharedActivityInput,
        workouts: [PulsarSharedWorkoutInput],
        rawLoad: Double,
        activeLoad: Double,
        movementLoad: Double,
        passiveHeartLoad: Double,
        progressiveScore: Double,
        safeguards: [String],
        score: Int,
        computedAt: Date
    ) {
        let averageHeartRateText = activity.averageElevatedHeartRate.map { String(Int($0.rounded())) } ?? "nil"
        let maxHeartRateText = activity.peakHeartRate.map { String(Int($0.rounded())) } ?? "nil"
        let workoutDetails = workouts.map { workout in
            let average = workout.averageHeartRate.map { String(Int($0.rounded())) } ?? "nil"
            let peak = workout.peakHeartRate.map { String(Int($0.rounded())) } ?? "nil"
            let energy = workout.activeEnergyKilocalories.map { String(Int($0.rounded())) } ?? "nil"
            return "\(workout.type):\(Int(workout.durationMinutes.rounded()))m:\(energy)kcal:avg\(average):max\(peak)"
        }.joined(separator: "|")
        let totalEnergy = activity.basalEnergyKilocalories.map { $0 + activity.activeEnergyKilocalories }
        PulsarSyncDebugLogger.log("strain inputs computedAt=\(computedAt) workoutsToday=\(workouts.count) workoutDetails=\(workoutDetails.isEmpty ? "none" : workoutDetails) activeEnergy=\(Int(activity.activeEnergyKilocalories.rounded())) totalEnergy=\(totalEnergy.map { String(Int($0.rounded())) } ?? "nil") exerciseMinutes=\(Int(activity.exerciseMinutes.rounded())) steps=\(Int(activity.steps.rounded())) distanceMeters=\(Int(activity.distanceMeters.rounded())) restingHR=\(activity.restingHeartRate.map { String(Int($0.rounded())) } ?? "nil") averageHeartRate=\(averageHeartRateText) maxHeartRate=\(maxHeartRateText) zoneMinutes=z1:\(Int(activity.zone1Minutes.rounded()))m,z2:\(Int(activity.zone2Minutes.rounded()))m,z3:\(Int(activity.zone3Minutes.rounded()))m,z4:\(Int(activity.zone4Minutes.rounded()))m,z5:\(Int(activity.zone5Minutes.rounded()))m elevatedMinutes=\(Int(activity.elevatedHeartRateMinutes.rounded())) moderateMinutes=\(Int(activity.moderateHeartRateMinutes.rounded())) vigorousMinutes=\(Int(activity.vigorousHeartRateMinutes.rounded())) activeLoad=\(String(format: "%.1f", activeLoad)) passiveMovementLoad=\(String(format: "%.1f", movementLoad)) passiveHeartLoad=\(String(format: "%.1f", passiveHeartLoad)) passiveLoad=\(String(format: "%.1f", movementLoad + passiveHeartLoad)) rawLoad=\(String(format: "%.1f", rawLoad)) progressiveScore=\(String(format: "%.1f", progressiveScore)) finalCurrentStrain=\(score) appliedSafeguards=\(safeguards.isEmpty ? "none" : safeguards.joined(separator: ","))")
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
    nonisolated private static func validRecentHeartRate(_ value: Double) -> Bool { (30...240).contains(value) }
    nonisolated private static func validRespiratoryRate(_ value: Double) -> Bool { (6...30).contains(value) }

    nonisolated private static func metricBaseline(_ values: [Double], minimumStandardDeviation: Double) -> (mean: Double, standardDeviation: Double)? {
        let values = values.filter(\.isFinite)
        guard values.count >= 7 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(max(1, values.count - 1))
        return (mean, max(sqrt(variance), minimumStandardDeviation))
    }

    nonisolated private static func zScore(_ value: Double, baseline: (mean: Double, standardDeviation: Double)) -> Double {
        PulsarMetricMath.clamp((value - baseline.mean) / baseline.standardDeviation, -3, 3)
    }

    nonisolated private static func sleepStress(today: PulsarSharedStressInput, sleep: PulsarSleepSyncMetric?) -> Double? {
        if let performance = today.sleepPerformance ?? sleep?.sleepPerformance {
            return PulsarMetricMath.clamp((0.78 - performance) * 2.25, -2, 2)
        }
        if let minutes = today.sleepDurationMinutes ?? sleep?.totalSleepMinutes, minutes > 0 {
            return PulsarMetricMath.clamp((420 - minutes) / 120, -2, 2)
        }
        return nil
    }

    nonisolated private static func loadStress(today: PulsarSharedStressInput, strain: PulsarStrainSyncMetric?) -> Double? {
        if let score = today.strainScore ?? strain.map({ Double($0.score) }) {
            return PulsarMetricMath.clamp((score - 50) / 25, -2, 2)
        }
        if let load = today.recentWorkoutLoad ?? strain?.rawLoad {
            return PulsarMetricMath.clamp((load - 95) / 45, -2, 2)
        }
        return nil
    }

    nonisolated private static func sigmoid(_ value: Double) -> Double {
        1 / (1 + exp(-value))
    }

    nonisolated static func stressLevelText(score: Int) -> String {
        switch PulsarStressCategory.category(for: score) {
        case .low:
            return "Low"
        case .balanced:
            return "Medium"
        case .elevated:
            return "Elevated"
        case .high:
            return "High"
        }
    }

    nonisolated private static func stressConfidence(
        baselineDayCount: Int,
        hasHeartRate: Bool,
        hasHRV: Bool,
        heartRateIsStale: Bool,
        hrvIsStale: Bool,
        movementState: PulsarSharedStressMovementState,
        calculationState: PulsarSharedStressCalculationState
    ) -> PulsarSyncConfidence {
        if calculationState.isPaused { return .low }
        var points = 0
        points += baselineDayCount >= 14 ? 2 : (baselineDayCount >= 7 ? 1 : 0)
        if hasHeartRate { points += 2 }
        if hasHRV { points += 2 }
        if heartRateIsStale { points -= 2 }
        if hrvIsStale { points -= 1 }
        if movementState == .lightMovement || movementState == .activeMovement || movementState == .cooldown {
            points -= 1
        }
        if points >= 4 { return .high }
        if points >= 2 { return .moderate }
        if hasHeartRate || hasHRV { return .low }
        return .missing
    }

    nonisolated private static func stressDrivers(
        score: Int,
        confidence: PulsarSyncConfidence,
        movementState: PulsarSharedStressMovementState,
        calculationState: PulsarSharedStressCalculationState,
        heartDeviation: Double?,
        hrvDeviation: Double?,
        hrvIsStale: Bool,
        heartRateIsStale: Bool
    ) -> [String] {
        if calculationState == .workoutPaused {
            return ["Stress tracking is paused during workouts because exercise naturally raises heart rate."]
        }
        if calculationState == .cooldownPaused {
            return ["Stress is paused while your heart rate settles after activity."]
        }
        if hrvIsStale || heartRateIsStale {
            return ["Stress confidence is limited because recent wearable data is stale."]
        }
        if movementState == .lightMovement || movementState == .activeMovement {
            return ["Stress is being adjusted because movement can naturally raise heart rate."]
        }

        let heart = heartDeviation ?? 0
        let hrv = hrvDeviation ?? 0
        if score >= 75, heart >= 1.5, hrv >= 1.2 {
            return ["Your heart rate is elevated relative to baseline while HRV is suppressed."]
        }
        if score >= 50, heart >= 0.8, hrv >= 0.6 {
            return ["HR and HRV suggest elevated physiological load right now."]
        }
        if hrv >= 1.2, heart < 0.35 {
            return ["HRV is lower than usual, but heart rate is near baseline."]
        }
        if confidence == .low {
            return ["Stress confidence is limited because recent HRV or heart-rate data is unavailable."]
        }
        return ["Your current HR and HRV are close to baseline."]
    }

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
