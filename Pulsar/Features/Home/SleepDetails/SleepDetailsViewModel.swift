//
//  SleepDetailsViewModel.swift
//  Pulsar
//

import Foundation
import Combine

enum SleepDetailsState: Equatable {
    case loading
    case loaded
    case permissionRequired
    case noData
    case error(String)
}

struct SleepMetricTileModel: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var value: String
    var subtitle: String?
}

struct SleepInsight: Identifiable, Equatable {
    var id: String { text }
    var text: String
}

@MainActor
final class SleepDetailsViewModel: ObservableObject {
    @Published private(set) var state: SleepDetailsState
    @Published private(set) var summary: SleepSummary

    private let provider: SleepSummaryProviding
    private let profile: UserProfile
    private let wakeUpDate: Date
    private let calendar: Calendar
    private let canRequestHealthData: Bool
    private let syncStore: PulsarWatchConnectivitySyncStore

    init(
        initialSummary: SleepSummary,
        profile: UserProfile,
        wakeUpDate: Date,
        provider: SleepSummaryProviding,
        calendar: Calendar = .current,
        canRequestHealthData: Bool = true,
        syncStore: PulsarWatchConnectivitySyncStore? = nil
    ) {
        self.summary = initialSummary
        self.profile = profile
        self.wakeUpDate = calendar.startOfDay(for: wakeUpDate)
        self.provider = provider
        self.calendar = calendar
        self.canRequestHealthData = canRequestHealthData
        self.syncStore = syncStore ?? .shared
        self.state = Self.state(for: initialSummary, canRequestHealthData: canRequestHealthData)
    }

    var totalSleepText: String { Self.durationText(minutes: summary.totalSleepMinutes) }
    var timeInBedText: String { Self.durationText(minutes: summary.timeInBedMinutes) }
    var awakeText: String { Self.durationText(minutes: summary.awakeMinutes) }
    var remText: String { Self.durationText(minutes: stageMinutes(.rem)) }
    var coreText: String { Self.durationText(minutes: stageMinutes(.core) + stageMinutes(.asleepUnspecified)) }
    var deepText: String { Self.durationText(minutes: stageMinutes(.deep)) }
    var efficiencyText: String { summary.sleepEfficiency > 0 ? Self.percentText(summary.sleepEfficiency) : "Not enough data" }
    var consistencyText: String { summary.sleepConsistency > 0 ? Self.percentText(summary.sleepConsistency) : "Not enough data" }
    var sleepStartText: String { summary.sleepStart.map(timeText) ?? "Not enough data" }
    var wakeTimeText: String { summary.wakeTime.map(timeText) ?? "Not enough data" }
    var awakeningsText: String { summary.analyzedSampleCount > 0 ? "\(summary.awakenings)" : "Not enough data" }
    var sampleCountText: String { summary.analyzedSampleCount > 0 ? "\(summary.analyzedSampleCount) samples" : "No samples" }
    var lastUpdatedText: String { summary.lastUpdated.map { "Updated \(relativeText($0))" } ?? "Not updated" }
    var alarmBadgeText: String? {
        guard profile.sleepSchedule.alarmEnabled else { return nil }
        return "Alarm \(timeText(minutesFromMidnight: profile.sleepSchedule.resolvedAlarmTimeMinutesFromMidnight))"
    }

    var dateSubtitle: String {
        if calendar.isDateInToday(wakeUpDate) { return "Last night" }
        return wakeUpDate.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var statusText: String {
        guard summary.totalSleepMinutes > 0 else { return "No sleep data" }
        if summary.sleepEfficiency < 0.78 || summary.awakenings >= 4 { return "Fragmented sleep" }
        if sleepDebtMinutes > 30 { return "Light sleep deficit" }
        if summary.score >= 85 { return "Excellent recovery" }
        if summary.sleepConsistency >= 0.75 { return "Consistent night" }
        return "Steady night"
    }

    var metricTiles: [SleepMetricTileModel] {
        [
            SleepMetricTileModel(title: "Total Sleep", value: totalSleepText, subtitle: "Actual asleep time"),
            SleepMetricTileModel(title: "Time in Bed", value: timeInBedText, subtitle: "Sleep window coverage"),
            SleepMetricTileModel(title: "Efficiency", value: efficiencyText, subtitle: "Sleep / in bed"),
            SleepMetricTileModel(title: "Awake", value: awakeText, subtitle: "Not counted as sleep"),
            SleepMetricTileModel(title: "Sleep Start", value: sleepStartText, subtitle: nil),
            SleepMetricTileModel(title: "Wake Time", value: wakeTimeText, subtitle: nil),
            SleepMetricTileModel(title: "REM", value: remText, subtitle: stagePercentText(.rem)),
            SleepMetricTileModel(title: "Deep", value: deepText, subtitle: stagePercentText(.deep)),
            SleepMetricTileModel(title: "Core / Light", value: coreText, subtitle: corePercentText),
            SleepMetricTileModel(title: "Awakenings", value: awakeningsText, subtitle: "During sleep"),
            SleepMetricTileModel(title: "Consistency", value: consistencyText, subtitle: nil),
            SleepMetricTileModel(title: "Sleep Debt", value: sleepDebtText, subtitle: "Against target")
        ]
    }

    var stageBreakdownRows: [StageMetric] {
        let total = max(1, summary.totalSleepMinutes)
        let coreMinutes = stageMinutes(.core) + stageMinutes(.asleepUnspecified)
        return [
            StageMetric(stage: .deep, minutes: stageMinutes(.deep), percentOfSleep: stageMinutes(.deep) / total),
            StageMetric(stage: .rem, minutes: stageMinutes(.rem), percentOfSleep: stageMinutes(.rem) / total),
            StageMetric(stage: .core, minutes: coreMinutes, percentOfSleep: coreMinutes / total),
            StageMetric(stage: .awake, minutes: summary.awakeMinutes, percentOfSleep: 0),
            StageMetric(stage: .inBed, minutes: summary.timeInBedMinutes, percentOfSleep: 0)
        ].filter { $0.minutes > 0 }
    }

    var insights: [SleepInsight] {
        guard summary.totalSleepMinutes > 0 else { return [] }
        var values: [String] = []
        let deepMinutes = stageMinutes(.deep)
        if deepMinutes > 0 {
            values.append("Your deep sleep was \(Self.durationText(minutes: deepMinutes)), around \(Self.percentText(deepMinutes / max(1, summary.totalSleepMinutes))) of your total sleep.")
        }
        values.append("You woke up \(summary.awakenings) \(summary.awakenings == 1 ? "time" : "times") during the night.")
        if summary.sleepEfficiency > 0 {
            let quality = summary.sleepEfficiency >= 0.88 ? "a stable night" : "more sleep fragmentation than usual"
            values.append("Your sleep efficiency was \(Self.percentText(summary.sleepEfficiency)), which suggests \(quality).")
        }
        if sleepDebtMinutes > 5 {
            values.append("You slept \(Self.durationText(minutes: sleepDebtMinutes)) less than your \(Self.durationText(minutes: profile.sleepSchedule.targetSleepHours * 60)) target.")
        } else if sleepDebtMinutes < -5 {
            values.append("You exceeded your sleep target by \(Self.durationText(minutes: abs(sleepDebtMinutes))).")
        }
        if let remInsight { values.append(remInsight) }
        return Array(values.prefix(4)).map { SleepInsight(text: $0) }
    }

    var sourceText: String {
        let sources = summary.sourceBadges.map(\.displayName)
        return sources.isEmpty ? "HealthKit" : sources.joined(separator: ", ")
    }

    var needsDetailedRefresh: Bool {
        guard canRequestHealthData else { return false }
        if summary.totalSleepMinutes > 0, summary.intervals.isEmpty { return true }
        if summary.analyzedSampleCount == 0 { return true }
        return false
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
        PulsarSyncDebugLogger.log("Sleep details refresh started wakeUpDate=\(wakeUpDate) reason=\(showBanner ? "manual" : "detailHydration")")
        if summary.totalSleepMinutes == 0 && summary.intervals.isEmpty {
            state = .loading
        }
        let syncSessionID = UUID()
        if showBanner {
            PulsarSyncBannerCenter.shared.showSyncing()
        }
        PulsarSyncDebugLogger.log("Sleep sync started session=\(syncSessionID.uuidString) wakeUpDate=\(wakeUpDate)")
        do {
            let refreshedAt = Date()
            let loaded = try await provider.sleepSummary(profile: profile, wakeUpDate: wakeUpDate, calendar: calendar, refreshedAt: refreshedAt)
            if loaded.totalSleepMinutes > 0 || summary.totalSleepMinutes == 0 {
                summary = loaded
            }
            state = Self.state(for: summary, canRequestHealthData: true)
            let dashboard = HomeDashboard(profile: profile, sleep: loaded, recovery: .missing, strain: .missing, generatedAt: refreshedAt, usingSampleData: false)
            if let payload = dashboard.syncPayload(sourceDevice: .iPhone, syncSessionID: syncSessionID, calendar: calendar) {
                syncStore.storeLocalPayload(payload, broadcast: true, reason: "iPhoneSleepDetailsSync")
                PulsarSyncDebugLogger.log("Sleep Score calculated value=\(payload.sleep?.score ?? 0) sleepDateKey=\(payload.sleep?.sleepDateKey ?? "none") session=\(syncSessionID.uuidString)")
            } else {
                PulsarSyncDebugLogger.log("invalid result ignored for Sleep details session=\(syncSessionID.uuidString)")
            }
            if showBanner {
                PulsarSyncBannerCenter.shared.showSuccess()
            }
        } catch {
            state = summary.totalSleepMinutes > 0 ? .loaded : .error("Sleep data could not be refreshed.")
            if showBanner {
                PulsarSyncBannerCenter.shared.showFailure()
            }
        }
    }

    func stageMinutes(_ stage: SleepStage) -> Double {
        switch stage {
        case .awake: summary.awakeMinutes
        case .core: summary.stageBreakdown.first(where: { $0.stage == .core })?.minutes ?? 0
        case .deep: summary.stageBreakdown.first(where: { $0.stage == .deep })?.minutes ?? 0
        case .rem: summary.stageBreakdown.first(where: { $0.stage == .rem })?.minutes ?? 0
        case .asleepUnspecified: summary.stageBreakdown.first(where: { $0.stage == .asleepUnspecified })?.minutes ?? 0
        case .inBed: summary.timeInBedMinutes
        }
    }

    func stagePercentText(_ stage: SleepStage) -> String {
        let minutes = stageMinutes(stage)
        guard summary.totalSleepMinutes > 0, minutes > 0 else { return "Not enough data" }
        return Self.percentText(minutes / summary.totalSleepMinutes)
    }

    static func durationText(minutes: Double) -> String {
        guard minutes > 0 else { return "--" }
        let rounded = Int(minutes.rounded())
        if rounded >= 60 { return "\(rounded / 60)h \(rounded % 60)m" }
        return "\(rounded)m"
    }

    static func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func state(for summary: SleepSummary, canRequestHealthData: Bool) -> SleepDetailsState {
        guard canRequestHealthData else { return .permissionRequired }
        if summary.confidenceExplanation == SleepSummary.permissionRequired.confidenceExplanation { return .permissionRequired }
        if summary.analyzedSampleCount == 0 || (summary.totalSleepMinutes == 0 && summary.intervals.isEmpty) { return .noData }
        return .loaded
    }

    private var corePercentText: String {
        let minutes = stageMinutes(.core) + stageMinutes(.asleepUnspecified)
        guard summary.totalSleepMinutes > 0, minutes > 0 else { return "Not enough data" }
        return Self.percentText(minutes / summary.totalSleepMinutes)
    }

    private var sleepDebtMinutes: Double {
        profile.sleepSchedule.targetSleepHours * 60 - summary.totalSleepMinutes
    }

    private var sleepDebtText: String {
        let debt = sleepDebtMinutes
        if abs(debt) < 5 { return "None" }
        return debt > 0 ? Self.durationText(minutes: debt) : "+\(Self.durationText(minutes: abs(debt)))"
    }

    private var remInsight: String? {
        let remIntervals = summary.intervals.filter { $0.stage == .rem }
        guard let sleepStart = summary.sleepStart,
              let wakeTime = summary.wakeTime,
              wakeTime > sleepStart,
              remIntervals.reduce(0, { $0 + $1.durationMinutes }) > 0 else { return nil }
        let midpoint = sleepStart.addingTimeInterval(wakeTime.timeIntervalSince(sleepStart) / 2)
        let lateREM = remIntervals.filter { $0.startDate >= midpoint }.reduce(0) { $0 + $1.durationMinutes }
        let totalREM = remIntervals.reduce(0) { $0 + $1.durationMinutes }
        if totalREM > 0, lateREM / totalREM >= 0.55 {
            return "Most of your REM sleep happened in the second half of the night."
        }
        return nil
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    private func timeText(minutesFromMidnight: Int) -> String {
        let components = DateComponents(hour: minutesFromMidnight / 60, minute: minutesFromMidnight % 60)
        let date = calendar.date(from: components) ?? Date()
        return timeText(date)
    }

    private func relativeText(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }
}
