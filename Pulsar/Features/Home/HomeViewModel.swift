//
//  HomeViewModel.swift
//  Pulsar
//

import Combine
import Foundation
import HealthKit

@MainActor
final class HomeViewModel: ObservableObject {
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

        var recordsSuccessfulSyncForThrottling: Bool {
            switch self {
            case .automaticAppEntry, .manual:
                return true
            case .silent(let reason):
                return reason.hasPrefix("healthKitAnchoredUpdate") || reason == "backgroundRefresh"
            }
        }
    }

    @Published private(set) var dashboard: HomeDashboard = .empty {
        didSet {
            persistWidgetSnapshot(for: dashboard)
        }
    }
    @Published private(set) var selectedDate: Date
    @Published private(set) var strainRecords: [DailyStrainRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var healthKitStatus = "No health data loaded"
    #if DEBUG
    @Published private(set) var latestOuraDebugReport: OuraSyncDebugReport?
    #endif

    let profileStore: ProfileStore
    private let healthKit: HealthKitGateway
    private let sleepDataService: SleepSummaryProviding
    private let strainDataService: StrainSummaryProviding
    private let recoveryDataService: RecoverySummaryProviding
    private let stressDataService: StressSummaryProviding
    private let healthMonitorDataService: HealthMonitorSummaryProviding
    private let lifecycleStore: AppLifecycleStore
    private let syncStore: PulsarWatchConnectivitySyncStore
    private let dashboardCache: PulsarDashboardCache
    private let dailyHistoryStore: DailyHealthHistoryStore
    private let bannerCenter: PulsarSyncBannerCenter
    private let healthEventMonitor: HealthEventMonitor
    private let ouraSyncService: OuraSyncServicing
    private let ouraConnectionStore: OuraConnectionStore
    private let sourcePriorityStore: HealthSourcePriorityStore
    private let syncPolicy: PulsarSyncPolicy
    private let calendar: Calendar
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []
    private var healthKitAnchors: [String: HKQueryAnchor] = [:]
    private var deferredSilentSyncTask: Task<Void, Never>?
    private var liveStressRefreshTask: Task<Void, Never>?
    private var lastLiveStressRefreshAt: Date?

    init(profileStore: ProfileStore? = nil, healthKit: HealthKitGateway = HealthKitGateway(), sleepDataService: SleepSummaryProviding? = nil, strainDataService: StrainSummaryProviding? = nil, recoveryDataService: RecoverySummaryProviding? = nil, stressDataService: StressSummaryProviding? = nil, healthMonitorDataService: HealthMonitorSummaryProviding? = nil, healthEventMonitor: HealthEventMonitor? = nil, lifecycleStore: AppLifecycleStore? = nil, syncStore: PulsarWatchConnectivitySyncStore? = nil, dashboardCache: PulsarDashboardCache? = nil, dailyHistoryStore: DailyHealthHistoryStore? = nil, bannerCenter: PulsarSyncBannerCenter? = nil, ouraSyncService: OuraSyncServicing? = nil, sourcePriorityStore: HealthSourcePriorityStore? = nil, syncPolicy: PulsarSyncPolicy = PulsarSyncPolicy(), calendar: Calendar = .current, defaults: UserDefaults = .standard) {
        self.profileStore = profileStore ?? ProfileStore()
        self.healthKit = healthKit
        let resolvedSleepDataService = sleepDataService ?? SleepDataService(healthKit: healthKit)
        let resolvedStrainDataService = strainDataService ?? StrainDataService(healthKit: healthKit)
        let ouraConfiguration = OuraIntegrationConfiguration.load(defaults: defaults)
        let ouraTokenStore = OuraKeychainTokenStore()
        let ouraAuthService = OuraAuthService(configuration: ouraConfiguration, tokenStorage: ouraTokenStore)
        let ouraAPIClient: OuraAPIClientProtocol = ouraConfiguration.mockMode
            ? MockOuraAPIClient()
            : URLSessionOuraAPIClient(authService: ouraAuthService)
        self.sleepDataService = resolvedSleepDataService
        self.strainDataService = resolvedStrainDataService
        self.recoveryDataService = recoveryDataService ?? RecoveryDataService(healthKit: healthKit, sleepDataService: resolvedSleepDataService, strainDataService: resolvedStrainDataService)
        self.stressDataService = stressDataService ?? StressDataService(healthKit: healthKit)
        self.healthMonitorDataService = healthMonitorDataService ?? HealthMonitorDataService(healthKit: healthKit)
        self.lifecycleStore = lifecycleStore ?? AppLifecycleStore()
        self.syncStore = syncStore ?? .shared
        self.dashboardCache = dashboardCache ?? PulsarDashboardCache()
        self.dailyHistoryStore = dailyHistoryStore ?? DailyHealthHistoryStore(defaults: defaults)
        self.bannerCenter = bannerCenter ?? .shared
        self.healthEventMonitor = healthEventMonitor ?? HealthEventMonitor(healthKit: healthKit, sleepDataService: resolvedSleepDataService, calendar: calendar)
        self.ouraConnectionStore = ouraAuthService.connectionStore
        self.ouraSyncService = ouraSyncService ?? OuraSyncService(
            apiClient: ouraAPIClient,
            authService: ouraAuthService,
            connectionStore: ouraAuthService.connectionStore
        )
        self.sourcePriorityStore = sourcePriorityStore ?? HealthSourcePriorityStore(defaults: defaults)
        self.syncPolicy = syncPolicy
        self.calendar = calendar
        self.defaults = defaults
        self.lifecycleStore.registerFirstLaunchIfNeeded()
        self.selectedDate = calendar.startOfDay(for: Date())
        refreshProfileFromStore()
        loadCalendarHistoryFromStores()
        loadCachedDashboardIfAvailable()
        observeSyncPayloads()
        observeSourcePriorityChanges()
        persistWidgetSnapshot(for: dashboard)
    }

    deinit {
        deferredSilentSyncTask?.cancel()
        liveStressRefreshTask?.cancel()
    }

    func refreshProfileFromStore() {
        dashboard.profile = profileStore.profile
    }

    #if DEBUG
    func usePreviewDashboard(_ dashboard: HomeDashboard, healthKitStatus: String = "HealthKit connected") {
        self.dashboard = dashboard
        self.selectedDate = calendar.startOfDay(for: dashboard.generatedAt)
        self.healthKitStatus = healthKitStatus
    }
    #endif

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
            recoveryScore: dashboard.recovery.score > 0 ? dashboard.recovery.score : nil,
            recentStrainScores: recentStrainScores(before: selectedDate),
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
        if !loadCachedDashboardIfAvailable() {
            dashboard = emptyDashboard(for: day)
            healthKitStatus = "No saved data for selected day"
        }
        await performSync(trigger: .silent(reason: "selectedDateChanged"))
    }

    func appDidBecomeActive() async {
        PulsarSyncDebugLogger.log("app became active")
        profileStore.refreshSleepPreferenceSideEffects(reason: "homeViewModelAppDidBecomeActive")
        startLiveStressUpdates()
        await requestAutomaticSync(reason: "appBecameActive")
    }

    func appDidResignActive() {
        stopLiveStressUpdates()
    }

    func requestInitialAppEntrySync() async {
        profileStore.refreshSleepPreferenceSideEffects(reason: "homeViewModelInitialEntry")
        startLiveStressUpdates()
        await requestAutomaticSync(reason: "initialAppEntry")
    }

    func load() async {
        PulsarSyncDebugLogger.log("Sync requested reason=manualRefresh")
        PulsarSyncDebugLogger.log("manual refresh started")
        await performSync(trigger: .manual(reason: "manualRefresh"))
    }

    #if DEBUG
    func dismissOuraDebugReport() {
        latestOuraDebugReport = nil
    }

    func homeRenderDiagnosticSignature(uiRenderedSleepMinutes: Double) -> String {
        [
            String(selectedDate.timeIntervalSinceReferenceDate),
            healthKitStatus,
            diagnosticDashboardState(dashboard, uiRenderedSleepMinutes: uiRenderedSleepMinutes),
            diagnosticRenderedRoutes(dashboard),
            diagnosticCurrentSourceSummary()
        ].joined(separator: "|")
    }

    func logHomeRenderedState(uiRenderedSleepMinutes: Double) {
        let dateKey = PulsarDailyMetricsDateKey.dateKey(for: selectedDate, calendar: calendar)
        let sleepDateKey = SleepWindowResolver.sleepDateKey(forWakeUpDate: selectedDate, calendar: calendar)
        PulsarSyncDebugLogger.log("home rendered state selectedDay=\(selectedDate) dateKey=\(dateKey) sleepDateKey=\(sleepDateKey) currentSources=\(diagnosticCurrentSourceSummary()) routes=\(diagnosticRenderedRoutes(dashboard)) \(diagnosticDashboardState(dashboard, uiRenderedSleepMinutes: uiRenderedSleepMinutes)) healthKitStatus=\(healthKitStatus)")
    }
    #endif

    private func requestAutomaticSync(reason: String) async {
        PulsarSyncDebugLogger.log("Sync requested reason=\(reason)")
        PulsarSyncDebugLogger.log("automatic sync requested reason=\(reason)")
        let now = Date()
        guard !isLoading else {
            PulsarSyncDebugLogger.log("automatic sync skipped because sync is already in progress reason=\(reason)")
            return
        }
        let hasStaleVisibleMetrics = visibleMetricsAreStale(now: now)
        let decision = syncPolicy.decision(
            lastSuccessfulSyncAt: lastSuccessfulAutomaticSyncAt,
            now: now,
            reason: reason,
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            hasStaleVisibleMetrics: hasStaleVisibleMetrics
        )
        guard decision.shouldSync else {
            PulsarSyncDebugLogger.log("automatic sync skipped because last sync was recent reason=\(reason) last=\(lastSuccessfulAutomaticSyncAt?.description ?? "none") minimumInterval=\(decision.minimumInterval) staleVisibleMetrics=\(hasStaleVisibleMetrics) lowPowerMode=\(ProcessInfo.processInfo.isLowPowerModeEnabled)")
            return
        }
        await performSync(trigger: .automaticAppEntry(reason: reason))
    }

    private func requestSilentSync(reason: String) async {
        PulsarSyncDebugLogger.log("Sync requested reason=\(reason)")
        let now = Date()
        guard !isLoading else {
            PulsarSyncDebugLogger.log("silent sync skipped because sync is already in progress reason=\(reason)")
            scheduleDeferredHealthKitSyncIfNeeded(reason: reason, delay: 5)
            return
        }
        let hasStaleVisibleMetrics = visibleMetricsAreStale(now: now)
        let decision = syncPolicy.decision(
            lastSuccessfulSyncAt: lastSuccessfulAutomaticSyncAt,
            now: now,
            reason: reason,
            lowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            hasStaleVisibleMetrics: hasStaleVisibleMetrics
        )
        guard decision.shouldSync else {
            PulsarSyncDebugLogger.log("silent sync skipped because last sync was recent reason=\(reason) last=\(lastSuccessfulAutomaticSyncAt?.description ?? "none") minimumInterval=\(decision.minimumInterval) staleVisibleMetrics=\(hasStaleVisibleMetrics) lowPowerMode=\(ProcessInfo.processInfo.isLowPowerModeEnabled)")
            if reason.hasPrefix("healthKitAnchoredUpdate") {
                let elapsed = lastSuccessfulAutomaticSyncAt.map { now.timeIntervalSince($0) } ?? 0
                let delay = max(1, decision.minimumInterval - elapsed)
                scheduleDeferredHealthKitSyncIfNeeded(reason: reason, delay: delay)
            }
            return
        }
        await performSync(trigger: .silent(reason: reason))
    }

    private func scheduleDeferredHealthKitSyncIfNeeded(reason: String, delay: TimeInterval) {
        guard reason.hasPrefix("healthKitAnchoredUpdate") else { return }
        guard deferredSilentSyncTask == nil else {
            PulsarSyncDebugLogger.log("deferred HealthKit sync already scheduled reason=\(reason)")
            return
        }
        let nanoseconds = UInt64(max(1, delay) * 1_000_000_000)
        deferredSilentSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            await self?.runDeferredHealthKitSync(reason: reason)
        }
        PulsarSyncDebugLogger.log("deferred HealthKit sync scheduled reason=\(reason) delay=\(String(format: "%.1f", max(1, delay)))s")
    }

    private func runDeferredHealthKitSync(reason: String) async {
        deferredSilentSyncTask = nil
        guard !Task.isCancelled else { return }
        PulsarSyncDebugLogger.log("deferred HealthKit sync running reason=\(reason)")
        await performSync(trigger: .silent(reason: "\(reason):deferred"))
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
            let healthKitDashboard = try await buildHealthKitDashboard(profile: profileStore.profile, date: referenceDate, wakeUpDate: wakeUpDate, generatedAt: refreshDate)
            let healthKitPayload = healthKitDashboard.syncPayload(sourceDevice: .iPhone, syncSessionID: syncSessionID, calendar: calendar)
            let ouraPayload = await syncOuraPayloadIfNeeded(for: wakeUpDate, reason: trigger.reason)
            dashboard = routedDashboard(
                healthKitDashboard: healthKitDashboard,
                ouraPayload: ouraPayload,
                date: referenceDate,
                generatedAt: refreshDate,
                now: refreshDate
            )
            logStrainValidation(dashboard: dashboard, context: ouraPayload == nil ? "iPhone" : "RoutedSources")
            healthKitStatus = "HealthKit connected"
            if let payload = healthKitPayload {
                didBuildValidPayload = payload.hasValidData
                let didCommitPayload = syncStore.storeLocalPayload(payload, broadcast: true, reason: "iPhoneHealthKitSync")
                didCommitDailyMetrics = payload.hasCompleteDailyScores && didCommitPayload
                upsertDailyRecordIfUsable(payload)
                PulsarSyncDebugLogger.log("calculated Strain value=\(payload.strain?.score ?? 0) session=\(syncSessionID.uuidString)")
                PulsarSyncDebugLogger.log("calculated Recovery value=\(payload.recovery?.score ?? 0) session=\(syncSessionID.uuidString)")
                PulsarSyncDebugLogger.log("calculated Stress value=\(payload.stress?.score ?? 0) session=\(syncSessionID.uuidString)")
                PulsarSyncDebugLogger.log("Sleep Score calculated value=\(payload.sleep?.score ?? 0) sleepDateKey=\(payload.sleep?.sleepDateKey ?? "none") session=\(syncSessionID.uuidString)")
            }
            if let ouraPayload {
                didBuildValidPayload = didBuildValidPayload || ouraPayload.hasValidData
                let didCommitOuraPayload = syncStore.storeLocalPayload(ouraPayload, broadcast: true, reason: "OuraCloudSync")
                didCommitDailyMetrics = didCommitDailyMetrics || (ouraPayload.hasCompleteDailyScores && didCommitOuraPayload)
                upsertDailyRecordIfUsable(ouraPayload)
                healthKitStatus = "HealthKit connected · Oura synced"
                PulsarOuraLogger.log("Oura payload committed dateKey=\(ouraPayload.resolvedDateKey) session=\(ouraPayload.syncSessionID?.uuidString ?? "none")")
            }
            if let cachedDashboard = sourceRoutedCachedDashboard(for: selectedDate) {
                dashboard = mergeWithLastKnownValues(cachedDashboard, fallback: dashboard)
            }
            dashboardCache.save(dashboard)
            await healthKit.startObservers { [weak self] sampleType in
                await self?.healthKitSamplesDidChange(sampleType)
            }
            await healthEventMonitor.processForegroundSnapshot(profile: profileStore.profile, dashboard: dashboard, now: refreshDate)
            let completedWithUsableData = didBuildValidPayload || hasVisibleMetrics(dashboard)
            if trigger.recordsSuccessfulSyncForThrottling, completedWithUsableData {
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

    private func healthKitSamplesDidChange(_ sampleType: HKSampleType) async {
        let metric = PulsarHealthKitIncrementalMetric.label(for: sampleType)
        let anchorKey = sampleType.identifier
        let start = calendar.date(byAdding: .day, value: -3, to: Date())
        let changes = await healthKit.anchoredChanges(for: sampleType, anchor: healthKitAnchors[anchorKey], start: start)
        healthKitAnchors[anchorKey] = changes.newAnchor
        PulsarHealthKitLogger.log("Anchored update received metric=\(metric) samples=\(changes.samples.count) deleted=\(changes.deletedObjects.count)")
        await healthEventMonitor.processObservedChange(
            sampleType: sampleType,
            profile: profileStore.profile,
            dashboard: dashboard
        )
        guard !changes.samples.isEmpty || !changes.deletedObjects.isEmpty else {
            return
        }
        if isStressRelevantSampleType(sampleType) {
            await refreshLiveStress(reason: "healthKitAnchoredUpdate:\(metric)", force: true)
        }
        await requestSilentSync(reason: "healthKitAnchoredUpdate:\(metric)")
    }

    private func startLiveStressUpdates() {
        guard liveStressRefreshTask == nil else { return }
        liveStressRefreshTask = Task { [weak self] in
            await self?.refreshLiveStress(reason: "foregroundStressStart", force: true)
            while !Task.isCancelled {
                let interval: TimeInterval = ProcessInfo.processInfo.isLowPowerModeEnabled ? 120 : 60
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.refreshLiveStress(reason: "foregroundStressTick", force: false)
            }
        }
    }

    private func stopLiveStressUpdates() {
        liveStressRefreshTask?.cancel()
        liveStressRefreshTask = nil
    }

    private func refreshLiveStress(reason: String, force: Bool) async {
        let now = Date()
        guard calendar.isDate(selectedDate, inSameDayAs: now) else { return }
        guard !isLoading else {
            PulsarSyncDebugLogger.log("live stress refresh skipped because sync is in progress reason=\(reason)")
            return
        }
        if !force, let lastLiveStressRefreshAt, now.timeIntervalSince(lastLiveStressRefreshAt) < 45 {
            return
        }
        lastLiveStressRefreshAt = now

        do {
            let referenceDate = dashboardReferenceDate(for: selectedDate, now: now)
            let stress = try await stressDataService.stressSummary(
                profile: profileStore.profile,
                date: referenceDate,
                calendar: calendar,
                refreshedAt: now,
                sleep: dashboard.sleep,
                strain: dashboard.strain
            )
            guard stressShouldReplaceCurrentStress(stress, current: dashboard.stress) else {
                PulsarSyncDebugLogger.log("live stress refresh skipped because visible state is unchanged reason=\(reason) score=\(stress.score.map(String.init) ?? "nil")")
                return
            }

            var updated = dashboard
            updated.stress = stress
            updated.generatedAt = max(updated.generatedAt, now)
            dashboard = updated
            dashboardCache.save(updated)
            upsertDailyRecordIfUsable(updated, date: referenceDate)

            let stressOnlyDashboard = HomeDashboard(
                profile: profileStore.profile,
                sleep: .missing,
                recovery: .missing,
                strain: .missing,
                stress: stress,
                healthMonitor: .missing(date: referenceDate),
                generatedAt: now,
                usingSampleData: false
            )
            if let payload = stressOnlyDashboard.syncPayload(sourceDevice: .iPhone, syncSessionID: UUID(), calendar: calendar) {
                _ = syncStore.storeLocalPayload(payload, broadcast: true, reason: "LiveStressRefresh")
            }
            PulsarSyncDebugLogger.log("live stress refresh accepted reason=\(reason) selectedDay=\(selectedDate) source=\(stress.sourceBadges.map(\.displayName).joined(separator: "+")) sleepMinutes=\(stress.signals.first(where: { $0.id == "sleep" })?.value ?? "nil") viewModelStress=\(stress.score.map(String.init) ?? "nil") missingSignals=\(stress.signals.filter { $0.availability == .unavailable }.map(\.id).joined(separator: ","))")
        } catch {
            PulsarSyncDebugLogger.log("live stress refresh failed reason=\(reason) error=\(error.localizedDescription)")
        }
    }

    private func stressShouldReplaceCurrentStress(_ stress: StressSummary, current: StressSummary) -> Bool {
        guard hasUsableStress(stress) else { return false }
        if current.score == nil && stress.score != nil { return true }
        if current.state != stress.state { return true }
        if current.confidence != stress.confidence { return true }
        if current.lastHeartRateTimestamp != stress.lastHeartRateTimestamp { return true }
        if current.lastHRVTimestamp != stress.lastHRVTimestamp { return true }
        if abs(Double((current.score ?? 0) - (stress.score ?? 0))) >= 2 { return true }
        return false
    }

    private func isStressRelevantSampleType(_ sampleType: HKSampleType) -> Bool {
        if sampleType.identifier == HKObjectType.workoutType().identifier { return true }
        let identifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .heartRateVariabilitySDNN,
            .restingHeartRate,
            .respiratoryRate,
            .appleSleepingWristTemperature,
            .activeEnergyBurned,
            .stepCount,
            .appleExerciseTime,
            .distanceWalkingRunning
        ]
        return identifiers
            .compactMap { HKObjectType.quantityType(forIdentifier: $0)?.identifier }
            .contains(sampleType.identifier)
    }

    private func buildHealthKitDashboard(profile: UserProfile, date: Date, wakeUpDate: Date, generatedAt: Date) async throws -> HomeDashboard {
        async let sleepTask = sleepDataService.sleepSummary(profile: profile, wakeUpDate: wakeUpDate, calendar: calendar, refreshedAt: generatedAt)
        async let strainTask = strainDataService.strainSummary(profile: profile, date: date, calendar: calendar, refreshedAt: generatedAt)
        async let recoveryTask = recoveryDataService.recoverySummary(profile: profile, date: date, calendar: calendar, refreshedAt: generatedAt)
        let (sleep, strain, recovery) = try await (sleepTask, strainTask, recoveryTask)
        let stress = try await stressDataService.stressSummary(profile: profile, date: date, calendar: calendar, refreshedAt: generatedAt, sleep: sleep, strain: strain)
        let healthMonitor = await healthMonitorDataService.healthMonitorSummary(
            profile: profile,
            date: date,
            calendar: calendar,
            refreshedAt: generatedAt,
            sleep: sleep,
            history: strainRecords
        )
        let dashboard = HomeDashboard(profile: profile, sleep: sleep, recovery: recovery, strain: strain, stress: stress, healthMonitor: healthMonitor, generatedAt: generatedAt, usingSampleData: false)
        upsertDailyRecordIfUsable(dashboard, date: date)
        return dashboard
    }

    private func syncOuraPayloadIfNeeded(for date: Date, reason: String) async -> PulsarDailyMetricsSyncPayload? {
        guard shouldAttemptOuraSync else {
            #if DEBUG
            if shouldShowOuraDebugReport(for: reason) {
                latestOuraDebugReport = OuraSyncDebugReport.skipped(
                    reason: reason,
                    date: date,
                    calendar: calendar,
                    message: ouraSyncSkippedDebugMessage
                )
            }
            #endif
            return nil
        }
        do {
            let mapped: OuraMappedHealthData
            if shouldRunManualOuraSyncOutsideRefreshTask(for: reason) {
                let syncTask = Task { [ouraSyncService, calendar] in
                    try await ouraSyncService.sync(date: date, calendar: calendar, reason: reason)
                }
                mapped = try await syncTask.value
            } else {
                mapped = try await ouraSyncService.sync(date: date, calendar: calendar, reason: reason)
            }
            #if DEBUG
            if shouldShowOuraDebugReport(for: reason) {
                latestOuraDebugReport = mapped.debugReport
            }
            #endif
            return mapped.payload
        } catch {
            #if DEBUG
            if shouldShowOuraDebugReport(for: reason) {
                latestOuraDebugReport = OuraSyncDebugReport.failed(
                    reason: reason,
                    date: date,
                    calendar: calendar,
                    error: error,
                    scopes: ouraDebugScopes
                )
            }
            #endif
            PulsarOuraLogger.log("Oura sync skipped reason=\(reason) error=\(error.localizedDescription)")
            return nil
        }
    }

    private func shouldRunManualOuraSyncOutsideRefreshTask(for reason: String) -> Bool {
        reason == "manualRefresh"
    }

    #if DEBUG
    private func shouldShowOuraDebugReport(for reason: String) -> Bool {
        reason == "manualRefresh"
    }

    private var ouraDebugScopes: Set<OuraScope> {
        ouraConnectionStore.storedToken?.scopes ?? []
    }

    private var ouraSyncSkippedDebugMessage: String {
        if ouraConnectionStore.storedToken == nil {
            return "Oura is not connected, so no Oura API request was made."
        }
        return "Oura is connected, but no source-priority category currently uses Oura, so no Oura API request was made."
    }
    #endif

    private func routedDashboard(
        healthKitDashboard: HomeDashboard,
        ouraPayload: PulsarDailyMetricsSyncPayload?,
        date: Date,
        generatedAt: Date,
        now: Date
    ) -> HomeDashboard {
        var sourceDashboards: [HealthSourceID: HomeDashboard] = [
            .appleWatch: healthKitDashboard,
            .iPhone: healthKitDashboard
        ]
        if let ouraPayload {
            let ouraDashboard = emptyDashboard(date: date, generatedAt: generatedAt)
                .applying(payload: ouraPayload, calendar: calendar)
            sourceDashboards[.ouraRing] = ouraDashboard
        }
        let routed = HealthDataSourceRouter(priorityStore: sourcePriorityStore, calendar: calendar)
            .routedDashboard(
                profile: profileStore.profile,
                date: date,
                generatedAt: generatedAt,
                sourceDashboards: sourceDashboards,
                snapshots: sourcePrioritySnapshots(now: now),
                now: now
            )
        #if DEBUG
        logRoutedDashboardResult(context: "liveSync", date: date, routed: routed, sourceDashboards: sourceDashboards)
        #endif
        return routed.dashboard
    }

    private func sourceDashboards(
        from payloadsBySource: [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload],
        date: Date
    ) -> [HealthSourceID: HomeDashboard] {
        payloadsBySource.reduce(into: [:]) { result, entry in
            let payload = entry.value
            guard payload.isValidPayload else { return }
            let dashboard = emptyDashboard(date: date, generatedAt: payload.syncedAt)
                .applying(payload: payload, calendar: calendar)
            let sourceID = entry.key.healthSourceIDForRouting
            if let existing = result[sourceID] {
                result[sourceID] = existing.applying(payload: payload, calendar: calendar)
            } else {
                result[sourceID] = dashboard
            }
            if entry.key == .iPhone {
                result[.iPhone] = dashboard
            }
        }
    }

    private func emptyDashboard(date: Date, generatedAt: Date) -> HomeDashboard {
        HomeDashboard(
            profile: profileStore.profile,
            sleep: .missing,
            recovery: .missing,
            strain: .missing,
            stress: .missing,
            healthMonitor: .missing(date: date),
            generatedAt: generatedAt,
            usingSampleData: false
        )
    }

    private var shouldAttemptOuraSync: Bool {
        guard ouraConnectionStore.storedToken != nil else { return false }
        return HealthSourcePriorityCategory.allCases.contains {
            let preference = sourcePriorityStore.preference(for: $0)
            return preference.currentSource == .ouraRing || $0.fallbackOrder.contains(.ouraRing)
        }
    }

    private func sourcePrioritySnapshots(now: Date) -> [HealthSourceSnapshot] {
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
                lastSyncAt: latestCachedDataAt(source: .appleWatch) ?? syncStore.latestAppleWatchBattery?.timestamp ?? lastSuccessfulAutomaticSyncAt,
                batteryPercentage: syncStore.latestAppleWatchBattery?.batteryPercentage
            ),
            OuraDeviceSourceProvider(
                configuration: OuraIntegrationConfiguration.load(defaults: defaults),
                connectionStore: ouraConnectionStore,
                syncService: ouraSyncService
            ).snapshot(),
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

    private func latestCachedDataAt(source: HealthSourceID) -> Date? {
        let dateKey = PulsarDailyMetricsDateKey.dateKey(for: selectedDate, calendar: calendar)
        let sleepDateKey = SleepWindowResolver.sleepDateKey(forWakeUpDate: selectedDate, calendar: calendar)
        let payloads = Array(syncStore.cachedDailyPayloadsBySource(forDateKey: dateKey).values) +
            Array(syncStore.cachedSleepPayloadsBySource(forSleepDateKey: sleepDateKey).values)
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

    private func buildPermissionRequiredDashboard(profile: UserProfile, date: Date) -> HomeDashboard {
        HomeDashboard(profile: profile, sleep: .permissionRequired, recovery: .missing, strain: .missing, stress: .missing, healthMonitor: .missing(date: date), generatedAt: date, usingSampleData: false)
    }

    private func buildUnavailableDashboard(profile: UserProfile, date: Date) -> HomeDashboard {
        var dashboard = HomeDashboard(profile: profile, sleep: .permissionRequired, recovery: .missing, strain: .missing, stress: .missing, healthMonitor: .missing(date: date), generatedAt: date, usingSampleData: false)
        dashboard.sleep.confidenceExplanation = "Health data is unavailable on this device."
        dashboard.sleep.notes = ["Pulsar cannot read sleep without HealthKit availability and permission. Demo data is only used in previews."]
        return dashboard
    }

    private func loadCalendarHistoryFromStores() {
        let payloadRecords = (syncStore.cachedDailyPayloads() + syncStore.cachedSleepPayloads())
            .compactMap { DailyStrainRecord(payload: $0, calendar: calendar) }
        if payloadRecords.isEmpty {
            strainRecords = dailyHistoryStore.loadRecords(calendar: calendar)
        } else {
            strainRecords = dailyHistoryStore.upsert(payloadRecords, calendar: calendar)
        }
    }

    private func upsertDailyRecordIfUsable(_ payload: PulsarDailyMetricsSyncPayload) {
        guard let record = DailyStrainRecord(payload: payload, calendar: calendar) else { return }
        strainRecords = dailyHistoryStore.upsert(record, calendar: calendar)
        if record.strainScore > 0 {
            lifecycleStore.registerStrainSync(on: record.date)
        }
    }

    private func upsertDailyRecordIfUsable(_ dashboard: HomeDashboard, date: Date) {
        guard hasVisibleMetrics(dashboard) else { return }
        let day = calendar.startOfDay(for: date)
        let sourceNames = [
            dashboard.sleep.sourceBadges,
            dashboard.recovery.sourceBadges,
            dashboard.strain.sourceBadges,
            dashboard.stress.sourceBadges,
            dashboard.healthMonitor.sourceBadges
        ]
            .flatMap { $0 }
            .map(\.displayName)
        let latestMetricDate = [
            dashboard.sleep.lastUpdated,
            dashboard.recovery.lastUpdated,
            dashboard.strain.lastUpdated,
            dashboard.stress.lastUpdated,
            dashboard.healthMonitor.lastUpdated,
            dashboard.generatedAt
        ]
            .compactMap { $0 }
            .max() ?? Date()
        let record = DailyStrainRecord(
            date: day,
            calendar: calendar,
            sleepScore: hasUsableSleep(dashboard.sleep) ? dashboard.sleep.score : nil,
            sleepMinutes: dashboard.sleep.totalSleepMinutes > 0 ? Int(dashboard.sleep.totalSleepMinutes.rounded()) : nil,
            recoveryScore: hasUsableRecovery(dashboard.recovery) ? dashboard.recovery.score : nil,
            stressScore: dailyStressScore(from: dashboard.stress),
            stressTimelineSamples: dashboard.stress.dailySamples,
            strainScore: hasUsableStrain(dashboard.strain) ? dashboard.strain.score : 0,
            respiratoryRate: dashboard.healthMonitor.metric(.respiratoryRate).value,
            respiratoryRateStatus: dashboard.healthMonitor.metric(.respiratoryRate).status,
            restingHeartRate: dashboard.healthMonitor.metric(.restingHeartRate).value,
            restingHeartRateStatus: dashboard.healthMonitor.metric(.restingHeartRate).status,
            hrv: dashboard.healthMonitor.metric(.hrv).value,
            hrvStatus: dashboard.healthMonitor.metric(.hrv).status,
            oxygenSaturation: dashboard.healthMonitor.metric(.oxygenSaturation).value,
            oxygenSaturationStatus: dashboard.healthMonitor.metric(.oxygenSaturation).status,
            wristTemperatureDeviation: dashboard.healthMonitor.metric(.wristTemperature).value,
            wristTemperatureStatus: dashboard.healthMonitor.metric(.wristTemperature).status,
            sleepDurationStatus: dashboard.healthMonitor.metric(.sleep).status,
            workoutMinutes: Int(dashboard.strain.workoutMinutes.rounded()),
            steps: dashboard.strain.steps,
            activeEnergyKilocalories: Int((dashboard.strain.activeEnergyKilocalories ?? dashboard.strain.movementLoad * 8).rounded()),
            confidence: highestConfidence([
                dashboard.sleep.confidence,
                dashboard.recovery.confidence,
                dashboard.strain.confidence,
                dashboard.stress.confidence
            ]),
            sourceName: sourceNames.first ?? "HealthKit",
            syncedAt: latestMetricDate
        )
        guard record.hasRecordedData else { return }
        strainRecords = dailyHistoryStore.upsert(record, calendar: calendar)
        if hasUsableStrain(dashboard.strain) {
            lifecycleStore.registerStrainSync(on: day)
        }
    }

    private func highestConfidence(_ grades: [ConfidenceGrade]) -> ConfidenceGrade {
        grades.max { confidenceRank($0) < confidenceRank($1) } ?? .missing
    }

    private func confidenceRank(_ grade: ConfidenceGrade) -> Int {
        switch grade {
        case .high:
            return 3
        case .moderate:
            return 2
        case .low:
            return 1
        case .missing:
            return 0
        }
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

        syncStore.$sourceCacheRevision
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyCurrentSourceRouting(statusMessage: nil)
            }
            .store(in: &cancellables)
    }

    private func observeSourcePriorityChanges() {
        NotificationCenter.default.publisher(for: .pulsarHealthSourcePreferenceDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.sourcePriorityStore.reloadFromDefaults()
                self?.applyCurrentSourceRouting(statusMessage: "Source setting updated")
            }
            .store(in: &cancellables)
    }

    private func applyCurrentSourceRouting(statusMessage: String?) {
        guard let routed = sourceRoutedCachedDashboard(for: selectedDate) else { return }
        dashboard = routed
        dashboardCache.save(routed)
        if let statusMessage {
            healthKitStatus = statusMessage
        }
    }

    @discardableResult
    private func loadCachedDashboardIfAvailable() -> Bool {
        if let cached = cachedDashboardFromSyncStore(for: selectedDate) {
            dashboard = cached
            healthKitStatus = "Showing saved daily data"
            return true
        }
        if let cached = dashboardCache.loadDashboard(for: selectedDate, calendar: calendar) {
            dashboard = sourceRoutedCachedDashboard(for: selectedDate) ?? cached
            healthKitStatus = "Showing latest available data"
            return true
        }
        if let historical = cachedDashboardFromHistoryStore(for: selectedDate) {
            dashboard = historical
            healthKitStatus = "Showing saved daily history"
            return true
        }
        return false
    }

    private func applyIncomingSyncPayload(_ payload: PulsarDailyMetricsSyncPayload?) {
        guard let payload, payload.isValidPayload else {
            PulsarSyncDebugLogger.log("silent payload update rejected because incoming data was older or invalid")
            return
        }
        upsertDailyRecordIfUsable(payload)
        guard payload.applies(to: selectedDate, calendar: calendar) else { return }
        let currentTimestamp = latestVisibleMetricTimestamp(in: dashboard)
        guard payload.syncedAt > currentTimestamp || payloadImprovesAnyMetric(payload, dashboard: dashboard) else {
            PulsarSyncDebugLogger.log("silent payload update rejected because incoming data was older or invalid session=\(payload.syncSessionID?.uuidString ?? "none")")
            return
        }
        dashboard = sourceRoutedCachedDashboard(for: selectedDate) ?? dashboard.applying(payload: payload, calendar: calendar)
        dashboardCache.save(dashboard)
        switch payload.sourceDevice {
        case .appleWatch:
            healthKitStatus = "Synced from Apple Watch"
        case .ouraRing:
            healthKitStatus = "HealthKit connected · Oura synced"
        case .iPhone:
            healthKitStatus = "HealthKit connected"
        }
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
        if !hasUsableStress(fresh.stress), hasUsableStress(fallback.stress) {
            merged.stress = fallback.stress
        }
        if !hasUsableHealthMonitor(fresh.healthMonitor), hasUsableHealthMonitor(fallback.healthMonitor) {
            merged.healthMonitor = fallback.healthMonitor
        }
        return merged
    }

    private func canonicalDashboard(for dashboard: HomeDashboard) -> HomeDashboard {
        sourceRoutedCachedDashboard(for: selectedDate) ?? dashboard
    }

    private func cachedDashboardFromSyncStore(for day: Date) -> HomeDashboard? {
        sourceRoutedCachedDashboard(for: day)
    }

    private func sourceRoutedCachedDashboard(for day: Date) -> HomeDashboard? {
        let dateKey = PulsarDailyMetricsDateKey.dateKey(for: day, calendar: calendar)
        let sleepDateKey = SleepWindowResolver.sleepDateKey(forWakeUpDate: day, calendar: calendar)
        var payloadsBySource = syncStore.cachedDailyPayloadsBySource(forDateKey: dateKey)
            .mapValues { $0.sanitizedForDeclaredSource() }
        for (source, sleepPayload) in syncStore.cachedSleepPayloadsBySource(forSleepDateKey: sleepDateKey) {
            let sleepPayload = sleepPayload.sanitizedForDeclaredSource()
            payloadsBySource[source] = payloadsBySource[source]
                .map { $0.merged(with: sleepPayload, calendar: calendar).sanitizedForDeclaredSource() } ?? sleepPayload
        }
        if payloadsBySource.isEmpty,
           let payload = syncStore.cachedDailyPayload(forDateKey: dateKey) ?? syncStore.cachedPayload(for: day, calendar: calendar) {
            let payload = payload.sanitizedForDeclaredSource()
            payloadsBySource[payload.sourceDevice] = payload
        }
        if let sleepPayload = syncStore.cachedSleepPayload(forSleepDateKey: sleepDateKey) {
            let sleepPayload = sleepPayload.sanitizedForDeclaredSource()
            payloadsBySource[sleepPayload.sourceDevice] = payloadsBySource[sleepPayload.sourceDevice]
                .map { $0.merged(with: sleepPayload, calendar: calendar).sanitizedForDeclaredSource() } ?? sleepPayload
        }
        let sourceDashboards = sourceDashboards(from: payloadsBySource, date: day)
        guard !sourceDashboards.isEmpty else { return nil }
        let now = Date()
        let routed = HealthDataSourceRouter(priorityStore: sourcePriorityStore, calendar: calendar)
            .routedDashboard(
                profile: profileStore.profile,
                date: day,
                generatedAt: sourceDashboards.values.map(\.generatedAt).max() ?? calendar.startOfDay(for: day),
                sourceDashboards: sourceDashboards,
                snapshots: sourcePrioritySnapshots(now: now),
                now: now
            )
        #if DEBUG
        PulsarSourceRouterLogger.log("cached payloads selectedDay=\(day) dateKey=\(dateKey) sleepDateKey=\(sleepDateKey) currentSources=\(diagnosticCurrentSourceSummary()) payloads=\(diagnosticPayloadSummary(payloadsBySource))")
        logRoutedDashboardResult(context: "cachedPayloads", date: day, routed: routed, sourceDashboards: sourceDashboards)
        #endif
        return routed.dashboard
    }

    private func persistWidgetSnapshot(for dashboard: HomeDashboard) {
        PulsarWidgetSyncService(calendar: calendar).persist(dashboard: dashboard)
    }

    private func cachedDashboardFromHistoryStore(for day: Date) -> HomeDashboard? {
        let normalizedDay = calendar.startOfDay(for: day)
        guard let record = strainRecords.first(where: { calendar.isDate($0.date, inSameDayAs: normalizedDay) }),
              record.hasRecordedData else { return nil }

        var sleep = SleepSummary.missing
        if let sleepScore = record.sleepScore {
            let sleepMinutes = Double(record.sleepMinutes ?? 0)
            let sleepWindow = SleepWindowResolver.window(forWakeUpDate: normalizedDay, calendar: calendar)
            let inferredWakeTime = sleepWindow.end
            let inferredSleepStart = sleepMinutes > 0 ? max(sleepWindow.start, inferredWakeTime.addingTimeInterval(-sleepMinutes * 60)) : nil
            sleep.score = sleepScore
            sleep.totalSleepMinutes = sleepMinutes
            sleep.timeInBedMinutes = sleepMinutes
            sleep.sleepEfficiency = sleepMinutes > 0 ? 1 : 0
            sleep.confidence = record.confidence
            sleep.wakeUpDate = normalizedDay
            sleep.stageBreakdown = sleepMinutes > 0 ? [StageMetric(stage: .asleepUnspecified, minutes: sleepMinutes, percentOfSleep: 1)] : []
            sleep.intervals = inferredSleepStart.map {
                [SleepStageInterval(stage: .asleepUnspecified, startDate: $0, endDate: inferredWakeTime)]
            } ?? []
            sleep.sleepStart = inferredSleepStart
            sleep.wakeTime = sleepMinutes > 0 ? inferredWakeTime : nil
            sleep.analyzedSampleCount = sleepMinutes > 0 ? 1 : 0
            sleep.queryStart = sleepWindow.start
            sleep.queryEnd = sleepWindow.end
            sleep.lastUpdated = record.syncedAt
            sleep.notes = ["Saved daily sleep history. Stage-level detail refreshes from HealthKit when available."]
        }

        var recovery = RecoverySummary.missing
        if let recoveryScore = record.recoveryScore {
            recovery.date = normalizedDay
            recovery.score = recoveryScore
            recovery.confidence = record.confidence
            recovery.lastUpdated = record.syncedAt
        }

        var strain = StrainSummary.missing
        if record.strainScore > 0 || record.steps > 0 || record.workoutMinutes > 0 {
            strain.date = normalizedDay
            strain.score = record.strainScore
            strain.confidence = record.confidence
            strain.workoutMinutes = Double(record.workoutMinutes)
            strain.steps = record.steps
            strain.activeEnergyKilocalories = Double(record.activeEnergyKilocalories)
            strain.lastUpdated = record.syncedAt
        }

        let stress = stressSummary(from: record, day: normalizedDay)

        return HomeDashboard(
            profile: profileStore.profile,
            sleep: sleep,
            recovery: recovery,
            strain: strain,
            stress: stress,
            healthMonitor: healthMonitorSummary(from: record, day: normalizedDay),
            generatedAt: normalizedDay,
            usingSampleData: false
        )
    }

    private func healthMonitorSummary(from record: DailyStrainRecord, day: Date) -> HealthMonitorSummary {
        HealthMonitorSummary(
            date: day,
            metrics: [
                healthMetric(.respiratoryRate, value: record.respiratoryRate, status: record.respiratoryRateStatus, updatedAt: record.syncedAt),
                healthMetric(.restingHeartRate, value: record.restingHeartRate, status: record.restingHeartRateStatus, updatedAt: record.syncedAt),
                healthMetric(.hrv, value: record.hrv, status: record.hrvStatus, updatedAt: record.syncedAt),
                healthMetric(.oxygenSaturation, value: record.oxygenSaturation, status: record.oxygenSaturationStatus, updatedAt: record.syncedAt),
                healthMetric(.wristTemperature, value: record.wristTemperatureDeviation, status: record.wristTemperatureStatus, updatedAt: record.syncedAt),
                healthMetric(.sleep, value: record.sleepMinutes.map(Double.init), status: record.sleepDurationStatus, updatedAt: record.syncedAt)
            ],
            lastUpdated: record.syncedAt,
            baselineWindowDays: 0,
            sourceBadges: []
        )
    }

    private func healthMetric(_ kind: HealthMetricKind, value: Double?, status: HealthMetricStatus?, updatedAt: Date) -> HealthMetricModel {
        guard let value else {
            return .noData(kind: kind, comparisonText: "No saved value for this metric on the selected day.", lastUpdated: updatedAt)
        }
        return HealthMetricModel(
            kind: kind,
            value: value,
            status: status ?? .normal,
            comparisonText: "Saved from daily history.",
            sourceBadges: [],
            lastUpdated: updatedAt
        )
    }

    private func stressSummary(from record: DailyStrainRecord, day: Date) -> StressSummary {
        let timelineSamples = record.stressTimelineSamples
        let timelineScore = PulsarStressTimelineDistribution.weightedAverage(
            samples: timelineSamples.map { PulsarStressTimelineSample(timestamp: $0.timestamp, score: $0.score) }
        ).map(PulsarStressScale.roundedScore)
        let score = record.stressScore ?? timelineScore
        guard score != nil || !timelineSamples.isEmpty else { return .missing }
        let queryStart = timelineSamples.first?.timestamp ?? day
        let queryEnd = timelineSamples.last?.timestamp ?? (calendar.date(byAdding: .day, value: 1, to: day)?.addingTimeInterval(-1) ?? day)
        return StressSummary(
            date: day,
            score: score,
            level: score.map(StressLevel.level(for:)),
            confidence: record.confidence,
            state: score == nil ? .noData : (record.confidence == .low ? .lowConfidence : .ready),
            driverInsights: ["Saved daily stress history"],
            drivers: [],
            signals: [],
            dailySamples: timelineSamples,
            analyzedSampleCount: max(timelineSamples.count, score == nil ? 0 : 1),
            baselineWindowDays: 0,
            availableSignalCount: 0,
            queryStart: queryStart,
            queryEnd: queryEnd,
            lastUpdated: record.syncedAt,
            sourceBadges: [],
            explanation: "Saved stress history for this day.",
            subtext: StressSummary.estimateSubtext
        )
    }

    private func emptyDashboard(for day: Date) -> HomeDashboard {
        HomeDashboard(
            profile: profileStore.profile,
            sleep: .missing,
            recovery: .missing,
            strain: .missing,
            stress: .missing,
            healthMonitor: .missing(date: day),
            generatedAt: calendar.startOfDay(for: day),
            usingSampleData: false
        )
    }

    private func payloadImprovesAnyMetric(_ payload: PulsarDailyMetricsSyncPayload, dashboard: HomeDashboard) -> Bool {
        let incomingSleepUpdatedAt = payload.sleep?.computedAt ?? .distantPast
        let currentSleepUpdatedAt = dashboard.sleep.lastUpdated ?? .distantPast
        let incomingDailyUpdatedAt = max(payload.strain?.computedAt ?? .distantPast, payload.recovery?.computedAt ?? .distantPast)
        let currentDailyUpdatedAt = max(dashboard.strain.lastUpdated ?? .distantPast, dashboard.recovery.lastUpdated ?? .distantPast)
        let incomingStrainUpdatedAt = payload.strain?.computedAt ?? .distantPast
        let currentStrainUpdatedAt = dashboard.strain.lastUpdated ?? .distantPast
        let incomingRecoveryUpdatedAt = payload.recovery?.computedAt ?? .distantPast
        let currentRecoveryUpdatedAt = dashboard.recovery.lastUpdated ?? .distantPast
        let incomingStressUpdatedAt = payload.stress?.computedAt ?? .distantPast
        let currentStressUpdatedAt = dashboard.stress.lastUpdated ?? .distantPast
        let canUseIncomingStressAsCanonical = payload.sourceDevice == .iPhone || !hasUsableStress(dashboard.stress)
        let incomingHealthMonitorUpdatedAt = payload.healthMonitor?.computedAt ?? .distantPast
        let currentHealthMonitorUpdatedAt = dashboard.healthMonitor.lastUpdated ?? .distantPast
        return ((!hasUsableStrain(dashboard.strain) || !hasUsableRecovery(dashboard.recovery)) && payload.hasCompleteDailyScores) ||
        (payload.hasCompleteDailyScores && incomingDailyUpdatedAt > currentDailyUpdatedAt) ||
        (!hasUsableStrain(dashboard.strain) && payload.hasValidStrain) ||
        (payload.hasValidStrain && incomingStrainUpdatedAt > currentStrainUpdatedAt) ||
        (!hasUsableRecovery(dashboard.recovery) && payload.hasValidRecovery) ||
        (payload.hasValidRecovery && incomingRecoveryUpdatedAt > currentRecoveryUpdatedAt) ||
        (!hasUsableSleep(dashboard.sleep) && payload.sleep?.isValid == true) ||
        (payload.sleep?.isValid == true && incomingSleepUpdatedAt > currentSleepUpdatedAt) ||
        (!hasUsableStress(dashboard.stress) && payload.stress?.isValid == true) ||
        (canUseIncomingStressAsCanonical && payload.stress?.isValid == true && incomingStressUpdatedAt > currentStressUpdatedAt) ||
        (!hasUsableHealthMonitor(dashboard.healthMonitor) && payload.healthMonitor?.isValid == true) ||
        (payload.healthMonitor?.isValid == true && incomingHealthMonitorUpdatedAt > currentHealthMonitorUpdatedAt)
    }

    #if DEBUG
    private func logRoutedDashboardResult(
        context: String,
        date: Date,
        routed: RoutedHealthDashboard,
        sourceDashboards: [HealthSourceID: HomeDashboard]
    ) {
        let dateKey = PulsarDailyMetricsDateKey.dateKey(for: date, calendar: calendar)
        let sleepDateKey = SleepWindowResolver.sleepDateKey(forWakeUpDate: date, calendar: calendar)
        let sourceSamples = sourceDashboards
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue){\(diagnosticSampleCounts($0.value))}" }
            .joined(separator: ";")
        PulsarSourceRouterLogger.log("dashboard routed context=\(context) selectedDay=\(date) dateKey=\(dateKey) sleepDateKey=\(sleepDateKey) decisions=\(diagnosticDecisionSummary(routed.decisions)) sourceSamples=\(sourceSamples.isEmpty ? "none" : sourceSamples) \(diagnosticDashboardState(routed.dashboard))")
    }

    private func diagnosticPayloadSummary(_ payloadsBySource: [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload]) -> String {
        let summaries = payloadsBySource
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { entry in
                let source = entry.key
                let payload = entry.value
                let sleepSamples = payload.sleep?.analyzedSampleCount ?? 0
                let healthSamples = payload.healthMonitor?.metrics.filter { $0.value != nil }.count ?? 0
                let recoveryInputs = [
                    payload.recovery?.hrvSDNN,
                    payload.recovery?.restingHeartRate,
                    payload.recovery?.sleepDuration,
                    payload.recovery?.strainScore,
                    payload.recovery?.respiratoryRate,
                    payload.recovery?.oxygenSaturation,
                    payload.recovery?.wristTemperatureDeviation
                ].compactMap { $0 }.count
                let missing = diagnosticMissingPayloadMetrics(payload)
                return "\(source.sourceRouterLogName){dateKey=\(payload.resolvedDateKey),sleepMinutes=\(diagnosticMinutes(payload.sleep?.totalSleepMinutes)),sleepSamples=\(sleepSamples),recoveryScore=\(payload.recovery?.score.description ?? "nil"),recoveryInputs=\(recoveryInputs),rhr=\(diagnosticNumber(payload.recovery?.restingHeartRate ?? syncHealthValue(.restingHeartRate, in: payload))),hrv=\(diagnosticNumber(payload.recovery?.hrvSDNN ?? syncHealthValue(.hrv, in: payload))),strainSamples=\(payload.strain?.analyzedSampleCount ?? 0),daytimeHRRows=\(payload.strain?.heartRateSampleCount ?? 0),workoutRows=\(payload.strain?.workoutSampleCount ?? 0),stressTimeline=\(payload.stress?.timelineSamples.count ?? 0),healthSamples=\(healthSamples),missing=\(missing.isEmpty ? "none" : missing.joined(separator: ","))}"
            }
        return summaries.isEmpty ? "none" : summaries.joined(separator: ";")
    }

    private func syncHealthValue(_ kind: PulsarHealthMetricSyncKind, in payload: PulsarDailyMetricsSyncPayload) -> Double? {
        payload.healthMonitor?.metrics.first(where: { $0.kind == kind })?.value
    }

    private func diagnosticMissingPayloadMetrics(_ payload: PulsarDailyMetricsSyncPayload) -> [String] {
        var missing: [String] = []
        if payload.sleep?.isValid != true { missing.append("sleep") }
        if payload.recovery?.isValid != true { missing.append("recovery") }
        if payload.strain?.isValid != true { missing.append("strain") }
        if payload.stress?.isValid != true { missing.append("stress") }
        for kind in PulsarHealthMetricSyncKind.allCases {
            if payload.healthMonitor?.metrics.first(where: { $0.kind == kind })?.value == nil {
                missing.append("health.\(kind.rawValue)")
            }
        }
        return missing
    }

    private func diagnosticCurrentSourceSummary() -> String {
        HealthSourcePriorityCategory.allCases.map { category in
            let preference = sourcePriorityStore.preference(for: category)
            return "\(category.rawValue){current=\(preference.currentSource.rawValue),fallbackEnabled=\(preference.fallbackEnabled)}"
        }
        .joined(separator: ";")
    }

    private func diagnosticDecisionSummary(_ decisions: [HealthSourcePriorityCategory: SourceRoutingDecision]) -> String {
        HealthSourcePriorityCategory.allCases.map { category in
            guard let decision = decisions[category] else {
                let preference = sourcePriorityStore.preference(for: category)
                return "\(category.rawValue){current=\(preference.currentSource.rawValue),displayed=none,fallback=false,fallbackEnabled=\(preference.fallbackEnabled),samples=0}"
            }
            return "\(category.rawValue){current=\(decision.currentSource.rawValue),displayed=\(diagnosticSourceText(decision.displayedSource)),fallback=\(decision.isFallback),fallbackEnabled=\(decision.fallbackEnabled),last=\(diagnosticDate(decision.lastDataAt))}"
        }
        .joined(separator: ";")
    }

    private func diagnosticRenderedRoutes(_ dashboard: HomeDashboard) -> String {
        let hrv = dashboard.healthMonitor.metric(.hrv)
        let rhr = dashboard.healthMonitor.metric(.restingHeartRate)
        return [
            diagnosticRenderedRoute(name: "sleep", category: .sleepRecovery, sourceBadges: dashboard.sleep.sourceBadges, sampleCount: dashboard.sleep.analyzedSampleCount),
            diagnosticRenderedRoute(name: "recovery", category: .sleepRecovery, sourceBadges: dashboard.recovery.sourceBadges, sampleCount: dashboard.recovery.analyzedSampleCount),
            diagnosticRenderedRoute(name: "activity", category: .activitySteps, sourceBadges: dashboard.strain.sourceBadges, sampleCount: dashboard.strain.analyzedSampleCount),
            diagnosticRenderedRoute(name: "workouts", category: .workoutsActivity, sourceBadges: dashboard.strain.sourceBadges, sampleCount: dashboard.strain.workouts.count),
            diagnosticRenderedRoute(name: "stress", category: .stressResilience, sourceBadges: dashboard.stress.sourceBadges, sampleCount: dashboard.stress.analyzedSampleCount),
            diagnosticMetricRoute(name: "rhr", metric: rhr, defaultCategory: .heartMetrics),
            diagnosticMetricRoute(name: "hrv", metric: hrv, defaultCategory: .heartMetrics)
        ].joined(separator: ";")
    }

    private func diagnosticRenderedRoute(
        name: String,
        category: HealthSourcePriorityCategory,
        sourceBadges: [SourceProvenance],
        sampleCount: Int
    ) -> String {
        let preference = sourcePriorityStore.preference(for: category)
        let displayed = diagnosticSourceID(from: sourceBadges)
        let isFallback = displayed.map { $0 != preference.currentSource } ?? false
        return "\(name){current=\(preference.currentSource.rawValue),displayed=\(diagnosticSourceText(displayed)),fallback=\(isFallback),fallbackEnabled=\(preference.fallbackEnabled),samples=\(sampleCount)}"
    }

    private func diagnosticMetricRoute(
        name: String,
        metric: HealthMetricModel,
        defaultCategory: HealthSourcePriorityCategory
    ) -> String {
        let category = metric.sourceResolution?.category ?? defaultCategory
        let preference = sourcePriorityStore.preference(for: category)
        let current = metric.sourceResolution?.currentSource ?? preference.currentSource
        let displayed = metric.sourceResolution?.displayedRecordSource ?? diagnosticSourceID(from: metric.sourceBadges)
        let isFallback = metric.sourceResolution?.fallbackUsed ?? (displayed.map { $0 != current } ?? false)
        return "\(name){current=\(current.rawValue),displayed=\(diagnosticSourceText(displayed)),fallback=\(isFallback),fallbackEnabled=\(preference.fallbackEnabled),samples=\(metric.hasData ? 1 : 0)}"
    }

    private func diagnosticDashboardState(_ dashboard: HomeDashboard, uiRenderedSleepMinutes: Double? = nil) -> String {
        let hrv = dashboard.healthMonitor.metric(.hrv)
        let rhr = dashboard.healthMonitor.metric(.restingHeartRate)
        let missing = diagnosticMissingMetrics(in: dashboard)
        let uiSleep = uiRenderedSleepMinutes.map(diagnosticMinutes) ?? "nil"
        return "rendered={sleepScore=\(dashboard.sleep.score),recoveryScore=\(dashboard.recovery.score),strainScore=\(dashboard.strain.score),stressScore=\(dashboard.stress.score.map(String.init) ?? "nil"),sleepMinutes=\(diagnosticMinutes(dashboard.sleep.totalSleepMinutes)),uiSleepMinutes=\(uiSleep),rhr=\(diagnosticNumber(rhr.value ?? dashboard.recovery.restingHeartRate)),hrv=\(diagnosticNumber(hrv.value ?? dashboard.recovery.hrvSDNN)),samples={\(diagnosticSampleCounts(dashboard))},recoveryInputs={\(diagnosticRecoveryInputs(dashboard.recovery))},missingMetrics=\(missing.isEmpty ? "none" : missing.joined(separator: ","))}"
    }

    private func diagnosticSampleCounts(_ dashboard: HomeDashboard) -> String {
        [
            "sleep=\(dashboard.sleep.analyzedSampleCount)",
            "recovery=\(dashboard.recovery.analyzedSampleCount)",
            "strain=\(dashboard.strain.analyzedSampleCount)",
            "workouts=\(dashboard.strain.workouts.count)",
            "stress=\(dashboard.stress.analyzedSampleCount)",
            "stressTimeline=\(dashboard.stress.dailySamples.count)",
            "healthMonitor=\(dashboard.healthMonitor.availableMetricCount)",
            "rhr=\(dashboard.healthMonitor.metric(.restingHeartRate).hasData ? 1 : 0)",
            "hrv=\(dashboard.healthMonitor.metric(.hrv).hasData ? 1 : 0)"
        ].joined(separator: ",")
    }

    private func diagnosticRecoveryInputs(_ recovery: RecoverySummary) -> String {
        [
            "score=\(recovery.score)",
            "hrv=\(diagnosticNumber(recovery.hrvSDNN))",
            "hrvBaseline=\(diagnosticNumber(recovery.hrvBaseline))",
            "rhr=\(diagnosticNumber(recovery.restingHeartRate))",
            "rhrBaseline=\(diagnosticNumber(recovery.restingHeartRateBaseline))",
            "sleepMinutes=\(diagnosticMinutes(recovery.sleepDuration.map { $0 / 60 }))",
            "sleepEfficiency=\(diagnosticNumber(recovery.sleepEfficiency, fractionDigits: 3))",
            "strainScore=\(diagnosticNumber(recovery.strainScore))",
            "hrvReadiness=\(diagnosticNumber(recovery.hrvReadiness, fractionDigits: 3))",
            "rhrReadiness=\(diagnosticNumber(recovery.restingHeartRateReadiness, fractionDigits: 3))",
            "sleepContribution=\(diagnosticNumber(recovery.sleepContribution, fractionDigits: 3))",
            "strainPenalty=\(diagnosticNumber(recovery.strainPenalty, fractionDigits: 3))"
        ].joined(separator: ",")
    }

    private func diagnosticMissingMetrics(in dashboard: HomeDashboard) -> [String] {
        var missing: [String] = []
        if !hasUsableSleep(dashboard.sleep) { missing.append("sleep") }
        if !hasUsableRecovery(dashboard.recovery) { missing.append("recovery") }
        if !hasUsableStrain(dashboard.strain) { missing.append("strain") }
        if !hasUsableStress(dashboard.stress) { missing.append("stress") }
        for kind in HealthMetricKind.allCases {
            if !dashboard.healthMonitor.metric(kind).hasData {
                missing.append("health.\(kind.rawValue)")
            }
        }
        return missing
    }

    private func diagnosticSourceID(from badges: [SourceProvenance]) -> HealthSourceID? {
        guard let first = badges.first else { return nil }
        let text = [
            first.sourceName,
            first.sourceBundleIdentifier,
            first.productType,
            first.deviceName,
            first.deviceManufacturer,
            first.deviceModel
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if text.contains("oura") { return .ouraRing }
        if first.isAppleWatchLike || text.contains("watch") || text.contains("healthkit") || text.contains("apple health") {
            return .appleWatch
        }
        if text.contains("iphone") { return .iPhone }
        if text.contains("manual") { return .manual }
        return nil
    }

    private func diagnosticSourceText(_ source: HealthSourceID?) -> String {
        source?.rawValue ?? "none"
    }

    private func diagnosticMinutes(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "nil" }
        return String(format: "%.1f", value)
    }

    private func diagnosticNumber(_ value: Double?, fractionDigits: Int = 1) -> String {
        guard let value, value.isFinite else { return "nil" }
        return String(format: "%.\(fractionDigits)f", value)
    }

    private func diagnosticDate(_ value: Date?) -> String {
        value.map { "\($0)" } ?? "nil"
    }
    #endif

    private func logStrainValidation(dashboard: HomeDashboard, context: String) {
        let strain = dashboard.strain
        let recoveryScore = dashboard.recovery.score > 0 ? dashboard.recovery.score : nil
        let targetRange = PulsarSharedMetricCalculator.recommendedStrainTargetRange(forRecoveryScore: recoveryScore, recentStrainScores: recentStrainScores(before: selectedDate))
        let zoneMinutes = strain.timeInZones
            .filter { $0.minutes > 0 }
            .map { "z\($0.zone)=\(Int($0.minutes.rounded()))m" }
            .joined(separator: ",")
        PulsarSyncDebugLogger.log("strain validation context=\(context) workoutsToday=\(strain.workouts.count) activeEnergy=\(Int((strain.activeEnergyKilocalories ?? 0).rounded())) totalEnergy=\((strain.activeEnergyKilocalories ?? 0) + (strain.basalEnergyKilocalories ?? 0) > 0 ? String(Int(((strain.activeEnergyKilocalories ?? 0) + (strain.basalEnergyKilocalories ?? 0)).rounded())) : "nil") exerciseMinutes=\(Int(strain.exerciseMinutes.rounded())) steps=\(strain.steps) averageHeartRate=\(strain.averageActiveHeartRate.map { String(Int($0.rounded())) } ?? "nil") maxHeartRate=\(strain.peakHeartRate.map { String(Int($0.rounded())) } ?? "nil") timeInZones=\(zoneMinutes.isEmpty ? "none" : zoneMinutes) activeLoad=\(String(format: "%.1f", strain.workoutLoad)) passiveLoad=\(String(format: "%.1f", strain.movementLoad)) rawLoad=\(String(format: "%.1f", strain.rawLoad)) recoveryScore=\(recoveryScore.map(String.init) ?? "nil") finalCurrentStrain=\(strain.score) targetStrainRange=\(targetRange?.displayText ?? "nil")")
    }

    func recommendedStrainTargetRange(for date: Date? = nil) -> PulsarSharedStrainTargetRange? {
        let day = calendar.startOfDay(for: date ?? selectedDate)
        let recoveryScore = dashboard.recovery.score > 0 ? dashboard.recovery.score : nil
        return PulsarSharedMetricCalculator.recommendedStrainTargetRange(
            forRecoveryScore: recoveryScore,
            recentStrainScores: recentStrainScores(before: day)
        )
    }

    private func recentStrainScores(before date: Date) -> [Int] {
        let day = calendar.startOfDay(for: date)
        return strainRecords
            .filter { $0.date < day && $0.strainScore > 0 }
            .sorted { $0.date < $1.date }
            .suffix(7)
            .map(\.strainScore)
    }

    private func latestVisibleMetricTimestamp(in dashboard: HomeDashboard) -> Date {
        max(
            max(
                max(dashboard.strain.lastUpdated ?? .distantPast, dashboard.recovery.lastUpdated ?? .distantPast),
                dashboard.stress.lastUpdated ?? .distantPast
            ),
            max(
                max(dashboard.sleep.lastUpdated ?? .distantPast, dashboard.healthMonitor.lastUpdated ?? .distantPast),
                dashboard.generatedAt
            )
        )
    }

    private func visibleMetricsAreStale(now: Date) -> Bool {
        let latest = latestVisibleMetricTimestamp(in: dashboard)
        guard latest > .distantPast else { return true }
        return now.timeIntervalSince(latest) >= syncPolicy.staleVisibleMetricMinimumInterval
    }

    private func hasVisibleMetrics(_ dashboard: HomeDashboard) -> Bool {
        hasUsableStrain(dashboard.strain) || hasUsableRecovery(dashboard.recovery) || hasUsableSleep(dashboard.sleep) || hasUsableStress(dashboard.stress) || hasUsableHealthMonitor(dashboard.healthMonitor)
    }

    private func hasUsableStrain(_ summary: StrainSummary) -> Bool {
        summary.lastUpdated != nil || summary.confidence != .missing || summary.score > 0 || summary.steps > 0 || summary.workoutMinutes > 0 || summary.exerciseMinutes > 0 || (summary.activeEnergyKilocalories ?? 0) > 0
    }

    private func hasUsableRecovery(_ summary: RecoverySummary) -> Bool {
        summary.score > 0 || summary.hrvSDNN != nil || summary.restingHeartRate != nil || summary.sleepDuration != nil || summary.strainScore != nil
    }

    private func hasUsableSleep(_ summary: SleepSummary) -> Bool {
        summary.score > 0 || summary.totalSleepMinutes > 0 || summary.sleepStart != nil || summary.wakeTime != nil
    }

    private func hasUsableStress(_ summary: StressSummary) -> Bool {
        summary.score != nil ||
            summary.state == .workoutPaused ||
            summary.state == .cooldown ||
            !summary.dailySamples.isEmpty ||
            (summary.state == .buildingBaseline && (summary.lastHeartRate != nil || summary.lastHRV != nil))
    }

    private func dailyStressScore(from summary: StressSummary) -> Int? {
        let average = PulsarStressTimelineDistribution.weightedAverage(
            samples: summary.dailySamples.map { PulsarStressTimelineSample(timestamp: $0.timestamp, score: $0.score) }
        )
        return (average ?? summary.currentScore).map(PulsarStressScale.roundedScore)
    }

    private func hasUsableHealthMonitor(_ summary: HealthMonitorSummary) -> Bool {
        summary.availableMetricCount > 0
    }

}
