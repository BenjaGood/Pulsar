//
//  StrainDetailsViewModel.swift
//  Pulsar
//

import Combine
import Foundation

enum StrainDetailsState: Equatable {
    case loading
    case loaded
    case permissionRequired
    case noData
    case error(String)
}

struct StrainMetricTileModel: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var value: String
    var subtitle: String?
    var symbol: String
}

struct StrainInsight: Identifiable, Equatable {
    var id: String { text }
    var text: String
}

struct StrainHeartLoadCallout: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var value: String
    var symbol: String
}

struct StrainTimelineMarker: Identifiable, Equatable {
    var id: String { "\(date.timeIntervalSinceReferenceDate)-\(label)" }
    var date: Date
    var label: String
}

struct StrainHeartLoadReference: Identifiable, Equatable {
    var id: String { title }
    var title: String
    var bpm: Double
}

struct StrainHeartLoadChartModel: Equatable {
    var range: DateInterval
    var heartRatePoints: [HeartRatePoint]
    var workoutBands: [WorkoutTimelineBand]
    var references: [StrainHeartLoadReference]
    var markers: [StrainTimelineMarker]
    var callouts: [StrainHeartLoadCallout]
    var steps: Int
    var exerciseMinutes: Double
    var activeEnergyKilocalories: Double?
    var yAxisMin: Double
    var yAxisMax: Double
    var intensityDescription: String

    var hasHeartRate: Bool { !heartRatePoints.isEmpty }
    var hasWorkouts: Bool { !workoutBands.isEmpty }
    var hasMovement: Bool { steps > 0 || exerciseMinutes > 0 || (activeEnergyKilocalories ?? 0) > 0 }
}

@MainActor
final class StrainDetailsViewModel: ObservableObject {
    @Published private(set) var state: StrainDetailsState
    @Published private(set) var summary: StrainSummary

    private let provider: StrainSummaryProviding
    private let profile: UserProfile
    private let date: Date
    private let recoveryScore: Int?
    private let recentStrainScores: [Int]
    private let adaptivePlan: AdaptiveStrainPlan?
    private let calendar: Calendar
    private let canRequestHealthData: Bool

    init(initialSummary: StrainSummary, profile: UserProfile, date: Date, recoveryScore: Int? = nil, recentStrainScores: [Int] = [], adaptivePlan: AdaptiveStrainPlan? = nil, provider: StrainSummaryProviding, calendar: Calendar = .current, canRequestHealthData: Bool = true) {
        self.summary = initialSummary
        self.profile = profile
        self.date = calendar.startOfDay(for: date)
        self.recoveryScore = recoveryScore
        self.recentStrainScores = recentStrainScores
        self.adaptivePlan = adaptivePlan
        self.provider = provider
        self.calendar = calendar
        self.canRequestHealthData = canRequestHealthData
        self.state = Self.state(for: initialSummary, canRequestHealthData: canRequestHealthData)
    }

    var hasCurrentStrainValue: Bool { Self.hasData(summary) }
    var scoreText: String { hasCurrentStrainValue ? "\(summary.score)" : "--" }
    var targetRange: PulsarSharedStrainTargetRange? {
        if let adaptivePlan {
            return adaptivePlan.recommendedRange
        }
        return PulsarSharedMetricCalculator.recommendedStrainTargetRange(
            forRecoveryScore: recoveryScore,
            recentStrainScores: recentStrainScores
        )
    }
    var recommendedTarget: Int? { targetRange?.upperBound }
    var recommendedTargetText: String { targetRange?.displayText ?? "--" }
    var adaptiveSafeLimitText: String { adaptivePlan?.safeUpperLimitText ?? "--" }
    var adaptivePriorityText: String { adaptivePlan?.recoveryPriority.label ?? "Recovery-aware" }
    var adaptiveZoneText: String { adaptivePlan?.optimalTrainingZone.label ?? "Adaptive target" }
    var adaptiveHeadline: String {
        adaptivePlan?.headline ?? "Strain adapts to recovery and recent load."
    }
    var adaptiveRationale: String {
        adaptivePlan?.rationale ?? "Pulsar adjusts this range from recovery, recent strain, and available HealthKit signals."
    }
    var targetProgressText: String {
        guard let targetRange, hasCurrentStrainValue else { return "Awaiting recovery target" }
        if let adaptivePlan, adaptivePlan.isApproachingCeiling(currentStrain: summary.score) {
            return "Near safe upper limit \(adaptivePlan.safeUpperLimit)"
        }
        if summary.score > targetRange.upperBound { return "Above recommended range" }
        if summary.score >= targetRange.lowerBound { return "Within recommended range" }
        return "\(Int((Double(summary.score) / Double(max(1, targetRange.lowerBound)) * 100).rounded()))% of lower target"
    }
    var activeStrainText: String { "\(Int(summary.workoutLoad.rounded()))" }
    var passiveStrainText: String { "\(Int(summary.movementLoad.rounded()))" }
    var workoutsText: String { summary.workouts.isEmpty ? "--" : "\(summary.workouts.count)" }
    var trainingTimeText: String { Self.durationText(minutes: summary.workoutMinutes) }
    var exerciseMinutesText: String { Self.durationText(minutes: summary.exerciseMinutes) }
    var stepsText: String { summary.steps > 0 ? summary.steps.formatted() : "--" }
    var activeEnergyText: String { summary.activeEnergyKilocalories.map { "\(Int($0.rounded())) kcal" } ?? "Not enough data" }
    var averageActiveHeartRateText: String { bpmText(summary.averageActiveHeartRate) }
    var peakHeartRateText: String { bpmText(summary.peakHeartRate) }
    var restingHeartRateText: String { bpmText(summary.restingHeartRate) }
    var hrvText: String { summary.hrvSDNNMilliseconds.map { "\(Int($0.rounded())) ms" } ?? "Not enough data" }
    var stepProgress: Double { summary.stepGoal > 0 ? min(1, Double(summary.steps) / Double(summary.stepGoal)) : 0 }
    var stepProgressText: String { summary.steps > 0 ? Self.percentText(stepProgress) : "Not enough data" }
    var sampleCountText: String { summary.analyzedSampleCount > 0 ? "\(summary.analyzedSampleCount) samples" : "No samples" }
    var lastUpdatedText: String { summary.lastUpdated.map { "Updated \($0.formatted(.relative(presentation: .named)))" } ?? "Not updated" }
    var queryText: String {
        guard let start = summary.queryStart, let end = summary.queryEnd else { return "Not available" }
        return "\(start.formatted(.dateTime.hour().minute())) - \(end.formatted(.dateTime.hour().minute()))"
    }

    var heartLoadChart: StrainHeartLoadChartModel {
        let range = chartRange
        let points = summary.heartRatePoints
            .filter { range.contains($0.date) }
            .sorted { $0.date < $1.date }
        let bands = summary.workoutBands
            .filter { $0.startDate < range.end && $0.endDate > range.start }
            .sorted { $0.startDate < $1.startDate }
        let bpmValues = points.map(\.bpm).filter { $0 > 0 }
        let observedMin = bpmValues.min() ?? summary.restingHeartRate ?? 60
        let observedMax = bpmValues.max() ?? summary.peakHeartRate ?? max(120, observedMin + 40)
        let paddedMin = max(40, floor((observedMin - 12) / 10) * 10)
        let paddedMax = max(paddedMin + 40, ceil((observedMax + 12) / 10) * 10)

        return StrainHeartLoadChartModel(
            range: range,
            heartRatePoints: points,
            workoutBands: bands,
            references: heartLoadReferences(min: paddedMin, max: paddedMax),
            markers: timelineMarkers(for: range),
            callouts: heartLoadCallouts(from: summary),
            steps: summary.steps,
            exerciseMinutes: summary.exerciseMinutes,
            activeEnergyKilocalories: summary.activeEnergyKilocalories,
            yAxisMin: paddedMin,
            yAxisMax: paddedMax,
            intensityDescription: "Activity intensity from this day's heart-rate range"
        )
    }

    var dateSubtitle: String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var isViewingToday: Bool {
        calendar.isDateInToday(date)
    }

    var accumulatedSubtitle: String {
        isViewingToday ? "Accumulated today" : "Recorded that day"
    }

    var workoutsSubtitle: String {
        summary.workouts.isEmpty ? "No logged workouts" : (isViewingToday ? "Logged today" : "Logged that day")
    }

    var workoutEmptyTitle: String {
        isViewingToday ? "No workouts logged today" : "No workouts logged for this date"
    }

    var statusText: String {
        if let targetRange, hasCurrentStrainValue, summary.score > targetRange.upperBound { return "Above target" }
        if let targetRange, hasCurrentStrainValue, targetRange.contains(summary.score) { return "In target range" }
        if summary.score >= 85 { return "Peak effort" }
        if summary.score >= 70 { return "High training load" }
        if summary.workoutMinutes >= 30 || summary.score >= 40 { return "Balanced effort" }
        if summary.workouts.isEmpty && summary.exerciseMinutes < 20 { return "Recovery-focused day" }
        return "Light activity day"
    }

    var metricTiles: [StrainMetricTileModel] {
        [
            StrainMetricTileModel(title: "Current Strain", value: scoreText, subtitle: accumulatedSubtitle, symbol: "bolt.heart.fill"),
            StrainMetricTileModel(title: "Target Range", value: recommendedTargetText, subtitle: adaptiveZoneText, symbol: "scope"),
            StrainMetricTileModel(title: "Safe Limit", value: adaptiveSafeLimitText, subtitle: targetProgressText, symbol: "shield.lefthalf.filled"),
            StrainMetricTileModel(title: "Recovery Debt", value: adaptivePlan.map { "\($0.recoveryDebt.score)" } ?? "--", subtitle: adaptivePlan?.recoveryDebt.label, symbol: "waveform.path.ecg.rectangle"),
            StrainMetricTileModel(title: "Active Strain", value: activeStrainText, subtitle: "Workout contribution", symbol: "figure.run"),
            StrainMetricTileModel(title: "Passive Strain", value: passiveStrainText, subtitle: "Movement + elevated HR", symbol: "figure.walk.motion"),
            StrainMetricTileModel(title: "Workouts", value: workoutsText, subtitle: workoutsSubtitle, symbol: "figure.run"),
            StrainMetricTileModel(title: "Training Time", value: trainingTimeText, subtitle: "Workout duration", symbol: "timer"),
            StrainMetricTileModel(title: "Exercise", value: exerciseMinutesText, subtitle: "Apple Exercise Time", symbol: "figure.walk.motion"),
            StrainMetricTileModel(title: "Steps", value: stepsText, subtitle: "\(stepProgressText) of goal", symbol: "shoeprints.fill"),
            StrainMetricTileModel(title: "Active Calories", value: activeEnergyText, subtitle: nil, symbol: "flame.fill"),
            StrainMetricTileModel(title: "Avg Active HR", value: averageActiveHeartRateText, subtitle: "Workout/active samples", symbol: "heart.fill"),
            StrainMetricTileModel(title: "Peak HR", value: peakHeartRateText, subtitle: "Highest observed", symbol: "waveform.path.ecg"),
            StrainMetricTileModel(title: "Resting HR", value: restingHeartRateText, subtitle: nil, symbol: "heart.text.square"),
            StrainMetricTileModel(title: "HRV", value: hrvText, subtitle: "SDNN", symbol: "sparkline")
        ]
    }

    var insights: [StrainInsight] {
        var values: [String] = []
        if let adaptivePlan {
            values.append(adaptivePlan.headline)
            values.append(adaptivePlan.rationale)
            if let recommendation = adaptivePlan.recommendations.first {
                values.append("\(recommendation.title): \(recommendation.detail)")
            }
        }
        values.append(dateAwareCopy(PulsarSharedMetricCalculator.strainGuidance(
            currentStrain: hasCurrentStrainValue ? summary.score : nil,
            targetRange: targetRange,
            recoveryScore: recoveryScore,
            activeStrain: summary.workoutLoad,
            passiveStrain: summary.movementLoad,
            workoutMinutes: summary.workoutMinutes,
            exerciseMinutes: summary.exerciseMinutes,
            steps: summary.steps,
            isEarlyDay: calendar.isDateInToday(date) && calendar.component(.hour, from: Date()) < 11
        )))
        if !summary.workouts.isEmpty {
            values.append("You completed \(summary.workouts.count) \(summary.workouts.count == 1 ? "workout" : "workouts") \(isViewingToday ? "today" : "that day") for a total of \(Self.durationText(minutes: summary.workoutMinutes)).")
            if summary.workoutLoad >= summary.movementLoad {
                values.append("Most of \(isViewingToday ? "today's" : "that day's") load came from active strain: workouts, duration, and workout intensity.")
            }
        } else if summary.exerciseMinutes < 20 {
            values.append(isViewingToday ? "Today looks recovery-focused with light movement and no logged workouts." : "That day looked recovery-focused with light movement and no logged workouts.")
        }
        if summary.movementLoad > 0 {
            values.append("Passive strain reflects walking, active calories, non-workout exercise, and sustained elevated heart rate.")
        }
        if let peak = summary.peakHeartRate {
            values.append("Your peak heart rate reached \(Int(peak.rounded())) bpm during your hardest observed effort.")
        }
        if summary.steps > 0 {
            values.append("You are \(stepProgressText) of the way to your \(summary.stepGoal.formatted()) step goal.")
        }
        if let hardest = summary.workouts.max(by: { ($0.peakHeartRate ?? $0.averageHeartRate ?? 0) < ($1.peakHeartRate ?? $1.averageHeartRate ?? 0) }) {
            values.append("Most of \(isViewingToday ? "today's" : "that day's") high-intensity signal came from \(hardest.workoutType.lowercased()).")
        }
        if values.isEmpty {
            values.append("Strain details will appear after HealthKit records movement, workouts, or heart-rate samples for this day.")
        }
        return Array(values.prefix(4)).map { StrainInsight(text: $0) }
    }

    private func dateAwareCopy(_ text: String) -> String {
        guard !isViewingToday else { return text }
        return text
            .replacingOccurrences(of: "today's", with: "that day's")
            .replacingOccurrences(of: "today", with: "that day")
            .replacingOccurrences(of: "Today", with: "That day")
    }

    var sourceText: String {
        let sources = summary.sourceBadges.map(\.displayName)
        return sources.isEmpty ? "HealthKit" : sources.joined(separator: ", ")
    }

    private var chartRange: DateInterval {
        let start = summary.queryStart ?? calendar.startOfDay(for: date)
        let fallbackDay = calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86_400)
        let end = summary.queryEnd ?? fallbackDay.end
        return DateInterval(start: start, end: max(end, start.addingTimeInterval(60)))
    }

    var needsDetailedRefresh: Bool {
        guard canRequestHealthData else { return false }
        if !Self.hasData(summary) { return true }
        return summary.analyzedSampleCount == 0 &&
            summary.heartRatePoints.isEmpty &&
            summary.workoutBands.isEmpty &&
            summary.timeline.isEmpty
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
        PulsarSyncDebugLogger.log("Strain details refresh started date=\(date) reason=\(showBanner ? "manual" : "detailHydration")")
        if showBanner {
            PulsarSyncBannerCenter.shared.showSyncing()
        }
        if !Self.hasData(summary) {
            state = .loading
        }
        do {
            let refreshedAt = Date()
            let loaded = try await provider.strainSummary(profile: profile, date: date, calendar: calendar, refreshedAt: refreshedAt)
            if Self.hasData(loaded) || !Self.hasData(summary) {
                summary = loaded
            }
            state = Self.state(for: summary, canRequestHealthData: true)
            if showBanner {
                PulsarSyncBannerCenter.shared.showSuccess()
            }
        } catch {
            state = Self.hasData(summary) ? .loaded : .error("Strain data could not be refreshed.")
            if showBanner {
                PulsarSyncBannerCenter.shared.showFailure()
            }
        }
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

    private static func state(for summary: StrainSummary, canRequestHealthData: Bool) -> StrainDetailsState {
        guard canRequestHealthData else { return .permissionRequired }
        return hasData(summary) ? .loaded : .noData
    }

    private static func hasData(_ summary: StrainSummary) -> Bool {
        summary.lastUpdated != nil || summary.confidence != .missing || summary.analyzedSampleCount > 0 || !summary.workouts.isEmpty || summary.steps > 0 || summary.exerciseMinutes > 0 || (summary.activeEnergyKilocalories ?? 0) > 0 || summary.score > 0
    }

    private func bpmText(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded())) bpm" } ?? "Not enough data"
    }

    private func heartLoadReferences(min minBPM: Double, max maxBPM: Double) -> [StrainHeartLoadReference] {
        let labels = ["Low", "Light", "Moderate", "Hard", "Peak"]
        return labels.enumerated().map { index, label in
            let fraction = Double(index) / Double(max(1, labels.count - 1))
            return StrainHeartLoadReference(title: label, bpm: minBPM + (maxBPM - minBPM) * fraction)
        }
    }

    private func timelineMarkers(for range: DateInterval) -> [StrainTimelineMarker] {
        let markerHours = [0, 6, 12, 18]
        var markers = markerHours.compactMap { hour -> StrainTimelineMarker? in
            guard let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: range.start), range.contains(date) else { return nil }
            return StrainTimelineMarker(date: date, label: "\(hour)")
        }
        let endLabel = calendar.isDateInToday(range.start) ? "Now" : "24"
        markers.append(StrainTimelineMarker(date: range.end, label: endLabel))
        return markers.sorted { $0.date < $1.date }
    }

    private func heartLoadCallouts(from summary: StrainSummary) -> [StrainHeartLoadCallout] {
        var callouts: [StrainHeartLoadCallout] = []
        if let peak = summary.peakHeartRate {
            callouts.append(StrainHeartLoadCallout(title: "Peak HR", value: "\(Int(peak.rounded())) bpm", symbol: "waveform.path.ecg"))
        }
        if let average = summary.averageActiveHeartRate {
            callouts.append(StrainHeartLoadCallout(title: "Avg active HR", value: "\(Int(average.rounded())) bpm", symbol: "heart.fill"))
        }
        if let hardest = summary.workoutBands.max(by: { ($0.peakHeartRate ?? $0.averageHeartRate ?? 0) < ($1.peakHeartRate ?? $1.averageHeartRate ?? 0) }) {
            callouts.append(StrainHeartLoadCallout(title: "Hardest effort", value: "\(timeOfDayLabel(for: hardest.startDate)) \(hardest.workoutType.lowercased())", symbol: "bolt.fill"))
        } else if let longest = summary.workoutBands.max(by: { $0.duration < $1.duration }) {
            callouts.append(StrainHeartLoadCallout(title: "Longest session", value: Self.durationText(minutes: longest.duration / 60), symbol: "timer"))
        }
        return Array(callouts.prefix(3))
    }

    private func timeOfDayLabel(for date: Date) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<22: return "Evening"
        default: return "Late"
        }
    }
}
