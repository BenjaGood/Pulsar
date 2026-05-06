//
//  RecoveryAnalyzer.swift
//  Pulsar
//

import Foundation

struct RecoveryAnalysisInput {
    var date: Date
    var biometrics: DailyBiometrics
    var baselineDays: [DailyBiometrics]
    var trendDays: [DailyBiometrics]
    var sleep: SleepSummary
    var strain: StrainSummary
    var queryInterval: DateInterval
    var refreshedAt: Date
}

struct RecoveryAnalyzer {
    func analyze(_ input: RecoveryAnalysisInput) -> RecoverySummary {
        var biometrics = input.biometrics
        biometrics.sleepPerformance = input.sleep.sleepPerformance > 0 ? input.sleep.sleepPerformance : nil
        biometrics.priorDayStrain = input.strain.score > 0 ? Double(input.strain.score) / 100 : nil

        var summary = RecoveryScoringEngine().score(today: biometrics, baselineDays: input.baselineDays)
        summary.date = input.date
        summary.sleepDuration = input.sleep.totalSleepMinutes > 0 ? input.sleep.totalSleepMinutes * 60 : nil
        summary.sleepEfficiency = input.sleep.sleepEfficiency > 0 ? input.sleep.sleepEfficiency : nil
        summary.deepSleep = stageSeconds(.deep, in: input.sleep)
        summary.remSleep = stageSeconds(.rem, in: input.sleep)
        summary.strainScore = input.strain.score > 0 ? Double(input.strain.score) : nil
        summary.components = components(summary: summary)
        summary.trend = trend(from: input.trendDays, baseline: input.baselineDays)
        summary.analyzedSampleCount += input.sleep.analyzedSampleCount + input.strain.analyzedSampleCount
        summary.queryStart = input.queryInterval.start
        summary.queryEnd = input.queryInterval.end
        summary.lastUpdated = input.refreshedAt
        summary.sourceBadges = SourceResolver.uniqueSourceBadges(summary.sourceBadges + input.sleep.sourceBadges + input.strain.sourceBadges)
        return summary
    }

    func componentStatus(contribution: Double?) -> RecoveryStatus {
        guard let contribution else { return .unknown }
        if contribution >= 0.68 { return .excellent }
        if contribution >= 0.54 { return .balanced }
        if contribution >= 0.42 { return .moderate }
        return .low
    }

    private func components(summary: RecoverySummary) -> [RecoveryComponent] {
        [
            RecoveryComponent(
                title: "HRV",
                valueText: summary.hrvSDNN.map { "\(Int($0.rounded())) ms" } ?? "Not enough data",
                contribution: contribution(summary.hrvReadiness),
                status: componentStatus(contribution: contribution(summary.hrvReadiness)),
                detail: hrvDetail(summary)
            ),
            RecoveryComponent(
                title: "Resting HR",
                valueText: summary.restingHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "Not enough data",
                contribution: contribution(summary.restingHeartRateReadiness),
                status: componentStatus(contribution: contribution(summary.restingHeartRateReadiness)),
                detail: restingHeartRateDetail(summary)
            ),
            RecoveryComponent(
                title: "Sleep",
                valueText: summary.sleepDuration.map { durationText(seconds: $0) } ?? "Not enough data",
                contribution: contribution(summary.sleepContribution),
                status: componentStatus(contribution: contribution(summary.sleepContribution)),
                detail: sleepDetail(summary)
            ),
            RecoveryComponent(
                title: "Strain",
                valueText: summary.strainScore.map { "\(Int($0.rounded()))" } ?? "Not enough data",
                contribution: contribution(1 - summary.strainPenalty),
                status: componentStatus(contribution: contribution(1 - summary.strainPenalty)),
                detail: strainDetail(summary)
            )
        ]
    }

    private func trend(from days: [DailyBiometrics], baseline: [DailyBiometrics]) -> [RecoveryTrendPoint] {
        days.sorted { $0.date < $1.date }.map { day in
            let score = RecoveryScoringEngine().score(today: day, baselineDays: baseline)
            return RecoveryTrendPoint(
                date: day.date,
                recoveryScore: score.score > 0 ? Double(score.score) : nil,
                hrv: day.hrvSDNNMilliseconds,
                restingHeartRate: day.restingHeartRateBPM,
                sleepDuration: nil,
                strainScore: day.priorDayStrain.map { $0 * 100 }
            )
        }
    }

    private func contribution(_ readiness: Double) -> Double? {
        readiness > 0 ? readiness : nil
    }

    private func stageSeconds(_ stage: SleepStage, in sleep: SleepSummary) -> TimeInterval? {
        guard let minutes = sleep.stageBreakdown.first(where: { $0.stage == stage })?.minutes, minutes > 0 else { return nil }
        return minutes * 60
    }

    private func hrvDetail(_ summary: RecoverySummary) -> String? {
        guard let hrv = summary.hrvSDNN else { return "Wear your watch overnight to build an HRV trend." }
        guard let baseline = summary.hrvBaseline, baseline > 0 else { return "More baseline data will make HRV trends clearer." }
        let delta = (hrv - baseline) / baseline
        if delta >= 0.06 { return "Above your recent average, which supports recovery." }
        if delta <= -0.06 { return "Below your recent average, so a lighter training day may fit better." }
        return "Near your recent average."
    }

    private func restingHeartRateDetail(_ summary: RecoverySummary) -> String? {
        guard let rhr = summary.restingHeartRate else { return "Resting heart rate was not available for this day." }
        guard let baseline = summary.restingHeartRateBaseline else { return "More baseline data will make resting heart-rate trends clearer." }
        let delta = rhr - baseline
        if delta <= -2 { return "Below your recent average, which supports recovery." }
        if delta >= 4 { return "Elevated compared with your recent average." }
        return "Close to your recent average."
    }

    private func sleepDetail(_ summary: RecoverySummary) -> String? {
        guard let duration = summary.sleepDuration else { return "Sleep data was unavailable for this recovery window." }
        let durationText = durationText(seconds: duration)
        if let efficiency = summary.sleepEfficiency {
            return "\(durationText) asleep with \(Int((efficiency * 100).rounded()))% efficiency."
        }
        return "\(durationText) asleep."
    }

    private func strainDetail(_ summary: RecoverySummary) -> String? {
        guard let strain = summary.strainScore else { return "Strain data was unavailable for this day." }
        if strain >= 75 { return "High strain can carry fatigue into recovery." }
        if strain >= 45 { return "Moderate strain is part of today's recovery context." }
        return "Lower strain gives recovery more room."
    }

    private func durationText(seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}
