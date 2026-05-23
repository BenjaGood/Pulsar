//
//  HealthDataSourceRouter.swift
//  Pulsar
//

import Foundation

enum SourceSelectionPolicy: Equatable {
    case currentOnly
    case currentWithFallback
}

enum PulsarSourceRouterLogger {
    static func log(_ message: String) {
        #if DEBUG
        print("[PulsarSourceRouter] \(message)")
        #endif
    }
}

struct DataFreshnessPolicy: Equatable {
    var staleAfter: TimeInterval

    static let daily = DataFreshnessPolicy(staleAfter: 36 * 60 * 60)
}

struct HealthMetricRecord: Identifiable, Equatable {
    var id: String
    var metricType: MeasurementHealthMetricType
    var value: Double
    var unit: String
    var startDate: Date
    var endDate: Date?
    var sourceProvider: HealthSourceID
    var sourceDeviceName: String?
    var category: HealthSourcePriorityCategory
    var ingestedAt: Date
    var externalIdentifier: String?
    var originalPayloadIdentifier: String?
    var confidence: ConfidenceGrade?
    var freshnessPolicy: DataFreshnessPolicy?

    var source: HealthSourceID {
        sourceProvider
    }
}

struct MetricSourceAvailability: Codable, Equatable, Identifiable {
    var id: HealthSourceID { source }
    var source: HealthSourceID
    var sampleCount: Int
    var lastSampleDate: Date?
    var isConnected: Bool
    var reason: String?
}

struct MetricSourceResolution: Codable, Equatable, Identifiable {
    var id: String {
        "\(category.rawValue)-\(metricType.rawValue)"
    }

    var metricType: MeasurementHealthMetricType
    var metricTitle: String
    var category: HealthSourcePriorityCategory
    var currentSource: HealthSourceID
    var displayedRecordSource: HealthSourceID?
    var fallbackUsed: Bool
    var fallbackReason: String? = nil
    var lastAvailableSampleDate: Date?
    var sourceDataAge: TimeInterval?
    var sourceAvailabilityByProvider: [MetricSourceAvailability]
    var selectedRecordIds: [String]

    var hasActiveData: Bool {
        displayedRecordSource != nil
    }

    init(
        metricType: MeasurementHealthMetricType,
        metricTitle: String,
        category: HealthSourcePriorityCategory,
        currentSource: HealthSourceID,
        displayedRecordSource: HealthSourceID?,
        fallbackUsed: Bool,
        fallbackReason: String? = nil,
        lastAvailableSampleDate: Date?,
        sourceDataAge: TimeInterval?,
        sourceAvailabilityByProvider: [MetricSourceAvailability],
        selectedRecordIds: [String]
    ) {
        self.metricType = metricType
        self.metricTitle = metricTitle
        self.category = category
        self.currentSource = currentSource
        self.displayedRecordSource = displayedRecordSource
        self.fallbackUsed = fallbackUsed
        self.fallbackReason = fallbackReason
        self.lastAvailableSampleDate = lastAvailableSampleDate
        self.sourceDataAge = sourceDataAge
        self.sourceAvailabilityByProvider = sourceAvailabilityByProvider
        self.selectedRecordIds = selectedRecordIds
    }

    private enum CodingKeys: String, CodingKey {
        case metricType
        case metricTitle
        case category
        case currentSource
        case displayedRecordSource
        case legacySource = "preferredSource"
        case legacyActiveSource = "activeSource"
        case legacyRecordSource = "actualRecordSource"
        case fallbackUsed
        case fallbackReason
        case lastAvailableSampleDate
        case sourceDataAge
        case sourceAvailabilityByProvider
        case selectedRecordIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metricType = try container.decode(MeasurementHealthMetricType.self, forKey: .metricType)
        metricTitle = try container.decode(String.self, forKey: .metricTitle)
        category = try container.decode(HealthSourcePriorityCategory.self, forKey: .category)
        currentSource = try container.decodeIfPresent(HealthSourceID.self, forKey: .currentSource)
            ?? container.decode(HealthSourceID.self, forKey: .legacySource)
        displayedRecordSource = try container.decodeIfPresent(HealthSourceID.self, forKey: .displayedRecordSource)
            ?? container.decodeIfPresent(HealthSourceID.self, forKey: .legacyRecordSource)
            ?? container.decodeIfPresent(HealthSourceID.self, forKey: .legacyActiveSource)
        fallbackUsed = try container.decode(Bool.self, forKey: .fallbackUsed)
        fallbackReason = try container.decodeIfPresent(String.self, forKey: .fallbackReason)
        lastAvailableSampleDate = try container.decodeIfPresent(Date.self, forKey: .lastAvailableSampleDate)
        sourceDataAge = try container.decodeIfPresent(TimeInterval.self, forKey: .sourceDataAge)
        sourceAvailabilityByProvider = try container.decode([MetricSourceAvailability].self, forKey: .sourceAvailabilityByProvider)
        selectedRecordIds = try container.decode([String].self, forKey: .selectedRecordIds)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metricType, forKey: .metricType)
        try container.encode(metricTitle, forKey: .metricTitle)
        try container.encode(category, forKey: .category)
        try container.encode(currentSource, forKey: .currentSource)
        try container.encodeIfPresent(displayedRecordSource, forKey: .displayedRecordSource)
        try container.encode(fallbackUsed, forKey: .fallbackUsed)
        try container.encodeIfPresent(fallbackReason, forKey: .fallbackReason)
        try container.encodeIfPresent(lastAvailableSampleDate, forKey: .lastAvailableSampleDate)
        try container.encodeIfPresent(sourceDataAge, forKey: .sourceDataAge)
        try container.encode(sourceAvailabilityByProvider, forKey: .sourceAvailabilityByProvider)
        try container.encode(selectedRecordIds, forKey: .selectedRecordIds)
    }
}

struct SourceRoutingDecision: Equatable {
    var category: HealthSourcePriorityCategory
    var currentSource: HealthSourceID
    var displayedSource: HealthSourceID?
    var isFallback: Bool
    var lastDataAt: Date?
    var fallbackEnabled: Bool
    var fallbackReason: String?

    var hasActiveData: Bool {
        displayedSource != nil
    }
}

struct RoutedHealthDashboard: Equatable {
    var dashboard: HomeDashboard
    var decisions: [HealthSourcePriorityCategory: SourceRoutingDecision]
}

final class UnifiedHealthTimelineStore {
    private(set) var records: [HealthMetricRecord] = []

    func upsert(_ newRecords: [HealthMetricRecord]) {
        for record in newRecords {
            if let index = records.firstIndex(where: { $0.id == record.id }) {
                records[index] = record
            } else {
                records.append(record)
            }
        }
        records.sort { $0.startDate < $1.startDate }
    }

    func records(
        category: HealthSourcePriorityCategory,
        source: HealthSourceID? = nil,
        in interval: DateInterval? = nil
    ) -> [HealthMetricRecord] {
        records.filter { record in
            guard record.category == category else { return false }
            if let source, record.source != source { return false }
            if let interval {
                let endDate = record.endDate ?? record.startDate
                return interval.intersects(DateInterval(start: record.startDate, end: max(endDate, record.startDate)))
            }
            return true
        }
    }
}

struct HealthDataSourceRouter {
    var priorityStore: HealthSourcePriorityStore
    var calendar: Calendar
    var freshnessPolicy: DataFreshnessPolicy = .daily

    private enum SleepRecoveryComponent {
        case sleep
        case recovery
    }

    func routedDashboard(
        profile: UserProfile,
        date: Date,
        generatedAt: Date,
        sourceDashboards: [HealthSourceID: HomeDashboard],
        snapshots: [HealthSourceSnapshot],
        now: Date = Date()
    ) -> RoutedHealthDashboard {
        var decisions = Dictionary(uniqueKeysWithValues: HealthSourcePriorityCategory.allCases.map { category in
            (category, decision(for: category, sourceDashboards: sourceDashboards, snapshots: snapshots, now: now))
        })
        decisions[.activitySteps] = strainComponentDecision(for: .activitySteps, sourceDashboards: sourceDashboards, snapshots: snapshots, now: now)
        decisions[.workoutsActivity] = strainComponentDecision(for: .workoutsActivity, sourceDashboards: sourceDashboards, snapshots: snapshots, now: now)
        decisions[.stressResilience] = stressDecision(sourceDashboards: sourceDashboards, snapshots: snapshots, now: now)
        let sleepDecision = sleepRecoveryDecision(component: .sleep, sourceDashboards: sourceDashboards, snapshots: snapshots)
        let recoveryDecision = sleepRecoveryDecision(component: .recovery, sourceDashboards: sourceDashboards, snapshots: snapshots)
        let emptyDashboard = HomeDashboard(
            profile: profile,
            sleep: .missing.withNoRecentSourceDataMessage(for: sleepDecision),
            recovery: .missing.withNoRecentSourceDataMessage(for: recoveryDecision),
            strain: .missing.withNoRecentSourceDataMessage(for: decisions[.activitySteps]),
            stress: .missing.withNoRecentSourceDataMessage(for: decisions[.stressResilience]),
            healthMonitor: .missing(date: date),
            generatedAt: generatedAt,
            usingSampleData: false
        )

        var routed = emptyDashboard
        if let source = sleepDecision.displayedSource,
           let dashboard = sourceDashboards[source] {
            routed.sleep = dashboard.sleep
        }
        if let source = recoveryDecision.displayedSource,
           let dashboard = sourceDashboards[source] {
            routed.recovery = dashboard.recovery
        }

        let activitySource = decisions[.activitySteps]?.displayedSource
        let workoutSource = decisions[.workoutsActivity]?.displayedSource
        routed.strain = combinedStrain(
            activity: activitySource.flatMap { sourceDashboards[$0]?.strain },
            workouts: workoutSource.flatMap { sourceDashboards[$0]?.strain },
            activityDecision: decisions[.activitySteps],
            workoutDecision: decisions[.workoutsActivity]
        )

        if let source = decisions[.stressResilience]?.displayedSource,
           var stress = sourceDashboards[source]?.stress {
            for supplemental in sourceDashboards
                .filter({ $0.key != source })
                .map(\.value.stress)
                .filter(\.hasSupplementalPhysiologyData) {
                stress = stress.mergedWithSupplementalStress(supplemental)
            }
            routed.stress = stress
        }

        routed.healthMonitor = routedHealthMonitor(
            date: date,
            sourceDashboards: sourceDashboards,
            decisions: decisions,
            snapshots: snapshots,
            now: now
        )
        routed.generatedAt = max(generatedAt, sourceDashboards.values.map(\.generatedAt).max() ?? generatedAt)
        return RoutedHealthDashboard(dashboard: routed, decisions: decisions)
    }

    private func sleepRecoveryDecision(
        component: SleepRecoveryComponent,
        sourceDashboards: [HealthSourceID: HomeDashboard],
        snapshots: [HealthSourceSnapshot]
    ) -> SourceRoutingDecision {
        let category = HealthSourcePriorityCategory.sleepRecovery
        let preference = priorityStore.preference(for: category)
        let currentSource = preference.currentSource

        if hasSleepRecoveryData(component, source: currentSource, sourceDashboards: sourceDashboards, snapshots: snapshots) {
            return SourceRoutingDecision(
                category: category,
                currentSource: currentSource,
                displayedSource: currentSource,
                isFallback: false,
                lastDataAt: lastSleepRecoveryDataAt(component, in: sourceDashboards[currentSource]),
                fallbackEnabled: preference.fallbackEnabled
            )
        }

        guard preference.fallbackEnabled else {
            return SourceRoutingDecision(
                category: category,
                currentSource: currentSource,
                displayedSource: nil,
                isFallback: false,
                lastDataAt: lastSleepRecoveryDataAt(component, in: sourceDashboards[currentSource]),
                fallbackEnabled: false
            )
        }

        for fallbackSource in category.fallbackOrder where fallbackSource != currentSource {
            if hasSleepRecoveryData(component, source: fallbackSource, sourceDashboards: sourceDashboards, snapshots: snapshots) {
                return SourceRoutingDecision(
                    category: category,
                    currentSource: currentSource,
                    displayedSource: fallbackSource,
                    isFallback: true,
                    lastDataAt: lastSleepRecoveryDataAt(component, in: sourceDashboards[fallbackSource]),
                    fallbackEnabled: true
                )
            }
        }

        return SourceRoutingDecision(
            category: category,
            currentSource: currentSource,
            displayedSource: nil,
            isFallback: false,
            lastDataAt: lastSleepRecoveryDataAt(component, in: sourceDashboards[currentSource]),
            fallbackEnabled: true
        )
    }

    private func hasSleepRecoveryData(
        _ component: SleepRecoveryComponent,
        source: HealthSourceID,
        sourceDashboards: [HealthSourceID: HomeDashboard],
        snapshots: [HealthSourceSnapshot]
    ) -> Bool {
        guard let dashboard = sourceDashboards[source] else { return false }
        if let snapshot = snapshots.first(where: { $0.sourceID == source }),
           !snapshot.connectionState.canProvideData,
           lastSleepRecoveryDataAt(component, in: dashboard) == nil {
            return false
        }
        switch component {
        case .sleep:
            return dashboard.sleep.hasRoutedData
        case .recovery:
            return dashboard.recovery.hasRoutedData
        }
    }

    private func lastSleepRecoveryDataAt(_ component: SleepRecoveryComponent, in dashboard: HomeDashboard?) -> Date? {
        guard let dashboard else { return nil }
        switch component {
        case .sleep:
            return dashboard.sleep.lastUpdated
        case .recovery:
            return dashboard.recovery.lastUpdated
        }
    }

    private func decision(
        for category: HealthSourcePriorityCategory,
        sourceDashboards: [HealthSourceID: HomeDashboard],
        snapshots: [HealthSourceSnapshot],
        now: Date
    ) -> SourceRoutingDecision {
        let preference = priorityStore.preference(for: category)
        let currentSource = preference.currentSource
        if let representativeKind = representativeHealthMetricKind(for: category) {
            let resolution = resolveSource(
                metricType: representativeKind.measurementMetricType,
                category: category,
                healthMetricKind: representativeKind,
                sourceDashboards: sourceDashboards,
                snapshots: snapshots,
                now: now
            )
            return SourceRoutingDecision(
                category: category,
                currentSource: currentSource,
                displayedSource: resolution.displayedRecordSource,
                isFallback: resolution.fallbackUsed,
                lastDataAt: resolution.lastAvailableSampleDate,
                fallbackEnabled: preference.fallbackEnabled,
                fallbackReason: resolution.fallbackReason
            )
        }

        if hasData(for: category, source: currentSource, sourceDashboards: sourceDashboards, snapshots: snapshots, now: now) {
            return SourceRoutingDecision(
                category: category,
                currentSource: currentSource,
                displayedSource: currentSource,
                isFallback: false,
                lastDataAt: lastDataAt(for: category, in: sourceDashboards[currentSource]),
                fallbackEnabled: preference.fallbackEnabled
            )
        }

        guard preference.fallbackEnabled else {
            return SourceRoutingDecision(
                category: category,
                currentSource: currentSource,
                displayedSource: nil,
                isFallback: false,
                lastDataAt: lastDataAt(for: category, in: sourceDashboards[currentSource]),
                fallbackEnabled: false
            )
        }

        for fallbackSource in category.fallbackOrder where fallbackSource != currentSource {
            if hasData(for: category, source: fallbackSource, sourceDashboards: sourceDashboards, snapshots: snapshots, now: now) {
                return SourceRoutingDecision(
                    category: category,
                    currentSource: currentSource,
                    displayedSource: fallbackSource,
                    isFallback: true,
                    lastDataAt: lastDataAt(for: category, in: sourceDashboards[fallbackSource]),
                    fallbackEnabled: true
                )
            }
        }

        return SourceRoutingDecision(
            category: category,
            currentSource: currentSource,
            displayedSource: nil,
            isFallback: false,
            lastDataAt: lastDataAt(for: category, in: sourceDashboards[currentSource]),
            fallbackEnabled: true
        )
    }

    private func strainComponentDecision(
        for category: HealthSourcePriorityCategory,
        sourceDashboards: [HealthSourceID: HomeDashboard],
        snapshots: [HealthSourceSnapshot],
        now: Date
    ) -> SourceRoutingDecision {
        let preference = priorityStore.preference(for: category)
        let currentSource = preference.currentSource
        let preferredOrder: [HealthSourceID] = [.appleWatch, .iPhone, .ouraRing, .manual]

        if let displayedSource = preferredOrder.first(where: {
            hasData(for: category, source: $0, sourceDashboards: sourceDashboards, snapshots: snapshots, now: now)
        }) {
            let reason = displayedSource == currentSource ? nil : "Pulsar uses \(displayedSource.routingDisplayName) for live strain because it has the strongest activity signal."
            return SourceRoutingDecision(
                category: category,
                currentSource: currentSource,
                displayedSource: displayedSource,
                isFallback: displayedSource != currentSource,
                lastDataAt: lastDataAt(for: category, in: sourceDashboards[displayedSource]),
                fallbackEnabled: preference.fallbackEnabled,
                fallbackReason: reason
            )
        }

        return SourceRoutingDecision(
            category: category,
            currentSource: currentSource,
            displayedSource: nil,
            isFallback: false,
            lastDataAt: lastDataAt(for: category, in: sourceDashboards[currentSource]),
            fallbackEnabled: preference.fallbackEnabled
        )
    }

    private func stressDecision(
        sourceDashboards: [HealthSourceID: HomeDashboard],
        snapshots: [HealthSourceSnapshot],
        now: Date
    ) -> SourceRoutingDecision {
        let category = HealthSourcePriorityCategory.stressResilience
        let preference = priorityStore.preference(for: category)
        let currentSource = preference.currentSource
        let preferredOrder: [HealthSourceID] = [.appleWatch, .iPhone, .ouraRing, .manual]

        if let displayedSource = preferredOrder.first(where: {
            hasData(for: category, source: $0, sourceDashboards: sourceDashboards, snapshots: snapshots, now: now)
        }) {
            let reason = displayedSource == currentSource ? nil : "Pulsar uses \(displayedSource.routingDisplayName) for live stress because it has the strongest recent physiology signal."
            return SourceRoutingDecision(
                category: category,
                currentSource: currentSource,
                displayedSource: displayedSource,
                isFallback: displayedSource != currentSource,
                lastDataAt: lastDataAt(for: category, in: sourceDashboards[displayedSource]),
                fallbackEnabled: preference.fallbackEnabled,
                fallbackReason: reason
            )
        }

        return SourceRoutingDecision(
            category: category,
            currentSource: currentSource,
            displayedSource: nil,
            isFallback: false,
            lastDataAt: lastDataAt(for: category, in: sourceDashboards[currentSource]),
            fallbackEnabled: preference.fallbackEnabled
        )
    }

    private func hasData(
        for category: HealthSourcePriorityCategory,
        source: HealthSourceID,
        sourceDashboards: [HealthSourceID: HomeDashboard],
        snapshots: [HealthSourceSnapshot],
        now: Date
    ) -> Bool {
        guard let dashboard = sourceDashboards[source] else { return false }
        if let snapshot = snapshots.first(where: { $0.sourceID == source }),
           !snapshot.connectionState.canProvideData,
           lastDataAt(for: category, in: dashboard) == nil {
            return false
        }
        switch category {
        case .sleepRecovery:
            return dashboard.sleep.hasRoutedData || dashboard.recovery.hasRoutedData
        case .workoutsActivity:
            return dashboard.strain.hasWorkoutData
        case .activitySteps:
            return dashboard.strain.hasActivityData
        case .heartMetrics:
            return dashboard.healthMonitor.metric(.hrv).hasData ||
                dashboard.healthMonitor.metric(.restingHeartRate).hasData ||
                dashboard.recovery.hrvSDNN != nil ||
                dashboard.recovery.restingHeartRate != nil
        case .temperatureCycle:
            return dashboard.healthMonitor.metric(.wristTemperature).hasData ||
                dashboard.recovery.wristTemperatureDeviation != nil
        case .stressResilience:
            return dashboard.stress.hasRoutedData
        case .manualEntries:
            return source == .manual && sourceDashboards[source] != nil
        }
    }

    private func representativeHealthMetricKind(for category: HealthSourcePriorityCategory) -> HealthMetricKind? {
        switch category {
        case .heartMetrics:
            return .restingHeartRate
        case .temperatureCycle:
            return .wristTemperature
        case .sleepRecovery, .workoutsActivity, .activitySteps, .stressResilience, .manualEntries:
            return nil
        }
    }

    private func lastDataAt(for category: HealthSourcePriorityCategory, in dashboard: HomeDashboard?) -> Date? {
        guard let dashboard else { return nil }
        switch category {
        case .sleepRecovery:
            return [dashboard.sleep.lastUpdated, dashboard.recovery.lastUpdated].compactMap { $0 }.max()
        case .workoutsActivity, .activitySteps:
            return dashboard.strain.lastUpdated ?? dashboard.strain.queryEnd
        case .heartMetrics:
            return [
                dashboard.healthMonitor.metric(.hrv).lastUpdated,
                dashboard.healthMonitor.metric(.restingHeartRate).lastUpdated,
                dashboard.recovery.lastUpdated
            ].compactMap { $0 }.max()
        case .temperatureCycle:
            return [
                dashboard.healthMonitor.metric(.wristTemperature).lastUpdated,
                dashboard.recovery.lastUpdated
            ].compactMap { $0 }.max()
        case .stressResilience:
            return dashboard.stress.lastUpdated ?? dashboard.stress.queryEnd
        case .manualEntries:
            return nil
        }
    }

    private func combinedStrain(
        activity: StrainSummary?,
        workouts: StrainSummary?,
        activityDecision: SourceRoutingDecision?,
        workoutDecision: SourceRoutingDecision?
    ) -> StrainSummary {
        guard activity?.hasActivityData == true || workouts?.hasWorkoutData == true else {
            return StrainSummary.missing.withNoRecentSourceDataMessage(for: activityDecision)
        }

        var combined = activity ?? workouts ?? .missing
        if let activity {
            combined.date = activity.date
            combined.movementLoad = activity.movementLoad
            combined.steps = activity.steps
            combined.activeEnergyKilocalories = activity.activeEnergyKilocalories
            combined.basalEnergyKilocalories = activity.basalEnergyKilocalories
            combined.exerciseMinutes = activity.exerciseMinutes
            combined.sourceBadges = activity.sourceBadges
            combined.lastUpdated = activity.lastUpdated
            combined.queryStart = activity.queryStart
            combined.queryEnd = activity.queryEnd
            combined.analyzedSampleCount = activity.analyzedSampleCount
        }

        if let workouts, workouts.hasWorkoutData {
            combined.workoutLoad = workouts.workoutLoad
            combined.workoutMinutes = workouts.workoutMinutes
            combined.workouts = workouts.workouts
            combined.workoutBands = workouts.workoutBands
            combined.ledger = workouts.ledger
            combined.timeInZones = workouts.timeInZones
            combined.averageActiveHeartRate = workouts.averageActiveHeartRate ?? combined.averageActiveHeartRate
            combined.peakHeartRate = workouts.peakHeartRate ?? combined.peakHeartRate
            combined.heartRatePoints = workouts.heartRatePoints
            combined.timeline = mergedTimeline(activity: activity?.timeline ?? combined.timeline, workouts: workouts.timeline)
            combined.sourceBadges = SourceResolver.uniqueSourceBadges(combined.sourceBadges + workouts.sourceBadges)
            combined.lastUpdated = [combined.lastUpdated, workouts.lastUpdated].compactMap { $0 }.max()
        }

        combined.rawLoad = max(0, combined.movementLoad + combined.workoutLoad)
        combined.score = routedCurrentStrainScore(for: combined)
        combined.confidence = combined.sourceBadges.isEmpty ? .missing : maxConfidence(activity?.confidence, workouts?.confidence)
        combined.notes = sourceRoutingNotes(activityDecision: activityDecision, workoutDecision: workoutDecision)
        return combined
    }

    private func routedCurrentStrainScore(for summary: StrainSummary) -> Int {
        let rawLoad = max(0, summary.rawLoad)
        var progressiveScore = 100 * (1 - exp(-rawLoad / 74))
        if progressiveScore > 70 {
            progressiveScore = 70 + pow((progressiveScore - 70) / 30, 1.24) * 30
        }
        if progressiveScore > 85 {
            progressiveScore = 85 + pow((progressiveScore - 85) / 15, 1.42) * 15
        }

        let hasWorkout = summary.workoutMinutes >= 5 || !summary.workouts.isEmpty || !summary.ledger.isEmpty
        let steps = max(0, Double(summary.steps))
        let exerciseMinutes = max(0, summary.exerciseMinutes)
        let activeEnergy = max(0, summary.activeEnergyKilocalories ?? 0)
        let sustainedElevatedHeartRate = summary.timeInZones.contains { zone in
            (zone.zone >= 4 && zone.minutes >= 8) || (zone.zone == 3 && zone.minutes >= 25)
        } || (summary.averageActiveHeartRate ?? 0) >= 115 || (summary.peakHeartRate ?? 0) >= 140
        var cap = 100.0

        if !hasWorkout {
            if exerciseMinutes < 10 && steps < 3_000 {
                cap = min(cap, (activeEnergy >= 180 || sustainedElevatedHeartRate) ? 25 : 18)
            } else if exerciseMinutes < 20 && steps < 6_000 {
                cap = min(cap, (activeEnergy >= 350 || sustainedElevatedHeartRate) ? 35 : 30)
            } else if exerciseMinutes < 30 && steps < 9_000 && !sustainedElevatedHeartRate {
                cap = min(cap, 45)
            }
        }

        let strongExertion = (hasWorkout && (summary.workoutMinutes >= 45 || summary.workoutLoad >= 56 || activeEnergy >= 620)) ||
            activeEnergy >= 800 ||
            exerciseMinutes >= 65 ||
            sustainedElevatedHeartRate ||
            summary.movementLoad >= 38
        if !strongExertion {
            cap = min(cap, 70)
        }

        let veryHardExertion = (hasWorkout && summary.workoutMinutes >= 75 && (summary.workoutLoad >= 78 || activeEnergy >= 850)) ||
            summary.workouts.count >= 2 && summary.workoutMinutes >= 70 ||
            activeEnergy >= 1_050 ||
            exerciseMinutes >= 105
        if !veryHardExertion {
            cap = min(cap, 88)
        }

        return Int(min(100, max(0, min(progressiveScore, cap))).rounded())
    }

    private func mergedTimeline(activity: [StrainTimelineInterval], workouts: [StrainTimelineInterval]) -> [StrainTimelineInterval] {
        let activityIntervals = activity.filter { !$0.isWorkout }
        let workoutIntervals = workouts.filter(\.isWorkout)
        return (activityIntervals + workoutIntervals).sorted { $0.startDate < $1.startDate }
    }

    private func routedHealthMonitor(
        date: Date,
        sourceDashboards: [HealthSourceID: HomeDashboard],
        decisions: [HealthSourcePriorityCategory: SourceRoutingDecision],
        snapshots: [HealthSourceSnapshot],
        now: Date
    ) -> HealthMonitorSummary {
        let metrics = HealthMetricKind.allCases.map { kind -> HealthMetricModel in
            let category = sourceCategory(for: kind)
            let resolution = resolveSource(
                metricType: kind.measurementMetricType,
                category: category,
                dateRange: dayInterval(containing: date),
                healthMetricKind: kind,
                sourceDashboards: sourceDashboards,
                snapshots: snapshots,
                now: now
            )
            let validatedResolution = validated(resolution)
            guard let source = validatedResolution.displayedRecordSource,
                  let metric = sourceDashboards[source]?.healthMonitor.metric(kind) else {
                return .noData(
                    kind: kind,
                    comparisonText: noRecentDataText(for: decisions[category], resolution: validatedResolution),
                    lastUpdated: validatedResolution.lastAvailableSampleDate,
                    sourceResolution: validatedResolution
                )
            }
            guard metricSourceMatches(metric, source: source) else {
                if !validatedResolution.fallbackUsed {
                    PulsarSourceRouterLogger.log("Invalid source resolution: displayed source does not match current source without fallback")
                }
                var correctedResolution = validatedResolution
                correctedResolution.displayedRecordSource = nil
                correctedResolution.fallbackReason = "No recent \(validatedResolution.currentSource.routingDisplayName) data available."
                correctedResolution.selectedRecordIds = []
                return .noData(
                    kind: kind,
                    comparisonText: noRecentDataText(for: decisions[category], resolution: correctedResolution),
                    lastUpdated: correctedResolution.lastAvailableSampleDate,
                    sourceResolution: correctedResolution
                )
            }
            var routedMetric = metric
            routedMetric.sourceResolution = validatedResolution
            return routedMetric
        }

        return HealthMonitorSummary(
            date: date,
            metrics: metrics,
            lastUpdated: metrics.compactMap(\.lastUpdated).max(),
            baselineWindowDays: sourceDashboards.values.map(\.healthMonitor.baselineWindowDays).max() ?? 0,
            sourceBadges: SourceResolver.uniqueSourceBadges(metrics.flatMap(\.sourceBadges))
        )
    }

    func resolveSource(
        metricType: MeasurementHealthMetricType,
        category: HealthSourcePriorityCategory,
        dateRange: DateInterval? = nil,
        healthMetricKind: HealthMetricKind? = nil,
        sourceDashboards: [HealthSourceID: HomeDashboard],
        snapshots: [HealthSourceSnapshot],
        now: Date = Date()
    ) -> MetricSourceResolution {
        let preference = priorityStore.preference(for: category)
        let currentSource = preference.currentSource
        PulsarSourceRouterLogger.log("resolve metric=\(metricType.rawValue) category=\(category.rawValue) current=\(currentSource.sourceRouterLogName) fallbackEnabled=\(preference.fallbackEnabled)")
        let snapshotsBySource = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.sourceID, $0) })
        let availability = HealthSourceID.allCases.map { source in
            sourceAvailability(
                source: source,
                metricType: metricType,
                category: category,
                healthMetricKind: healthMetricKind,
                dashboard: sourceDashboards[source],
                snapshot: snapshotsBySource[source]
            )
        }
        availability.forEach { sourceAvailability in
            let reason = sourceAvailability.reason.map { " reason=\($0)" } ?? ""
            let last = sourceAvailability.lastSampleDate.map { " last=\($0)" } ?? ""
            PulsarSourceRouterLogger.log("source query metric=\(metricType.rawValue) source=\(sourceAvailability.source.sourceRouterLogName) samples=\(sourceAvailability.sampleCount)\(last)\(reason)")
        }
        let availabilityBySource = Dictionary(uniqueKeysWithValues: availability.map { ($0.source, $0) })

        if let currentAvailability = availabilityBySource[currentSource],
           currentAvailability.sampleCount > 0 {
            PulsarSourceRouterLogger.log("resolved metric=\(metricType.rawValue) displayedSource=\(currentSource.sourceRouterLogName) fallback=false samples=\(currentAvailability.sampleCount)")
            return MetricSourceResolution(
                metricType: metricType,
                metricTitle: healthMetricKind?.title ?? metricType.label,
                category: category,
                currentSource: currentSource,
                displayedRecordSource: currentSource,
                fallbackUsed: false,
                fallbackReason: nil,
                lastAvailableSampleDate: currentAvailability.lastSampleDate,
                sourceDataAge: currentAvailability.lastSampleDate.map { now.timeIntervalSince($0) },
                sourceAvailabilityByProvider: availability,
                selectedRecordIds: selectedRecordIds(for: metricType, healthMetricKind: healthMetricKind, source: currentSource, dateRange: dateRange)
            )
        }

        guard preference.fallbackEnabled else {
            let currentReason = availabilityBySource[currentSource]?.reason
            let reason = currentReason ?? noValidSampleReason(source: currentSource, metricType: metricType, healthMetricKind: healthMetricKind)
            PulsarSourceRouterLogger.log("noData metric=\(metricType.rawValue) source=\(currentSource.sourceRouterLogName) reason=\(reason)")
            return MetricSourceResolution(
                metricType: metricType,
                metricTitle: healthMetricKind?.title ?? metricType.label,
                category: category,
                currentSource: currentSource,
                displayedRecordSource: nil,
                fallbackUsed: false,
                fallbackReason: reason,
                lastAvailableSampleDate: currentAvailabilityDate(currentSource: currentSource, availabilityBySource: availabilityBySource),
                sourceDataAge: currentAvailabilityDate(currentSource: currentSource, availabilityBySource: availabilityBySource).map { now.timeIntervalSince($0) },
                sourceAvailabilityByProvider: availability,
                selectedRecordIds: []
            )
        }

        for fallbackSource in category.fallbackOrder where fallbackSource != currentSource {
            guard let fallbackAvailability = availabilityBySource[fallbackSource],
                  fallbackAvailability.sampleCount > 0 else { continue }
            let reason = availabilityBySource[currentSource]?.reason ?? noValidSampleReason(source: currentSource, metricType: metricType, healthMetricKind: healthMetricKind)
            PulsarSourceRouterLogger.log("resolved metric=\(metricType.rawValue) displayedSource=\(fallbackSource.sourceRouterLogName) fallback=true reason=\(reason)")
            return MetricSourceResolution(
                metricType: metricType,
                metricTitle: healthMetricKind?.title ?? metricType.label,
                category: category,
                currentSource: currentSource,
                displayedRecordSource: fallbackSource,
                fallbackUsed: true,
                fallbackReason: reason,
                lastAvailableSampleDate: fallbackAvailability.lastSampleDate,
                sourceDataAge: fallbackAvailability.lastSampleDate.map { now.timeIntervalSince($0) },
                sourceAvailabilityByProvider: availability,
                selectedRecordIds: selectedRecordIds(for: metricType, healthMetricKind: healthMetricKind, source: fallbackSource, dateRange: dateRange)
            )
        }

        let currentReason = availabilityBySource[currentSource]?.reason
        let reason = currentReason ?? "No connected source has a valid \(healthMetricKind?.title ?? metricType.label) sample for the selected day."
        PulsarSourceRouterLogger.log("noData metric=\(metricType.rawValue) source=\(currentSource.sourceRouterLogName) reason=\(reason)")
        return MetricSourceResolution(
            metricType: metricType,
            metricTitle: healthMetricKind?.title ?? metricType.label,
            category: category,
            currentSource: currentSource,
            displayedRecordSource: nil,
            fallbackUsed: false,
            fallbackReason: reason,
            lastAvailableSampleDate: availability.compactMap(\.lastSampleDate).max(),
            sourceDataAge: availability.compactMap(\.lastSampleDate).max().map { now.timeIntervalSince($0) },
            sourceAvailabilityByProvider: availability,
            selectedRecordIds: []
        )
    }

    private func sourceAvailability(
        source: HealthSourceID,
        metricType: MeasurementHealthMetricType,
        category: HealthSourcePriorityCategory,
        healthMetricKind: HealthMetricKind?,
        dashboard: HomeDashboard?,
        snapshot: HealthSourceSnapshot?
    ) -> MetricSourceAvailability {
        let canProvideData = source == .manual || snapshot?.connectionState.canProvideData == true || dashboard != nil
        let metric = healthMetricKind.flatMap { dashboard?.healthMonitor.metric($0) }
        let hasMetricSample = metric.map { metricSourceMatches($0, source: source) } ?? false
        let lastSampleDate = metric?.lastUpdated
        let sampleCount = hasMetricSample ? 1 : 0
        let reason: String?
        if sampleCount > 0 {
            reason = nil
        } else if !canProvideData {
            reason = "\(source.routingDisplayName) is not connected or authorized for \(metricType.label)."
        } else {
            reason = noValidSampleReason(source: source, metricType: metricType, healthMetricKind: healthMetricKind)
        }
        return MetricSourceAvailability(
            source: source,
            sampleCount: sampleCount,
            lastSampleDate: lastSampleDate,
            isConnected: canProvideData,
            reason: reason
        )
    }

    private func noValidSampleReason(
        source: HealthSourceID,
        metricType: MeasurementHealthMetricType,
        healthMetricKind: HealthMetricKind?
    ) -> String {
        if source == .ouraRing && isTemperatureTrendMetric(metricType: metricType, healthMetricKind: healthMetricKind) {
            return "No Oura temperature trend available yet. Wear your ring overnight."
        }
        return "\(source.routingDisplayName) has no valid \(healthMetricKind?.title ?? metricType.label) sample for the selected day."
    }

    private func isTemperatureTrendMetric(
        metricType: MeasurementHealthMetricType,
        healthMetricKind: HealthMetricKind?
    ) -> Bool {
        metricType == .temperature || healthMetricKind == .wristTemperature
    }

    private func validated(_ resolution: MetricSourceResolution) -> MetricSourceResolution {
        guard !resolution.fallbackUsed,
              let displayedSource = resolution.displayedRecordSource,
              displayedSource != resolution.currentSource else {
            return resolution
        }

        PulsarSourceRouterLogger.log("Invalid source resolution: displayed source does not match current source without fallback")
        var copy = resolution
        copy.displayedRecordSource = nil
        copy.fallbackReason = "No recent \(resolution.currentSource.routingDisplayName) data available."
        copy.selectedRecordIds = []
        return copy
    }

    private func metricSourceMatches(_ metric: HealthMetricModel, source: HealthSourceID) -> Bool {
        guard metric.hasData else { return false }
        guard !metric.sourceBadges.isEmpty else { return false }
        return metric.sourceBadges.contains { sourceBadge($0, matches: source) }
    }

    private func sourceBadge(_ badge: SourceProvenance, matches source: HealthSourceID) -> Bool {
        let text = [
            badge.sourceName,
            badge.sourceBundleIdentifier,
            badge.productType,
            badge.deviceName,
            badge.deviceManufacturer,
            badge.deviceModel
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        switch source {
        case .appleWatch:
            return badge.isAppleWatchLike ||
                text.contains("healthkit") ||
                text.contains("apple health") ||
                text.contains("com.apple.health")
        case .ouraRing:
            return text.contains("oura")
        case .iPhone:
            return text.contains("iphone")
        case .manual:
            return text.contains("manual")
        }
    }

    private func selectedRecordIds(
        for metricType: MeasurementHealthMetricType,
        healthMetricKind: HealthMetricKind?,
        source: HealthSourceID,
        dateRange: DateInterval?
    ) -> [String] {
        let metricKey = healthMetricKind?.rawValue ?? metricType.rawValue
        if let dateRange {
            return ["\(source.rawValue):\(metricKey):\(Int(dateRange.start.timeIntervalSinceReferenceDate))-\(Int(dateRange.end.timeIntervalSinceReferenceDate))"]
        }
        return ["\(source.rawValue):\(metricKey)"]
    }

    private func currentAvailabilityDate(
        currentSource: HealthSourceID,
        availabilityBySource: [HealthSourceID: MetricSourceAvailability]
    ) -> Date? {
        availabilityBySource[currentSource]?.lastSampleDate
    }

    private func sourceCategory(for kind: HealthMetricKind) -> HealthSourcePriorityCategory {
        switch kind {
        case .hrv, .restingHeartRate:
            return .heartMetrics
        case .wristTemperature:
            return .temperatureCycle
        case .respiratoryRate, .oxygenSaturation, .sleep:
            return .sleepRecovery
        }
    }

    private func dayInterval(containing date: Date) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 60 * 60)
        return DateInterval(start: start, end: end)
    }

    private func sourceRoutingNotes(activityDecision: SourceRoutingDecision?, workoutDecision: SourceRoutingDecision?) -> [String] {
        var notes: [String] = []
        if let activityDecision {
            notes.append(noteText(prefix: "Activity", decision: activityDecision))
        }
        if let workoutDecision {
            notes.append(noteText(prefix: "Workouts", decision: workoutDecision))
        }
        return notes
    }

    private func noteText(prefix: String, decision: SourceRoutingDecision) -> String {
        if let activeSource = decision.displayedSource {
            let fallback = decision.isFallback ? " using fallback" : ""
            return "\(prefix) from \(activeSource.routingDisplayName)\(fallback)."
        }
        return noRecentDataText(for: decision)
    }

    private func noRecentDataText(for decision: SourceRoutingDecision?) -> String {
        guard let decision else { return "No recent data available." }
        return "No recent \(decision.currentSource.routingDisplayName) data available."
    }

    private func noRecentDataText(for decision: SourceRoutingDecision?, resolution: MetricSourceResolution) -> String {
        if let fallbackReason = resolution.fallbackReason, !fallbackReason.isEmpty {
            return fallbackReason
        }
        return noRecentDataText(for: decision)
    }

    private func maxConfidence(_ lhs: ConfidenceGrade?, _ rhs: ConfidenceGrade?) -> ConfidenceGrade {
        let values = [lhs, rhs].compactMap { $0 }
        if values.contains(.high) { return .high }
        if values.contains(.moderate) { return .moderate }
        if values.contains(.low) { return .low }
        return .missing
    }
}

private extension HealthSourceID {
    var sourceRouterLogName: String {
        switch self {
        case .appleWatch:
            return "appleWatchHealthKit"
        case .ouraRing:
            return "ouraRing"
        case .iPhone:
            return "iPhoneSensors"
        case .manual:
            return "manual"
        }
    }
}

extension PulsarSyncSourceDevice {
    var healthSourceIDForRouting: HealthSourceID {
        switch self {
        case .ouraRing:
            return .ouraRing
        case .appleWatch, .iPhone:
            return .appleWatch
        }
    }
}

private extension HealthSourceID {
    var routingDisplayName: String {
        switch self {
        case .appleWatch:
            return "Apple Watch / HealthKit"
        case .ouraRing:
            return "Oura Ring"
        case .iPhone:
            return "iPhone"
        case .manual:
            return "Manual Entry"
        }
    }
}

private extension SleepSummary {
    var hasRoutedData: Bool {
        score > 0 || totalSleepMinutes > 0 || lastUpdated != nil
    }

    func withNoRecentSourceDataMessage(for decision: SourceRoutingDecision?) -> SleepSummary {
        var copy = self
        if !copy.hasRoutedData, let decision {
            copy.confidenceExplanation = "No recent \(decision.currentSource.routingDisplayName) sleep data available."
            copy.notes = [copy.confidenceExplanation]
        }
        return copy
    }
}

private extension RecoverySummary {
    var hasRoutedData: Bool {
        score > 0 || hrvSDNN != nil || restingHeartRate != nil || lastUpdated != nil
    }

    func withNoRecentSourceDataMessage(for decision: SourceRoutingDecision?) -> RecoverySummary {
        var copy = self
        if !copy.hasRoutedData, let decision {
            copy.explanation = "No recent \(decision.currentSource.routingDisplayName) recovery data available."
            copy.notes = [copy.explanation]
        }
        return copy
    }
}

private extension StrainSummary {
    var hasActivityData: Bool {
        steps > 0 || movementLoad > 0 || (activeEnergyKilocalories ?? 0) > 0 || exerciseMinutes > 0
    }

    var hasWorkoutData: Bool {
        workoutMinutes > 0 || workoutLoad > 0 || !workouts.isEmpty || !ledger.isEmpty
    }

    func withNoRecentSourceDataMessage(for decision: SourceRoutingDecision?) -> StrainSummary {
        var copy = self
        if !copy.hasActivityData, !copy.hasWorkoutData, let decision {
            copy.notes = ["No recent \(decision.currentSource.routingDisplayName) activity data available."]
        }
        return copy
    }
}

private extension StressSummary {
    var hasLivePhysiologyData: Bool {
        lastHeartRate != nil ||
            lastHRV != nil ||
            nonActivityStress != nil ||
            activityAdjustedStress != nil ||
            state == .workoutPaused ||
            state == .cooldown
    }

    var hasSupplementalPhysiologyData: Bool {
        lastHeartRate != nil ||
            lastHRV != nil ||
            nonActivityStress != nil ||
            activityAdjustedStress != nil ||
            state == .workoutPaused ||
            state == .cooldown
    }

    var hasRoutedData: Bool {
        hasLivePhysiologyData || score != nil || !dailySamples.isEmpty
    }

    func mergedWithSupplementalStress(_ supplemental: StressSummary) -> StressSummary {
        var copy = self
        if copy.lastHeartRate == nil {
            copy.lastHeartRate = supplemental.lastHeartRate
            copy.lastHeartRateTimestamp = supplemental.lastHeartRateTimestamp
        }
        if copy.lastHRV == nil {
            copy.lastHRV = supplemental.lastHRV
            copy.lastHRVTimestamp = supplemental.lastHRVTimestamp
        }
        if copy.nonActivityStress == nil {
            copy.nonActivityStress = supplemental.nonActivityStress
        }
        if copy.activityAdjustedStress == nil {
            copy.activityAdjustedStress = supplemental.activityAdjustedStress
        }
        if copy.movementStateText == nil {
            copy.movementStateText = supplemental.movementStateText
        }
        if copy.stressStatusText == nil {
            copy.stressStatusText = supplemental.stressStatusText
        }
        copy.availableSignalCount = max(copy.availableSignalCount, supplemental.availableSignalCount)
        copy.analyzedSampleCount = max(copy.analyzedSampleCount, supplemental.analyzedSampleCount)
        copy.signals = mergedStressSignals(primary: copy.signals, supplemental: supplemental.signals)
        copy.sourceBadges = SourceResolver.uniqueSourceBadges(copy.sourceBadges + supplemental.sourceBadges)
        if !supplemental.driverInsights.isEmpty {
            copy.driverInsights = Array(uniqueStrings(copy.driverInsights + supplemental.driverInsights).prefix(4))
        }
        return copy
    }

    func withNoRecentSourceDataMessage(for decision: SourceRoutingDecision?) -> StressSummary {
        var copy = self
        if !copy.hasRoutedData, let decision {
            copy.explanation = "No recent \(decision.currentSource.routingDisplayName) stress data available."
            copy.driverInsights = [copy.explanation]
        }
        return copy
    }

    private func mergedStressSignals(primary: [StressSignal], supplemental: [StressSignal]) -> [StressSignal] {
        var result = primary
        let existingIDs = Set(result.map(\.id))
        result.append(contentsOf: supplemental.filter { !existingIDs.contains($0.id) && $0.availability != .unavailable })
        return result
    }

    private func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
