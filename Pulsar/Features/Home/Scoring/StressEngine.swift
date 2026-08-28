//
//  StressEngine.swift
//  Pulsar
//

import Foundation

enum StressMotionContext: String, Codable, Equatable {
    case resting
    case light
    case active
    case workout
    case postWorkout
    case highArtifact
    case unknown
}

struct StressDailySignals: Identifiable, Codable, Equatable {
    var id: Date { date }
    var date: Date
    var computedAt: Date?
    var heartRateVariabilitySDNN: Double?
    var heartRateVariabilityTimestamp: Date?
    var restingHeartRate: Double?
    var walkingHeartRateAverage: Double?
    var sleepRespiratoryRate: Double?
    var wristTemperatureDelta: Double?
    var sleepDurationHours: Double?
    var sleepInterruptions: Double?
    var bedtimeConsistency: Double?
    var bedtimeMinutesFromMidnight: Double?
    var recentWorkoutLoad: Double?
    var strainScore: Double?
    var currentMotionContext: StressMotionContext = .unknown
    var currentHeartRate: Double?
    var currentHeartRateTimestamp: Date?
    var recentHeartRate: Double?
    var minutesSinceWorkout: Double?
    var lastWorkoutEnd: Date?
    var recentSteps: Double?
    var recentActiveEnergyKilocalories: Double?
    var recentExerciseMinutes: Double?
    var previousStressScore: Int?
    var previousStressTimestamp: Date? = nil
    var overnightWearMinutes: Double?
    var motionArtifactLevel: Double?
    var signalQuality: Double?
    var sourceBadges: [SourceProvenance] = []

    var availableTodaySignalCount: Int {
        [
            heartRateVariabilitySDNN,
            restingHeartRate,
            walkingHeartRateAverage,
            sleepRespiratoryRate,
            wristTemperatureDelta,
            sleepDurationHours,
            sleepInterruptions,
            bedtimeConsistency,
            bedtimeMinutesFromMidnight,
            recentWorkoutLoad,
            strainScore,
            currentHeartRate,
            recentHeartRate
        ].compactMap { $0 }.count
    }

    var hasAnyBaselineSignal: Bool {
        heartRateVariabilitySDNN != nil ||
            restingHeartRate != nil ||
            walkingHeartRateAverage != nil ||
            sleepRespiratoryRate != nil ||
            wristTemperatureDelta != nil ||
            sleepDurationHours != nil ||
            sleepInterruptions != nil ||
            bedtimeConsistency != nil ||
            bedtimeMinutesFromMidnight != nil ||
            recentWorkoutLoad != nil
    }
}

struct StressMetricBaseline: Codable, Equatable {
    var mean: Double
    var standardDeviation: Double
    var sampleCount: Int
}

struct StressBaseline: Codable, Equatable {
    var validDayCount: Int
    var hrvSDNN: StressMetricBaseline?
    var restingHeartRate: StressMetricBaseline?
    var walkingHeartRateAverage: StressMetricBaseline?
    var sleepRespiratoryRate: StressMetricBaseline?
    var wristTemperatureDelta: StressMetricBaseline?
    var sleepDurationHours: StressMetricBaseline?
    var sleepInterruptions: StressMetricBaseline?
    var bedtimeConsistency: StressMetricBaseline?
    var bedtimeMinutesFromMidnight: StressMetricBaseline?
    var recentWorkoutLoad: StressMetricBaseline?

    var availableMetricCount: Int {
        [
            hrvSDNN,
            restingHeartRate,
            walkingHeartRateAverage,
            sleepRespiratoryRate,
            wristTemperatureDelta,
            sleepDurationHours,
            sleepInterruptions,
            bedtimeConsistency,
            bedtimeMinutesFromMidnight,
            recentWorkoutLoad
        ].compactMap { $0 }.count
    }

    var scoringMetricCount: Int {
        [
            hrvSDNN,
            restingHeartRate,
            walkingHeartRateAverage
        ].compactMap { $0 }.count
    }

    var isSufficient: Bool {
        validDayCount >= StressBaselineBuilder.minimumBaselineDays && scoringMetricCount > 0
    }
}

struct StressBaselineBuilder {
    static let minimumBaselineDays = 7
    static let preferredBaselineDays = 14
    static let rollingWindowDays = 21

    func build(from days: [StressDailySignals]) -> StressBaseline {
        let recentDays = Array(days.sorted { $0.date < $1.date }.suffix(Self.rollingWindowDays))
        let validDays = recentDays.filter(\.hasAnyBaselineSignal)

        return StressBaseline(
            validDayCount: validDays.count,
            hrvSDNN: metric(validDays.compactMap(\.heartRateVariabilitySDNN), minimumStandardDeviation: 4),
            restingHeartRate: metric(validDays.compactMap(\.restingHeartRate), minimumStandardDeviation: 2),
            walkingHeartRateAverage: metric(validDays.compactMap(\.walkingHeartRateAverage), minimumStandardDeviation: 3),
            sleepRespiratoryRate: metric(validDays.compactMap(\.sleepRespiratoryRate), minimumStandardDeviation: 0.35),
            wristTemperatureDelta: metric(validDays.compactMap(\.wristTemperatureDelta), minimumStandardDeviation: 0.08),
            sleepDurationHours: metric(validDays.compactMap(\.sleepDurationHours), minimumStandardDeviation: 0.45),
            sleepInterruptions: metric(validDays.compactMap(\.sleepInterruptions), minimumStandardDeviation: 1),
            bedtimeConsistency: metric(validDays.compactMap(\.bedtimeConsistency), minimumStandardDeviation: 0.08),
            bedtimeMinutesFromMidnight: metric(validDays.compactMap(\.bedtimeMinutesFromMidnight), minimumStandardDeviation: 35),
            recentWorkoutLoad: metric(validDays.compactMap(\.recentWorkoutLoad), minimumStandardDeviation: 8)
        )
    }

    private func metric(_ values: [Double], minimumStandardDeviation: Double) -> StressMetricBaseline? {
        let values = values.filter(\.isFinite).sorted()
        guard values.count >= Self.minimumBaselineDays,
              let median = ScoreMath.median(values) else { return nil }
        let medianAbsoluteDeviation = ScoreMath.medianAbsoluteDeviation(values, median: median) ?? 0
        return StressMetricBaseline(
            mean: median,
            standardDeviation: max(medianAbsoluteDeviation * 1.4826, minimumStandardDeviation),
            sampleCount: values.count
        )
    }
}

struct StressScoringService {
    let engine = StressEngine()

    func summary(today: StressDailySignals, baselineDays: [StressDailySignals]) -> StressSummary {
        engine.score(today: today, baselineDays: baselineDays)
    }
}

struct StressTimelinePointBuilder {
    var maximumSampleCount = 36

    func samples(
        summary: StressSummary,
        today: StressDailySignals,
        baseline: StressBaseline,
        heartSamples: [HeartRateSample],
        sleep: SleepSummary,
        strain: StrainSummary,
        interval: DateInterval,
        referenceDate: Date
    ) -> [StressSample] {
        guard let baseScore = summary.currentScore else { return [] }
        let effectiveEnd = min(max(referenceDate, interval.start), interval.end)
        let validHeartSamples = heartSamples
            .filter {
                $0.bpm.isFinite &&
                    $0.bpm > 30 &&
                    $0.bpm < 220 &&
                    $0.end >= interval.start &&
                    $0.end <= effectiveEnd
            }
            .sorted { $0.end < $1.end }

        guard validHeartSamples.count >= 2 else { return [] }

        let sampled = rollingHeartRateSamples(from: validHeartSamples, maximumCount: maximumSampleCount)
        let bpmValues = validHeartSamples.map(\.bpm)
        let daySpread = max(8, standardDeviation(bpmValues))
        let restingHeartRate = baseline.restingHeartRate?.mean ??
            today.restingHeartRate ??
            percentile(bpmValues, fraction: 0.20) ??
            62
        let walkingHeartRate = baseline.walkingHeartRateAverage?.mean ??
            today.walkingHeartRateAverage ??
            restingHeartRate + 24
        let restingSpread = max(7, baseline.restingHeartRate?.standardDeviation ?? daySpread * 0.45)
        let hrvDeviation = hrvStressDeviation(today: today, baseline: baseline)
        let dailyOffset = (PulsarStressScale.clampedScore(baseScore) - 50) * 0.12

        let rawSamples = sampled.map { sample in
            let context = context(at: sample.end, sleep: sleep, strain: strain)
            let score = contextualScore(
                heartRate: sample.bpm,
                context: context,
                dailyOffset: dailyOffset,
                hrvDeviation: hrvDeviation,
                restingHeartRate: restingHeartRate,
                walkingHeartRate: walkingHeartRate,
                restingSpread: restingSpread,
                daySpread: daySpread
            )
            return StressSample(
                timestamp: sample.end,
                score: score,
                confidence: summary.confidence,
                context: context
            )
        }

        return calibrate(rawSamples, toward: baseScore, range: DateInterval(start: interval.start, end: effectiveEnd))
    }

    private func contextualScore(
        heartRate: Double,
        context: StressContext,
        dailyOffset: Double,
        hrvDeviation: Double?,
        restingHeartRate: Double,
        walkingHeartRate: Double,
        restingSpread: Double,
        daySpread: Double
    ) -> Double {
        let expectation: Double
        let base: Double
        let spread: Double
        let multiplier: Double
        let hrvMultiplier: Double

        switch context {
        case .sleep:
            expectation = max(40, restingHeartRate - 6)
            base = 18 + dailyOffset * 0.35
            spread = max(7, restingSpread)
            multiplier = 8
            hrvMultiplier = 3.2
        case .rest:
            expectation = restingHeartRate + 4
            base = 28 + dailyOffset * 0.55
            spread = max(8, restingSpread * 1.15)
            multiplier = 9
            hrvMultiplier = 5.8
        case .cooldown:
            expectation = restingHeartRate + 16
            base = 24 + dailyOffset * 0.25
            spread = max(10, daySpread * 0.55)
            multiplier = 5
            hrvMultiplier = 2.2
        case .movementFiltered:
            expectation = walkingHeartRate
            base = 33 + dailyOffset * 0.30
            spread = max(13, daySpread * 0.78)
            multiplier = 5.5
            hrvMultiplier = 2.0
        case .active:
            expectation = walkingHeartRate
            base = 38 + dailyOffset * 0.35
            spread = max(15, daySpread * 0.85)
            multiplier = 5.0
            hrvMultiplier = 1.5
        case .workout:
            expectation = walkingHeartRate + 32
            base = 8
            spread = max(16, daySpread * 0.85)
            multiplier = 0
            hrvMultiplier = 0
        case .recovery:
            expectation = restingHeartRate + 12
            base = 26 + dailyOffset * 0.25
            spread = max(10, daySpread * 0.55)
            multiplier = 5
            hrvMultiplier = 2.4
        case .unknown:
            expectation = restingHeartRate + 14
            base = 36 + dailyOffset * 0.65
            spread = max(10, daySpread * 0.60)
            multiplier = 9
            hrvMultiplier = 4.0
        }

        let residual = ScoreMath.clamp((heartRate - expectation) / spread, -2.5, 2.5)
        var score = base + residual * multiplier
        if let hrvDeviation {
            score += ScoreMath.clamp(hrvDeviation, -1.5, 2.5) * hrvMultiplier
        }

        switch context {
        case .sleep:
            if residual < 1.0 { score = min(score, 45) }
            if residual < 1.8 { score = min(score, 58) }
        case .rest:
            if residual < 1.4 { score = min(score, 58) }
        case .cooldown, .recovery:
            score = min(score, 42)
        case .movementFiltered:
            score = min(score, 52)
        case .active:
            score = min(score, 58)
        case .workout:
            score = min(score, 12)
        case .unknown:
            break
        }

        return PulsarStressScale.clampedScore(score)
    }

    private func calibrate(_ samples: [StressSample], toward targetScore: Double, range: DateInterval) -> [StressSample] {
        guard let average = PulsarStressTimelineDistribution.weightedAverage(samples: timelineSamples(from: samples), range: range) else {
            return samples
        }
        let delta = ScoreMath.clamp(PulsarStressScale.clampedScore(targetScore) - average, -10, 10)
        guard abs(delta) >= 0.5 else { return samples }

        return samples.map { sample in
            var copy = sample
            let multiplier: Double
            switch sample.context {
            case .sleep:
                multiplier = delta > 0 ? 0.35 : 0.55
            case .rest:
                multiplier = 0.65
            case .cooldown, .recovery:
                multiplier = delta > 0 ? 0.20 : 0.75
            case .workout:
                multiplier = delta > 0 ? 0.0 : 0.55
            case .movementFiltered:
                multiplier = delta > 0 ? 0.35 : 0.70
            case .active:
                multiplier = delta > 0 ? 0.25 : 0.70
            case .unknown, nil:
                multiplier = 0.85
            }
            copy.score = PulsarStressScale.clampedScore(sample.score + delta * multiplier)
            return copy
        }
    }

    private func context(at date: Date, sleep: SleepSummary, strain: StrainSummary) -> StressContext {
        if sleep.intervals.contains(where: { $0.stage.isSleep && $0.startDate <= date && $0.endDate >= date }) {
            return .sleep
        }
        if strain.workoutBands.contains(where: { $0.startDate <= date && $0.endDate >= date }) {
            return .workout
        }
        if let latestWorkout = strain.workoutBands
            .filter({ $0.endDate <= date })
            .max(by: { $0.endDate < $1.endDate }),
           date.timeIntervalSince(latestWorkout.endDate) <= 12 * 60 {
            return .cooldown
        }
        if let interval = strain.timeline.last(where: { $0.startDate <= date && $0.endDate >= date }) {
            switch interval.intensity {
            case .rest:
                return .rest
            case .light:
                return .movementFiltered
            case .moderate, .hard, .peak:
                return .active
            }
        }
        return .unknown
    }

    private func hrvStressDeviation(today: StressDailySignals, baseline: StressBaseline) -> Double? {
        guard let current = today.heartRateVariabilitySDNN,
              current.isFinite,
              let hrvBaseline = baseline.hrvSDNN else { return nil }
        return ScoreMath.clamp((hrvBaseline.mean - current) / max(4, hrvBaseline.standardDeviation), -2, 3)
    }

    private func rollingHeartRateSamples(from samples: [HeartRateSample], maximumCount: Int) -> [HeartRateSample] {
        let anchors = downsample(samples, maximumCount: maximumCount)
        return anchors.map { anchor in
            let windowStart = anchor.end.addingTimeInterval(-10 * 60)
            let window = samples.filter { $0.end >= windowStart && $0.end <= anchor.end }
            let bpm = robustAverage(window.map(\.bpm)) ?? anchor.bpm
            return HeartRateSample(start: anchor.start, end: anchor.end, bpm: bpm, provenance: anchor.provenance)
        }
    }

    private func robustAverage(_ values: [Double]) -> Double? {
        let sorted = values.filter { $0.isFinite && $0 > 30 && $0 < 220 }.sorted()
        guard !sorted.isEmpty else { return nil }
        if sorted.count >= 5 {
            let trimmed = sorted.dropFirst().dropLast()
            return trimmed.reduce(0, +) / Double(trimmed.count)
        }
        if sorted.count >= 3 {
            return sorted[sorted.count / 2]
        }
        return sorted.reduce(0, +) / Double(sorted.count)
    }

    private func downsample(_ samples: [HeartRateSample], maximumCount: Int) -> [HeartRateSample] {
        guard samples.count > maximumCount, maximumCount > 1 else { return samples }
        let stride = max(1, samples.count / maximumCount)
        var reduced = samples.enumerated().compactMap { index, sample in
            index.isMultiple(of: stride) || index == samples.count - 1 ? sample : nil
        }
        if reduced.first?.end != samples.first?.end {
            reduced.insert(samples[0], at: 0)
        }
        var limited = Array(reduced.prefix(max(1, maximumCount - 1)))
        if limited.last?.end != samples.last?.end {
            limited.append(samples[samples.count - 1])
        }
        return limited
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        let values = values.filter(\.isFinite)
        guard values.count >= 2 else { return 8 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(max(1, values.count - 1))
        return sqrt(variance)
    }

    private func percentile(_ values: [Double], fraction: Double) -> Double? {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return nil }
        let index = Int((Double(sorted.count - 1) * ScoreMath.clamp(fraction)).rounded(.down))
        return sorted[min(sorted.count - 1, max(0, index))]
    }

    private func timelineSamples(from samples: [StressSample]) -> [PulsarStressTimelineSample] {
        samples.map { PulsarStressTimelineSample(timestamp: $0.timestamp, score: $0.score) }
    }
}

struct StressEngine {
    var baselineBuilder = StressBaselineBuilder()

    func score(today: StressDailySignals, baselineDays: [StressDailySignals]) -> StressSummary {
        let sourceBadges = SourceResolver.uniqueSourceBadges(today.sourceBadges + baselineDays.flatMap(\.sourceBadges))

        guard today.availableTodaySignalCount > 0 else {
            var missing = StressSummary.missing
            missing.date = today.date
            missing.sourceBadges = sourceBadges
            return missing
        }

        let baseline = baselineBuilder.build(from: baselineDays)
        guard baseline.isSufficient else {
            return StressSummary.buildingBaseline(
                date: today.date,
                baselineWindowDays: baseline.validDayCount,
                analyzedSampleCount: today.availableTodaySignalCount,
                sourceBadges: sourceBadges
            )
        }

        guard let metric = PulsarSharedMetricCalculator.makeStressMetric(
            today: sharedStressInput(from: today),
            baselineDays: sharedStressBaselineDays(from: baselineDays),
            sleep: nil,
            strain: nil,
            computedAt: today.computedAt ?? today.currentHeartRateTimestamp ?? today.heartRateVariabilityTimestamp ?? today.date
        ) else {
            var missing = StressSummary.missing
            missing.date = today.date
            missing.baselineWindowDays = baseline.validDayCount
            missing.analyzedSampleCount = today.availableTodaySignalCount
            missing.sourceBadges = sourceBadges
            return missing
        }

        let signalQualityLimited = today.currentMotionContext == .highArtifact ||
            (today.motionArtifactLevel ?? 0) > 0.65 ||
            (today.signalQuality ?? 1) < 0.45
        let confidence: ConfidenceGrade = signalQualityLimited ? .low : metric.confidence.appConfidence
        let score = metric.isPaused ? nil : metric.score
        let state = signalQualityLimited ? .lowConfidence : stressSummaryState(from: metric)
        var insights = metric.driverInsights.isEmpty ? ["Your heart and recovery signals are close to your normal baseline."] : metric.driverInsights
        if signalQualityLimited {
            insights.insert("Low confidence because motion or signal quality may be affecting heart-rate data.", at: 0)
        }
        return StressSummary(
            date: today.date,
            score: score,
            level: score.map(StressLevel.level(for:)),
            confidence: confidence,
            state: state,
            driverInsights: insights,
            drivers: stressDrivers(from: metric, insights: insights),
            signals: stressSignals(from: metric),
            dailySamples: [],
            analyzedSampleCount: today.availableTodaySignalCount,
            baselineWindowDays: baseline.validDayCount,
            availableSignalCount: metric.availableSignalCount,
            lastHeartRate: metric.recentHeartRate,
            lastHeartRateTimestamp: metric.heartRateTimestamp,
            lastHRV: metric.hrvSDNN,
            lastHRVTimestamp: metric.hrvTimestamp,
            nonActivityStress: metric.nonActivityStress.map(PulsarStressScale.roundedScore),
            activityAdjustedStress: metric.activityAdjustedStress.map(PulsarStressScale.roundedScore),
            movementStateText: metric.movementState.flatMap(PulsarSharedStressMovementState.init(rawValue:))?.displayText,
            stressStatusText: metric.sharedCalculationState.displayText,
            queryStart: nil,
            queryEnd: nil,
            lastUpdated: nil,
            sourceBadges: sourceBadges,
            explanation: explanation(metric: metric, state: state),
            subtext: StressSummary.estimateSubtext
        )
    }

    private func sharedStressInput(from today: StressDailySignals) -> PulsarSharedStressInput {
        PulsarSharedStressInput(
            date: today.date,
            hrvSDNN: today.heartRateVariabilitySDNN,
            hrvTimestamp: today.heartRateVariabilityTimestamp,
            restingHeartRate: today.restingHeartRate,
            respiratoryRate: today.sleepRespiratoryRate,
            recentHeartRate: today.currentHeartRate ?? today.recentHeartRate,
            heartRateTimestamp: today.currentHeartRateTimestamp,
            daytimeHeartRate: today.walkingHeartRateAverage,
            sleepDurationMinutes: today.sleepDurationHours.map { $0 * 60 },
            sleepPerformance: nil,
            strainScore: today.strainScore,
            recentWorkoutLoad: today.recentWorkoutLoad,
            isWorkoutActive: today.currentMotionContext == .workout,
            lastWorkoutEnd: today.lastWorkoutEnd,
            recentSteps: today.recentSteps,
            recentActiveEnergyKilocalories: today.recentActiveEnergyKilocalories,
            recentExerciseMinutes: today.recentExerciseMinutes,
            movementState: sharedMovementState(from: today.currentMotionContext),
            previousScore: today.previousStressScore,
            previousScoreTimestamp: today.previousStressTimestamp,
            sourceNames: today.sourceBadges.map(\.displayName)
        )
    }

    private func sharedStressBaselineDays(from days: [StressDailySignals]) -> [PulsarSharedBiometricsDay] {
        days.map {
            PulsarSharedBiometricsDay(
                date: $0.date,
                hrvSDNN: $0.heartRateVariabilitySDNN,
                restingHeartRate: $0.restingHeartRate,
                daytimeHeartRate: $0.walkingHeartRateAverage,
                respiratoryRate: $0.sleepRespiratoryRate,
                oxygenSaturation: nil,
                wristTemperatureDeviation: $0.wristTemperatureDelta,
                sleepPerformance: nil,
                strainScore: nil,
                recentWorkoutLoad: $0.recentWorkoutLoad,
                sourceNames: $0.sourceBadges.map(\.displayName)
            )
        }
    }

    private func sharedMovementState(from context: StressMotionContext) -> PulsarSharedStressMovementState {
        switch context {
        case .resting:
            return .inactive
        case .light:
            return .lightMovement
        case .active:
            return .activeMovement
        case .workout:
            return .workout
        case .postWorkout:
            return .cooldown
        case .highArtifact, .unknown:
            return .unknown
        }
    }

    private func stressSummaryState(from metric: PulsarStressSyncMetric) -> StressSummaryState {
        switch metric.sharedCalculationState {
        case .workoutPaused:
            return .workoutPaused
        case .cooldownPaused:
            return .cooldown
        case .lowConfidence:
            return .lowConfidence
        case .measuring:
            return metric.confidence == .low ? .lowConfidence : .ready
        }
    }

    private func stressDrivers(from metric: PulsarStressSyncMetric, insights: [String]) -> [StressDriver] {
        if metric.isPaused {
            return [
                StressDriver(
                    id: "stress-paused",
                    title: metric.sharedCalculationState.displayText,
                    detail: insights.first ?? "Stress is paused while activity-related heart-rate elevation settles.",
                    severity: .neutral,
                    relatedMetric: "Activity"
                )
            ]
        }
        return insights.prefix(3).enumerated().map { index, insight in
            StressDriver(
                id: "stress-driver-\(index)",
                title: insight,
                detail: "Based on available heart, breathing, sleep, and load signals relative to your personal baseline, with movement filtered out.",
                severity: (metric.score >= 75 ? .high : (metric.score >= 50 ? .elevated : .neutral)),
                relatedMetric: nil
            )
        }
    }

    private func stressSignals(from metric: PulsarStressSyncMetric) -> [StressSignal] {
        [
            StressSignal(
                id: "heart-rate",
                title: "Last HR",
                value: metric.recentHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "Not available",
                baseline: metric.daytimeHeartRateBaseline.map { "Daytime baseline \(Int($0.rounded())) bpm" },
                availability: metric.recentHeartRate == nil ? .unavailable : .available
            ),
            StressSignal(
                id: "hrv",
                title: "Last HRV",
                value: metric.hrvSDNN.map { "\(Int($0.rounded())) ms" } ?? "Not available",
                baseline: metric.hrvBaseline.map { "Baseline \(Int($0.rounded())) ms" },
                availability: metric.hrvSDNN == nil ? .unavailable : .available
            ),
            StressSignal(
                id: "resting-heart-rate",
                title: "Resting HR",
                value: metric.restingHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "Not available",
                baseline: metric.restingHeartRateBaseline.map { "Baseline \(Int($0.rounded())) bpm" },
                availability: metric.restingHeartRate == nil ? .unavailable : .available
            ),
            StressSignal(
                id: "respiratory-rate",
                title: "Respiratory rate",
                value: metric.respiratoryRate.map { $0.formatted(.number.precision(.fractionLength(1))) + " breaths/min" } ?? "Not available",
                baseline: "Compared with your rolling baseline",
                availability: metric.respiratoryRate == nil ? .unavailable : .available
            ),
            StressSignal(
                id: "sleep-duration",
                title: "Sleep duration",
                value: metric.sleepDurationMinutes.map { Int($0.rounded()).formatted() + " min" } ?? "Not available",
                baseline: "Supports the daily estimate",
                availability: metric.sleepDurationMinutes == nil ? .unavailable : .available
            ),
            StressSignal(
                id: "non-activity-stress",
                title: "Non-activity stress",
                value: metric.nonActivityStress.map { "\(PulsarStressScale.roundedScore($0))" } ?? "Paused",
                baseline: "Inactive-only estimate",
                availability: metric.nonActivityStress == nil ? .limited : .available
            ),
            StressSignal(
                id: "activity-adjusted-stress",
                title: "Activity-adjusted stress",
                value: metric.activityAdjustedStress.map { "\(PulsarStressScale.roundedScore($0))" } ?? "Paused",
                baseline: metric.movementState.flatMap(PulsarSharedStressMovementState.init(rawValue:))?.displayText,
                availability: metric.activityAdjustedStress == nil ? .limited : .available
            ),
            StressSignal(
                id: "movement-state",
                title: "Movement state",
                value: metric.movementState.flatMap(PulsarSharedStressMovementState.init(rawValue:))?.displayText ?? "Unknown",
                baseline: metric.appliedAdjustments.isEmpty ? nil : metric.appliedAdjustments.joined(separator: ", "),
                availability: .available
            )
        ]
    }

    private func explanation(metric: PulsarStressSyncMetric, state: StressSummaryState) -> String {
        if state == .workoutPaused {
            return "Stress pauses during workouts to separate exercise from daily load."
        }
        if state == .cooldown {
            return "Stress resumes after your heart rate settles."
        }
        if state == .lowConfidence || metric.confidence == .low {
            return "Recent wearable data is limited, so this score is an estimate."
        }
        return metric.driverInsights.first ?? "Your heart and recovery signals are close to your normal baseline."
    }
}
