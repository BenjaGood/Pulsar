//
//  MeasurementSourceManager.swift
//  Pulsar
//

import AuthenticationServices
import Combine
import Foundation

enum MeasurementDeviceType: String, Codable, CaseIterable, Identifiable {
    case appleWatch
    case ouraRing
    case airPodsPro3

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleWatch:
            return "Apple Watch"
        case .ouraRing:
            return "Oura Ring"
        case .airPodsPro3:
            return "AirPods Pro 3"
        }
    }

    var assetName: String {
        switch self {
        case .appleWatch:
            return "AppleWatchDevice"
        case .ouraRing:
            return "OuraRingDevice"
        case .airPodsPro3:
            return "AirPodsPro3Device"
        }
    }

    var healthSourceID: HealthSourceID {
        switch self {
        case .appleWatch:
            return .appleWatch
        case .ouraRing:
            return .ouraRing
        case .airPodsPro3:
            return .airPodsPro3
        }
    }
}

enum MeasurementDeviceConnectionStatus: String, Codable, Hashable {
    case connected
    case connecting
    case available
    case setupRequired
    case syncError
    case tokenExpired
    case disconnected

    var label: String {
        switch self {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .available:
            return "Available"
        case .setupRequired:
            return "Connection unavailable"
        case .syncError:
            return "Sync Error"
        case .tokenExpired:
            return "Token Expired"
        case .disconnected:
            return "Not Connected"
        }
    }
}

enum MeasurementHealthMetricType: String, Codable, CaseIterable, Identifiable, Hashable {
    case heartRate
    case hrv
    case respiratoryRate
    case sleep
    case activity
    case workouts
    case recovery
    case readiness
    case restingHeartRate
    case oxygenSaturation
    case strain
    case stress
    case temperature
    case cycle

    nonisolated var id: String { rawValue }

    nonisolated var label: String {
        switch self {
        case .heartRate:
            return "Heart rate"
        case .hrv:
            return "HRV"
        case .respiratoryRate:
            return "Respiratory rate"
        case .sleep:
            return "Sleep"
        case .activity:
            return "Activity"
        case .workouts:
            return "Workouts"
        case .recovery:
            return "Recovery"
        case .readiness:
            return "Readiness"
        case .restingHeartRate:
            return "Resting heart rate"
        case .oxygenSaturation:
            return "SpO2"
        case .strain:
            return "Strain"
        case .stress:
            return "Stress"
        case .temperature:
            return "Temperature trend"
        case .cycle:
            return "Cycle"
        }
    }
}

enum OuraConnectionFlowState: Equatable {
    case idle
    case preparing
    case openingLogin
    case waitingForCallback
    case connected
    case failed(errorMessage: String)

    var isConnecting: Bool {
        switch self {
        case .preparing, .openingLogin, .waitingForCallback:
            return true
        case .idle, .connected, .failed:
            return false
        }
    }
}

struct OuraConnectionAlert: Identifiable, Equatable {
    enum Kind: Equatable {
        case configurationMissing
        case connectionFailed
    }

    let id = UUID()
    var kind: Kind
    var title: String
    var message: String
    var debugAuthorizationURL: URL?
}

struct MeasurementDevice: Identifiable, Codable, Equatable {
    var id: MeasurementDeviceType { type }
    var name: String
    var type: MeasurementDeviceType
    var connectionStatus: MeasurementDeviceConnectionStatus
    var batteryPercentage: Int?
    var isActiveSource: Bool
    var supportedMetrics: [MeasurementHealthMetricType]
    var lastSyncAt: Date?

    var batteryText: String {
        if let batteryPercentage {
            return "Battery \(batteryPercentage)%"
        }
        return "Battery unavailable"
    }

    var canBecomeActiveSource: Bool {
        guard type != .airPodsPro3 else { return false }
        return connectionStatus == .connected || connectionStatus == .available
    }

    var primaryActionTitle: String {
        if type == .airPodsPro3 {
            return "Workout backup only"
        }
        if type == .ouraRing {
            switch connectionStatus {
            case .connected, .available:
                return isActiveSource ? "Current source" : "Use as source"
            case .connecting:
                return "Connecting..."
            case .setupRequired:
                return "Connect Oura"
            case .syncError:
                return "Retry sync"
            case .tokenExpired:
                return "Reconnect Oura"
            case .disconnected:
                return "Connect Oura"
            }
        }
        if isActiveSource { return "Current source" }
        if connectionStatus == .setupRequired { return "Set up \(name)" }
        return "Use as source"
    }
}

struct OuraVisibleDataRow: Identifiable, Equatable {
    var id: String
    var title: String
    var value: String
    var detail: String
    var isAvailable: Bool
}

@MainActor
final class MeasurementSourceManager: ObservableObject {
    @Published private(set) var activeDeviceType: MeasurementDeviceType
    @Published private(set) var appleWatchBatterySnapshot: AppleWatchBatterySnapshot?
    @Published private(set) var isOuraSyncing = false
    @Published private(set) var ouraConnectionFlowState: OuraConnectionFlowState = .idle
    @Published private(set) var ouraConnectionAlert: OuraConnectionAlert?
    @Published private(set) var sourcePreferences: [HealthSourcePriorityCategory: HealthSourcePreference]

    private let defaults: UserDefaults
    private let syncStore: PulsarWatchConnectivitySyncStore?
    private let ouraAuthService: OuraAuthService
    private let ouraSyncService: OuraSyncServicing
    private let ouraConnectionStore: OuraConnectionStore
    private let sourcePriorityStore: HealthSourcePriorityStore
    private let ouraConfiguration: OuraIntegrationConfiguration
    private let activeDeviceKey = "pulsar.measurementSource.activeDevice.v1"
    private var cancellables: Set<AnyCancellable> = []

    init(
        defaults: UserDefaults = .standard,
        syncStore: PulsarWatchConnectivitySyncStore? = nil,
        ouraAuthService: OuraAuthService? = nil,
        ouraSyncService: OuraSyncServicing? = nil,
        sourcePriorityStore: HealthSourcePriorityStore? = nil,
        ouraConfiguration: OuraIntegrationConfiguration? = nil
    ) {
        let resolvedSyncStore = syncStore ?? PulsarWatchConnectivitySyncStore.shared
        let configuration = ouraConfiguration ?? OuraIntegrationConfiguration.load(defaults: defaults)
        let tokenStore = OuraKeychainTokenStore()
        let resolvedOuraAuthService = ouraAuthService ?? OuraAuthService(configuration: configuration, tokenStorage: tokenStore)
        let apiClient: OuraAPIClientProtocol = configuration.mockMode
            ? MockOuraAPIClient()
            : URLSessionOuraAPIClient(authService: resolvedOuraAuthService)
        let resolvedOuraSyncService = ouraSyncService ?? OuraSyncService(
            apiClient: apiClient,
            authService: resolvedOuraAuthService,
            connectionStore: resolvedOuraAuthService.connectionStore
        )
        let resolvedPriorityStore = sourcePriorityStore ?? HealthSourcePriorityStore(defaults: defaults)
        self.defaults = defaults
        self.syncStore = resolvedSyncStore
        self.ouraConfiguration = configuration
        self.ouraAuthService = resolvedOuraAuthService
        self.ouraSyncService = resolvedOuraSyncService
        self.ouraConnectionStore = resolvedOuraAuthService.connectionStore
        self.sourcePriorityStore = resolvedPriorityStore
        self.sourcePreferences = resolvedPriorityStore.preferences
        self.appleWatchBatterySnapshot = resolvedSyncStore.latestAppleWatchBattery
        self.ouraConnectionFlowState = resolvedOuraAuthService.connectionStore.isConnected ? .connected : .idle
        if let stored = defaults.string(forKey: activeDeviceKey) {
            if let deviceType = MeasurementDeviceType(rawValue: stored) {
                self.activeDeviceType = deviceType == .airPodsPro3 ? .appleWatch : deviceType
            } else {
                self.activeDeviceType = .appleWatch
            }
        } else {
            self.activeDeviceType = .appleWatch
        }

        resolvedSyncStore.$latestAppleWatchBattery
            .sink { [weak self] snapshot in
                self?.appleWatchBatterySnapshot = snapshot
            }
            .store(in: &cancellables)

        resolvedOuraAuthService.connectionStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        resolvedPriorityStore.$preferences
            .sink { [weak self] preferences in
                self?.sourcePreferences = preferences
            }
            .store(in: &cancellables)
    }

    var activeDevice: MeasurementDevice {
        device(for: activeDeviceType)
    }

    var availableDevices: [MeasurementDevice] {
        MeasurementDeviceType.allCases.map(device(for:))
    }

    var ouraTodayRows: [OuraVisibleDataRow] {
        guard let payload = latestOuraPayload() else {
            return [
                OuraVisibleDataRow(
                    id: "oura-sync",
                    title: "Oura sync",
                    value: "No data yet",
                    detail: "Tap Sync now after the Oura app has synced your ring.",
                    isAvailable: false
                )
            ]
        }

        return [
            ouraActivityRow(from: payload),
            ouraHeartRateRow(from: payload),
            ouraStressRow(from: payload),
            ouraSleepRow(from: payload),
            ouraRecoveryRow(from: payload),
            ouraHealthMonitorRow(from: payload)
        ]
    }

    var sourcePrioritySnapshots: [HealthSourceSnapshot] {
        [
            HealthSourceSnapshot(
                sourceID: .appleWatch,
                connectionState: .connected,
                syncState: .idle,
                supportedMetrics: [
                    .heartRate,
                    .hrv,
                    .respiratoryRate,
                    .sleep,
                    .activity,
                    .workouts,
                    .recovery,
                    .readiness,
                    .restingHeartRate,
                    .oxygenSaturation,
                    .strain,
                    .stress,
                    .temperature,
                    .cycle
                ],
                lastSyncAt: latestCachedDataAt(source: .appleWatch) ?? appleWatchBatterySnapshot?.timestamp,
                batteryPercentage: appleWatchBatterySnapshot?.batteryPercentage
            ),
            OuraDeviceSourceProvider(
                configuration: ouraConfiguration,
                connectionStore: ouraConnectionStore,
                syncService: ouraSyncService
            ).snapshot(),
            HealthSourceSnapshot(
                sourceID: .airPodsPro3,
                connectionState: .available,
                syncState: .idle,
                supportedMetrics: [],
                lastSyncAt: nil,
                batteryPercentage: nil
            ),
            HealthSourceSnapshot(
                sourceID: .iPhone,
                connectionState: .available,
                syncState: .idle,
                supportedMetrics: [.heartRate, .activity, .workouts, .strain, .temperature, .cycle],
                lastSyncAt: latestCachedDataAt(source: .iPhone),
                batteryPercentage: nil
            ),
            HealthSourceSnapshot(
                sourceID: .manual,
                connectionState: .available,
                syncState: .idle,
                supportedMetrics: Set(MeasurementHealthMetricType.allCases),
                lastSyncAt: latestCachedDataAt(source: .manual),
                batteryPercentage: nil
            )
        ]
    }

    func preference(for category: HealthSourcePriorityCategory) -> HealthSourcePreference {
        sourcePriorityStore.preference(for: category)
    }

    func setCurrentSource(_ source: HealthSourceID, for category: HealthSourcePriorityCategory) {
        sourcePriorityStore.setCurrentSource(source, for: category)
    }

    func setFallbackEnabled(_ enabled: Bool, for category: HealthSourcePriorityCategory) {
        sourcePriorityStore.setFallbackEnabled(enabled, for: category)
    }

    func resolvedSource(for category: HealthSourcePriorityCategory) -> ResolvedHealthSource {
        sourcePriorityStore.resolvedSource(for: category, snapshots: sourcePrioritySnapshots)
    }

    func routingDecision(for category: HealthSourcePriorityCategory) -> SourceRoutingDecision {
        let preference = sourcePriorityStore.preference(for: category)
        let currentSource = preference.currentSource

        if category == .manualEntries {
            return SourceRoutingDecision(
                category: category,
                currentSource: currentSource,
                displayedSource: .manual,
                isFallback: currentSource != .manual,
                lastDataAt: Date(),
                fallbackEnabled: preference.fallbackEnabled
            )
        }

        if let primaryMetricDecision = metricRoutingResolutions(for: category).first {
            return SourceRoutingDecision(
                category: category,
                currentSource: currentSource,
                displayedSource: primaryMetricDecision.displayedRecordSource,
                isFallback: primaryMetricDecision.fallbackUsed,
                lastDataAt: primaryMetricDecision.lastAvailableSampleDate,
                fallbackEnabled: preference.fallbackEnabled,
                fallbackReason: primaryMetricDecision.fallbackReason
            )
        }

        return SourceRoutingDecision(
            category: category,
            currentSource: currentSource,
            displayedSource: nil,
            isFallback: false,
            lastDataAt: nil,
            fallbackEnabled: true
        )
    }

    func metricRoutingResolutions(for category: HealthSourcePriorityCategory) -> [MetricSourceResolution] {
        let preference = sourcePriorityStore.preference(for: category)
        return metricDescriptors(for: category).map { descriptor in
            metricRoutingResolution(
                metricType: descriptor.metricType,
                metricTitle: descriptor.title,
                category: category,
                preference: preference
            )
        }
    }

    private func metricRoutingResolution(
        metricType: MeasurementHealthMetricType,
        metricTitle: String,
        category: HealthSourcePriorityCategory,
        preference: HealthSourcePreference
    ) -> MetricSourceResolution {
        let currentSource = preference.currentSource
        let now = Date()
        let availability = HealthSourceID.allCases.map { source in
            cachedAvailability(for: metricType, metricTitle: metricTitle, source: source)
        }
        let availabilityBySource = Dictionary(uniqueKeysWithValues: availability.map { ($0.source, $0) })

        if let currentAvailability = availabilityBySource[currentSource],
           currentAvailability.sampleCount > 0 {
            return MetricSourceResolution(
                metricType: metricType,
                metricTitle: metricTitle,
                category: category,
                currentSource: currentSource,
                displayedRecordSource: currentSource,
                fallbackUsed: false,
                fallbackReason: nil,
                lastAvailableSampleDate: currentAvailability.lastSampleDate,
                sourceDataAge: currentAvailability.lastSampleDate.map { now.timeIntervalSince($0) },
                sourceAvailabilityByProvider: availability,
                selectedRecordIds: selectedRecordIds(for: metricType, source: currentSource)
            )
        }

        let currentReason = availabilityBySource[currentSource]?.reason ??
            noValidCachedSampleReason(source: currentSource, metricType: metricType, metricTitle: metricTitle)

        guard preference.fallbackEnabled else {
            let fallbackReason = currentReason == ouraTemperatureTrendUnavailableText
                ? currentReason
                : "\(currentReason) Auto fallback is off."
            return MetricSourceResolution(
                metricType: metricType,
                metricTitle: metricTitle,
                category: category,
                currentSource: currentSource,
                displayedRecordSource: nil,
                fallbackUsed: false,
                fallbackReason: fallbackReason,
                lastAvailableSampleDate: availabilityBySource[currentSource]?.lastSampleDate,
                sourceDataAge: availabilityBySource[currentSource]?.lastSampleDate.map { now.timeIntervalSince($0) },
                sourceAvailabilityByProvider: availability,
                selectedRecordIds: []
            )
        }

        for fallbackSource in category.fallbackOrder where fallbackSource != currentSource {
            guard let fallbackAvailability = availabilityBySource[fallbackSource],
                  fallbackAvailability.sampleCount > 0 else { continue }
            return MetricSourceResolution(
                metricType: metricType,
                metricTitle: metricTitle,
                category: category,
                currentSource: currentSource,
                displayedRecordSource: fallbackSource,
                fallbackUsed: true,
                fallbackReason: currentReason,
                lastAvailableSampleDate: fallbackAvailability.lastSampleDate,
                sourceDataAge: fallbackAvailability.lastSampleDate.map { now.timeIntervalSince($0) },
                sourceAvailabilityByProvider: availability,
                selectedRecordIds: selectedRecordIds(for: metricType, source: fallbackSource)
            )
        }

        let latest = availability.compactMap(\.lastSampleDate).max()
        return MetricSourceResolution(
            metricType: metricType,
            metricTitle: metricTitle,
            category: category,
            currentSource: currentSource,
            displayedRecordSource: nil,
            fallbackUsed: false,
            fallbackReason: currentReason,
            lastAvailableSampleDate: latest,
            sourceDataAge: latest.map { now.timeIntervalSince($0) },
            sourceAvailabilityByProvider: availability,
            selectedRecordIds: []
        )
    }

    private func cachedAvailability(
        for metricType: MeasurementHealthMetricType,
        metricTitle: String,
        source: HealthSourceID
    ) -> MetricSourceAvailability {
        if source == .manual {
            return MetricSourceAvailability(
                source: source,
                sampleCount: metricType == .cycle ? 1 : 0,
                lastSampleDate: metricType == .cycle ? Date() : nil,
                isConnected: true,
                reason: metricType == .cycle ? nil : "Manual Entry has no \(metricTitle) record for the selected day."
            )
        }

        let snapshot = sourcePrioritySnapshots.first(where: { $0.sourceID == source })
        let isConnected = snapshot?.connectionState.canProvideData == true
        let availability = cachedMetricAvailability(for: metricType, source: source)
        let reason: String?
        if availability.sampleCount > 0 {
            reason = nil
        } else if !isConnected {
            reason = "\(source.priorityDebugName) is not connected or authorized for \(metricTitle)."
        } else {
            reason = noValidCachedSampleReason(source: source, metricType: metricType, metricTitle: metricTitle)
        }
        return MetricSourceAvailability(
            source: source,
            sampleCount: availability.sampleCount,
            lastSampleDate: availability.lastSampleDate,
            isConnected: isConnected,
            reason: reason
        )
    }

    private var ouraTemperatureTrendUnavailableText: String {
        "No Oura temperature trend available yet. Wear your ring overnight."
    }

    private func noValidCachedSampleReason(
        source: HealthSourceID,
        metricType: MeasurementHealthMetricType,
        metricTitle: String
    ) -> String {
        if source == .ouraRing && metricType == .temperature {
            return ouraTemperatureTrendUnavailableText
        }
        return "\(source.priorityDebugName) has no valid \(metricTitle) sample for the selected day."
    }

    private func cachedMetricAvailability(
        for metricType: MeasurementHealthMetricType,
        source: HealthSourceID
    ) -> (sampleCount: Int, lastSampleDate: Date?) {
        guard let syncStore else { return (0, nil) }
        let calendar = Calendar.current
        let dateKey = PulsarDailyMetricsDateKey.dateKey(for: Date(), calendar: calendar)
        let payloads = uniquePayloads(
            Array(syncStore.cachedDailyPayloadsBySource(forDateKey: dateKey).values) +
                Array(syncStore.cachedSleepPayloadsBySource(forSleepDateKey: dateKey).values)
        )
        let matches = payloads
            .filter { $0.sourceDevice.healthSourceIDForRouting == source }
            .compactMap { payloadMetricAvailability(in: $0, metricType: metricType) }
        return (
            sampleCount: matches.reduce(0) { $0 + $1.sampleCount },
            lastSampleDate: matches.compactMap(\.lastSampleDate).max()
        )
    }

    private func uniquePayloads(_ payloads: [PulsarDailyMetricsSyncPayload]) -> [PulsarDailyMetricsSyncPayload] {
        var seen = Set<String>()
        return payloads.filter { payload in
            let key = payload.syncSessionID?.uuidString ?? payload.dataFingerprint ?? "\(payload.sourceDevice.rawValue)-\(payload.syncedAt.timeIntervalSinceReferenceDate)"
            return seen.insert(key).inserted
        }
    }

    private func payloadMetricAvailability(
        in payload: PulsarDailyMetricsSyncPayload,
        metricType: MeasurementHealthMetricType
    ) -> (sampleCount: Int, lastSampleDate: Date?)? {
        switch metricType {
        case .sleep:
            if let sleep = payload.sleep,
               sleep.totalSleepMinutes > 0 || sleep.score > 0 {
                return (max(sleep.analyzedSampleCount, 1), sleep.computedAt)
            }
            return healthMonitorAvailability(in: payload, kind: .sleep)
        case .recovery, .readiness:
            guard let recovery = payload.recovery,
                  recovery.score > 0 || recovery.hrvSDNN != nil || recovery.restingHeartRate != nil else { return nil }
            return (1, recovery.computedAt)
        case .respiratoryRate:
            if let recovery = payload.recovery, recovery.respiratoryRate != nil {
                return (1, recovery.computedAt)
            }
            return healthMonitorAvailability(in: payload, kind: .respiratoryRate)
        case .oxygenSaturation:
            if let recovery = payload.recovery, recovery.oxygenSaturation != nil {
                return (1, recovery.computedAt)
            }
            return healthMonitorAvailability(in: payload, kind: .oxygenSaturation)
        case .hrv:
            if let recovery = payload.recovery, recovery.hrvSDNN != nil {
                return (1, recovery.computedAt)
            }
            return healthMonitorAvailability(in: payload, kind: .hrv)
        case .restingHeartRate:
            if let recovery = payload.recovery, recovery.restingHeartRate != nil {
                return (1, recovery.computedAt)
            }
            return healthMonitorAvailability(in: payload, kind: .restingHeartRate)
        case .heartRate:
            guard let strain = payload.strain,
                  strain.averageActiveHeartRate != nil || strain.peakHeartRate != nil else { return nil }
            return (max(strain.heartRateSampleCount ?? 0, 1), strain.computedAt)
        case .activity, .strain:
            guard let strain = payload.strain,
                  strain.steps > 0 || strain.movementLoad > 0 || (strain.activeEnergyKilocalories ?? 0) > 0 else { return nil }
            return (max(strain.activitySampleCount ?? 0, 1), strain.computedAt)
        case .workouts:
            guard let strain = payload.strain,
                  strain.workoutMinutes > 0 || strain.workoutLoad > 0 else { return nil }
            return (max(strain.workoutSampleCount ?? 0, 1), strain.computedAt)
        case .stress:
            guard let stress = payload.stress,
                  stress.score >= 0 || !stress.timelineSamples.isEmpty else { return nil }
            return (max(stress.timelineSamples.count, 1), stress.computedAt)
        case .temperature:
            if let recovery = payload.recovery, recovery.wristTemperatureDeviation != nil {
                return (1, recovery.computedAt)
            }
            return healthMonitorAvailability(in: payload, kind: .wristTemperature)
        case .cycle:
            return nil
        }
    }

    private func healthMonitorAvailability(
        in payload: PulsarDailyMetricsSyncPayload,
        kind: PulsarHealthMetricSyncKind
    ) -> (sampleCount: Int, lastSampleDate: Date?)? {
        guard let healthMonitor = payload.healthMonitor,
              healthMonitor.metrics.contains(where: { $0.kind == kind && $0.value != nil }) else { return nil }
        return (1, healthMonitor.computedAt)
    }

    private func selectedRecordIds(for metricType: MeasurementHealthMetricType, source: HealthSourceID) -> [String] {
        guard let availability = cachedMetricAvailability(for: metricType, source: source).lastSampleDate else { return [] }
        return ["\(source.rawValue):\(metricType.rawValue):\(Int(availability.timeIntervalSinceReferenceDate))"]
    }

    private func metricDescriptors(for category: HealthSourcePriorityCategory) -> [(metricType: MeasurementHealthMetricType, title: String)] {
        switch category {
        case .sleepRecovery:
            return [(.sleep, "Sleep"), (.recovery, "Recovery"), (.respiratoryRate, "Respiratory Rate"), (.oxygenSaturation, "SpO2")]
        case .workoutsActivity:
            return [(.workouts, "Workouts")]
        case .activitySteps:
            return [(.activity, "Activity / Steps")]
        case .heartMetrics:
            return [(.restingHeartRate, "Resting Heart Rate"), (.hrv, "HRV"), (.heartRate, "Heart Rate")]
        case .temperatureCycle:
            return [(.temperature, "Temperature Trend"), (.cycle, "Cycle")]
        case .stressResilience:
            return [(.stress, "Stress / Resilience")]
        case .manualEntries:
            return [(.cycle, "Manual Entry")]
        }
    }

    private func lastCachedDataAt(for category: HealthSourcePriorityCategory, source: HealthSourceID) -> Date? {
        guard source != .manual else { return nil }
        guard let syncStore else { return sourcePrioritySnapshots.first(where: { $0.sourceID == source })?.lastSyncAt }
        let calendar = Calendar.current
        let dateKey = PulsarDailyMetricsDateKey.dateKey(for: Date(), calendar: calendar)
        let payloads = Array(syncStore.cachedDailyPayloadsBySource(forDateKey: dateKey).values) +
            Array(syncStore.cachedSleepPayloadsBySource(forSleepDateKey: dateKey).values)
        return payloads
            .filter { $0.sourceDevice.healthSourceIDForRouting == source }
            .compactMap { payload in
                categoryDataTimestamp(in: payload, category: category)
            }
            .max()
    }

    private func categoryDataTimestamp(in payload: PulsarDailyMetricsSyncPayload, category: HealthSourcePriorityCategory) -> Date? {
        switch category {
        case .sleepRecovery:
            return [
                payload.sleep?.computedAt,
                payload.recovery?.computedAt,
                healthMonitorTimestamp(in: payload, kinds: [.sleep, .respiratoryRate, .oxygenSaturation])
            ].compactMap { $0 }.max()
        case .workoutsActivity:
            guard let strain = payload.strain,
                  strain.workoutMinutes > 0 || strain.workoutLoad > 0 else { return nil }
            return strain.computedAt
        case .activitySteps:
            guard let strain = payload.strain,
                  strain.steps > 0 || strain.movementLoad > 0 || (strain.activeEnergyKilocalories ?? 0) > 0 else { return nil }
            return strain.computedAt
        case .heartMetrics:
            return [
                payload.recovery.flatMap { $0.hrvSDNN != nil || $0.restingHeartRate != nil ? $0.computedAt : nil },
                healthMonitorTimestamp(in: payload, kinds: [.hrv, .restingHeartRate])
            ].compactMap { $0 }.max()
        case .temperatureCycle:
            return [
                payload.recovery.flatMap { $0.wristTemperatureDeviation != nil ? $0.computedAt : nil },
                healthMonitorTimestamp(in: payload, kinds: [.wristTemperature])
            ].compactMap { $0 }.max()
        case .stressResilience:
            return payload.stress?.computedAt
        case .manualEntries:
            return nil
        }
    }

    private func healthMonitorTimestamp(
        in payload: PulsarDailyMetricsSyncPayload,
        kinds: Set<PulsarHealthMetricSyncKind>
    ) -> Date? {
        guard let healthMonitor = payload.healthMonitor,
              healthMonitor.metrics.contains(where: { kinds.contains($0.kind) && $0.value != nil }) else {
            return nil
        }
        return healthMonitor.computedAt
    }

    func connectOura() async {
        PulsarOuraLogger.log("Connect tapped")
        guard !isOuraSyncing else {
            PulsarOuraLogger.log("Connect ignored because an Oura operation is already in progress")
            ouraConnectionAlert = OuraConnectionAlert(
                kind: .connectionFailed,
                title: "Oura is already working",
                message: "Oura is already connecting or syncing. Please try again in a moment.",
                debugAuthorizationURL: nil
            )
            return
        }
        ouraConnectionFlowState = .preparing
        PulsarOuraLogger.log("OAuth config validation started")
        let missingKeys = ouraConfiguration.missingConfigurationKeys()
        if missingKeys.isEmpty {
            PulsarOuraLogger.log("OAuth config valid")
        } else {
            PulsarOuraLogger.log("OAuth config missing")
            missingKeys.forEach { missingKey in
                PulsarOuraLogger.log("Missing \(missingKey)")
            }
        }
        guard ouraConfiguration.isReadyForOAuth, missingKeys.isEmpty else {
            let message = ouraUnavailableMessage(missingKeys: missingKeys)
            ouraConnectionFlowState = .failed(errorMessage: message)
            ouraConnectionStore.markSyncError(message)
            ouraConnectionAlert = OuraConnectionAlert(
                kind: .configurationMissing,
                title: ouraUnavailableTitle,
                message: message,
                debugAuthorizationURL: nil
            )
            return
        }
        isOuraSyncing = true
        defer { isOuraSyncing = false }
        do {
            try await ouraAuthService.connect { [weak self] phase in
                switch phase {
                case .openingLogin:
                    self?.ouraConnectionFlowState = .openingLogin
                case .waitingForCallback:
                    self?.ouraConnectionFlowState = .waitingForCallback
                }
            }
            ouraConnectionFlowState = .connected
            PulsarBackgroundRefreshCoordinator.schedule(reason: "ouraConnected")
            if device(for: .ouraRing).canBecomeActiveSource {
                focusedOuraAfterConnection()
            }
        } catch {
            let message = userFacingOuraConnectionError(error)
            ouraConnectionFlowState = .failed(errorMessage: message)
            ouraConnectionStore.markSyncError(message)
            ouraConnectionAlert = OuraConnectionAlert(
                kind: .connectionFailed,
                title: "Oura connection failed",
                message: message,
                debugAuthorizationURL: ouraAuthService.lastAuthorizationURL
            )
        }
    }

    func syncOuraNow() async {
        guard !isOuraSyncing else { return }
        isOuraSyncing = true
        defer { isOuraSyncing = false }
        do {
            let mapped = try await ouraSyncService.sync(date: Date(), calendar: .current, reason: "manualRefresh")
            if let payload = mapped.payload {
                _ = syncStore?.storeLocalPayload(payload, broadcast: true, reason: "OuraManualSync")
            }
            ouraConnectionFlowState = .connected
            PulsarBackgroundRefreshCoordinator.schedule(reason: "ouraManualSync")
            ouraConnectionAlert = nil
            objectWillChange.send()
        } catch {
            ouraConnectionStore.markSyncError(error.localizedDescription)
            PulsarOuraLogger.log("Manual Oura sync failed: \(error.localizedDescription)")
        }
    }

    private func latestCachedDataAt(source: HealthSourceID) -> Date? {
        guard let syncStore else { return nil }
        let calendar = Calendar.current
        let dateKey = PulsarDailyMetricsDateKey.dateKey(for: Date(), calendar: calendar)
        let payloads = Array(syncStore.cachedDailyPayloadsBySource(forDateKey: dateKey).values) +
            Array(syncStore.cachedSleepPayloadsBySource(forSleepDateKey: dateKey).values)
        return payloads
            .filter { $0.sourceDevice.healthSourceIDForRouting == source }
            .compactMap { payload in
                [
                    payload.dailyMetricsComputedAt,
                    payload.sleepComputedAt,
                    payload.stressComputedAt,
                    payload.healthMonitorComputedAt,
                    payload.syncedAt
                ].compactMap { $0 }.max()
            }
            .max()
    }

    private func latestOuraPayload(date: Date = Date(), calendar: Calendar = .current) -> PulsarDailyMetricsSyncPayload? {
        guard let syncStore else { return nil }
        let dateKey = PulsarDailyMetricsDateKey.dateKey(for: date, calendar: calendar)
        let sleepDateKey = SleepWindowResolver.sleepDateKey(forWakeUpDate: date, calendar: calendar)
        var payload = syncStore.cachedDailyPayloadsBySource(forDateKey: dateKey)[.ouraRing]?.sanitizedForDeclaredSource()
        if let sleepPayload = syncStore.cachedSleepPayloadsBySource(forSleepDateKey: sleepDateKey)[.ouraRing]?.sanitizedForDeclaredSource() {
            payload = payload
                .map { $0.merged(with: sleepPayload, calendar: calendar).sanitizedForDeclaredSource() } ?? sleepPayload
        }
        return payload
    }

    private func ouraActivityRow(from payload: PulsarDailyMetricsSyncPayload) -> OuraVisibleDataRow {
        guard let strain = payload.strain else {
            return OuraVisibleDataRow(
                id: "activity",
                title: "Activity",
                value: "No row",
                detail: "No Oura daily_activity row for today.",
                isAvailable: false
            )
        }

        let activeCalories = strain.activeEnergyKilocalories.map { "\(wholeNumberText($0)) active cal" } ?? "active cal unavailable"
        return OuraVisibleDataRow(
            id: "activity",
            title: "Activity",
            value: "\(strain.steps.formatted()) steps",
            detail: "score \(strain.score) · \(activeCalories)",
            isAvailable: true
        )
    }

    private func ouraHeartRateRow(from payload: PulsarDailyMetricsSyncPayload) -> OuraVisibleDataRow {
        guard let strain = payload.strain,
              strain.averageActiveHeartRate != nil || strain.peakHeartRate != nil else {
            return OuraVisibleDataRow(
                id: "heartRate",
                title: "Heart rate",
                value: "No row",
                detail: "No Oura daytime heart-rate summary is available in today's mapped payload.",
                isAvailable: false
            )
        }

        let average = strain.averageActiveHeartRate.map { "avg \(wholeNumberText($0)) bpm" }
        let peak = strain.peakHeartRate.map { "max \(wholeNumberText($0)) bpm" }
        return OuraVisibleDataRow(
            id: "heartRate",
            title: "Heart rate",
            value: [average, peak].compactMap { $0 }.joined(separator: " · "),
            detail: "From Oura heartrate rows used in the activity summary.",
            isAvailable: true
        )
    }

    private func ouraStressRow(from payload: PulsarDailyMetricsSyncPayload) -> OuraVisibleDataRow {
        guard let stress = payload.stress else {
            return OuraVisibleDataRow(
                id: "stress",
                title: "Stress",
                value: "No row",
                detail: "No Oura daily_stress row for today.",
                isAvailable: false
            )
        }

        return OuraVisibleDataRow(
            id: "stress",
            title: "Stress",
            value: "score \(stress.score) \(stress.levelText)",
            detail: stress.driverInsights.first ?? "Daily stress from Oura Cloud.",
            isAvailable: true
        )
    }

    private func ouraSleepRow(from payload: PulsarDailyMetricsSyncPayload) -> OuraVisibleDataRow {
        guard let sleep = payload.sleep else {
            return OuraVisibleDataRow(
                id: "sleep",
                title: "Sleep",
                value: "No row",
                detail: "No Oura sleep row for today's sleep date yet.",
                isAvailable: false
            )
        }

        return OuraVisibleDataRow(
            id: "sleep",
            title: "Sleep",
            value: "score \(sleep.score)",
            detail: "\(wholeNumberText(sleep.totalSleepMinutes))m sleep",
            isAvailable: true
        )
    }

    private func ouraRecoveryRow(from payload: PulsarDailyMetricsSyncPayload) -> OuraVisibleDataRow {
        guard let recovery = payload.recovery else {
            return OuraVisibleDataRow(
                id: "recovery",
                title: "Recovery",
                value: "No row",
                detail: "No Oura daily_readiness row for today.",
                isAvailable: false
            )
        }

        return OuraVisibleDataRow(
            id: "recovery",
            title: "Recovery",
            value: "score \(recovery.score)",
            detail: recovery.statusText,
            isAvailable: true
        )
    }

    private func ouraHealthMonitorRow(from payload: PulsarDailyMetricsSyncPayload) -> OuraVisibleDataRow {
        guard let healthMonitor = payload.healthMonitor else {
            return OuraVisibleDataRow(
                id: "healthMonitor",
                title: "Health Monitor",
                value: "No mapped tile",
                detail: "Oura has no sleep/rest heart-rate, HRV, SpO2, respiratory, or temperature row for the health tiles.",
                isAvailable: false
            )
        }

        let availableMetrics = healthMonitor.metrics
            .filter { $0.value != nil }
            .map { healthMetricTitle($0.kind) }
        return OuraVisibleDataRow(
            id: "healthMonitor",
            title: "Health Monitor",
            value: availableMetrics.isEmpty ? "No mapped tile" : availableMetrics.joined(separator: " · "),
            detail: "Mapped from Oura sleep, readiness, SpO2, or rest samples.",
            isAvailable: !availableMetrics.isEmpty
        )
    }

    private func healthMetricTitle(_ kind: PulsarHealthMetricSyncKind) -> String {
        switch kind {
        case .respiratoryRate:
            return "Respiratory"
        case .restingHeartRate:
            return "Resting HR"
        case .hrv:
            return "HRV"
        case .oxygenSaturation:
            return "SpO2"
        case .wristTemperature:
            return "Temp"
        case .sleep:
            return "Sleep"
        }
    }

    private func wholeNumberText(_ value: Double) -> String {
        Int(value.rounded()).formatted()
    }

    func disconnectOura() async {
        await ouraAuthService.disconnect()
        ouraConnectionFlowState = .idle
        if activeDeviceType == .ouraRing {
            selectActiveDevice(.appleWatch)
        }
    }

    func dismissOuraConnectionAlert() {
        ouraConnectionAlert = nil
    }

    func isPrimaryActionDisabled(for device: MeasurementDevice) -> Bool {
        if device.type == .airPodsPro3 {
            return true
        }
        if device.type == .ouraRing {
            return ouraConnectionFlowState.isConnecting
        }
        return device.isActiveSource
    }

    func selectActiveDevice(_ device: MeasurementDevice) {
        selectActiveDevice(device.type)
    }

    func selectActiveDevice(_ type: MeasurementDeviceType) {
        guard activeDeviceType != type else { return }
        guard device(for: type).canBecomeActiveSource else { return }
        activeDeviceType = type
        defaults.set(type.rawValue, forKey: activeDeviceKey)
    }

    func refreshDeviceStatus() {
        objectWillChange.send()
    }

    private func focusedOuraAfterConnection() {
        // Kept separate so the connection path can update source status without
        // changing category preferences behind the user's back.
        objectWillChange.send()
    }

    func device(for type: MeasurementDeviceType) -> MeasurementDevice {
        switch type {
        case .appleWatch:
            return MeasurementDevice(
                name: type.displayName,
                type: type,
                connectionStatus: .connected,
                batteryPercentage: appleWatchBatterySnapshot?.batteryPercentage,
                isActiveSource: activeDeviceType == type,
                supportedMetrics: [.heartRate, .hrv, .respiratoryRate, .sleep, .activity, .workouts, .strain, .stress, .recovery, .restingHeartRate, .oxygenSaturation, .temperature, .cycle],
                lastSyncAt: appleWatchBatterySnapshot?.timestamp
            )
        case .ouraRing:
            return MeasurementDevice(
                name: type.displayName,
                type: type,
                connectionStatus: ouraDeviceConnectionStatus,
                batteryPercentage: nil,
                isActiveSource: activeDeviceType == type,
                supportedMetrics: [.sleep, .recovery, .readiness, .hrv, .restingHeartRate, .heartRate, .respiratoryRate, .oxygenSaturation, .activity, .workouts, .stress, .temperature, .cycle],
                lastSyncAt: ouraConnectionStore.lastSyncAt
            )
        case .airPodsPro3:
            return MeasurementDevice(
                name: type.displayName,
                type: type,
                connectionStatus: .available,
                batteryPercentage: nil,
                isActiveSource: false,
                supportedMetrics: [.heartRate],
                lastSyncAt: nil
            )
        }
    }

    private var ouraDeviceConnectionStatus: MeasurementDeviceConnectionStatus {
        if ouraConnectionFlowState.isConnecting { return .connecting }
        guard ouraConfiguration.isReadyForOAuth else { return .setupRequired }
        switch ouraConnectionStore.status {
        case .notConnected:
            return .disconnected
        case .connecting:
            return .connecting
        case .connected:
            return .connected
        case .syncError:
            return .syncError
        case .tokenExpired:
            return .tokenExpired
        }
    }

    private func ouraUnavailableMessage(missingKeys: [String]) -> String {
        #if DEBUG
        let baseMessage = "Oura connection is not configured yet. Backend token exchange is required before login can start."
        let keys = missingKeys.isEmpty ? ["Unknown Oura configuration value"] : missingKeys
        return "\(baseMessage)\n\nMissing config: \(keys.joined(separator: ", "))"
        #else
        return "Please try again later."
        #endif
    }

    private var ouraUnavailableTitle: String {
        #if DEBUG
        return "Oura connection is not configured yet"
        #else
        return "Oura connection is not available yet."
        #endif
    }

    private func userFacingOuraConnectionError(_ error: Error) -> String {
        if let authenticationError = error as? ASWebAuthenticationSessionError,
           authenticationError.code == .canceledLogin {
            return "Oura login was canceled. Tap Connect Oura to try again."
        }
        if let error = error as? OuraAPIError {
            switch error {
            case .transport(let message):
                return message
            case .notConfigured(let message):
                if message.localizedCaseInsensitiveContains("backend") {
                    return message
                }
                return ouraUnavailableMessage(missingKeys: ouraConfiguration.missingConfigurationKeys())
            default:
                break
            }
        }
        return error.localizedDescription
    }
}

private extension HealthSourceID {
    var priorityDebugName: String {
        switch self {
        case .appleWatch:
            return "Apple Watch / HealthKit"
        case .ouraRing:
            return "Oura Ring"
        case .airPodsPro3:
            return "AirPods Pro 3 workout backup"
        case .iPhone:
            return "iPhone Sensors"
        case .manual:
            return "Manual Entry"
        }
    }
}
