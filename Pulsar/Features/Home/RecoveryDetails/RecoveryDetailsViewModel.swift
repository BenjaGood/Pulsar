//
//  RecoveryDetailsViewModel.swift
//  Pulsar
//

import Combine
import Foundation

enum RecoveryDetailsState: Equatable {
    case loading
    case loaded
    case permissionRequired
    case noData
    case error(String)
}

struct RecoveryMetricTileModel: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var value: String
    var subtitle: String?
    var symbol: String
}

struct RecoveryInsight: Identifiable, Equatable {
    var id: String { text }
    var text: String
}

@MainActor
final class RecoveryDetailsViewModel: ObservableObject {
    @Published private(set) var state: RecoveryDetailsState
    @Published private(set) var summary: RecoverySummary

    private let provider: RecoverySummaryProviding
    private let profile: UserProfile
    private let date: Date
    private let calendar: Calendar
    private let canRequestHealthData: Bool

    init(initialSummary: RecoverySummary, profile: UserProfile, date: Date, provider: RecoverySummaryProviding, calendar: Calendar = .current, canRequestHealthData: Bool = true) {
        self.summary = initialSummary
        self.profile = profile
        self.date = calendar.startOfDay(for: date)
        self.provider = provider
        self.calendar = calendar
        self.canRequestHealthData = canRequestHealthData
        self.state = Self.state(for: initialSummary, canRequestHealthData: canRequestHealthData)
    }

    var scoreText: String { summary.score > 0 ? "\(summary.score)" : "--" }
    var statusText: String { summary.status.label }
    var hrvText: String { bpmOrMS(summary.hrvSDNN, unit: "ms") }
    var hrvBaselineText: String { summary.hrvBaseline.map { "7-day avg \(Int($0.rounded())) ms" } ?? "Build baseline" }
    var restingHeartRateText: String { bpmOrMS(summary.restingHeartRate, unit: "bpm") }
    var restingHeartRateBaselineText: String { summary.restingHeartRateBaseline.map { "7-day avg \(Int($0.rounded())) bpm" } ?? "Build baseline" }
    var sleepDurationText: String { summary.sleepDuration.map(Self.durationText(seconds:)) ?? "Not enough data" }
    var sleepEfficiencyText: String { summary.sleepEfficiency.map { Self.percentText($0) } ?? "Not enough data" }
    var deepSleepText: String { summary.deepSleep.map(Self.durationText(seconds:)) ?? "Not enough data" }
    var remSleepText: String { summary.remSleep.map(Self.durationText(seconds:)) ?? "Not enough data" }
    var strainText: String { summary.strainScore.map { "\(Int($0.rounded()))" } ?? "Not enough data" }
    var respiratoryRateText: String { summary.respiratoryRate.map { String(format: "%.1f/min", $0) } ?? "Not enough data" }
    var oxygenText: String { summary.oxygenSaturation.map { "\(Int(($0 * 100).rounded()))%" } ?? "Not enough data" }
    var wristTemperatureText: String { summary.wristTemperatureDeviation.map { String(format: "%+.1f C", $0) } ?? "Not enough data" }
    var sampleCountText: String { summary.analyzedSampleCount > 0 ? "\(summary.analyzedSampleCount) samples" : "No samples" }
    var lastUpdatedText: String { summary.lastUpdated.map { "Updated \($0.formatted(.relative(presentation: .named)))" } ?? "Not updated" }
    var baselineText: String { summary.baselineWindowDays > 0 ? "\(summary.baselineWindowDays)-day window" : "Not available" }
    var queryText: String {
        guard let start = summary.queryStart, let end = summary.queryEnd else { return "Not available" }
        return "\(start.formatted(.dateTime.hour().minute())) - \(end.formatted(.dateTime.hour().minute()))"
    }

    var dateSubtitle: String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var recoveryBalanceSubtitle: String {
        calendar.isDateInToday(date)
            ? "What is supporting or reducing recovery today"
            : "What supported or reduced recovery that day"
    }

    var metricTiles: [RecoveryMetricTileModel] {
        var tiles = [
            RecoveryMetricTileModel(title: "Recovery", value: scoreText, subtitle: "Baseline-relative", symbol: "heart.text.square.fill"),
            RecoveryMetricTileModel(title: "HRV", value: hrvText, subtitle: hrvBaselineText, symbol: "waveform.path.ecg"),
            RecoveryMetricTileModel(title: "Resting HR", value: restingHeartRateText, subtitle: restingHeartRateBaselineText, symbol: "heart.fill"),
            RecoveryMetricTileModel(title: "Sleep", value: sleepDurationText, subtitle: "Total sleep", symbol: "moon.zzz.fill"),
            RecoveryMetricTileModel(title: "Efficiency", value: sleepEfficiencyText, subtitle: "Sleep quality signal", symbol: "gauge.with.dots.needle.bottom.50percent"),
            RecoveryMetricTileModel(title: "Deep Sleep", value: deepSleepText, subtitle: nil, symbol: "bed.double.fill"),
            RecoveryMetricTileModel(title: "REM Sleep", value: remSleepText, subtitle: nil, symbol: "brain.head.profile"),
            RecoveryMetricTileModel(title: "Strain", value: strainText, subtitle: "Training context", symbol: "figure.run.circle.fill")
        ]
        if summary.respiratoryRate != nil { tiles.append(RecoveryMetricTileModel(title: "Respiration", value: respiratoryRateText, subtitle: "Breaths per minute", symbol: "lungs.fill")) }
        if summary.oxygenSaturation != nil { tiles.append(RecoveryMetricTileModel(title: "Oxygen", value: oxygenText, subtitle: "Latest sample", symbol: "drop.fill")) }
        if summary.wristTemperatureDeviation != nil { tiles.append(RecoveryMetricTileModel(title: "Wrist Temp", value: wristTemperatureText, subtitle: "Latest sample", symbol: "thermometer.medium")) }
        return tiles
    }

    var insights: [RecoveryInsight] {
        var values: [String] = []
        if let hrv = summary.hrvSDNN, let baseline = summary.hrvBaseline, baseline > 0 {
            let percent = (hrv - baseline) / baseline
            if percent <= -0.06 { values.append("Your HRV is \(abs(Int((percent * 100).rounded())))% below your recent average, so a lighter training day may fit better.") }
            else if percent >= 0.06 { values.append("Your HRV is \(Int((percent * 100).rounded()))% above your recent average, which supports recovery.") }
        }
        if let rhr = summary.restingHeartRate, let baseline = summary.restingHeartRateBaseline {
            let delta = Int((rhr - baseline).rounded())
            if delta >= 4 { values.append("Your resting heart rate is \(delta) bpm above your recent average.") }
            else if delta <= -2 { values.append("Your resting heart rate is \(abs(delta)) bpm below your recent average.") }
        }
        if let sleep = summary.sleepDuration {
            var text = "You slept \(Self.durationText(seconds: sleep))"
            if let efficiency = summary.sleepEfficiency { text += " with \(Self.percentText(efficiency)) efficiency" }
            values.append(text + ".")
        }
        if let strain = summary.strainScore, strain >= 75 {
            values.append("Recent strain was high, so a lighter session may fit better today.")
        }
        if values.isEmpty {
            values.append("Recovery trends need more data. Wear your watch for a few more nights to improve accuracy.")
        }
        return Array(values.prefix(4)).map { RecoveryInsight(text: $0) }
    }

    var sourceText: String {
        let sources = summary.sourceBadges.map(\.displayName)
        return sources.isEmpty ? "HealthKit" : sources.joined(separator: ", ")
    }

    var needsDetailedRefresh: Bool {
        guard canRequestHealthData else { return false }
        if !Self.hasData(summary) { return true }
        return summary.components.isEmpty || summary.trend.isEmpty
    }

    func loadIfNeeded() async {
        guard needsDetailedRefresh else { return }
        await refresh(showBanner: false)
    }

    func load() async {
        await refresh(showBanner: true)
    }

    private func refresh(showBanner: Bool) async {
        guard canRequestHealthData else {
            state = .permissionRequired
            return
        }
        PulsarSyncDebugLogger.log("Recovery details refresh started date=\(date) reason=\(showBanner ? "manual" : "detailHydration")")
        if showBanner {
            PulsarSyncBannerCenter.shared.showSyncing()
        }
        if !Self.hasData(summary) {
            state = .loading
        }
        do {
            let refreshedAt = Date()
            let loaded = try await provider.recoverySummary(profile: profile, date: date, calendar: calendar, refreshedAt: refreshedAt)
            if Self.hasData(loaded) || !Self.hasData(summary) {
                summary = loaded
            }
            state = Self.state(for: summary, canRequestHealthData: true)
            if showBanner {
                PulsarSyncBannerCenter.shared.showSuccess()
            }
        } catch {
            state = Self.hasData(summary) ? .loaded : .error("Recovery data could not be refreshed.")
            if showBanner {
                PulsarSyncBannerCenter.shared.showFailure()
            }
        }
    }

    static func durationText(seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes > 0 else { return "--" }
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }

    static func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func state(for summary: RecoverySummary, canRequestHealthData: Bool) -> RecoveryDetailsState {
        guard canRequestHealthData else { return .permissionRequired }
        return hasData(summary) ? .loaded : .noData
    }

    private static func hasData(_ summary: RecoverySummary) -> Bool {
        summary.analyzedSampleCount > 0 || summary.score > 0 || summary.hrvSDNN != nil || summary.restingHeartRate != nil || summary.sleepDuration != nil || summary.strainScore != nil
    }

    private func bpmOrMS(_ value: Double?, unit: String) -> String {
        value.map { "\(Int($0.rounded())) \(unit)" } ?? "Not enough data"
    }
}
