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

    @Published private(set) var dashboard: HomeDashboard = .empty {
        didSet {
            persistWidgetSnapshot(for: dashboard)
        }
    }
    @Published private(set) var selectedDate: Date
    @Published private(set) var strainRecords: [DailyStrainRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var healthKitStatus = "No HealthKit data loaded"

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
    private let calendar: Calendar
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []

    init(profileStore: ProfileStore? = nil, healthKit: HealthKitGateway = HealthKitGateway(), sleepDataService: SleepSummaryProviding? = nil, strainDataService: StrainSummaryProviding? = nil, recoveryDataService: RecoverySummaryProviding? = nil, stressDataService: StressSummaryProviding? = nil, healthMonitorDataService: HealthMonitorSummaryProviding? = nil, healthEventMonitor: HealthEventMonitor? = nil, lifecycleStore: AppLifecycleStore? = nil, syncStore: PulsarWatchConnectivitySyncStore? = nil, dashboardCache: PulsarDashboardCache? = nil, dailyHistoryStore: DailyHealthHistoryStore? = nil, bannerCenter: PulsarSyncBannerCenter? = nil, calendar: Calendar = .current, defaults: UserDefaults = .standard) {
        self.profileStore = profileStore ?? ProfileStore()
        self.healthKit = healthKit
        let resolvedSleepDataService = sleepDataService ?? SleepDataService(healthKit: healthKit)
        let resolvedStrainDataService = strainDataService ?? StrainDataService(healthKit: healthKit)
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
        self.calendar = calendar
        self.defaults = defaults
        self.lifecycleStore.registerFirstLaunchIfNeeded()
        self.selectedDate = calendar.startOfDay(for: Date())
        refreshProfileFromStore()
        loadCalendarHistoryFromStores()
        loadCachedDashboardIfAvailable()
        observeSyncPayloads()
        persistWidgetSnapshot(for: dashboard)
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
        await requestAutomaticSync(reason: "appBecameActive")
    }

    func requestInitialAppEntrySync() async {
        profileStore.refreshSleepPreferenceSideEffects(reason: "homeViewModelInitialEntry")
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
            logStrainValidation(dashboard: dashboard, context: "iPhone")
            healthKitStatus = "HealthKit connected"
            if let payload = dashboard.syncPayload(sourceDevice: .iPhone, syncSessionID: syncSessionID, calendar: calendar) {
                didBuildValidPayload = payload.hasValidData
                let didCommitPayload = syncStore.storeLocalPayload(payload, broadcast: true, reason: "iPhoneHealthKitSync")
                didCommitDailyMetrics = payload.hasCompleteDailyScores && didCommitPayload
                upsertDailyRecordIfUsable(payload)
                dashboard = canonicalDashboard(for: dashboard)
                dashboardCache.save(dashboard)
                PulsarSyncDebugLogger.log("calculated Strain value=\(payload.strain?.score ?? 0) session=\(syncSessionID.uuidString)")
                PulsarSyncDebugLogger.log("calculated Recovery value=\(payload.recovery?.score ?? 0) session=\(syncSessionID.uuidString)")
                PulsarSyncDebugLogger.log("calculated Stress value=\(payload.stress?.score ?? 0) session=\(syncSessionID.uuidString)")
                PulsarSyncDebugLogger.log("Sleep Score calculated value=\(payload.sleep?.score ?? 0) sleepDateKey=\(payload.sleep?.sleepDateKey ?? "none") session=\(syncSessionID.uuidString)")
            } else {
                dashboardCache.save(dashboard)
            }
            await healthKit.startObservers { [weak self] sampleType in
                await self?.healthKitSamplesDidChange(sampleType)
            }
            await healthEventMonitor.processForegroundSnapshot(profile: profileStore.profile, dashboard: dashboard, now: refreshDate)
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

    private func healthKitSamplesDidChange(_ sampleType: HKSampleType) async {
        PulsarSyncDebugLogger.log("HealthKit observer update received; deferring full sync until app entry or manual refresh")
        await healthEventMonitor.processObservedChange(
            sampleType: sampleType,
            profile: profileStore.profile,
            dashboard: dashboard
        )
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
            stressScore: dashboard.stress.score,
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
    }

    @discardableResult
    private func loadCachedDashboardIfAvailable() -> Bool {
        if let cached = dashboardCache.loadDashboard(for: selectedDate, calendar: calendar) {
            dashboard = cached
            healthKitStatus = "Showing latest available data"
            return true
        }
        if let cached = cachedDashboardFromSyncStore(for: selectedDate) {
            dashboard = cached
            healthKitStatus = "Showing saved daily data"
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
        if !hasUsableStress(fresh.stress), hasUsableStress(fallback.stress) {
            merged.stress = fallback.stress
        }
        if !hasUsableHealthMonitor(fresh.healthMonitor), hasUsableHealthMonitor(fallback.healthMonitor) {
            merged.healthMonitor = fallback.healthMonitor
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

    private func cachedDashboardFromSyncStore(for day: Date) -> HomeDashboard? {
        let dateKey = PulsarDailyMetricsDateKey.dateKey(for: day, calendar: calendar)
        let sleepDateKey = SleepWindowResolver.sleepDateKey(forWakeUpDate: day, calendar: calendar)
        var payload = syncStore.cachedDailyPayload(forDateKey: dateKey) ?? syncStore.cachedPayload(for: day, calendar: calendar)
        if let sleepPayload = syncStore.cachedSleepPayload(forSleepDateKey: sleepDateKey) {
            payload = payload.map { $0.merged(with: sleepPayload, calendar: calendar) } ?? sleepPayload
        }
        guard let payload, payload.isValidPayload else { return nil }
        let base = HomeDashboard(
            profile: profileStore.profile,
            sleep: .missing,
            recovery: .missing,
            strain: .missing,
            stress: .missing,
            healthMonitor: .missing(date: day),
            generatedAt: calendar.startOfDay(for: day),
            usingSampleData: false
        )
        return base.applying(payload: payload, calendar: calendar)
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
        let incomingStressUpdatedAt = payload.stress?.computedAt ?? .distantPast
        let currentStressUpdatedAt = dashboard.stress.lastUpdated ?? .distantPast
        let canUseIncomingStressAsCanonical = payload.sourceDevice == .iPhone || !hasUsableStress(dashboard.stress)
        let incomingHealthMonitorUpdatedAt = payload.healthMonitor?.computedAt ?? .distantPast
        let currentHealthMonitorUpdatedAt = dashboard.healthMonitor.lastUpdated ?? .distantPast
        return ((!hasUsableStrain(dashboard.strain) || !hasUsableRecovery(dashboard.recovery)) && payload.hasCompleteDailyScores) ||
        (payload.hasCompleteDailyScores && incomingDailyUpdatedAt > currentDailyUpdatedAt) ||
        (!hasUsableSleep(dashboard.sleep) && payload.sleep?.isValid == true) ||
        (payload.sleep?.isValid == true && incomingSleepUpdatedAt > currentSleepUpdatedAt) ||
        (!hasUsableStress(dashboard.stress) && payload.stress?.isValid == true) ||
        (canUseIncomingStressAsCanonical && payload.stress?.isValid == true && incomingStressUpdatedAt > currentStressUpdatedAt) ||
        (!hasUsableHealthMonitor(dashboard.healthMonitor) && payload.healthMonitor?.isValid == true) ||
        (payload.healthMonitor?.isValid == true && incomingHealthMonitorUpdatedAt > currentHealthMonitorUpdatedAt)
    }

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
        summary.score != nil || summary.state == .buildingBaseline || summary.analyzedSampleCount > 0
    }

    private func hasUsableHealthMonitor(_ summary: HealthMonitorSummary) -> Bool {
        summary.availableMetricCount > 0
    }

}
