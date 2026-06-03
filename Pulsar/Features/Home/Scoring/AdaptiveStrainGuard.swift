//
//  AdaptiveStrainGuard.swift
//  Pulsar
//

import Foundation

enum AdaptiveRecoveryPriority: String, Codable, Equatable, CaseIterable {
    case primed
    case balanced
    case recovery
    case protective

    var label: String {
        switch self {
        case .primed: "Primed"
        case .balanced: "Balanced"
        case .recovery: "Recovery priority"
        case .protective: "Protective"
        }
    }
}

enum AdaptiveTrainingZone: String, Codable, Equatable {
    case recoveryMovement
    case lowIntensity
    case aerobicBase
    case strengthMaintenance
    case performance

    var label: String {
        switch self {
        case .recoveryMovement: "Recovery movement"
        case .lowIntensity: "Low intensity"
        case .aerobicBase: "Aerobic base"
        case .strengthMaintenance: "Light strength"
        case .performance: "Performance"
        }
    }
}

enum AdaptiveStrainSignalSeverity: String, Codable, Equatable {
    case supportive
    case neutral
    case elevated
    case protective
}

struct AdaptiveStrainSignal: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var detail: String
    var severity: AdaptiveStrainSignalSeverity
}

struct AdaptiveWorkoutRecommendation: Identifiable, Codable, Equatable {
    var id: String { title }
    var title: String
    var detail: String
    var systemImage: String
}

struct RecoveryDebtSnapshot: Codable, Equatable {
    var score: Int
    var sleepDebtDays: Int
    var highStrainDays: Int
    var lowHRVDays: Int
    var elevatedRHRDays: Int
    var highStressDays: Int

    var label: String {
        switch score {
        case 75...100: "High recovery debt"
        case 50..<75: "Meaningful recovery debt"
        case 25..<50: "Light recovery debt"
        default: "Low recovery debt"
        }
    }
}

struct AdaptiveStrainPlan: Codable, Equatable {
    var date: Date
    var recommendedRange: PulsarSharedStrainTargetRange
    var optimalTrainingZone: AdaptiveTrainingZone
    var safeUpperLimit: Int
    var recoveryPriority: AdaptiveRecoveryPriority
    var recoveryDebt: RecoveryDebtSnapshot
    var fatigueScore: Int
    var acuteChronicLoadRatio: Double?
    var trainingConsistency: Double
    var headline: String
    var rationale: String
    var recommendations: [AdaptiveWorkoutRecommendation]
    var signals: [AdaptiveStrainSignal]
    var confidence: ConfidenceGrade
    var startingStrainScore: Int
    var restingHeartRate: Double?
    var maxHeartRate: Double?
    var generatedAt: Date

    var safeUpperLimitText: String { "\(safeUpperLimit)" }

    func isApproachingCeiling(currentStrain: Int) -> Bool {
        currentStrain >= max(recommendedRange.upperBound, safeUpperLimit - 6)
    }
}

struct AdaptiveStrainGuardInput {
    var profile: UserProfile
    var sleep: SleepSummary
    var recovery: RecoverySummary
    var strain: StrainSummary
    var stress: StressSummary
    var recentRecords: [DailyStrainRecord]
    var date: Date
    var calendar: Calendar
    var generatedAt: Date
}

struct AdaptiveStrainGuard {
    func makePlan(input: AdaptiveStrainGuardInput) -> AdaptiveStrainPlan? {
        let hasUsefulData = input.recovery.score > 0 ||
            input.sleep.score > 0 ||
            input.strain.score > 0 ||
            input.stress.score != nil ||
            !input.recentRecords.isEmpty
        guard hasUsefulData else { return nil }

        let recoveryScore = resolvedRecoveryScore(input)
        let debt = RecoveryDebtCalculator().calculate(input: input)
        let acuteChronicRatio = acuteChronicLoadRatio(strain: input.strain, recentRecords: input.recentRecords)
        let consistency = trainingConsistency(input.recentRecords)
        let fatigue = FatigueScoringEngine().score(
            recoveryScore: recoveryScore,
            recoveryDebt: debt.score,
            stressScore: input.stress.score,
            sleepScore: input.sleep.score > 0 ? input.sleep.score : nil,
            acuteChronicLoadRatio: acuteChronicRatio,
            recentStrainScores: input.recentRecords.map(\.strainScore)
        )
        let baseRange = baseRange(forRecoveryScore: recoveryScore)
        let range = adjustedRange(
            baseRange: baseRange,
            recoveryScore: recoveryScore,
            fatigueScore: fatigue,
            debtScore: debt.score,
            acuteChronicLoadRatio: acuteChronicRatio,
            recentStrainScores: input.recentRecords.map(\.strainScore)
        )
        let priority = recoveryPriority(
            recoveryScore: recoveryScore,
            debtScore: debt.score,
            fatigueScore: fatigue,
            stressScore: input.stress.score
        )
        let zone = optimalZone(priority: priority, recoveryScore: recoveryScore, recentRecords: input.recentRecords)
        let safeUpperLimit = safeUpperLimit(
            range: range,
            priority: priority,
            debtScore: debt.score,
            fatigueScore: fatigue
        )
        let signals = signals(input: input, debt: debt, fatigueScore: fatigue, acuteChronicLoadRatio: acuteChronicRatio)
        let headline = headline(priority: priority, signals: signals, recentRecords: input.recentRecords)
        let rationale = rationale(priority: priority, signals: signals, recoveryScore: recoveryScore)
        let maxHeartRate = input.profile.resolvedMaxHeartRate(on: input.generatedAt, calendar: input.calendar)?.value

        let plan = AdaptiveStrainPlan(
            date: input.date,
            recommendedRange: range,
            optimalTrainingZone: zone,
            safeUpperLimit: safeUpperLimit,
            recoveryPriority: priority,
            recoveryDebt: debt,
            fatigueScore: fatigue,
            acuteChronicLoadRatio: acuteChronicRatio,
            trainingConsistency: consistency,
            headline: headline,
            rationale: rationale,
            recommendations: recommendations(priority: priority, zone: zone),
            signals: signals,
            confidence: confidence(input: input, debt: debt),
            startingStrainScore: max(0, input.strain.score),
            restingHeartRate: input.recovery.restingHeartRate ?? input.strain.restingHeartRate,
            maxHeartRate: maxHeartRate,
            generatedAt: input.generatedAt
        )

        PulsarSyncDebugLogger.log("[PulsarAdaptiveStrainGuard] plan generated recovery=\(recoveryScore.map(String.init) ?? "nil") debt=\(debt.score) fatigue=\(fatigue) target=\(range.displayText) ceiling=\(safeUpperLimit) priority=\(priority.rawValue) zone=\(zone.rawValue) acl=\(acuteChronicRatio.map { String(format: "%.2f", $0) } ?? "nil")")
        return plan
    }

    private func resolvedRecoveryScore(_ input: AdaptiveStrainGuardInput) -> Int? {
        if input.recovery.score > 0 { return input.recovery.score }
        return input.recentRecords.last(where: { $0.recoveryScore != nil })?.recoveryScore
    }

    private func baseRange(forRecoveryScore recoveryScore: Int?) -> PulsarSharedStrainTargetRange {
        guard let recoveryScore else {
            return PulsarSharedStrainTargetRange(lowerBound: 28, upperBound: 44)
        }
        switch recoveryScore {
        case 85...100:
            return PulsarSharedStrainTargetRange(lowerBound: 64, upperBound: 82)
        case 70..<85:
            return PulsarSharedStrainTargetRange(lowerBound: 52, upperBound: 68)
        case 55..<70:
            return PulsarSharedStrainTargetRange(lowerBound: 38, upperBound: 54)
        case 40..<55:
            return PulsarSharedStrainTargetRange(lowerBound: 24, upperBound: 40)
        default:
            return PulsarSharedStrainTargetRange(lowerBound: 8, upperBound: 24)
        }
    }

    private func adjustedRange(
        baseRange: PulsarSharedStrainTargetRange,
        recoveryScore: Int?,
        fatigueScore: Int,
        debtScore: Int,
        acuteChronicLoadRatio: Double?,
        recentStrainScores: [Int]
    ) -> PulsarSharedStrainTargetRange {
        let consecutiveHigh = consecutiveHighStrainDays(recentStrainScores)
        let ratioPenalty: Int
        if let acuteChronicLoadRatio {
            ratioPenalty = acuteChronicLoadRatio >= 1.45 ? 12 : (acuteChronicLoadRatio >= 1.25 ? 7 : 0)
        } else {
            ratioPenalty = 0
        }
        var penalty = Int((Double(fatigueScore) * 0.18 + Double(debtScore) * 0.22).rounded()) + ratioPenalty
        if consecutiveHigh >= 3 { penalty += 12 }
        if (recoveryScore ?? 55) >= 85, debtScore < 22, fatigueScore < 30 {
            penalty -= 6
        }

        let lower = max(5, min(88, baseRange.lowerBound - max(0, penalty - 8)))
        let upper = max(lower + 7, min(94, baseRange.upperBound - max(0, penalty)))
        return PulsarSharedStrainTargetRange(lowerBound: lower, upperBound: upper)
    }

    private func safeUpperLimit(
        range: PulsarSharedStrainTargetRange,
        priority: AdaptiveRecoveryPriority,
        debtScore: Int,
        fatigueScore: Int
    ) -> Int {
        let buffer: Int
        switch priority {
        case .protective: buffer = 3
        case .recovery: buffer = 5
        case .balanced: buffer = 8
        case .primed: buffer = 12
        }
        let debtCompression = Int((Double(max(debtScore, fatigueScore)) * 0.04).rounded())
        return max(range.upperBound, min(96, range.upperBound + max(0, buffer - debtCompression)))
    }

    private func recoveryPriority(
        recoveryScore: Int?,
        debtScore: Int,
        fatigueScore: Int,
        stressScore: Int?
    ) -> AdaptiveRecoveryPriority {
        if debtScore >= 74 || fatigueScore >= 76 || (recoveryScore ?? 100) < 42 || (stressScore ?? 0) >= 86 {
            return .protective
        }
        if debtScore >= 50 || fatigueScore >= 56 || (recoveryScore ?? 100) < 58 || (stressScore ?? 0) >= 72 {
            return .recovery
        }
        if (recoveryScore ?? 0) >= 82, debtScore < 28, fatigueScore < 36 {
            return .primed
        }
        return .balanced
    }

    private func optimalZone(priority: AdaptiveRecoveryPriority, recoveryScore: Int?, recentRecords: [DailyStrainRecord]) -> AdaptiveTrainingZone {
        switch priority {
        case .protective:
            return .recoveryMovement
        case .recovery:
            return .lowIntensity
        case .primed:
            return .performance
        case .balanced:
            let recentHighStrength = recentRecords.suffix(4).contains { $0.workoutMinutes >= 35 && $0.strainScore < 58 }
            if recentHighStrength && (recoveryScore ?? 70) < 78 { return .strengthMaintenance }
            return .aerobicBase
        }
    }

    private func signals(
        input: AdaptiveStrainGuardInput,
        debt: RecoveryDebtSnapshot,
        fatigueScore: Int,
        acuteChronicLoadRatio: Double?
    ) -> [AdaptiveStrainSignal] {
        var values: [AdaptiveStrainSignal] = []
        if let hrv = input.recovery.hrvSDNN, let baseline = input.recovery.hrvBaseline, baseline > 0 {
            let delta = (hrv - baseline) / baseline
            if delta <= -0.08 {
                values.append(.init(id: "hrv", title: "HRV below baseline", detail: "Your nervous system signal is suppressed compared with your recent baseline.", severity: .protective))
            } else if delta >= 0.08 {
                values.append(.init(id: "hrv", title: "HRV supportive", detail: "HRV is above your recent baseline.", severity: .supportive))
            }
        }
        if let rhr = input.recovery.restingHeartRate, let baseline = input.recovery.restingHeartRateBaseline {
            let delta = rhr - baseline
            if delta >= 4 {
                values.append(.init(id: "rhr", title: "Resting HR elevated", detail: "Resting heart rate is running above baseline, which can reflect unresolved stress.", severity: .elevated))
            } else if delta <= -2 {
                values.append(.init(id: "rhr", title: "Resting HR settled", detail: "Resting heart rate is below your recent baseline.", severity: .supportive))
            }
        }
        if input.sleep.score > 0, input.sleep.score < 68 {
            values.append(.init(id: "sleep", title: "Sleep limited recovery", detail: "Sleep duration or quality is reducing today's training tolerance.", severity: .elevated))
        }
        if let score = input.stress.score, score >= 70 {
            values.append(.init(id: "stress", title: "Stress load elevated", detail: "Recent stress is adding to today's recovery load.", severity: score >= 85 ? .protective : .elevated))
        }
        if let acuteChronicLoadRatio, acuteChronicLoadRatio >= 1.25 {
            values.append(.init(id: "acuteLoad", title: "Recent load is stacked", detail: "The last week is outpacing your longer-term load.", severity: acuteChronicLoadRatio >= 1.45 ? .protective : .elevated))
        }
        if debt.highStrainDays >= 3 {
            values.append(.init(id: "strainStack", title: "Consecutive high strain", detail: "Multiple high-load days in a row call for a lower ceiling even if recovery looks acceptable.", severity: .protective))
        }
        if fatigueScore >= 60 {
            values.append(.init(id: "fatigue", title: "Fatigue accumulation", detail: "Pulsar is lowering the target to protect long-term adaptation.", severity: .elevated))
        }
        if values.isEmpty {
            values.append(.init(id: "baseline", title: "Signals are stable", detail: "Recovery, strain, and stress signals are not showing meaningful overload.", severity: .supportive))
        }
        return values
    }

    private func headline(priority: AdaptiveRecoveryPriority, signals: [AdaptiveStrainSignal], recentRecords: [DailyStrainRecord]) -> String {
        if consecutiveHighStrainDays(recentRecords.map(\.strainScore)) >= 3 {
            return "Your recent load is stacked. Keep today intentionally lighter."
        }
        switch priority {
        case .protective:
            return "Today is better suited for low-intensity movement."
        case .recovery:
            return "Your nervous system is still recovering."
        case .balanced:
            return "Build strain gradually and stay below the upper range."
        case .primed:
            return "You are highly recovered and primed for performance."
        }
    }

    private func rationale(priority: AdaptiveRecoveryPriority, signals: [AdaptiveStrainSignal], recoveryScore: Int?) -> String {
        if let first = signals.first(where: { $0.severity == .protective || $0.severity == .elevated }) {
            return first.detail
        }
        if priority == .primed {
            return "Your recovery signals support a higher training ceiling today."
        }
        if let recoveryScore {
            return "Today's target is adjusted from recovery \(recoveryScore), recent load, stress, and sleep quality."
        }
        return "Today's target is conservative until Pulsar has enough readiness data."
    }

    private func recommendations(priority: AdaptiveRecoveryPriority, zone: AdaptiveTrainingZone) -> [AdaptiveWorkoutRecommendation] {
        switch priority {
        case .protective:
            return [
                .init(title: "Recovery walk", detail: "Keep it conversational and stop if HR climbs unusually fast.", systemImage: "figure.walk"),
                .init(title: "Mobility or stretching", detail: "Favor tissue quality and easy range of motion.", systemImage: "figure.cooldown"),
                .init(title: "Breathwork", detail: "Downshift stress without adding cardiovascular load.", systemImage: "wind")
            ]
        case .recovery:
            return [
                .init(title: "Zone 2 cardio", detail: "Stay smooth and below hard effort.", systemImage: "heart.circle"),
                .init(title: "Light strength", detail: "Reduce volume and extend rests.", systemImage: "dumbbell"),
                .init(title: "Mobility", detail: "A short recovery block fits today's physiology.", systemImage: "figure.flexibility")
            ]
        case .balanced:
            return [
                .init(title: zone == .strengthMaintenance ? "Lighter strength" : "Aerobic base", detail: "Build steady strain without chasing a peak.", systemImage: zone == .strengthMaintenance ? "dumbbell" : "figure.run"),
                .init(title: "Recovery walk", detail: "Useful if you approach the upper range early.", systemImage: "figure.walk")
            ]
        case .primed:
            return [
                .init(title: "Performance session", detail: "You have room for higher intensity if the workout feels normal.", systemImage: "bolt.heart"),
                .init(title: "Quality strength", detail: "Good day for progressive sets while maintaining form.", systemImage: "dumbbell")
            ]
        }
    }

    private func confidence(input: AdaptiveStrainGuardInput, debt: RecoveryDebtSnapshot) -> ConfidenceGrade {
        var count = 0
        if input.recovery.score > 0 { count += 1 }
        if input.sleep.score > 0 { count += 1 }
        if input.strain.score > 0 || input.strain.lastUpdated != nil { count += 1 }
        if input.stress.score != nil { count += 1 }
        if input.recentRecords.count >= 7 { count += 1 }
        if count >= 4, input.recovery.confidence == .high || input.recovery.confidence == .moderate { return .high }
        if count >= 3 { return .moderate }
        if count > 0 { return .low }
        return .missing
    }

    private func acuteChronicLoadRatio(strain: StrainSummary, recentRecords: [DailyStrainRecord]) -> Double? {
        if strain.sevenVsTwentyEightRatio.isFinite, strain.sevenVsTwentyEightRatio > 0 {
            return strain.sevenVsTwentyEightRatio
        }
        let recent = recentRecords.suffix(7).map(\.strainScore).filter { $0 > 0 }
        guard recent.count >= 4 else { return nil }
        let acute = Double(recent.reduce(0, +)) / Double(recent.count)
        let chronicSource = recentRecords.suffix(28).map(\.strainScore).filter { $0 > 0 }
        guard chronicSource.count >= 10 else { return nil }
        let chronic = Double(chronicSource.reduce(0, +)) / Double(chronicSource.count)
        guard chronic > 0 else { return nil }
        return acute / chronic
    }

    private func trainingConsistency(_ records: [DailyStrainRecord]) -> Double {
        let recent = records.suffix(7)
        guard !recent.isEmpty else { return 0 }
        let activeDays = recent.filter { $0.strainScore >= 20 || $0.workoutMinutes >= 10 || $0.steps >= 4_000 }.count
        return Double(activeDays) / Double(recent.count)
    }

    private func consecutiveHighStrainDays(_ scores: [Int]) -> Int {
        var count = 0
        for score in scores.reversed() {
            guard score >= 72 else { break }
            count += 1
        }
        return count
    }
}

struct RecoveryDebtCalculator {
    func calculate(input: AdaptiveStrainGuardInput) -> RecoveryDebtSnapshot {
        let recent = Array(input.recentRecords.suffix(7))
        let sleepDebtDays = consecutiveDays(recent.map { record in
            (record.sleepScore ?? 100) < 66 || (record.sleepMinutes ?? 480) < Int(input.profile.sleepSchedule.targetSleepHours * 60 - 45)
        })
        let highStrainDays = consecutiveDays(recent.map { $0.strainScore >= 72 })
        let lowHRVDays = recent.filter { $0.hrvStatus == .lower }.count
        let elevatedRHRDays = recent.filter { $0.restingHeartRateStatus == .higher }.count
        let highStressDays = recent.filter { ($0.stressScore ?? 0) >= 70 }.count

        var score = 0
        if input.sleep.score > 0 {
            if input.sleep.score < 45 { score += 26 }
            else if input.sleep.score < 66 { score += 16 }
        }
        let targetSleepMinutes = input.profile.sleepSchedule.targetSleepHours * 60
        if input.sleep.totalSleepMinutes > 0, targetSleepMinutes - input.sleep.totalSleepMinutes >= 75 {
            score += 10
        }
        score += min(24, sleepDebtDays * 8)
        score += min(30, highStrainDays * 10)
        score += min(18, lowHRVDays * 5)
        score += min(18, elevatedRHRDays * 5)
        score += min(18, highStressDays * 5)

        if input.recovery.hrvReadiness > 0, input.recovery.hrvReadiness < 0.42 { score += 14 }
        if input.recovery.restingHeartRateReadiness > 0, input.recovery.restingHeartRateReadiness < 0.42 { score += 12 }
        if let stress = input.stress.score {
            if stress >= 85 { score += 18 }
            else if stress >= 70 { score += 10 }
        }
        if input.recovery.score > 0, input.recovery.score < 45 { score += 16 }

        return RecoveryDebtSnapshot(
            score: min(100, max(0, score)),
            sleepDebtDays: sleepDebtDays,
            highStrainDays: highStrainDays,
            lowHRVDays: lowHRVDays,
            elevatedRHRDays: elevatedRHRDays,
            highStressDays: highStressDays
        )
    }

    private func consecutiveDays(_ flags: [Bool]) -> Int {
        var count = 0
        for value in flags.reversed() {
            guard value else { break }
            count += 1
        }
        return count
    }
}

struct FatigueScoringEngine {
    func score(
        recoveryScore: Int?,
        recoveryDebt: Int,
        stressScore: Int?,
        sleepScore: Int?,
        acuteChronicLoadRatio: Double?,
        recentStrainScores: [Int]
    ) -> Int {
        let recoveryFatigue = recoveryScore.map { max(0, 100 - $0) } ?? 42
        let stressFatigue = stressScore ?? 45
        let sleepFatigue = sleepScore.map { max(0, 100 - $0) } ?? 35
        let ratioFatigue: Int
        if let acuteChronicLoadRatio {
            ratioFatigue = Int(min(100, max(0, (acuteChronicLoadRatio - 0.85) * 90)).rounded())
        } else {
            ratioFatigue = 35
        }
        let recent = recentStrainScores.suffix(7).filter { $0 > 0 }
        let accumulated = recent.isEmpty ? 35 : Int((Double(recent.reduce(0, +)) / Double(recent.count)).rounded())
        let consecutiveHigh = consecutiveHighStrainDays(recentStrainScores)
        let stackedFatigue = min(100, accumulated + consecutiveHigh * 8)

        let weighted = Double(recoveryFatigue) * 0.24 +
            Double(recoveryDebt) * 0.31 +
            Double(stressFatigue) * 0.16 +
            Double(sleepFatigue) * 0.13 +
            Double(ratioFatigue) * 0.10 +
            Double(stackedFatigue) * 0.06
        return min(100, max(0, Int(weighted.rounded())))
    }

    private func consecutiveHighStrainDays(_ scores: [Int]) -> Int {
        var count = 0
        for score in scores.reversed() {
            guard score >= 72 else { break }
            count += 1
        }
        return count
    }
}

struct AdaptiveHeartRateSample: Equatable {
    var timestamp: Date
    var bpm: Double
}

enum AdaptiveWorkoutCoachingSeverity: String, Codable, Equatable {
    case informational
    case caution
    case protective
}

struct AdaptiveWorkoutCoaching: Identifiable, Codable, Equatable {
    var id: String { "\(severity.rawValue)-\(message)" }
    var title: String
    var message: String
    var severity: AdaptiveWorkoutCoachingSeverity
    var triggeredAt: Date
}

struct RealTimeWorkoutAdaptationInput {
    var plan: AdaptiveStrainPlan
    var workoutKind: PulsarOutdoorWorkoutKind
    var elapsedTime: TimeInterval
    var currentHeartRate: Double?
    var averageHeartRate: Double?
    var maxObservedHeartRate: Double?
    var recentHeartRates: [AdaptiveHeartRateSample]
    var sampledAt: Date
}

struct RealTimeWorkoutAdaptationEngine {
    func evaluate(_ input: RealTimeWorkoutAdaptationInput) -> AdaptiveWorkoutCoaching? {
        guard let currentHeartRate = input.currentHeartRate, currentHeartRate > 0 else { return nil }
        guard input.elapsedTime >= 180 else { return nil }

        let resting = input.plan.restingHeartRate ?? 60
        let maxHeartRate = input.plan.maxHeartRate ?? max(180, resting + 105)
        let reserve = max(60, maxHeartRate - resting)
        let reservePercent = (currentHeartRate - resting) / reserve
        let estimatedStrain = estimatedCurrentStrain(input: input, reservePercent: reservePercent)
        let priority = input.plan.recoveryPriority
        let isStrengthLike = input.workoutKind == .strength || input.workoutKind == .core
        let isHighIntensityKind = input.workoutKind == .hiit || input.workoutKind == .boxing
        let riseRate = heartRateRisePerMinute(input.recentHeartRates)

        if estimatedStrain >= input.plan.safeUpperLimit - 2 {
            return AdaptiveWorkoutCoaching(
                title: "Adaptive Strain Guard",
                message: "You are approaching today's optimal recovery threshold.",
                severity: .protective,
                triggeredAt: input.sampledAt
            )
        }

        if (priority == .protective || priority == .recovery), let riseRate, riseRate >= 6.0, input.elapsedTime <= 720 {
            return AdaptiveWorkoutCoaching(
                title: "Adaptive Strain Guard",
                message: "Your heart rate is rising faster than usual for today's readiness. Ease the pace and reassess.",
                severity: priority == .protective ? .protective : .caution,
                triggeredAt: input.sampledAt
            )
        }

        if priority == .protective, reservePercent >= (isStrengthLike ? 0.82 : 0.74), input.elapsedTime >= 420 {
            return AdaptiveWorkoutCoaching(
                title: "Adaptive Strain Guard",
                message: isStrengthLike
                    ? "Your cardiovascular response is elevated today. Take longer rests or end early."
                    : "Your cardiovascular response is elevated today. Consider ending this workout early to improve long-term recovery.",
                severity: .protective,
                triggeredAt: input.sampledAt
            )
        }

        if priority == .recovery, reservePercent >= (isHighIntensityKind ? 0.76 : 0.80), input.elapsedTime >= 600 {
            return AdaptiveWorkoutCoaching(
                title: "Adaptive Strain Guard",
                message: isHighIntensityKind
                    ? "Today is not ideal for hard intervals. Keep this session controlled."
                    : "You are above the best training zone for today's recovery. Settle into an easier effort.",
                severity: .caution,
                triggeredAt: input.sampledAt
            )
        }

        if input.workoutKind == .walking, priority != .primed, reservePercent >= 0.70 {
            return AdaptiveWorkoutCoaching(
                title: "Adaptive Strain Guard",
                message: "Keep this walk easy today; your heart rate is reading more like training load.",
                severity: .caution,
                triggeredAt: input.sampledAt
            )
        }

        return nil
    }

    private func estimatedCurrentStrain(input: RealTimeWorkoutAdaptationInput, reservePercent: Double) -> Int {
        let elapsedMinutes = max(0, input.elapsedTime / 60)
        let density: Double
        switch reservePercent {
        case ..<0.52: density = 0.08
        case ..<0.66: density = 0.16
        case ..<0.78: density = 0.27
        case ..<0.88: density = 0.40
        default: density = 0.54
        }
        return min(100, input.plan.startingStrainScore + Int((elapsedMinutes * density).rounded()))
    }

    private func heartRateRisePerMinute(_ samples: [AdaptiveHeartRateSample]) -> Double? {
        let valid = samples
            .filter { $0.bpm > 0 }
            .sorted { $0.timestamp < $1.timestamp }
        guard let first = valid.first, let last = valid.last, last.timestamp.timeIntervalSince(first.timestamp) >= 120 else {
            return nil
        }
        let minutes = last.timestamp.timeIntervalSince(first.timestamp) / 60
        guard minutes > 0 else { return nil }
        return max(0, (last.bpm - first.bpm) / minutes)
    }
}
