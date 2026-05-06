//
//  HomeViewModel.swift
//  Pulsar
//

import Combine
import Foundation
import HealthKit

@MainActor
final class HomeViewModel: ObservableObject {
    private static let minimumAutomaticSyncInterval: TimeInterval = 12 * 60
    private static let lastSuccessfulAutomaticSyncKey = "pulsar.iphone.lastSuccessfulAutomaticSyncAt.v1"

    private enum SyncTrigger {
        case automaticAppEntry(reason: String)
        case manual(reason: String)
        case silent(reason: String)

        var reason: String {
            switch self {
            case .automaticAppEntry(let reason), .manual(let reason), .silent(let reason):
                reason
            }
        }

        var showsBanner: Bool {
            switch self {
            case .automaticAppEntry, .manual: true
            case .silent: false
            }
        }

        var isAutomatic: Bool {
            if case .automaticAppEntry = self { return true }
            return false
        }

        var isManual: Bool {
            if case .manual = self { return true }
            return false
        }
    }

    @Published private(set) var dashboard: HomeDashboard = .empty
    @Published private(set) var selectedDate: Date
    @Published private(set) var strainRecords: [DailyStrainRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var healthKitStatus = "No HealthKit data loaded"

    let profileStore: ProfileStore
    private let healthKit: HealthKitGateway
    private let sleepDataService: SleepSummaryProviding
    private let strainDataService: StrainSummaryProviding
    private let recoveryDataService: RecoverySummaryProviding
    private let lifecycleStore: AppLifecycleStore
    private let syncStore: PulsarWatchConnectivitySyncStore
    private let dashboardCache: PulsarDashboardCache
    private let bannerCenter: PulsarSyncBannerCenter
    private let calendar: Calendar
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []

    init(profileStore: ProfileStore? = nil, healthKit: HealthKitGateway = HealthKitGateway(), sleepDataService: SleepSummaryProviding? = nil, strainDataService: StrainSummaryProviding? = nil, recoveryDataService: RecoverySummaryProviding? = nil, lifecycleStore: AppLifecycleStore? = nil, syncStore: PulsarWatchConnectivitySyncStore? = nil, dashboardCache: PulsarDashboardCache? = nil, bannerCenter: PulsarSyncBannerCenter? = nil, calendar: Calendar = .current, defaults: UserDefaults = .standard) {
        self.profileStore = profileStore ?? ProfileStore()
        self.healthKit = healthKit
        let resolvedSleepDataService = sleepDataService ?? SleepDataService(healthKit: healthKit)
        let resolvedStrainDataService = strainDataService ?? StrainDataService(healthKit: healthKit)
        self.sleepDataService = resolvedSleepDataService
        self.strainDataService = resolvedStrainDataService
        self.recoveryDataService = recoveryDataService ?? RecoveryDataService(healthKit: healthKit, sleepDataService: resolvedSleepDataService, strainDataService: resolvedStrainDataService)
        self.lifecycleStore = lifecycleStore ?? AppLifecycleStore()
        self.syncStore = syncStore ?? .shared
        self.dashboardCache = dashboardCache ?? PulsarDashboardCache()
        self.bannerCenter = bannerCenter ?? .shared
        self.calendar = calendar
        self.defaults = defaults
        self.lifecycleStore.registerFirstLaunchIfNeeded()
        self.selectedDate = calendar.startOfDay(for: Date())
        refreshProfileFromStore()
        loadCachedDashboardIfAvailable()
        observeSyncPayloads()
    }

    func refreshProfileFromStore() {
        dashboard.profile = profileStore.profile
    }

    func makeSleepDetailsViewModel() -> SleepDetailsViewModel {
        SleepDetailsViewModel(
            initialSummary: dashboard.sleep,
            profile: profileStore.profile,
            wakeUpDate: selectedDate,
            provider: sleepDataService,
            calendar: calendar,
            canRequestHealthData: lifecycleStore.hasSeenHealthKitOnboarding && dashboard.sleep.confidenceExplanation != SleepSummary.permissionRequired.confidenceExplanation,
            syncStore: syncStore
        )
    }

    func makeStrainDetailsViewModel() -> StrainDetailsViewModel {
        StrainDetailsViewModel(
            initialSummary: dashboard.strain,
            profile: profileStore.profile,
            date: selectedDate,
            provider: strainDataService,
            calendar: calendar,
            canRequestHealthData: lifecycleStore.hasSeenHealthKitOnboarding
        )
    }

    func makeRecoveryDetailsViewModel() -> RecoveryDetailsViewModel {
        RecoveryDetailsViewModel(
            initialSummary: dashboard.recovery,
            profile: profileStore.profile,
            date: selectedDate,
            provider: recoveryDataService,
            calendar: calendar,
            canRequestHealthData: lifecycleStore.hasSeenHealthKitOnboarding
        )
    }

    private var lastSuccessfulAutomaticSyncAt: Date? {
        get { defaults.object(forKey: Self.lastSuccessfulAutomaticSyncKey) as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Self.lastSuccessfulAutomaticSyncKey)
            } else {
                defaults.removeObject(forKey: Self.lastSuccessfulAutomaticSyncKey)
            }
        }
    }

    func selectDate(_ date: Date) async {
        let day = calendar.startOfDay(for: date)
        guard !calendar.isDate(day, inSameDayAs: selectedDate) else { return }
        selectedDate = day
        await performSync(trigger: .silent(reason: "selectedDateChanged"))
    }

    func appDidBecomeActive() async {
        PulsarSyncDebugLogger.log("app became active")
        await requestAutomaticSync(reason: "appBecameActive")
    }

    func requestInitialAppEntrySync() async {
        await requestAutomaticSync(reason: "initialAppEntry")
    }

    func load() async {
        PulsarSyncDebugLogger.log("manual refresh started")
        await performSync(trigger: .manual(reason: "manualRefresh"))
    }

    private func requestAutomaticSync(reason: String) async {
        PulsarSyncDebugLogger.log("automatic sync requested reason=\(reason)")
        let now = Date()
        guard !isLoading else {
            PulsarSyncDebugLogger.log("automatic sync skipped because sync is already in progress reason=\(reason)")
            return
        }
        if let lastSuccessfulAutomaticSyncAt,
           now.timeIntervalSince(lastSuccessfulAutomaticSyncAt) < Self.minimumAutomaticSyncInterval {
            PulsarSyncDebugLogger.log("automatic sync skipped because last sync was recent reason=\(reason) last=\(lastSuccessfulAutomaticSyncAt) minimumInterval=\(Self.minimumAutomaticSyncInterval)")
            return
        }
        await performSync(trigger: .automaticAppEntry(reason: reason))
    }

    private func performSync(trigger: SyncTrigger) async {
        guard !isLoading else {
            let prefix = trigger.isAutomatic ? "automatic" : (trigger.isManual ? "manual" : "silent")
            PulsarSyncDebugLogger.log("\(prefix) sync skipped because sync is already in progress reason=\(trigger.reason)")
            return
        }
        isLoading = true
        defer { isLoading = false }
        if trigger.showsBanner {
            PulsarSyncDebugLogger.log("visible sync pill shown reason=\(trigger.reason)")
            bannerCenter.showSyncing()
        }
        let syncSessionID = UUID()
        PulsarSyncDebugLogger.log("sync started day=\(selectedDate) session=\(syncSessionID.uuidString) reason=\(trigger.reason)")

        let refreshDate = Date()
        let referenceDate = dashboardReferenceDate(for: selectedDate, now: refreshDate)
        let wakeUpDate = selectedDate
        var didCommitDailyMetrics = false
        var didBuildValidPayload = false

        do {
            let authorizationStatus = await healthKit.authorizationRequestStatus()
            PulsarSyncDebugLogger.log("HealthKit permissions status=\(authorizationStatus.rawValue)")
            if authorizationStatus == .shouldRequest && !lifecycleStore.hasSeenHealthKitOnboarding {
                throw HealthKitGatewayError.authorizationDenied
            }
            try await healthKit.requestAuthorization()
            let profilePayload = await healthKit.fetchProfile()
            profileStore.mergeHealthKitProfile(
                heightCentimeters: profilePayload.heightCentimeters,
                weightKilograms: profilePayload.weightKilograms,
                dateOfBirth: profilePayload.dateOfBirth,
                biologicalSex: profilePayload.biologicalSex
            )
            let freshDashboard = try await buildHealthKitDashboard(profile: profileStore.profile, date: referenceDate, wakeUpDate: wakeUpDate, generatedAt: refreshDate)
            dashboard = canonicalDashboard(for: mergeWithLastKnownValues(freshDashboard, fallback: dashboard))
            healthKitStatus = "HealthKit connected"
            if let payload = dashboard.syncPayload(sourceDevice: .iPhone, syncSessionID: syncSessionID, calendar: calendar) {
                didBuildValidPayload = payload.hasValidData
                let didCommitPayload = syncStore.storeLocalPayload(payload, broadcast: true, reason: "iPhoneHealthKitSync")
                didCommitDailyMetrics = payload.hasCompleteDailyScores && didCommitPayload
                dashboard = canonicalDashboard(for: dashboard)
                dashboardCache.save(dashboard)
                PulsarSyncDebugLogger.log("calculated Strain value=\(payload.strain?.score ?? 0) session=\(syncSessionID.uuidString)")
                PulsarSyncDebugLogger.log("calculated Recovery value=\(payload.recovery?.score ?? 0) session=\(syncSessionID.uuidString)")
                PulsarSyncDebugLogger.log("Sleep Score calculated value=\(payload.sleep?.score ?? 0) sleepDateKey=\(payload.sleep?.sleepDateKey ?? "none") session=\(syncSessionID.uuidString)")
            } else {
                dashboardCache.save(dashboard)
            }
            await healthKit.startObservers { [weak self] _ in
                await self?.healthKitSamplesDidChange()
            }
            let completedWithUsableData = didBuildValidPayload || hasVisibleMetrics(dashboard)
            if (trigger.isAutomatic || trigger.isManual), completedWithUsableData {
                lastSuccessfulAutomaticSyncAt = refreshDate
            }
            if trigger.showsBanner {
                if completedWithUsableData {
                    bannerCenter.showSuccess()
                } else {
                    PulsarSyncDebugLogger.log("sync completed without a usable payload session=\(syncSessionID.uuidString) dailyCommit=\(didCommitDailyMetrics)")
                    bannerCenter.showFailure()
                }
            }
        } catch HealthKitGatewayError.healthDataUnavailable {
            if !hasVisibleMetrics(dashboard) {
                dashboard = buildUnavailableDashboard(profile: profileStore.profile, date: referenceDate)
            }
            healthKitStatus = "HealthKit unavailable"
            if trigger.showsBanner { bannerCenter.showFailure() }
        } catch {
            if !hasVisibleMetrics(dashboard) {
                dashboard = buildPermissionRequiredDashboard(profile: profileStore.profile, date: referenceDate)
            }
            healthKitStatus = "Health permission required"
            if trigger.showsBanner { bannerCenter.showFailure() }
        }
    }

    private func healthKitSamplesDidChange() async {
        PulsarSyncDebugLogger.log("HealthKit observer update received; deferring full sync until app entry or manual refresh")
    }

    private func buildHealthKitDashboard(profile: UserProfile, date: Date, wakeUpDate: Date, generatedAt: Date) async throws -> HomeDashboard {
        async let sleepTask = sleepDataService.sleepSummary(profile: profile, wakeUpDate: wakeUpDate, calendar: calendar, refreshedAt: generatedAt)
        async let strainTask = strainDataService.strainSummary(profile: profile, date: date, calendar: calendar, refreshedAt: generatedAt)
        async let recoveryTask = recoveryDataService.recoverySummary(profile: profile, date: date, calendar: calendar, refreshedAt: generatedAt)
        let (sleep, strain, recovery) = try await (sleepTask, strainTask, recoveryTask)
        upsertStrainRecordIfUsable(strain, date: date)
        return HomeDashboard(profile: profile, sleep: sleep, recovery: recovery, strain: strain, generatedAt: generatedAt, usingSampleData: false)
    }

    private func buildPermissionRequiredDashboard(profile: UserProfile, date: Date) -> HomeDashboard {
        HomeDashboard(profile: profile, sleep: .permissionRequired, recovery: .missing, strain: .missing, generatedAt: date, usingSampleData: false)
    }

    private func buildUnavailableDashboard(profile: UserProfile, date: Date) -> HomeDashboard {
        var dashboard = HomeDashboard(profile: profile, sleep: .permissionRequired, recovery: .missing, strain: .missing, generatedAt: date, usingSampleData: false)
        dashboard.sleep.confidenceExplanation = "Health data is unavailable on this device."
        dashboard.sleep.notes = ["Pulsar cannot read sleep without HealthKit availability and permission. Demo data is only used in previews."]
        return dashboard
    }

    private func upsertStrainRecordIfUsable(_ summary: StrainSummary, date: Date) {
        guard summary.confidence != .missing,
              summary.score > 0,
              (!summary.sourceBadges.isEmpty || summary.steps > 0 || summary.workoutMinutes > 0) else { return }

        let day = calendar.startOfDay(for: date)
        let record = DailyStrainRecord(
            date: day,
            strainScore: summary.score,
            workoutMinutes: Int(summary.workoutMinutes.rounded()),
            steps: summary.steps,
            activeEnergyKilocalories: Int((summary.activeEnergyKilocalories ?? summary.movementLoad * 8).rounded()),
            confidence: summary.confidence,
            sourceName: summary.sourceBadges.first?.displayName ?? "HealthKit"
        )
        strainRecords.removeAll { calendar.isDate($0.date, inSameDayAs: day) }
        strainRecords.append(record)
        strainRecords.sort { $0.date < $1.date }
        lifecycleStore.registerStrainSync(on: day)
    }

    private func dashboardReferenceDate(for date: Date, now: Date) -> Date {
        if calendar.isDate(date, inSameDayAs: now) { return now }
        guard let interval = calendar.dateInterval(of: .day, for: date) else { return date }
        return interval.end.addingTimeInterval(-1)
    }

    private func observeSyncPayloads() {
        syncStore.$latestPayload
            .receive(on: RunLoop.main)
            .sink { [weak self] payload in
                self?.applyIncomingSyncPayload(payload)
            }
            .store(in: &cancellables)
    }

    private func loadCachedDashboardIfAvailable() {
        guard let cached = dashboardCache.loadDashboard(for: selectedDate, calendar: calendar) else { return }
        dashboard = cached
        healthKitStatus = "Showing latest available data"
    }

    private func applyIncomingSyncPayload(_ payload: PulsarDailyMetricsSyncPayload?) {
        guard let payload, payload.isValidPayload, payload.applies(to: selectedDate, calendar: calendar) else {
            PulsarSyncDebugLogger.log("silent payload update rejected because incoming data was older or invalid")
            return
        }
        let currentTimestamp = latestVisibleMetricTimestamp(in: dashboard)
        guard payload.syncedAt > currentTimestamp || payloadImprovesAnyMetric(payload, dashboard: dashboard) else {
            PulsarSyncDebugLogger.log("silent payload update rejected because incoming data was older or invalid session=\(payload.syncSessionID?.uuidString ?? "none")")
            return
        }
        dashboard = dashboard.applying(payload: payload, calendar: calendar)
        dashboardCache.save(dashboard)
        healthKitStatus = payload.sourceDevice == .appleWatch ? "Synced from Apple Watch" : "HealthKit connected"
        PulsarSyncDebugLogger.log("silent payload update accepted source=\(payload.sourceDevice.rawValue) sleepDateKey=\(payload.sleep?.sleepDateKey ?? "none") session=\(payload.syncSessionID?.uuidString ?? "none") fingerprint=\(payload.resolvedDataFingerprint)")
    }

    private func mergeWithLastKnownValues(_ fresh: HomeDashboard, fallback: HomeDashboard) -> HomeDashboard {
        guard hasVisibleMetrics(fallback) else { return fresh }
        var merged = fresh
        if !hasUsableStrain(fresh.strain), hasUsableStrain(fallback.strain) {
            merged.strain = fallback.strain
        }
        if !hasUsableRecovery(fresh.recovery), hasUsableRecovery(fallback.recovery) {
            merged.recovery = fallback.recovery
        }
        if !hasUsableSleep(fresh.sleep), hasUsableSleep(fallback.sleep) {
            merged.sleep = fallback.sleep
        }
        return merged
    }

    private func canonicalDashboard(for dashboard: HomeDashboard) -> HomeDashboard {
        let sleepDateKey = SleepWindowResolver.sleepDateKey(forWakeUpDate: selectedDate, calendar: calendar)
        let dateKey = PulsarDailyMetricsDateKey.dateKey(for: selectedDate, calendar: calendar)
        var payload = syncStore.cachedDailyPayload(forDateKey: dateKey) ?? syncStore.cachedPayload(for: selectedDate, calendar: calendar)
        if let sleepPayload = syncStore.cachedSleepPayload(forSleepDateKey: sleepDateKey) {
            payload = payload.map { $0.merged(with: sleepPayload, calendar: calendar) } ?? sleepPayload
        }
        guard let payload else { return dashboard }
        guard payload.isValidPayload else { return dashboard }
        let currentTimestamp = latestVisibleMetricTimestamp(in: dashboard)
        guard payload.syncedAt >= currentTimestamp || payloadImprovesAnyMetric(payload, dashboard: dashboard) else { return dashboard }
        return dashboard.applying(payload: payload, calendar: calendar)
    }

    private func payloadImprovesAnyMetric(_ payload: PulsarDailyMetricsSyncPayload, dashboard: HomeDashboard) -> Bool {
        let incomingSleepUpdatedAt = payload.sleep?.computedAt ?? .distantPast
        let currentSleepUpdatedAt = dashboard.sleep.lastUpdated ?? .distantPast
        let incomingDailyUpdatedAt = max(payload.strain?.computedAt ?? .distantPast, payload.recovery?.computedAt ?? .distantPast)
        let currentDailyUpdatedAt = max(dashboard.strain.lastUpdated ?? .distantPast, dashboard.recovery.lastUpdated ?? .distantPast)
        return ((!hasUsableStrain(dashboard.strain) || !hasUsableRecovery(dashboard.recovery)) && payload.hasCompleteDailyScores) ||
        (payload.hasCompleteDailyScores && incomingDailyUpdatedAt > currentDailyUpdatedAt) ||
        (!hasUsableSleep(dashboard.sleep) && payload.sleep?.isValid == true) ||
        (payload.sleep?.isValid == true && incomingSleepUpdatedAt > currentSleepUpdatedAt)
    }

    private func latestVisibleMetricTimestamp(in dashboard: HomeDashboard) -> Date {
        max(
            max(dashboard.strain.lastUpdated ?? .distantPast, dashboard.recovery.lastUpdated ?? .distantPast),
            max(dashboard.sleep.lastUpdated ?? .distantPast, dashboard.generatedAt)
        )
    }

    private func hasVisibleMetrics(_ dashboard: HomeDashboard) -> Bool {
        hasUsableStrain(dashboard.strain) || hasUsableRecovery(dashboard.recovery) || hasUsableSleep(dashboard.sleep)
    }

    private func hasUsableStrain(_ summary: StrainSummary) -> Bool {
        summary.score > 0 || summary.steps > 0 || summary.workoutMinutes > 0 || summary.exerciseMinutes > 0 || (summary.activeEnergyKilocalories ?? 0) > 0
    }

    private func hasUsableRecovery(_ summary: RecoverySummary) -> Bool {
        summary.score > 0 || summary.hrvSDNN != nil || summary.restingHeartRate != nil || summary.sleepDuration != nil || summary.strainScore != nil
    }

    private func hasUsableSleep(_ summary: SleepSummary) -> Bool {
        summary.score > 0 || summary.totalSleepMinutes > 0 || summary.sleepStart != nil || summary.wakeTime != nil
    }

}
