//
//  WatchHealthKitStore.swift
//  Pulsar Watch App Watch App
//

import Foundation
import HealthKit
import Combine

@MainActor
final class WatchHealthKitStore: ObservableObject {
    @Published private(set) var snapshot: WatchDailyHealthSnapshot = .empty
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    @Published private(set) var syncBannerState: WatchSyncBannerState?

    private let healthStore = HKHealthStore()
    private let calendar: Calendar
    private let syncStore: PulsarWatchConnectivitySyncStore
    private let hasRequestedAuthorizationKey = "pulsar.watch.healthkit.requested.v1"
    private var cancellables: Set<AnyCancellable> = []
    private var activeSyncSessionID: UUID?
    private var latestCompletedSyncStartedAt: Date?
    private var visiblePayloadFingerprint: String?
    private var visiblePayloadSyncedAt: Date?
    private var visibleDailyMetricsComputedAt: Date?
    private var deferredPayloadDuringSync: PulsarDailyMetricsSyncPayload?
    private var bannerDismissTask: Task<Void, Never>?

    init(calendar: Calendar = .current, syncStore: PulsarWatchConnectivitySyncStore? = nil) {
        self.calendar = calendar
        self.syncStore = syncStore ?? .shared
        observeSyncPayloads()
        let dateKey = PulsarDailyMetricsDateKey.dateKey(for: Date(), calendar: calendar)
        if let cached = self.syncStore.cachedDailyPayload(forDateKey: dateKey) ?? self.syncStore.cachedPayload(for: Date(), calendar: calendar) {
            applySyncPayload(cached, state: snapshot.healthKitState, reason: "cached values loaded")
        }
    }

    deinit {
        bannerDismissTask?.cancel()
    }

    var hasRequestedAuthorization: Bool {
        UserDefaults.standard.bool(forKey: hasRequestedAuthorizationKey)
    }

    func viewAppeared() {
        PulsarSyncDebugLogger.log("Watch view appeared")
    }

    func load() async {
        guard !isLoading else {
            PulsarSyncDebugLogger.log("watch sync request skipped because a sync is already running session=\(activeSyncSessionID?.uuidString ?? "none")")
            return
        }

        let sessionID = UUID()
        let startedAt = Date()
        let sleepDateKey = SleepWindowResolver.sleepDateKey(forWakeUpDate: startedAt, calendar: calendar)
        let dateKey = PulsarDailyMetricsDateKey.dateKey(for: startedAt, calendar: calendar)
        var cached = syncStore.cachedDailyPayload(forDateKey: dateKey) ?? syncStore.cachedPayload(for: startedAt, calendar: calendar)
        if let sleepPayload = syncStore.cachedSleepPayload(forSleepDateKey: sleepDateKey) {
            cached = cached.map { $0.merged(with: sleepPayload, calendar: calendar) } ?? sleepPayload
        }
        if let cached {
            applySyncPayload(cached, state: snapshot.healthKitState, reason: "cached values loaded")
        }
        beginSync(sessionID: sessionID, startedAt: startedAt)

        guard HKHealthStore.isHealthDataAvailable() else {
            if snapshot.strain.score == nil && snapshot.recovery.score == nil {
                snapshot = emptySnapshot(state: .unavailable)
            } else {
                snapshot.healthKitState = .unavailable
            }
            message = "Health data is not available on this Apple Watch."
            finishSync(sessionID: sessionID, startedAt: startedAt, result: .hidden)
            return
        }

        let authorizationStatus = await authorizationRequestStatus()
        PulsarSyncDebugLogger.log("watch HealthKit permissions status=\(authorizationStatus.rawValue) session=\(sessionID.uuidString)")
        guard authorizationStatus == .unnecessary || hasRequestedAuthorization else {
            if snapshot.strain.score == nil && snapshot.recovery.score == nil {
                snapshot = emptySnapshot(state: .notRequested)
            } else {
                snapshot.healthKitState = .notRequested
            }
            message = "Connect Apple Health to view today’s Pulsar metrics."
            finishSync(sessionID: sessionID, startedAt: startedAt, result: .hidden)
            return
        }

        let didSyncValidData = await refreshSnapshot(state: .connected, sessionID: sessionID, startedAt: startedAt)
        finishSync(sessionID: sessionID, startedAt: startedAt, result: didSyncValidData ? .success : (hasVisibleMetrics ? .failure : .hidden))
    }

    func requestAuthorization() async {
        guard !isLoading else {
            PulsarSyncDebugLogger.log("watch authorization sync skipped because a sync is already running session=\(activeSyncSessionID?.uuidString ?? "none")")
            return
        }

        let sessionID = UUID()
        let startedAt = Date()
        beginSync(sessionID: sessionID, startedAt: startedAt)

        guard HKHealthStore.isHealthDataAvailable() else {
            snapshot = emptySnapshot(state: .unavailable)
            message = "Health data is not available on this Apple Watch."
            finishSync(sessionID: sessionID, startedAt: startedAt, result: .hidden)
            return
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                healthStore.requestAuthorization(toShare: [], read: Self.requiredReadTypes) { success, error in
                    if let error { continuation.resume(throwing: error) }
                    else if success { continuation.resume() }
                    else { continuation.resume(throwing: WatchHealthKitError.authorizationDenied) }
                }
            }
            UserDefaults.standard.set(true, forKey: hasRequestedAuthorizationKey)
            message = nil
            let didSyncValidData = await refreshSnapshot(state: .connected, sessionID: sessionID, startedAt: startedAt)
            finishSync(sessionID: sessionID, startedAt: startedAt, result: didSyncValidData ? .success : (hasVisibleMetrics ? .failure : .hidden))
        } catch {
            UserDefaults.standard.set(true, forKey: hasRequestedAuthorizationKey)
            if snapshot.strain.score == nil && snapshot.recovery.score == nil {
                snapshot = emptySnapshot(state: .needsPermission)
            } else {
                snapshot.healthKitState = .needsPermission
            }
            message = "Pulsar needs Apple Health permission. Manage access from the iPhone app or Apple Health."
            finishSync(sessionID: sessionID, startedAt: startedAt, result: .hidden)
        }
    }

    private func refreshSnapshot(state: WatchHealthKitState, sessionID: UUID, startedAt: Date) async -> Bool {
        let now = startedAt
        let dayInterval = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: calendar.startOfDay(for: now), duration: 86_400)
        let dateKey = PulsarDailyMetricsDateKey.dateKey(for: now, calendar: calendar)
        let targetSleepHours = targetSleepHours(for: now)
        async let sleep = fetchSleepResult(now: now, targetSleepHours: targetSleepHours, computedAt: startedAt)
        async let activity = fetchActivity(interval: dayInterval)
        async let heart = fetchHeartMetrics(interval: dayInterval)
        async let workouts = fetchWorkouts(interval: dayInterval)
        async let recentLoads = fetchRecentRawLoads(endingAt: dayInterval.end)
        let values = await (sleep, activity, heart, workouts, recentLoads)
        guard canCommitSync(sessionID: sessionID, startedAt: startedAt) else {
            PulsarSyncDebugLogger.log("older sync result ignored on watch session=\(sessionID.uuidString)")
            return false
        }
        PulsarSyncDebugLogger.log("HealthKit query completed on watch session=\(sessionID.uuidString) workouts=\(values.3.count) steps=\(Int(values.1.steps.rounded())) activeEnergy=\(Int(values.1.activeEnergy.rounded())) hrv=\(values.2.hrvSDNN.map { String(Int($0.rounded())) } ?? "nil") rhr=\(values.2.restingHeartRate.map { String(Int($0.rounded())) } ?? "nil") sleepMinutes=\(Int(values.0.summary.totalSleepMinutes.rounded())) sleepDateKey=\(values.0.metric?.sleepDateKey ?? "none") recentLoadDays=\(values.4.count)")

        let strainMetric = PulsarSharedMetricCalculator.makeStrainMetric(
            activity: PulsarSharedActivityInput(
                steps: values.1.steps,
                activeEnergyKilocalories: values.1.activeEnergy,
                exerciseMinutes: values.1.workoutMinutes
            ),
            workouts: values.3.map {
                PulsarSharedWorkoutInput(
                    type: $0.type,
                    durationMinutes: $0.durationMinutes,
                    activeEnergyKilocalories: $0.activeEnergy,
                    averageHeartRate: $0.averageHeartRate,
                    peakHeartRate: $0.averageHeartRate,
                    sourceName: $0.sourceName
                )
            },
            recentRawLoads: values.4,
            computedAt: startedAt
        )
        let baselineDays = await fetchRecoveryBaselineDays(before: dayInterval.start)
        guard canCommitSync(sessionID: sessionID, startedAt: startedAt) else {
            PulsarSyncDebugLogger.log("older sync result ignored after baseline query on watch session=\(sessionID.uuidString)")
            return false
        }
        let recoveryMetric = PulsarSharedMetricCalculator.makeRecoveryMetric(
            today: PulsarSharedBiometricsDay(
                date: now,
                hrvSDNN: values.2.hrvSDNN,
                restingHeartRate: values.2.restingHeartRate,
                respiratoryRate: values.2.respiratoryRate,
                oxygenSaturation: nil,
                wristTemperatureDeviation: nil,
                sleepPerformance: values.0.metric.map(\.sleepPerformance),
                strainScore: strainMetric.map { Double($0.score) },
                sourceNames: detectedSources(sleep: values.0.summary, workouts: values.3)
            ),
            baselineDays: baselineDays,
            computedAt: startedAt
        )
        let hasCompleteDailyMetrics = strainMetric?.isValid == true && recoveryMetric?.isValid == true
        if (strainMetric != nil || recoveryMetric != nil) && !hasCompleteDailyMetrics {
            PulsarSyncDebugLogger.log("invalid or partial Recovery/Strain result ignored on watch dateKey=\(dateKey) strainValid=\(strainMetric?.isValid == true) recoveryValid=\(recoveryMetric?.isValid == true) session=\(sessionID.uuidString)")
        }
        let sources = detectedSources(sleep: values.0.summary, workouts: values.3)
        let localPayload = PulsarDailyMetricsSyncPayload(
            date: calendar.startOfDay(for: now),
            dateKey: dateKey,
            syncedAt: startedAt,
            sourceDevice: .appleWatch,
            strain: hasCompleteDailyMetrics ? strainMetric : nil,
            recovery: hasCompleteDailyMetrics ? recoveryMetric : nil,
            sleep: values.0.metric,
            syncSessionID: sessionID,
            validityFlag: true
        )
        var didCommitPayload = false
        if localPayload.isValidPayload {
            didCommitPayload = syncStore.storeLocalPayload(localPayload, broadcast: true, reason: "watchHealthKitSync")
            PulsarSyncDebugLogger.log("calculated Strain value=\(localPayload.strain?.score ?? 0) session=\(sessionID.uuidString)")
            PulsarSyncDebugLogger.log("calculated Recovery value=\(localPayload.recovery?.score ?? 0) session=\(sessionID.uuidString)")
            PulsarSyncDebugLogger.log("Sleep Score calculated value=\(localPayload.sleep?.score ?? 0) sleepDateKey=\(localPayload.sleep?.sleepDateKey ?? "none") session=\(sessionID.uuidString)")
        } else {
            PulsarSyncDebugLogger.log("invalid/empty result ignored on watch session=\(sessionID.uuidString)")
        }

        var displayPayload = syncStore.cachedDailyPayload(forDateKey: dateKey) ?? syncStore.cachedPayload(for: now, calendar: calendar)
        if let sleepPayload = syncStore.cachedSleepPayload(forSleepDateKey: SleepWindowResolver.sleepDateKey(forWakeUpDate: now, calendar: calendar)) {
            displayPayload = displayPayload.map { $0.merged(with: sleepPayload, calendar: calendar) } ?? sleepPayload
        }
        if let cachedPayload = displayPayload, localPayload.isValidPayload {
            displayPayload = cachedPayload.merged(with: localPayload, calendar: calendar)
        } else if localPayload.isValidPayload {
            displayPayload = localPayload
        }
        if let deferredPayloadDuringSync {
            if deferredPayloadDuringSync.isValidPayload {
                displayPayload = displayPayload.map { $0.merged(with: deferredPayloadDuringSync, calendar: calendar) } ?? deferredPayloadDuringSync
                PulsarSyncDebugLogger.log("staged WatchConnectivity payload folded into watch UI commit session=\(deferredPayloadDuringSync.syncSessionID?.uuidString ?? "none")")
            } else {
                PulsarSyncDebugLogger.log("invalid staged WatchConnectivity payload ignored on watch")
            }
            self.deferredPayloadDuringSync = nil
        }

        commitHealthSnapshot(
            date: now,
            state: state,
            sleep: values.0.summary,
            payload: displayPayload,
            activity: values.1,
            heart: values.2,
            workouts: values.3,
            sources: sources,
            reason: "watchHealthKitSync"
        )
        if didCommitPayload, displayPayload?.hasCompleteDailyScores == true {
            message = nil
            PulsarSyncDebugLogger.log("sync finished on watch session=\(sessionID.uuidString)")
            return true
        } else {
            message = "No usable HealthKit signal was available yet. Pulsar will keep trying to sync."
            PulsarSyncDebugLogger.log("sync finished on watch without usable values session=\(sessionID.uuidString)")
            return false
        }
    }

    private enum WatchSyncCompletionResult {
        case success
        case failure
        case hidden
    }

    private struct WatchSleepFetchResult {
        var summary: WatchSleepSummary
        var metric: PulsarSleepSyncMetric?

        static let empty = WatchSleepFetchResult(summary: .empty, metric: nil)
    }

    private var hasVisibleMetrics: Bool {
        snapshot.strain.score != nil || snapshot.recovery.score != nil || snapshot.sleep.score != nil
    }

    private func payloadFillsMissingVisibleMetric(_ payload: PulsarDailyMetricsSyncPayload) -> Bool {
        ((snapshot.strain.score == nil || snapshot.recovery.score == nil) && payload.hasCompleteDailyScores) ||
        (snapshot.sleep.score == nil && payload.sleep?.isValid == true)
    }

    private func targetSleepHours(for date: Date) -> Double {
        let sleepDateKey = SleepWindowResolver.sleepDateKey(forWakeUpDate: date, calendar: calendar)
        return syncStore.cachedSleepPayload(forSleepDateKey: sleepDateKey)?.sleep?.targetSleepHours ??
            syncStore.cachedPayload(for: date, calendar: calendar)?.sleep?.targetSleepHours ??
            PulsarSharedSleepCalculator.defaultTargetSleepHours
    }

    private func beginSync(sessionID: UUID, startedAt: Date) {
        bannerDismissTask?.cancel()
        bannerDismissTask = nil
        activeSyncSessionID = sessionID
        deferredPayloadDuringSync = nil
        isLoading = true
        syncBannerState = .syncing("Syncing health data…")
        PulsarSyncDebugLogger.log("sync started on watch session=\(sessionID.uuidString) startedAt=\(startedAt)")
    }

    private func finishSync(sessionID: UUID, startedAt: Date, result: WatchSyncCompletionResult) {
        guard activeSyncSessionID == sessionID else {
            PulsarSyncDebugLogger.log("older sync completion ignored on watch session=\(sessionID.uuidString) active=\(activeSyncSessionID?.uuidString ?? "none")")
            return
        }
        guard latestCompletedSyncStartedAt.map({ startedAt >= $0 }) ?? true else {
            PulsarSyncDebugLogger.log("older sync completion ignored on watch session=\(sessionID.uuidString) startedAt=\(startedAt) latest=\(latestCompletedSyncStartedAt ?? .distantPast)")
            return
        }

        latestCompletedSyncStartedAt = startedAt
        activeSyncSessionID = nil
        isLoading = false

        switch result {
        case .success:
            syncBannerState = .success("Health data synced")
            scheduleBannerDismiss(after: 1_450_000_000)
        case .failure:
            syncBannerState = .failure("Unable to sync. Showing latest data.")
            scheduleBannerDismiss(after: 2_100_000_000)
        case .hidden:
            syncBannerState = nil
        }
    }

    private func scheduleBannerDismiss(after nanoseconds: UInt64) {
        bannerDismissTask?.cancel()
        bannerDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            syncBannerState = nil
        }
    }

    private func canCommitSync(sessionID: UUID, startedAt: Date) -> Bool {
        guard activeSyncSessionID == sessionID else { return false }
        if let latestCompletedSyncStartedAt, startedAt < latestCompletedSyncStartedAt { return false }
        return true
    }

    private func commitHealthSnapshot(
        date: Date,
        state: WatchHealthKitState,
        sleep: WatchSleepSummary,
        payload: PulsarDailyMetricsSyncPayload?,
        activity: WatchActivitySummary,
        heart: WatchHeartMetricsSummary,
        workouts: [WatchWorkoutSummary],
        sources: [String],
        reason: String
    ) {
        let validPayload = payload.flatMap { candidate -> PulsarDailyMetricsSyncPayload? in
            guard candidate.isValidPayload,
                  candidate.applies(to: date, calendar: calendar) else { return nil }
            return candidate
        }
        if let payload, validPayload == nil {
            PulsarSyncDebugLogger.log("invalid/empty result ignored on watch reason=\(reason) session=\(payload.syncSessionID?.uuidString ?? "none")")
        }

        let nextSleep = validPayload.flatMap { watchSleep(from: $0.sleep) } ?? (sleep.score != nil ? sleep : snapshot.sleep)
        let nextRecovery: WatchRecoverySummary
        let nextStrain: WatchStrainSummary
        if let validPayload, validPayload.hasCompleteDailyScores, canApplyDailyMetrics(from: validPayload) {
            nextRecovery = watchRecovery(from: validPayload.recovery) ?? snapshot.recovery
            nextStrain = watchStrain(from: validPayload.strain, workouts: workouts, activity: activity) ?? snapshot.strain
            visibleDailyMetricsComputedAt = dailyMetricsComputedAt(in: validPayload)
        } else if let validPayload, validPayload.hasCompleteDailyScores {
            PulsarSyncDebugLogger.log("older Recovery/Strain result ignored on watch reason=\(reason) session=\(validPayload.syncSessionID?.uuidString ?? "none") incoming=\(dailyMetricsComputedAt(in: validPayload) ?? .distantPast) visible=\(visibleDailyMetricsComputedAt ?? .distantPast)")
            nextRecovery = snapshot.recovery
            nextStrain = snapshot.strain
        } else {
            nextRecovery = snapshot.recovery
            nextStrain = snapshot.strain
        }
        if let validPayload {
            if visiblePayloadFingerprint == validPayload.resolvedDataFingerprint {
                PulsarSyncDebugLogger.log("watch UI kept stable because payload fingerprint was unchanged reason=\(reason) session=\(validPayload.syncSessionID?.uuidString ?? "none")")
            } else {
                PulsarSyncDebugLogger.log("watch UI updated reason=\(reason) session=\(validPayload.syncSessionID?.uuidString ?? "none") fingerprint=\(validPayload.resolvedDataFingerprint)")
            }
            visiblePayloadFingerprint = validPayload.resolvedDataFingerprint
            visiblePayloadSyncedAt = validPayload.syncedAt
        }

        snapshot = WatchDailyHealthSnapshot(
            date: date,
            healthKitState: state,
            sleep: nextSleep,
            recovery: nextRecovery,
            strain: nextStrain,
            activity: activity,
            heart: heart,
            workouts: workouts,
            detectedSources: sources
        )
    }

    private func fetchSleepResult(now: Date, targetSleepHours: Double, computedAt: Date) async -> WatchSleepFetchResult {
        let wakeUpDate = calendar.startOfDay(for: now)
        let analysis = await fetchSleepAnalysis(wakeUpDate: wakeUpDate, logSamples: true)
        guard analysis.hasSamples else {
            PulsarSyncDebugLogger.log("invalid/empty sleep result ignored on watch sleepDateKey=\(SleepWindowResolver.sleepDateKey(forWakeUpDate: wakeUpDate, calendar: calendar))")
            return .empty
        }

        var recentAnalyses: [SleepAnalysisSummary] = []
        for offset in 1...10 {
            guard let priorWakeDate = calendar.date(byAdding: .day, value: -offset, to: wakeUpDate) else { continue }
            let priorAnalysis = await fetchSleepAnalysis(wakeUpDate: priorWakeDate, logSamples: false)
            if priorAnalysis.hasSamples {
                recentAnalyses.append(priorAnalysis)
            }
        }

        guard let metric = PulsarSharedSleepCalculator.makeSleepMetric(
            analysis: analysis,
            recentAnalyses: recentAnalyses,
            targetSleepHours: targetSleepHours,
            computedAt: computedAt,
            calendar: calendar
        ) else {
            PulsarSyncDebugLogger.log("invalid/empty sleep result ignored on watch sleepDateKey=\(SleepWindowResolver.sleepDateKey(forWakeUpDate: wakeUpDate, calendar: calendar))")
            return .empty
        }

        PulsarSyncDebugLogger.log("Sleep Score calculated on watch score=\(metric.score) sleepDateKey=\(metric.sleepDateKey) sessionWindow=\(metric.sleepStart)-\(metric.sleepEnd)")
        return WatchSleepFetchResult(summary: watchSleep(from: metric) ?? .empty, metric: metric)
    }

    private func fetchSleepAnalysis(wakeUpDate: Date, logSamples: Bool) async -> SleepAnalysisSummary {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return emptySleepAnalysis(wakeUpDate: wakeUpDate) }
        let window = SleepWindowResolver.window(forWakeUpDate: wakeUpDate, calendar: calendar)
        if logSamples {
            PulsarSyncDebugLogger.log("Sleep sync selected canonical window on watch sleepDateKey=\(SleepWindowResolver.sleepDateKey(forWakeUpDate: wakeUpDate, calendar: calendar)) start=\(window.start) end=\(window.end)")
        }
        let samples = await categorySamples(type: type, start: window.start, end: window.end)
        if logSamples {
            PulsarSyncDebugLogger.log("HealthKit sleep samples loaded on watch count=\(samples.count) sleepDateKey=\(SleepWindowResolver.sleepDateKey(forWakeUpDate: wakeUpDate, calendar: calendar))")
        }
        let analysisSamples = samples.map { sleepAnalysisSample(for: $0) }
        #if DEBUG
        if logSamples {
            SleepDebugLogger.logQuery(platform: "watchOS", start: window.start, end: window.end, samples: analysisSamples)
        }
        #endif
        return SleepAnalyzer().analyze(samples: analysisSamples, wakeUpDate: wakeUpDate, calendar: calendar)
    }

    private func emptySleepAnalysis(wakeUpDate: Date) -> SleepAnalysisSummary {
        let window = SleepWindowResolver.window(forWakeUpDate: wakeUpDate, calendar: calendar)
        return SleepAnalysisSummary(
            wakeUpDate: calendar.startOfDay(for: wakeUpDate),
            queryStart: window.start,
            queryEnd: window.end,
            rawSampleCount: 0,
            usedSampleCount: 0,
            totalSleepMinutes: 0,
            timeInBedMinutes: 0,
            awakeMinutes: 0,
            wasoMinutes: 0,
            remMinutes: 0,
            coreMinutes: 0,
            deepMinutes: 0,
            asleepUnspecifiedMinutes: 0,
            awakenings: 0,
            mergedIntervals: [],
            sourceNames: []
        )
    }

    private func fetchActivity(interval: DateInterval) async -> WatchActivitySummary {
        async let steps = sumQuantity(.stepCount, unit: .count(), interval: interval)
        async let energy = sumQuantity(.activeEnergyBurned, unit: .kilocalorie(), interval: interval)
        async let exercise = sumQuantity(.appleExerciseTime, unit: .minute(), interval: interval)
        let values = await (steps, energy, exercise)
        return WatchActivitySummary(steps: values.0, activeEnergy: values.1, workoutMinutes: values.2)
    }

    private func fetchHeartMetrics(interval: DateInterval) async -> WatchHeartMetricsSummary {
        async let latest = mostRecentQuantity(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: interval.start, end: interval.end)
        async let resting = mostRecentQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: interval.start, end: interval.end)
        async let hrv = mostRecentQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: interval.start, end: interval.end)
        async let respiratory = mostRecentQuantity(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), start: interval.start, end: interval.end)
        let values = await (latest, resting, hrv, respiratory)
        return WatchHeartMetricsSummary(latestHeartRate: values.0, restingHeartRate: values.1, hrvSDNN: values.2, respiratoryRate: values.3)
    }

    private func fetchWorkouts(interval: DateInterval) async -> [WatchWorkoutSummary] {
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 8, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            healthStore.execute(query)
        }

        var summaries: [WatchWorkoutSummary] = []
        for workout in workouts {
            let averageHeartRate = await averageHeartRate(start: workout.startDate, end: workout.endDate)
            summaries.append(WatchWorkoutSummary(id: workout.uuid, type: workout.workoutActivityType.watchDisplayName, start: workout.startDate, durationMinutes: workout.duration / 60, activeEnergy: activeEnergy(for: workout), averageHeartRate: averageHeartRate, sourceName: workout.sourceRevision.source.name))
        }
        return summaries
    }

    private func activeEnergy(for workout: HKWorkout) -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else { return nil }
        return workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: .kilocalorie())
    }

    private func detectedSources(sleep: WatchSleepSummary, workouts: [WatchWorkoutSummary]) -> [String] {
        var sources: Set<String> = []
        if let source = sleep.sourceName { sources.insert(source) }
        for workout in workouts { if let source = workout.sourceName { sources.insert(source) } }
        return sources.sorted()
    }

    private func emptySnapshot(state: WatchHealthKitState) -> WatchDailyHealthSnapshot {
        var snapshot = WatchDailyHealthSnapshot.empty
        snapshot.date = Date()
        snapshot.healthKitState = state
        return snapshot
    }

    private func sumQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, interval: DateInterval) async -> Double {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return 0 }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            healthStore.execute(query)
        }
    }

    private func mostRecentQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else { continuation.resume(returning: nil); return }
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            healthStore.execute(query)
        }
    }

    private func averageHeartRate(start: Date, end: Date) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, statistics, _ in
                continuation.resume(returning: statistics?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
            }
            healthStore.execute(query)
        }
    }

    private func categorySamples(type: HKCategoryType, start: Date, end: Date) async -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples as? [HKCategorySample] ?? [])
            }
            healthStore.execute(query)
        }
    }

    private func sleepAnalysisSample(for sample: HKCategorySample) -> SleepAnalysisSample {
        SleepAnalysisSample(
            id: sample.uuid.uuidString,
            stage: sleepAnalysisStage(for: sample.value),
            start: sample.startDate,
            end: sample.endDate,
            sourceName: sample.sourceRevision.source.name,
            sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
            deviceName: sample.device?.name
        )
    }

    private func sleepAnalysisStage(for value: Int) -> SleepAnalysisStage {
        switch value {
        case HKCategoryValueSleepAnalysis.awake.rawValue: .awake
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue: .asleepCore
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: .asleepDeep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue: .asleepREM
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: .asleepUnspecified
        case HKCategoryValueSleepAnalysis.inBed.rawValue: .inBed
        default: .asleepUnspecified
        }
    }

    static var requiredReadTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        let identifiers: [HKQuantityTypeIdentifier] = [.heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .respiratoryRate, .oxygenSaturation, .appleSleepingWristTemperature, .activeEnergyBurned, .appleExerciseTime, .stepCount, .bodyMass, .height]
        identifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) }.forEach { types.insert($0) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        types.insert(HKObjectType.workoutType())
        return types
    }

    private func authorizationRequestStatus() async -> HKAuthorizationRequestStatus {
        await withCheckedContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: Self.requiredReadTypes) { status, _ in
                continuation.resume(returning: status)
            }
        }
    }

    private func fetchRecentRawLoads(endingAt end: Date) async -> [Double] {
        guard let start = calendar.date(byAdding: .day, value: -28, to: end),
              let type = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else { return [] }
        let anchor = calendar.startOfDay(for: start)
        var interval = DateComponents()
        interval.day = 1
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, collection, _ in
                var values: [Double] = []
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let kilocalories = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    values.append(max(0, kilocalories / 8))
                }
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    private func fetchRecoveryBaselineDays(before date: Date) async -> [PulsarSharedBiometricsDay] {
        var values: [PulsarSharedBiometricsDay] = []
        for offset in 1...28 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { continue }
            let interval = calendar.dateInterval(of: .day, for: day) ?? DateInterval(start: day, duration: 86_400)
            async let hrv = mostRecentQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: interval.start, end: interval.end)
            async let resting = mostRecentQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: interval.start, end: interval.end)
            async let respiratory = mostRecentQuantity(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), start: interval.start, end: interval.end)
            let biometrics = await (hrv, resting, respiratory)
            values.append(
                PulsarSharedBiometricsDay(
                    date: day,
                    hrvSDNN: biometrics.0,
                    restingHeartRate: biometrics.1,
                    respiratoryRate: biometrics.2,
                    oxygenSaturation: nil,
                    wristTemperatureDeviation: nil,
                    sleepPerformance: nil,
                    strainScore: nil,
                    sourceNames: []
                )
            )
        }
        return values
    }

    private func observeSyncPayloads() {
        syncStore.$latestPayload
            .receive(on: RunLoop.main)
            .sink { [weak self] payload in
                guard let self, let payload else { return }
                self.applySyncPayload(payload, state: self.snapshot.healthKitState, reason: "WatchConnectivity payload received")
            }
            .store(in: &cancellables)
    }

    private func applySyncPayload(_ payload: PulsarDailyMetricsSyncPayload, state: WatchHealthKitState, reason: String) {
        guard payload.isValidPayload,
              payload.applies(to: Date(), calendar: calendar) else {
            PulsarSyncDebugLogger.log("payload rejected on watch reason=\(reason) session=\(payload.syncSessionID?.uuidString ?? "none")")
            return
        }

        if isLoading {
            if let deferredPayloadDuringSync,
               deferredPayloadDuringSync.syncedAt > payload.syncedAt,
               deferredPayloadDuringSync.resolvedDataFingerprint != payload.resolvedDataFingerprint {
                PulsarSyncDebugLogger.log("older WatchConnectivity payload staged update ignored on watch session=\(payload.syncSessionID?.uuidString ?? "none")")
                return
            }
            deferredPayloadDuringSync = payload
            PulsarSyncDebugLogger.log("WatchConnectivity payload staged during active watch sync session=\(payload.syncSessionID?.uuidString ?? "none") fingerprint=\(payload.resolvedDataFingerprint)")
            return
        }

        if let visiblePayloadSyncedAt,
           payload.syncedAt < visiblePayloadSyncedAt,
           hasVisibleMetrics,
           !payloadFillsMissingVisibleMetric(payload) {
            PulsarSyncDebugLogger.log("WatchConnectivity payload rejected on watch because it was older session=\(payload.syncSessionID?.uuidString ?? "none") incoming=\(payload.syncedAt) visible=\(visiblePayloadSyncedAt)")
            return
        }

        if visiblePayloadFingerprint == payload.resolvedDataFingerprint,
           hasVisibleMetrics {
            PulsarSyncDebugLogger.log("WatchConnectivity payload kept stable on watch because fingerprint was unchanged session=\(payload.syncSessionID?.uuidString ?? "none")")
            return
        }

        let nextSleep = watchSleep(from: payload.sleep) ?? snapshot.sleep
        let nextStrain: WatchStrainSummary
        let nextRecovery: WatchRecoverySummary
        if payload.hasCompleteDailyScores, canApplyDailyMetrics(from: payload) {
            nextStrain = watchStrain(from: payload.strain, workouts: snapshot.workouts, activity: snapshot.activity) ?? snapshot.strain
            nextRecovery = watchRecovery(from: payload.recovery) ?? snapshot.recovery
            visibleDailyMetricsComputedAt = dailyMetricsComputedAt(in: payload)
        } else if payload.hasCompleteDailyScores {
            PulsarSyncDebugLogger.log("WatchConnectivity Recovery/Strain payload rejected on watch because daily metrics were older session=\(payload.syncSessionID?.uuidString ?? "none") incoming=\(dailyMetricsComputedAt(in: payload) ?? .distantPast) visible=\(visibleDailyMetricsComputedAt ?? .distantPast)")
            nextStrain = snapshot.strain
            nextRecovery = snapshot.recovery
        } else {
            nextStrain = snapshot.strain
            nextRecovery = snapshot.recovery
        }
        guard nextSleep.score != nil || nextStrain.score != nil || nextRecovery.score != nil else {
            PulsarSyncDebugLogger.log("WatchConnectivity payload rejected on watch because it had no visible values session=\(payload.syncSessionID?.uuidString ?? "none")")
            return
        }

        snapshot.sleep = nextSleep
        snapshot.strain = nextStrain
        snapshot.recovery = nextRecovery
        snapshot.date = max(snapshot.date, payload.syncedAt)
        snapshot.healthKitState = state
        visiblePayloadFingerprint = payload.resolvedDataFingerprint
        visiblePayloadSyncedAt = payload.syncedAt
        message = nil
        PulsarSyncDebugLogger.log("WatchConnectivity payload accepted on watch reason=\(reason) source=\(payload.sourceDevice.rawValue) sleepDateKey=\(payload.sleep?.sleepDateKey ?? "none") session=\(payload.syncSessionID?.uuidString ?? "none") fingerprint=\(payload.resolvedDataFingerprint)")
    }

    private func canApplyDailyMetrics(from payload: PulsarDailyMetricsSyncPayload) -> Bool {
        guard payload.hasCompleteDailyScores,
              let incomingComputedAt = dailyMetricsComputedAt(in: payload) else { return false }
        if snapshot.strain.score == nil || snapshot.recovery.score == nil { return true }
        return visibleDailyMetricsComputedAt.map { incomingComputedAt >= $0 } ?? true
    }

    private func dailyMetricsComputedAt(in payload: PulsarDailyMetricsSyncPayload) -> Date? {
        guard let strain = payload.strain, let recovery = payload.recovery, strain.isValid, recovery.isValid else { return nil }
        return max(strain.computedAt, recovery.computedAt)
    }

    private func watchSleep(from metric: PulsarSleepSyncMetric?) -> WatchSleepSummary? {
        guard let metric, metric.isValid else { return nil }
        return WatchSleepSummary(
            score: metric.score,
            totalSleepMinutes: metric.totalSleepMinutes,
            timeInBedMinutes: metric.timeInBedMinutes,
            efficiency: metric.sleepEfficiency,
            consistency: metric.sleepConsistency,
            awakeMinutes: metric.awakeMinutes,
            remMinutes: metric.remMinutes,
            coreMinutes: metric.coreMinutes,
            deepMinutes: metric.deepMinutes,
            asleepUnspecifiedMinutes: metric.asleepUnspecifiedMinutes,
            sourceName: metric.sourceNames.first
        )
    }

    private func watchRecovery(from metric: PulsarRecoverySyncMetric?) -> WatchRecoverySummary? {
        guard let metric, metric.isValid else { return nil }
        return WatchRecoverySummary(
            score: metric.score > 0 ? metric.score : nil,
            label: metric.statusText,
            hrv: metric.hrvSDNN,
            restingHeartRate: metric.restingHeartRate,
            respiratoryRate: metric.respiratoryRate,
            sleepPerformance: metric.sleepContribution > 0 ? metric.sleepContribution : nil
        )
    }

    private func watchStrain(from metric: PulsarStrainSyncMetric?, workouts: [WatchWorkoutSummary], activity: WatchActivitySummary) -> WatchStrainSummary? {
        guard let metric, metric.isValid else { return nil }
        return WatchStrainSummary(
            score: metric.score > 0 ? metric.score : nil,
            workoutMinutes: max(metric.workoutMinutes, activity.workoutMinutes),
            activeEnergy: metric.activeEnergyKilocalories ?? activity.activeEnergy,
            steps: Double(metric.steps),
            zoneMinutes: [],
            lastWorkout: workouts.first
        )
    }
}

private enum WatchHealthKitError: Error {
    case authorizationDenied
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, self))
    }
}

private extension HKWorkoutActivityType {
    var watchDisplayName: String {
        switch self {
        case .running: "Run"
        case .walking: "Walk"
        case .cycling: "Ride"
        case .traditionalStrengthTraining: "Strength"
        case .functionalStrengthTraining: "Functional"
        case .swimming: "Swim"
        case .hiking: "Hike"
        case .yoga: "Yoga"
        case .highIntensityIntervalTraining: "HIIT"
        default: "Workout"
        }
    }
}
