//
//  HealthSourcePriorityStore.swift
//  Pulsar
//

import Combine
import Foundation

enum HealthSourcePriorityCategory: String, CaseIterable, Identifiable, Codable, Hashable {
    case sleepRecovery
    case workoutsActivity
    case activitySteps
    case heartMetrics
    case temperatureCycle
    case stressResilience
    case manualEntries

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleepRecovery:
            return "Sleep & Recovery Source"
        case .workoutsActivity:
            return "Workout Source"
        case .activitySteps:
            return "Activity / Steps Source"
        case .heartMetrics:
            return "Heart Metrics Source"
        case .temperatureCycle:
            return "Temperature & Cycle Source"
        case .stressResilience:
            return "Stress & Resilience Source"
        case .manualEntries:
            return "Manual Entry Source"
        }
    }

    var metrics: Set<MeasurementHealthMetricType> {
        switch self {
        case .sleepRecovery:
            return [.sleep, .recovery, .readiness, .respiratoryRate, .oxygenSaturation]
        case .workoutsActivity:
            return [.workouts]
        case .activitySteps:
            return [.activity, .strain]
        case .heartMetrics:
            return [.heartRate, .hrv, .restingHeartRate]
        case .temperatureCycle:
            return [.temperature, .cycle]
        case .stressResilience:
            return [.stress]
        case .manualEntries:
            return Set(MeasurementHealthMetricType.allCases)
        }
    }

    var defaultCurrentSource: HealthSourceID {
        switch self {
        case .sleepRecovery:
            return .ouraRing
        case .workoutsActivity:
            return .appleWatch
        case .activitySteps:
            return .appleWatch
        case .heartMetrics:
            return .ouraRing
        case .temperatureCycle:
            return .ouraRing
        case .stressResilience:
            return .ouraRing
        case .manualEntries:
            return .manual
        }
    }

    var fallbackOrder: [HealthSourceID] {
        switch self {
        case .sleepRecovery:
            return [.ouraRing, .appleWatch, .iPhone, .manual]
        case .workoutsActivity:
            return [.appleWatch, .ouraRing, .iPhone, .manual]
        case .activitySteps:
            return [.appleWatch, .ouraRing, .iPhone, .manual]
        case .heartMetrics:
            return [.ouraRing, .appleWatch, .iPhone, .manual]
        case .temperatureCycle:
            return [.ouraRing, .appleWatch, .iPhone, .manual]
        case .stressResilience:
            return [.ouraRing, .appleWatch, .iPhone, .manual]
        case .manualEntries:
            return [.manual, .iPhone, .appleWatch, .ouraRing]
        }
    }
}

struct HealthSourcePreference: Codable, Equatable {
    var currentSource: HealthSourceID
    var fallbackEnabled: Bool
    var selectedAt: Date? = nil

    var sourceSwitchTimestamp: Date? {
        get { selectedAt }
        set { selectedAt = newValue }
    }

    static func defaultValue(for category: HealthSourcePriorityCategory) -> HealthSourcePreference {
        HealthSourcePreference(currentSource: category.defaultCurrentSource, fallbackEnabled: true, selectedAt: nil)
    }

    private enum CodingKeys: String, CodingKey {
        case currentSource
        case fallbackEnabled
        case selectedAt
        case legacySource = "preferredSource"
    }

    init(currentSource: HealthSourceID, fallbackEnabled: Bool, selectedAt: Date? = nil) {
        self.currentSource = currentSource
        self.fallbackEnabled = fallbackEnabled
        self.selectedAt = selectedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentSource = try container.decodeIfPresent(HealthSourceID.self, forKey: .currentSource)
            ?? container.decode(HealthSourceID.self, forKey: .legacySource)
        fallbackEnabled = try container.decode(Bool.self, forKey: .fallbackEnabled)
        selectedAt = try container.decodeIfPresent(Date.self, forKey: .selectedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(currentSource, forKey: .currentSource)
        try container.encode(fallbackEnabled, forKey: .fallbackEnabled)
        try container.encodeIfPresent(selectedAt, forKey: .selectedAt)
    }
}

struct ResolvedHealthSource: Equatable {
    var category: HealthSourcePriorityCategory
    var currentSource: HealthSourceID
    var displayedSource: HealthSourceID
    var isFallback: Bool
    var lastDataAt: Date?
}

extension Notification.Name {
    static let pulsarHealthSourcePreferenceDidChange = Notification.Name("pulsar.healthSourcePreferenceDidChange")
}

final class HealthSourcePriorityStore: ObservableObject {
    @Published private(set) var preferences: [HealthSourcePriorityCategory: HealthSourcePreference]

    private let defaults: UserDefaults
    private let key = "pulsar.healthSourcePriority.preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([HealthSourcePriorityCategory: HealthSourcePreference].self, from: data) {
            preferences = Self.withDefaults(decoded)
        } else {
            preferences = Self.defaultPreferences()
        }
    }

    func preference(for category: HealthSourcePriorityCategory) -> HealthSourcePreference {
        preferences[category] ?? .defaultValue(for: category)
    }

    func setCurrentSource(_ source: HealthSourceID, for category: HealthSourcePriorityCategory) {
        var preference = self.preference(for: category)
        preference.currentSource = source
        preference.sourceSwitchTimestamp = Date()
        preferences[category] = preference
        save()
    }

    func setFallbackEnabled(_ isEnabled: Bool, for category: HealthSourcePriorityCategory) {
        var preference = self.preference(for: category)
        preference.fallbackEnabled = isEnabled
        preferences[category] = preference
        save()
    }

    func reloadFromDefaults() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([HealthSourcePriorityCategory: HealthSourcePreference].self, from: data) {
            preferences = Self.withDefaults(decoded)
        } else {
            preferences = Self.defaultPreferences()
        }
    }

    func resolvedSource(
        for category: HealthSourcePriorityCategory,
        snapshots: [HealthSourceSnapshot],
        now: Date = Date()
    ) -> ResolvedHealthSource {
        HealthSourcePriorityResolver.resolve(
            category: category,
            preference: preference(for: category),
            snapshots: snapshots,
            now: now
        )
    }

    private func save() {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: .pulsarHealthSourcePreferenceDidChange, object: self)
    }

    private static func defaultPreferences() -> [HealthSourcePriorityCategory: HealthSourcePreference] {
        Dictionary(uniqueKeysWithValues: HealthSourcePriorityCategory.allCases.map {
            ($0, HealthSourcePreference.defaultValue(for: $0))
        })
    }

    private static func withDefaults(_ decoded: [HealthSourcePriorityCategory: HealthSourcePreference]) -> [HealthSourcePriorityCategory: HealthSourcePreference] {
        var merged = defaultPreferences()
        for (category, preference) in decoded {
            merged[category] = preference
        }
        return merged
    }
}

enum HealthSourcePriorityResolver {
    static func resolve(
        category: HealthSourcePriorityCategory,
        preference: HealthSourcePreference,
        snapshots: [HealthSourceSnapshot],
        now: Date = Date(),
        staleAfter: TimeInterval = 36 * 60 * 60
    ) -> ResolvedHealthSource {
        let bySource = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.sourceID, $0) })
        let current = preference.currentSource

        if isUsable(current, for: category, snapshots: bySource, now: now, staleAfter: staleAfter) {
            return ResolvedHealthSource(category: category, currentSource: current, displayedSource: current, isFallback: false, lastDataAt: bySource[current]?.lastSyncAt)
        }

        guard preference.fallbackEnabled else {
            return ResolvedHealthSource(category: category, currentSource: current, displayedSource: current, isFallback: false, lastDataAt: bySource[current]?.lastSyncAt)
        }

        for source in category.fallbackOrder where source != current {
            if isUsable(source, for: category, snapshots: bySource, now: now, staleAfter: staleAfter) {
                return ResolvedHealthSource(category: category, currentSource: current, displayedSource: source, isFallback: true, lastDataAt: bySource[source]?.lastSyncAt)
            }
        }

        return ResolvedHealthSource(category: category, currentSource: current, displayedSource: current, isFallback: false, lastDataAt: bySource[current]?.lastSyncAt)
    }

    private static func isUsable(
        _ source: HealthSourceID,
        for category: HealthSourcePriorityCategory,
        snapshots: [HealthSourceID: HealthSourceSnapshot],
        now: Date,
        staleAfter: TimeInterval
    ) -> Bool {
        if source == .manual {
            return true
        }
        if source == .airPodsPro3 {
            return false
        }
        guard let snapshot = snapshots[source],
              snapshot.connectionState.canProvideData,
              !snapshot.supportedMetrics.isDisjoint(with: category.metrics) else {
            return false
        }
        guard let lastSyncAt = snapshot.lastSyncAt else {
            return source == .appleWatch || source == .iPhone
        }
        return now.timeIntervalSince(lastSyncAt) <= staleAfter
    }
}

enum HealthSampleDeduplicator {
    nonisolated static func deduplicate(
        _ samples: [CanonicalHealthSample],
        sourcePriority: [HealthSourceID],
        overlapTolerance: TimeInterval = 5 * 60
    ) -> [CanonicalHealthSample] {
        var kept: [CanonicalHealthSample] = []
        for sample in samples.sorted(by: sampleSort) {
            if let duplicateIndex = kept.firstIndex(where: { isDuplicate($0, sample, tolerance: overlapTolerance) }) {
                let current = kept[duplicateIndex]
                if shouldReplaceCurrentSample(sample, current: current, sourcePriority: sourcePriority) {
                    kept[duplicateIndex] = sample
                }
            } else {
                kept.append(sample)
            }
        }
        return kept.sorted { $0.startAt < $1.startAt }
    }

    private nonisolated static func sampleSort(_ lhs: CanonicalHealthSample, _ rhs: CanonicalHealthSample) -> Bool {
        if lhs.metric != rhs.metric {
            return lhs.metric.rawValue < rhs.metric.rawValue
        }
        return lhs.startAt < rhs.startAt
    }

    private nonisolated static func isDuplicate(
        _ lhs: CanonicalHealthSample,
        _ rhs: CanonicalHealthSample,
        tolerance: TimeInterval
    ) -> Bool {
        guard lhs.metric == rhs.metric else { return false }
        let lhsEnd = lhs.endAt ?? lhs.startAt
        let rhsEnd = rhs.endAt ?? rhs.startAt
        let startsClose = abs(lhs.startAt.timeIntervalSince(rhs.startAt)) <= tolerance
        let endsClose = abs(lhsEnd.timeIntervalSince(rhsEnd)) <= tolerance
        return startsClose && endsClose
    }

    private nonisolated static func shouldReplaceCurrentSample(
        _ lhs: CanonicalHealthSample,
        current rhs: CanonicalHealthSample,
        sourcePriority: [HealthSourceID]
    ) -> Bool {
        let lhsRank = sourcePriority.firstIndex(of: lhs.sourceID) ?? Int.max
        let rhsRank = sourcePriority.firstIndex(of: rhs.sourceID) ?? Int.max
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        return lhs.syncedAt > rhs.syncedAt
    }
}

enum OuraPriorityPayloadFilter {
    static func filteredPayload(
        from payload: PulsarDailyMetricsSyncPayload,
        priorityStore: HealthSourcePriorityStore,
        snapshots: [HealthSourceSnapshot],
        now: Date = Date()
    ) -> PulsarDailyMetricsSyncPayload? {
        guard payload.sourceDevice == .ouraRing else { return payload }
        let activeCategories = Set(
            HealthSourcePriorityCategory.allCases.filter {
                priorityStore.resolvedSource(for: $0, snapshots: snapshots, now: now).displayedSource == .ouraRing
            }
        )

        var copy = payload
        copy.sleep = activeCategories.contains(.sleepRecovery) ? payload.sleep : nil
        copy.recovery = activeCategories.contains(.sleepRecovery) ? payload.recovery : nil
        copy.stress = activeCategories.contains(.stressResilience) ? payload.stress : nil
        copy.strain = activeCategories.contains(.workoutsActivity) || activeCategories.contains(.activitySteps) ? payload.strain : nil
        copy.healthMonitor = filteredHealthMonitor(payload.healthMonitor, activeCategories: activeCategories)
        copy.dataFingerprint = nil
        return copy.isValidPayload ? copy : nil
    }

    private static func filteredHealthMonitor(
        _ healthMonitor: PulsarHealthMonitorSyncMetric?,
        activeCategories: Set<HealthSourcePriorityCategory>
    ) -> PulsarHealthMonitorSyncMetric? {
        guard let healthMonitor else { return nil }
        let allowedKinds = allowedHealthMetricKinds(activeCategories: activeCategories)
        guard !allowedKinds.isEmpty else { return nil }
        let metrics = healthMonitor.metrics.filter { allowedKinds.contains($0.kind) }
        let filtered = PulsarHealthMonitorSyncMetric(
            metrics: metrics,
            baselineWindowDays: healthMonitor.baselineWindowDays,
            sourceNames: healthMonitor.sourceNames,
            computedAt: healthMonitor.computedAt
        )
        return filtered.isValid ? filtered : nil
    }

    private static func allowedHealthMetricKinds(
        activeCategories: Set<HealthSourcePriorityCategory>
    ) -> Set<PulsarHealthMetricSyncKind> {
        var kinds = Set<PulsarHealthMetricSyncKind>()
        if activeCategories.contains(.sleepRecovery) {
            kinds.formUnion([.sleep, .respiratoryRate, .oxygenSaturation])
        }
        if activeCategories.contains(.heartMetrics) {
            kinds.formUnion([.hrv, .restingHeartRate])
        }
        if activeCategories.contains(.temperatureCycle) {
            kinds.insert(.wristTemperature)
        }
        return kinds
    }
}
