//
//  SleepScoringEngine.swift
//  Pulsar
//

import Foundation

struct SleepScoringEngine {
    var calendar: Calendar = .current

    func score(night: NightlySleepInput, recentNights: [NightlySleepInput], schedule: SleepSchedule) -> SleepSummary {
        let analyzer = SleepAnalyzer()
        let analysis = analyzer.analyze(samples: night.analysisSamples, wakeUpDate: night.nightEnd, calendar: calendar)
        guard analysis.hasSamples else { return .missing }
        let recentAnalyses = recentNights.map {
            analyzer.analyze(samples: $0.analysisSamples, wakeUpDate: $0.nightEnd, calendar: calendar)
        }
        guard let sharedMetric = PulsarSharedSleepCalculator.makeSleepMetric(
            analysis: analysis,
            recentAnalyses: recentAnalyses,
            targetSleepHours: schedule.targetSleepHours,
            computedAt: Date(),
            calendar: calendar
        ) else { return .missing }

        let timeInBed = analysis.timeInBedMinutes
        let sleepMinutes = analysis.totalSleepMinutes
        let awakeMinutes = analysis.awakeMinutes
        let wasoMinutes = analysis.wasoMinutes
        let efficiency = sharedMetric.sleepEfficiency
        let durationAdequacy = sharedMetric.durationAdequacy
        let regularity = sharedMetric.regularity
        let continuity = sharedMetric.continuity
        let performance = sharedMetric.sleepPerformance
        let breakdown = stageBreakdown(analysis, totalSleepMinutes: sleepMinutes)
        let confidence = confidenceGrade(for: analysis, sleepMinutes: sleepMinutes)
        let notes = notes(for: analysis, timeInBed: timeInBed, sleepMinutes: sleepMinutes, regularity: regularity)

        return SleepSummary(
            wakeUpDate: analysis.wakeUpDate,
            score: sharedMetric.score,
            confidence: confidence.grade,
            confidenceExplanation: confidence.explanation,
            timeInBedMinutes: timeInBed,
            totalSleepMinutes: sleepMinutes,
            sleepEfficiency: efficiency,
            awakeMinutes: awakeMinutes,
            wasoMinutes: wasoMinutes,
            sleepConsistency: regularity,
            sleepPerformance: performance,
            durationAdequacy: durationAdequacy,
            regularity: regularity,
            continuity: continuity,
            stageBreakdown: breakdown,
            intervals: sleepStageIntervals(from: analysis.mergedIntervals),
            sleepStart: sharedMetric.sleepStart,
            wakeTime: sharedMetric.sleepEnd,
            awakenings: analysis.awakenings,
            analyzedSampleCount: analysis.usedSampleCount,
            queryStart: analysis.queryStart,
            queryEnd: analysis.queryEnd,
            lastUpdated: nil,
            sourceBadges: sourceBadges(from: night.segments, sourceNames: analysis.sourceNames),
            notes: notes
        )
    }

    private func stageBreakdown(_ analysis: SleepAnalysisSummary, totalSleepMinutes: Double) -> [StageMetric] {
        SleepStage.allCases
            .filter(\.contributesToStageBreakdown)
            .compactMap { stage in
                let minutes = analysis.mergedIntervals.filter { $0.stage.homeStage == stage }.reduce(0) { $0 + $1.durationMinutes }
                guard minutes > 0 else { return nil }
                let denominator = stage == .awake ? max(1, totalSleepMinutes + minutes) : max(1, totalSleepMinutes)
                return StageMetric(stage: stage, minutes: minutes, percentOfSleep: minutes / denominator)
            }
    }

    private func hasStagedSleep(_ analysis: SleepAnalysisSummary) -> Bool {
        analysis.coreMinutes > 0 || analysis.deepMinutes > 0 || analysis.remMinutes > 0
    }

    func sleepConsistency(for nights: [NightlySleepInput]) -> Double {
        let validNights = nights
            .filter { !$0.segments.filter { $0.stage.isSleep }.isEmpty }
            .sorted { $0.nightStart < $1.nightStart }
        guard validNights.count >= 3 else { return interimRegularity(for: validNights) }
        guard validNights.count >= 7 else { return interimRegularity(for: validNights) }

        let sleepBins = validNights.map { asleepBins(for: $0) }
        let pairScores = zip(sleepBins, sleepBins.dropFirst()).map { lhs, rhs in
            let overlap = lhs.intersection(rhs).count
            let union = lhs.union(rhs).count
            return union == 0 ? 0.0 : Double(overlap) / Double(union)
        }
        return ScoreMath.clamp(pairScores.reduce(0, +) / max(1, Double(pairScores.count)))
    }

    private func asleepBins(for night: NightlySleepInput) -> Set<Int> {
        var bins = Set<Int>()
        for segment in night.segments where segment.stage.isSleep {
            let startMinutes = minutesFromNoon(segment.start)
            let endMinutes = minutesFromNoon(segment.end)
            let startBin = Int(startMinutes / 30)
            let endBin = Int(ceil(endMinutes / 30))
            for bin in startBin..<max(startBin + 1, endBin) {
                bins.insert((bin + 48) % 48)
            }
        }
        return bins
    }

    private func minutesFromNoon(_ date: Date) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
        return minutes >= 12 * 60 ? minutes - 12 * 60 : minutes + 12 * 60
    }

    private func interimRegularity(for nights: [NightlySleepInput]) -> Double {
        guard nights.count >= 2 else { return 0.55 }
        let bedtimes = nights.map { minutesFromNoon($0.nightStart) }
        let wakeTimes = nights.map { minutesFromNoon($0.nightEnd) }
        let midpoints = zip(bedtimes, wakeTimes).map { pair in (pair.0 + pair.1) / 2 }
        let bedtimeScore = variabilityScore(values: bedtimes, toleratedMinutes: 60)
        let wakeScore = variabilityScore(values: wakeTimes, toleratedMinutes: 60)
        let midpointScore = variabilityScore(values: midpoints, toleratedMinutes: 45)
        return ScoreMath.clamp(bedtimeScore * 0.35 + wakeScore * 0.35 + midpointScore * 0.30)
    }

    private func variabilityScore(values: [Double], toleratedMinutes: Double) -> Double {
        guard values.count >= 2, let median = ScoreMath.median(values) else { return 0.55 }
        let deviations = values.map { abs($0 - median) }
        let averageDeviation = deviations.reduce(0, +) / Double(deviations.count)
        return ScoreMath.clamp(1 - averageDeviation / toleratedMinutes)
    }

    private func confidenceGrade(for analysis: SleepAnalysisSummary, sleepMinutes: Double) -> (grade: ConfidenceGrade, explanation: String) {
        guard sleepMinutes >= 120 else {
            return (.low, "Sleep coverage was too short for a reliable nightly score.")
        }
        if hasStagedSleep(analysis) {
            return (.high, "Sleep/wake and Apple-style Core, Deep, and REM stages were available from the primary source.")
        }
        if analysis.asleepUnspecifiedMinutes > 0 {
            return (.moderate, "Only binary asleep/awake sleep was available, so stage percentages are limited.")
        }
        return (.low, "Sleep samples were incomplete or missing stage detail.")
    }

    private func notes(for analysis: SleepAnalysisSummary, timeInBed: Double, sleepMinutes: Double, regularity: Double) -> [String] {
        var notes: [String] = []
        if !hasStagedSleep(analysis) {
            notes.append("Stage data is unavailable; Pulsar falls back to sleep/wake metrics.")
        }
        if analysis.hasSamples && sleepMinutes == 0 {
            notes.append("HealthKit reported in-bed or awake sleep-analysis samples, but no actual asleep stage was available.")
        }
        if timeInBed > 0, sleepMinutes / timeInBed < 0.80 {
            notes.append("Sleep efficiency was below the target range because awake time was elevated.")
        }
        if regularity < 0.70 {
            notes.append("Sleep timing was variable across the recent window.")
        }
        if notes.isEmpty {
            notes.append("Top-line sleep performance emphasizes duration, efficiency, regularity, and continuity rather than noisy stage dominance.")
        }
        return notes
    }

    private func sourceBadges(from segments: [SleepSegment], sourceNames: [String]) -> [SourceProvenance] {
        let selected = segments.filter { sourceNames.contains($0.provenance.sourceName) || sourceNames.contains($0.provenance.displayName) }
        let provenances = selected.isEmpty ? segments.map(\.provenance) : selected.map(\.provenance)
        return SourceResolver.uniqueSourceBadges(provenances)
    }

    private func sleepStageIntervals(from intervals: [SleepAnalysisInterval]) -> [SleepStageInterval] {
        intervals.map { interval in
            SleepStageInterval(stage: interval.stage.homeStage, startDate: interval.start, endDate: interval.end)
        }
    }
}

private extension NightlySleepInput {
    var analysisSamples: [SleepAnalysisSample] {
        segments.map { segment in
            SleepAnalysisSample(
                id: segment.id.uuidString,
                stage: segment.stage.analysisStage,
                start: segment.start,
                end: segment.end,
                sourceName: segment.provenance.sourceName,
                sourceBundleIdentifier: segment.provenance.sourceBundleIdentifier,
                deviceName: segment.provenance.deviceName
            )
        }
    }
}

private extension SleepStage {
    var analysisStage: SleepAnalysisStage {
        switch self {
        case .awake: .awake
        case .core: .asleepCore
        case .deep: .asleepDeep
        case .rem: .asleepREM
        case .asleepUnspecified: .asleepUnspecified
        case .inBed: .inBed
        }
    }
}

private extension SleepAnalysisStage {
    var homeStage: SleepStage {
        switch self {
        case .awake: .awake
        case .asleepCore: .core
        case .asleepDeep: .deep
        case .asleepREM: .rem
        case .asleepUnspecified: .asleepUnspecified
        case .inBed: .inBed
        }
    }
}
