import Combine
import Foundation
import WatchConnectivity
#if os(watchOS)
import WatchKit
#endif

struct AppleWatchBatterySnapshot: Codable, Equatable {
    var batteryPercentage: Int
    var timestamp: Date
}

@MainActor
final class PulsarWatchConnectivitySyncStore: NSObject, ObservableObject {
    static let shared = PulsarWatchConnectivitySyncStore()

    @Published private(set) var latestPayload: PulsarDailyMetricsSyncPayload?
    @Published private(set) var latestSleepPreferences: PulsarSleepPreferencesSyncPayload?
    @Published private(set) var latestAppleWatchBattery: AppleWatchBatterySnapshot?
    @Published private(set) var activeWorkoutState: PulsarActiveWorkoutSyncState?
    @Published private(set) var activeGymState: ActiveGymWorkoutState?
    @Published private(set) var savedGymRoutines: [WatchGymRoutinePlan]

    private let defaults: UserDefaults
    private let cacheKey = "pulsar.sync.cachedDailyMetricsPayload.v1"
    private let dailyCacheKey = "pulsar.sync.cachedDailyMetricPayloadsByDateKey.v1"
    private let sleepCacheKey = "pulsar.sync.cachedSleepPayloadsByDateKey.v1"
    private let sleepPreferencesCacheKey = "pulsar.sync.cachedSleepPreferencesPayload.v1"
    private let appleWatchBatteryCacheKey = "pulsar.sync.appleWatchBattery.v1"
    private let activeWorkoutCacheKey = "pulsar.sync.activeWorkoutState.v1"
    private let activeGymCacheKey = "pulsar.sync.activeGymWorkoutState.v1"
    private let savedGymRoutinesCacheKey = "pulsar.sync.savedGymRoutines.v1"
    private let session: WCSession?
    private var dailyPayloadsByDateKey: [String: PulsarDailyMetricsSyncPayload]
    private var sleepPayloadsByDateKey: [String: PulsarDailyMetricsSyncPayload]
    private var activeWorkoutStateHandler: ((PulsarActiveWorkoutSyncState) -> Void)?
    private var gymActionHandler: ((ActiveGymWorkoutAction) -> Void)?
    #if os(iOS)
    private let gymLiveActivityManager = GymLiveActivityManager()
    #endif

    private override init() {
        self.defaults = .standard
        self.session = WCSession.isSupported() ? WCSession.default : nil
        if let data = defaults.data(forKey: dailyCacheKey),
           let payloads = try? JSONDecoder().decode([String: PulsarDailyMetricsSyncPayload].self, from: data) {
            self.dailyPayloadsByDateKey = payloads.filter { key, payload in
                key == payload.resolvedDateKey && payload.isValidPayload && (payload.hasCompleteDailyScores || payload.hasValidStress)
            }
        } else {
            self.dailyPayloadsByDateKey = [:]
        }
        if let data = defaults.data(forKey: sleepCacheKey),
           let payloads = try? JSONDecoder().decode([String: PulsarDailyMetricsSyncPayload].self, from: data) {
            self.sleepPayloadsByDateKey = payloads.filter { $0.value.isValidPayload && $0.value.sleep?.isValid == true }
        } else {
            self.sleepPayloadsByDateKey = [:]
        }
        if let data = defaults.data(forKey: cacheKey),
           let payload = PulsarSyncPayloadCodec.decode(data: data),
           payload.isValidPayload {
            self.latestPayload = payload
        } else {
            self.latestPayload = nil
        }
        if let data = defaults.data(forKey: sleepPreferencesCacheKey),
           let payload = try? JSONDecoder().decode(PulsarSleepPreferencesSyncPayload.self, from: data),
           payload.isValid {
            self.latestSleepPreferences = payload
        } else {
            self.latestSleepPreferences = nil
        }
        if let data = defaults.data(forKey: appleWatchBatteryCacheKey),
           let snapshot = try? JSONDecoder().decode(AppleWatchBatterySnapshot.self, from: data),
           Self.isValidAppleWatchBattery(snapshot) {
            self.latestAppleWatchBattery = snapshot
        } else {
            self.latestAppleWatchBattery = nil
        }
        if let data = defaults.data(forKey: activeWorkoutCacheKey),
           let state = Self.decodeActiveWorkoutState(data),
           Self.shouldRestoreCachedActiveWorkoutState(state) {
            self.activeWorkoutState = state
        } else {
            self.activeWorkoutState = nil
            defaults.removeObject(forKey: activeWorkoutCacheKey)
        }
        if let data = defaults.data(forKey: activeGymCacheKey),
           let state = ActiveGymWorkoutCodec.decodeState(data),
           Self.shouldRestoreCachedActiveGymState(state) {
            self.activeGymState = state
        } else {
            self.activeGymState = nil
            defaults.removeObject(forKey: activeGymCacheKey)
        }
        if let data = defaults.data(forKey: savedGymRoutinesCacheKey),
           let routines = try? JSONDecoder().decode([WatchGymRoutinePlan].self, from: data) {
            self.savedGymRoutines = routines.sorted { $0.updatedAt > $1.updatedAt }
        } else {
            self.savedGymRoutines = []
        }
        super.init()
        activateSessionIfNeeded()
    }

    func cachedPayload(for day: Date, calendar: Calendar = .current) -> PulsarDailyMetricsSyncPayload? {
        let dateKey = PulsarDailyMetricsDateKey.dateKey(for: day, calendar: calendar)
        if let payload = cachedDailyPayload(forDateKey: dateKey) {
            return payload
        }
        guard let latestPayload,
              latestPayload.isValidPayload,
              latestPayload.applies(to: day, calendar: calendar) else { return nil }
        return latestPayload
    }

    func cachedDailyPayload(forDateKey dateKey: String) -> PulsarDailyMetricsSyncPayload? {
        guard !dateKey.isEmpty,
              let payload = dailyPayloadsByDateKey[dateKey],
              payload.isValidPayload,
              payload.hasCompleteDailyScores || payload.hasValidStress else { return nil }
        return payload
    }

    func cachedSleepPayload(forSleepDateKey sleepDateKey: String) -> PulsarDailyMetricsSyncPayload? {
        guard !sleepDateKey.isEmpty,
              let payload = sleepPayloadsByDateKey[sleepDateKey],
              payload.isValidPayload,
              payload.sleep?.isValid == true else { return nil }
        return payload
    }

    func cachedDailyPayloads() -> [PulsarDailyMetricsSyncPayload] {
        dailyPayloadsByDateKey.values
            .filter { $0.isValidPayload && ($0.hasCompleteDailyScores || $0.hasValidStress) }
            .sorted { $0.resolvedDateKey < $1.resolvedDateKey }
    }

    func cachedSleepPayloads() -> [PulsarDailyMetricsSyncPayload] {
        sleepPayloadsByDateKey.values
            .filter { $0.isValidPayload && $0.sleep?.isValid == true }
            .sorted { $0.resolvedDateKey < $1.resolvedDateKey }
    }

    func cachedSleepPreferences() -> PulsarSleepPreferencesSyncPayload? {
        guard let latestSleepPreferences, latestSleepPreferences.isValid else { return nil }
        return latestSleepPreferences
    }

    @discardableResult
    func storeAppleWatchBattery(_ snapshot: AppleWatchBatterySnapshot, broadcast: Bool, reason: String) -> Bool {
        apply(appleWatchBattery: snapshot, broadcast: broadcast, reason: reason)
    }

    #if os(watchOS)
    func refreshAndSendAppleWatchBattery(reason: String = "watchBatteryRefresh") {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true

        let batteryLevel = device.batteryLevel
        guard batteryLevel >= 0 else {
            PulsarSyncDebugLogger.log("Skipped \(reason) because Apple Watch battery level is unavailable")
            return
        }

        let percentage = min(100, max(0, Int((batteryLevel * 100).rounded())))
        let snapshot = AppleWatchBatterySnapshot(batteryPercentage: percentage, timestamp: Date())
        storeAppleWatchBattery(snapshot, broadcast: true, reason: reason)
    }
    #endif

    func registerGymActionHandler(_ handler: @escaping (ActiveGymWorkoutAction) -> Void) {
        gymActionHandler = handler
    }

    func unregisterGymActionHandler() {
        gymActionHandler = nil
    }

    func registerActiveWorkoutStateHandler(_ handler: @escaping (PulsarActiveWorkoutSyncState) -> Void) {
        activeWorkoutStateHandler = handler
        if let activeWorkoutState {
            handler(activeWorkoutState)
        }
    }

    func unregisterActiveWorkoutStateHandler() {
        activeWorkoutStateHandler = nil
    }

    @discardableResult
    func storeActiveWorkoutState(_ state: PulsarActiveWorkoutSyncState, broadcast: Bool, reason: String) -> Bool {
        apply(activeWorkoutState: state, broadcast: broadcast, reason: reason)
    }

    @discardableResult
    func storeActiveGymState(_ state: ActiveGymWorkoutState, broadcast: Bool, reason: String) -> Bool {
        apply(activeGymState: state, broadcast: broadcast, reason: reason)
    }

    func pruneStaleActiveWorkoutState(reason: String) {
        if let activeWorkoutState,
           let staleReason = activeWorkoutState.staleRouteReason() {
            clearActiveWorkoutState(reason: "\(reason).\(staleReason)", broadcastEndedState: false)
        }

        if let activeGymState,
           let staleReason = activeGymState.staleRouteReason() {
            clearActiveGymState(reason: "\(reason).\(staleReason)", broadcastEndedState: false)
        }
    }

    func isRoutableActiveWorkoutState(_ state: PulsarActiveWorkoutSyncState) -> Bool {
        state.isValidLiveRouteCandidate()
    }

    func isRoutableActiveGymState(_ state: ActiveGymWorkoutState) -> Bool {
        state.isValidLiveRouteCandidate()
    }

    func clearActiveWorkoutState(reason: String, broadcastEndedState: Bool = false) {
        let previous = activeWorkoutState
        if broadcastEndedState, var ended = previous, ended.phase.isLive {
            ended.phase = .ended
            ended.endedAt = Date()
            ended.updatedAt = Date()
            apply(activeWorkoutState: ended, broadcast: true, reason: "\(reason).endedBroadcast")
        }

        activeWorkoutState = nil
        defaults.removeObject(forKey: activeWorkoutCacheKey)
        PulsarSyncDebugLogger.log("Active workout state cleared reason=\(reason) session=\(previous?.sessionId.uuidString ?? "none")")
    }

    func clearActiveGymState(reason: String, broadcastEndedState: Bool = false) {
        let previous = activeGymState
        if broadcastEndedState, var ended = previous, !ended.isFinished {
            ended.isFinished = true
            ended.updatedAt = Date()
            storeActiveGymState(ended, broadcast: true, reason: "\(reason).finishedBroadcast")
        }

        activeGymState = nil
        defaults.removeObject(forKey: activeGymCacheKey)
        if let previous,
           activeWorkoutState?.sessionId == previous.sessionId {
            activeWorkoutState = nil
            defaults.removeObject(forKey: activeWorkoutCacheKey)
        }
        PulsarSyncDebugLogger.log("Active Gym state cleared reason=\(reason) session=\(previous?.sessionId.uuidString ?? "none")")
    }

    func sendGymAction(_ action: ActiveGymWorkoutAction) {
        guard let session,
              let data = ActiveGymWorkoutCodec.encodeAction(action) else { return }
        let payload = [Self.activeGymActionPayloadKey: data]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                PulsarSyncDebugLogger.log("Active Gym action sendMessage failed kind=\(action.kind.rawValue) error=\(error.localizedDescription)")
            }
        }
        session.transferUserInfo(payload)
        PulsarSyncDebugLogger.log("Active Gym action queued kind=\(action.kind.rawValue) session=\(action.sessionId?.uuidString ?? "none")")
    }

    @discardableResult
    func storeSavedGymRoutines(_ routines: [WatchGymRoutinePlan], broadcast: Bool, reason: String) -> Bool {
        let sortedRoutines = routines.sorted { $0.updatedAt > $1.updatedAt }
        guard sortedRoutines != savedGymRoutines else { return false }

        savedGymRoutines = sortedRoutines
        persistSavedGymRoutines(sortedRoutines)
        PulsarSyncDebugLogger.log("Saved Gym routines updated via \(reason) count=\(sortedRoutines.count)")

        if broadcast {
            sendSavedGymRoutinesToCounterpart(sortedRoutines)
        }
        return true
    }

    @discardableResult
    func storeLocalPayload(_ payload: PulsarDailyMetricsSyncPayload, broadcast: Bool, reason: String) -> Bool {
        apply(payload: payload, broadcast: broadcast, reason: reason)
    }

    @discardableResult
    func storeSleepPreferences(_ payload: PulsarSleepPreferencesSyncPayload, broadcast: Bool, reason: String) -> Bool {
        apply(sleepPreferences: payload, broadcast: broadcast, reason: reason)
    }

    #if os(iOS)
    @discardableResult
    func storeSleepPreferences(for profile: UserProfile, broadcast: Bool, reason: String) -> Bool {
        storeSleepPreferences(PulsarSleepPreferencesSyncPayload(profile: profile), broadcast: broadcast, reason: reason)
    }
    #endif

    private func activateSessionIfNeeded() {
        guard let session else {
            PulsarSyncDebugLogger.log("WatchConnectivity unsupported on this device")
            return
        }
        session.delegate = self
        session.activate()
        PulsarSyncDebugLogger.log("WatchConnectivity session activating")
    }

    @discardableResult
    private func apply(payload incoming: PulsarDailyMetricsSyncPayload, broadcast: Bool, reason: String) -> Bool {
        guard incoming.isValidPayload else {
            PulsarSyncDebugLogger.log("Skipped \(reason) payload because it was empty, invalid, or partial daily data session=\(incoming.syncSessionID?.uuidString ?? "none") source=\(incoming.sourceDevice.rawValue) dateKey=\(incoming.resolvedDateKey.isEmpty ? "missing" : incoming.resolvedDateKey)")
            return false
        }

        let currentPayload = latestPayload?.isValidPayload == true ? latestPayload : nil

        if let latestPayload = currentPayload,
           latestPayload.resolvedDateKey == incoming.resolvedDateKey,
           latestPayload.resolvedDataFingerprint == incoming.resolvedDataFingerprint {
            PulsarSyncDebugLogger.log("Skipped \(reason) payload because HealthKit data fingerprint was unchanged session=\(incoming.syncSessionID?.uuidString ?? "none") fingerprint=\(incoming.resolvedDataFingerprint)")
            return false
        }

        if let latestPayload = currentPayload,
           latestPayload.resolvedDateKey == incoming.resolvedDateKey,
           incoming.syncedAt < latestPayload.syncedAt,
           !incomingCanFillMissingMetric(incoming, current: latestPayload),
           !incomingCarriesNewerMetric(incoming, current: latestPayload),
           !latestPayload.resolvedDataFingerprint.isEmpty {
            PulsarSyncDebugLogger.log("Skipped \(reason) payload because incoming data was older session=\(incoming.syncSessionID?.uuidString ?? "none") incoming=\(incoming.syncedAt) cached=\(latestPayload.syncedAt)")
            return false
        }

        let merged = currentPayload.map { $0.merged(with: incoming) } ?? incoming
        guard merged != latestPayload else {
            PulsarSyncDebugLogger.log("Skipped \(reason) payload because cached data was already newer or equivalent session=\(incoming.syncSessionID?.uuidString ?? "none")")
            return false
        }

        latestPayload = merged
        persist(merged)
        persistDailyPayloadIfNeeded(merged)
        persistSleepPayloadIfNeeded(merged)
        PulsarSyncDebugLogger.log("Cache updated via \(reason): source=\(merged.sourceDevice.rawValue) dateKey=\(merged.resolvedDateKey) syncedAt=\(merged.syncedAt) session=\(merged.syncSessionID?.uuidString ?? "none") fingerprint=\(merged.resolvedDataFingerprint)")

        if broadcast {
            sendToCounterpart(metricPayload: merged)
        }
        return true
    }

    @discardableResult
    private func apply(sleepPreferences incoming: PulsarSleepPreferencesSyncPayload, broadcast: Bool, reason: String) -> Bool {
        guard incoming.isValid else {
            PulsarSyncDebugLogger.log("Skipped \(reason) sleep preferences because payload was invalid")
            return false
        }
        if let latestSleepPreferences,
           latestSleepPreferences == incoming {
            PulsarSyncDebugLogger.log("Skipped \(reason) sleep preferences because the payload was unchanged")
            return false
        }
        if let latestSleepPreferences,
           incoming.syncedAt < latestSleepPreferences.syncedAt,
           latestSleepPreferences != incoming {
            PulsarSyncDebugLogger.log("Skipped \(reason) sleep preferences because cached data was newer incoming=\(incoming.syncedAt) cached=\(latestSleepPreferences.syncedAt)")
            return false
        }

        latestSleepPreferences = incoming
        persistSleepPreferences(incoming)
        PulsarSyncDebugLogger.log("Sleep preferences cache updated via \(reason) syncedAt=\(incoming.syncedAt) alarmEnabled=\(incoming.alarmEnabled)")

        if broadcast {
            sendToCounterpart(sleepPreferences: incoming)
        }
        return true
    }

    @discardableResult
    private func apply(appleWatchBattery incoming: AppleWatchBatterySnapshot, broadcast: Bool, reason: String) -> Bool {
        guard Self.isValidAppleWatchBattery(incoming) else {
            PulsarSyncDebugLogger.log("Skipped \(reason) Apple Watch battery because payload was invalid")
            return false
        }

        if let latestAppleWatchBattery,
           incoming.timestamp <= latestAppleWatchBattery.timestamp,
           incoming.batteryPercentage == latestAppleWatchBattery.batteryPercentage {
            PulsarSyncDebugLogger.log("Skipped \(reason) Apple Watch battery because cached value was equivalent")
            return false
        }

        latestAppleWatchBattery = incoming
        persistAppleWatchBattery(incoming)
        PulsarSyncDebugLogger.log("Apple Watch battery updated via \(reason) percentage=\(incoming.batteryPercentage)")

        if broadcast {
            sendAppleWatchBatteryToCounterpart(incoming)
        }
        return true
    }

    @discardableResult
    private func apply(activeWorkoutState incoming: PulsarActiveWorkoutSyncState, broadcast: Bool, reason: String) -> Bool {
        guard shouldApply(activeWorkoutState: incoming) else {
            PulsarSyncDebugLogger.log("Active workout state skipped via \(reason) session=\(incoming.sessionId.uuidString) type=\(incoming.kind.workoutTypeRawValue) phase=\(incoming.phase.rawValue) updatedAt=\(incoming.updatedAt)")
            return false
        }

        activeWorkoutState = incoming
        persistActiveWorkoutState(incoming)
        PulsarSyncDebugLogger.log("Active workout state applied via \(reason) session=\(incoming.sessionId.uuidString) type=\(incoming.kind.workoutTypeRawValue) phase=\(incoming.phase.rawValue) startedFrom=\(incoming.startedFrom.rawValue) updatedFrom=\(incoming.lastUpdatedFrom.rawValue)")
        activeWorkoutStateHandler?(incoming)

        if broadcast {
            sendActiveWorkoutStateToCounterpart(incoming)
        }
        return true
    }

    @discardableResult
    private func apply(activeGymState incoming: ActiveGymWorkoutState, broadcast: Bool, reason: String) -> Bool {
        guard shouldApply(activeGymState: incoming) else {
            PulsarSyncDebugLogger.log("Active Gym state skipped via \(reason) session=\(incoming.sessionId.uuidString) type=\(incoming.workoutKind?.rawValue ?? "unknown") updatedAt=\(incoming.updatedAt) finished=\(incoming.isFinished)")
            return false
        }

        activeGymState = incoming
        persistActiveGymState(incoming)
        let activeState = PulsarActiveWorkoutSyncState(gymState: incoming)
        apply(activeWorkoutState: activeState, broadcast: false, reason: "\(reason).gymBridge")
        PulsarSyncDebugLogger.log("Active Gym state updated via \(reason) session=\(incoming.sessionId.uuidString) type=\(incoming.workoutKind?.rawValue ?? "unknown") startedFrom=\(incoming.startedFrom?.rawValue ?? "unknown") progress=\(incoming.completedSets)/\(incoming.totalSets) finished=\(incoming.isFinished)")

        if broadcast {
            sendGymStateToCounterpart(incoming)
        }
        return true
    }

    private func persist(_ payload: PulsarDailyMetricsSyncPayload) {
        guard let data = PulsarSyncPayloadCodec.encode(payload) else { return }
        defaults.set(data, forKey: cacheKey)
    }

    private func persistDailyPayloadIfNeeded(_ payload: PulsarDailyMetricsSyncPayload) {
        guard payload.hasCompleteDailyScores || payload.hasValidStress else { return }
        let dailyComputedAt = [payload.dailyMetricsComputedAt, payload.stressComputedAt, payload.healthMonitorComputedAt].compactMap { $0 }.max()
        guard let dailyComputedAt else { return }
        let dateKey = payload.resolvedDateKey
        guard !dateKey.isEmpty else { return }
        let dailyPayload = PulsarDailyMetricsSyncPayload(
            date: payload.date,
            dateKey: dateKey,
            syncedAt: dailyComputedAt,
            sourceDevice: payload.sourceDevice,
            strain: payload.strain,
            recovery: payload.recovery,
            sleep: nil,
            stress: payload.stress,
            healthMonitor: payload.healthMonitor,
            syncSessionID: payload.syncSessionID,
            validityFlag: true
        )
        guard dailyPayload.isValidPayload else { return }
        if let cached = dailyPayloadsByDateKey[dateKey],
           cached.isValidPayload,
           (cached.dailyMetricsComputedAt ?? cached.syncedAt) > dailyComputedAt,
           cached.resolvedDataFingerprint != dailyPayload.resolvedDataFingerprint {
            PulsarSyncDebugLogger.log("Skipped daily cache update because cached Recovery/Strain payload was newer dateKey=\(dateKey)")
            return
        }
        dailyPayloadsByDateKey[dateKey] = dailyPayload
        guard let data = try? JSONEncoder().encode(dailyPayloadsByDateKey) else { return }
        defaults.set(data, forKey: dailyCacheKey)
        PulsarSyncDebugLogger.log("Daily Recovery/Strain cache updated dateKey=\(dateKey) strain=\(dailyPayload.strain?.score ?? 0) recovery=\(dailyPayload.recovery?.score ?? 0) session=\(dailyPayload.syncSessionID?.uuidString ?? "none")")
    }

    private func persistSleepPayloadIfNeeded(_ payload: PulsarDailyMetricsSyncPayload) {
        guard let sleep = payload.sleep, sleep.isValid else { return }
        let sleepPayload = PulsarDailyMetricsSyncPayload(
            date: payload.date,
            dateKey: payload.resolvedDateKey.isEmpty ? sleep.sleepDateKey : payload.resolvedDateKey,
            syncedAt: sleep.computedAt,
            sourceDevice: payload.sourceDevice,
            strain: nil,
            recovery: nil,
            sleep: sleep,
            syncSessionID: payload.syncSessionID,
            validityFlag: true
        )
        guard sleepPayload.isValidPayload else { return }
        if let cached = sleepPayloadsByDateKey[sleep.sleepDateKey],
           cached.isValidPayload,
           (cached.sleepComputedAt ?? cached.syncedAt) > sleep.computedAt,
           cached.resolvedDataFingerprint != sleepPayload.resolvedDataFingerprint {
            PulsarSyncDebugLogger.log("Skipped sleep cache update because cached sleep payload was newer sleepDateKey=\(sleep.sleepDateKey)")
            return
        }
        sleepPayloadsByDateKey[sleep.sleepDateKey] = sleepPayload
        guard let data = try? JSONEncoder().encode(sleepPayloadsByDateKey) else { return }
        defaults.set(data, forKey: sleepCacheKey)
        PulsarSyncDebugLogger.log("Sleep cache updated sleepDateKey=\(sleep.sleepDateKey) score=\(sleep.score) session=\(sleepPayload.syncSessionID?.uuidString ?? "none")")
    }

    private func persistSleepPreferences(_ payload: PulsarSleepPreferencesSyncPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: sleepPreferencesCacheKey)
    }

    private func persistAppleWatchBattery(_ snapshot: AppleWatchBatterySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: appleWatchBatteryCacheKey)
    }

    private func persistActiveWorkoutState(_ state: PulsarActiveWorkoutSyncState) {
        guard let data = Self.encodeActiveWorkoutState(state) else { return }
        defaults.set(data, forKey: activeWorkoutCacheKey)
    }

    private func persistActiveGymState(_ state: ActiveGymWorkoutState) {
        guard let data = ActiveGymWorkoutCodec.encodeState(state) else { return }
        defaults.set(data, forKey: activeGymCacheKey)
    }

    private func persistSavedGymRoutines(_ routines: [WatchGymRoutinePlan]) {
        guard let data = try? JSONEncoder().encode(routines) else { return }
        defaults.set(data, forKey: savedGymRoutinesCacheKey)
    }

    private func sendToCounterpart(metricPayload: PulsarDailyMetricsSyncPayload? = nil, sleepPreferences: PulsarSleepPreferencesSyncPayload? = nil) {
        guard let session else { return }
        let metric = metricPayload ?? latestPayload
        let sleepPreferences = sleepPreferences ?? latestSleepPreferences
        let applicationContext = makeApplicationContext(
            metricPayload: metric,
            sleepPreferences: sleepPreferences,
            activeWorkoutState: activeWorkoutState,
            activeGymState: activeGymState,
            savedGymRoutines: savedGymRoutines
        )

        guard !applicationContext.isEmpty else { return }

        do {
            try session.updateApplicationContext(applicationContext)
            PulsarSyncDebugLogger.log("WatchConnectivity applicationContext updated metricSession=\(metric?.syncSessionID?.uuidString ?? "none") alarmEnabled=\(sleepPreferences?.alarmEnabled == true)")
        } catch {
            PulsarSyncDebugLogger.log("Failed to update applicationContext: \(error.localizedDescription)")
        }

        session.transferUserInfo(applicationContext)
        PulsarSyncDebugLogger.log("WatchConnectivity payload queued for transfer metricSession=\(metric?.syncSessionID?.uuidString ?? "none") alarmEnabled=\(sleepPreferences?.alarmEnabled == true)")
    }

    private func sendGymStateToCounterpart(_ state: ActiveGymWorkoutState) {
        guard let session,
              let data = ActiveGymWorkoutCodec.encodeState(state) else { return }

        var realtimePayload: [String: Any] = [Self.activeGymStatePayloadKey: data]
        if let activeData = Self.encodeActiveWorkoutState(PulsarActiveWorkoutSyncState(gymState: state)) {
            realtimePayload[Self.activeWorkoutStatePayloadKey] = activeData
        }
        if session.isReachable {
            session.sendMessage(realtimePayload, replyHandler: nil) { error in
                PulsarSyncDebugLogger.log("Active Gym state sendMessage failed session=\(state.sessionId.uuidString) error=\(error.localizedDescription)")
            }
            PulsarSyncDebugLogger.log("Active Gym state sendMessage sent session=\(state.sessionId.uuidString) reachable=true")
        } else {
            PulsarSyncDebugLogger.log("Active Gym state sendMessage skipped session=\(state.sessionId.uuidString) reachable=false fallback=applicationContext")
        }

        let applicationContext = makeApplicationContext(
            metricPayload: latestPayload,
            sleepPreferences: latestSleepPreferences,
            activeWorkoutState: activeWorkoutState,
            activeGymState: state,
            savedGymRoutines: savedGymRoutines
        )
        do {
            try session.updateApplicationContext(applicationContext)
            PulsarSyncDebugLogger.log("Active Gym state applicationContext updated session=\(state.sessionId.uuidString)")
        } catch {
            PulsarSyncDebugLogger.log("Failed to update Active Gym applicationContext: \(error.localizedDescription)")
        }
        session.transferUserInfo(realtimePayload)
        PulsarSyncDebugLogger.log("Active Gym state transferUserInfo queued session=\(state.sessionId.uuidString)")
    }

    private func sendSavedGymRoutinesToCounterpart(_ routines: [WatchGymRoutinePlan]? = nil) {
        let routines = routines ?? savedGymRoutines
        guard let session,
              let data = try? JSONEncoder().encode(routines) else { return }

        let payload = [Self.savedGymRoutinesPayloadKey: data]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                PulsarSyncDebugLogger.log("Saved Gym routines sendMessage failed error=\(error.localizedDescription)")
            }
        }

        let applicationContext = makeApplicationContext(
            metricPayload: latestPayload,
            sleepPreferences: latestSleepPreferences,
            activeWorkoutState: activeWorkoutState,
            activeGymState: activeGymState,
            savedGymRoutines: routines
        )
        do {
            try session.updateApplicationContext(applicationContext)
            PulsarSyncDebugLogger.log("Saved Gym routines applicationContext updated count=\(routines.count)")
        } catch {
            PulsarSyncDebugLogger.log("Failed to update saved Gym routines applicationContext: \(error.localizedDescription)")
        }
        session.transferUserInfo(applicationContext)
    }

    private func makeApplicationContext(
        metricPayload: PulsarDailyMetricsSyncPayload?,
        sleepPreferences: PulsarSleepPreferencesSyncPayload?,
        activeWorkoutState: PulsarActiveWorkoutSyncState?,
        activeGymState: ActiveGymWorkoutState?,
        savedGymRoutines: [WatchGymRoutinePlan]
    ) -> [String: Any] {
        var applicationContext: [String: Any] = [:]
        if let metricPayload, let data = PulsarSyncPayloadCodec.encode(metricPayload) {
            applicationContext[PulsarSyncPayloadCodec.payloadKey] = data
        }
        if let sleepPreferences,
           let data = try? JSONEncoder().encode(sleepPreferences) {
            applicationContext[Self.sleepPreferencesPayloadKey] = data
        }
        if let latestAppleWatchBattery,
           let data = try? JSONEncoder().encode(latestAppleWatchBattery) {
            applicationContext[Self.appleWatchBatteryPayloadKey] = data
        }
        if let activeWorkoutState,
           let data = Self.encodeActiveWorkoutState(activeWorkoutState) {
            applicationContext[Self.activeWorkoutStatePayloadKey] = data
        }
        if let activeGymState,
           let data = ActiveGymWorkoutCodec.encodeState(activeGymState) {
            applicationContext[Self.activeGymStatePayloadKey] = data
        }
        if let data = try? JSONEncoder().encode(savedGymRoutines) {
            applicationContext[Self.savedGymRoutinesPayloadKey] = data
        }
        return applicationContext
    }

    private func sendAppleWatchBatteryToCounterpart(_ snapshot: AppleWatchBatterySnapshot) {
        guard let session else { return }
        guard session.activationState == .activated else {
            PulsarSyncDebugLogger.log("Skipped Apple Watch battery transfer because WatchConnectivity is not activated")
            return
        }
        let payload = Self.appleWatchBatteryMessage(from: snapshot)

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                PulsarSyncDebugLogger.log("Apple Watch battery sendMessage failed error=\(error.localizedDescription)")
            }
        }

        session.transferUserInfo(payload)
        PulsarSyncDebugLogger.log("Apple Watch battery queued for transfer percentage=\(snapshot.batteryPercentage)")
    }

    private func sendActiveWorkoutStateToCounterpart(_ state: PulsarActiveWorkoutSyncState) {
        guard let session,
              let data = Self.encodeActiveWorkoutState(state) else { return }
        let payload = [Self.activeWorkoutStatePayloadKey: data]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                PulsarSyncDebugLogger.log("Active workout sendMessage failed session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) phase=\(state.phase.rawValue) error=\(error.localizedDescription)")
            }
            PulsarSyncDebugLogger.log("Active workout sendMessage sent session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) phase=\(state.phase.rawValue) reachable=true")
        } else {
            PulsarSyncDebugLogger.log("Active workout sendMessage skipped session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) phase=\(state.phase.rawValue) reachable=false fallback=applicationContext+transferUserInfo")
        }

        let applicationContext = makeApplicationContext(
            metricPayload: latestPayload,
            sleepPreferences: latestSleepPreferences,
            activeWorkoutState: state,
            activeGymState: activeGymState,
            savedGymRoutines: savedGymRoutines
        )
        do {
            try session.updateApplicationContext(applicationContext)
            PulsarSyncDebugLogger.log("Active workout applicationContext updated session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) phase=\(state.phase.rawValue)")
        } catch {
            PulsarSyncDebugLogger.log("Active workout applicationContext failed session=\(state.sessionId.uuidString) error=\(error.localizedDescription)")
        }

        session.transferUserInfo(payload)
        PulsarSyncDebugLogger.log("Active workout transferUserInfo queued session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) phase=\(state.phase.rawValue)")
    }

    private func receive(dictionary: [String: Any], reason: String) {
        var didApplyAnyPayload = false

        if let data = dictionary[PulsarSyncPayloadCodec.payloadKey] as? Data,
           let payload = PulsarSyncPayloadCodec.decode(data: data) {
            didApplyAnyPayload = apply(payload: payload, broadcast: false, reason: reason) || didApplyAnyPayload
        } else if dictionary[PulsarSyncPayloadCodec.payloadKey] != nil {
            PulsarSyncDebugLogger.log("Skipped \(reason) metrics payload because decoding failed")
        }

        if let data = dictionary[Self.sleepPreferencesPayloadKey] as? Data,
           let payload = try? JSONDecoder().decode(PulsarSleepPreferencesSyncPayload.self, from: data) {
            didApplyAnyPayload = apply(sleepPreferences: payload, broadcast: false, reason: reason) || didApplyAnyPayload
        } else if dictionary[Self.sleepPreferencesPayloadKey] != nil {
            PulsarSyncDebugLogger.log("Skipped \(reason) sleep preferences because decoding failed")
        }

        if let data = dictionary[Self.appleWatchBatteryPayloadKey] as? Data,
           let snapshot = try? JSONDecoder().decode(AppleWatchBatterySnapshot.self, from: data) {
            didApplyAnyPayload = apply(appleWatchBattery: snapshot, broadcast: false, reason: reason) || didApplyAnyPayload
        } else if let snapshot = Self.decodeAppleWatchBatteryMessage(dictionary) {
            didApplyAnyPayload = apply(appleWatchBattery: snapshot, broadcast: false, reason: reason) || didApplyAnyPayload
        } else if dictionary[Self.appleWatchBatteryPayloadKey] != nil ||
                    dictionary[Self.appleWatchBatteryTypeKey] as? String == Self.appleWatchBatteryMessageType {
            PulsarSyncDebugLogger.log("Skipped \(reason) Apple Watch battery because decoding failed")
        }

        if let data = dictionary[Self.activeWorkoutStatePayloadKey] as? Data,
           let state = Self.decodeActiveWorkoutState(data) {
            didApplyAnyPayload = apply(activeWorkoutState: state, broadcast: false, reason: reason) || didApplyAnyPayload
        } else if dictionary[Self.activeWorkoutStatePayloadKey] != nil {
            PulsarSyncDebugLogger.log("Skipped \(reason) active workout state because decoding failed")
        }

        if let data = dictionary[Self.activeGymStatePayloadKey] as? Data,
           let state = ActiveGymWorkoutCodec.decodeState(data) {
            let didApplyGymState = apply(activeGymState: state, broadcast: false, reason: reason)
            didApplyAnyPayload = didApplyGymState || didApplyAnyPayload
            PulsarSyncDebugLogger.log("Active Gym state received via \(reason) session=\(state.sessionId.uuidString) progress=\(state.completedSets)/\(state.totalSets) finished=\(state.isFinished)")
            #if os(iOS)
            if didApplyGymState {
                syncLiveActivity(for: state)
            }
            #endif
        } else if dictionary[Self.activeGymStatePayloadKey] != nil {
            PulsarSyncDebugLogger.log("Skipped \(reason) Active Gym state because decoding failed")
        }

        if let data = dictionary[Self.savedGymRoutinesPayloadKey] as? Data,
           let routines = try? JSONDecoder().decode([WatchGymRoutinePlan].self, from: data) {
            didApplyAnyPayload = storeSavedGymRoutines(routines, broadcast: false, reason: reason) || didApplyAnyPayload
        } else if dictionary[Self.savedGymRoutinesPayloadKey] != nil {
            PulsarSyncDebugLogger.log("Skipped \(reason) saved Gym routines because decoding failed")
        }

        if let data = dictionary[Self.activeGymActionPayloadKey] as? Data,
           let action = ActiveGymWorkoutCodec.decodeAction(data) {
            didApplyAnyPayload = true
            PulsarSyncDebugLogger.log("Active Gym action received via \(reason) kind=\(action.kind.rawValue) session=\(action.sessionId?.uuidString ?? "none")")
            if action.kind == .requestSavedRoutines {
                #if os(iOS)
                refreshSavedGymRoutinesFromPhoneStore(reason: "watchRequestedSavedRoutines")
                #endif
                sendSavedGymRoutinesToCounterpart()
            }
            gymActionHandler?(action)
        } else if dictionary[Self.activeGymActionPayloadKey] != nil {
            PulsarSyncDebugLogger.log("Skipped \(reason) Active Gym action because decoding failed")
        }

        if !didApplyAnyPayload {
            PulsarSyncDebugLogger.log("Skipped \(reason) payload because nothing valid could be applied")
        }
    }

    private func incomingCanFillMissingMetric(_ incoming: PulsarDailyMetricsSyncPayload, current: PulsarDailyMetricsSyncPayload) -> Bool {
        (current.hasCompleteDailyScores == false && incoming.hasCompleteDailyScores) ||
        (current.sleep?.isValid != true && incoming.sleep?.isValid == true) ||
        (current.stress?.isValid != true && incoming.stress?.isValid == true) ||
        (current.healthMonitor?.isValid != true && incoming.healthMonitor?.isValid == true)
    }

    private func incomingCarriesNewerMetric(_ incoming: PulsarDailyMetricsSyncPayload, current: PulsarDailyMetricsSyncPayload) -> Bool {
        if let incomingDaily = incoming.dailyMetricsComputedAt,
           let currentDaily = current.dailyMetricsComputedAt,
           incomingDaily > currentDaily {
            return true
        }
        if let incomingSleep = incoming.sleepComputedAt,
           let currentSleep = current.sleepComputedAt,
           incomingSleep > currentSleep {
            return true
        }
        if let incomingStress = incoming.stressComputedAt,
           let currentStress = current.stressComputedAt,
           incomingStress > currentStress {
            return true
        }
        if let incomingHealthMonitor = incoming.healthMonitorComputedAt,
           let currentHealthMonitor = current.healthMonitorComputedAt,
           incomingHealthMonitor > currentHealthMonitor {
            return true
        }
        return false
    }

    private static let sleepPreferencesPayloadKey = "pulsar.sleepPreferences.payload.v1"
    private static let appleWatchBatteryPayloadKey = "pulsar.appleWatchBattery.payload.v1"
    private static let appleWatchBatteryTypeKey = "type"
    private static let appleWatchBatteryMessageType = "appleWatchBattery"
    private static let appleWatchBatteryPercentageKey = "batteryPercentage"
    private static let appleWatchBatteryTimestampKey = "timestamp"
    private static let activeWorkoutStatePayloadKey = "pulsar.activeWorkout.state.v1"
    private static let activeGymStatePayloadKey = "pulsar.activeGymWorkout.state.v1"
    private static let activeGymActionPayloadKey = "pulsar.activeGymWorkout.action.v1"
    private static let savedGymRoutinesPayloadKey = "pulsar.savedGymRoutines.payload.v1"

    private static func isValidAppleWatchBattery(_ snapshot: AppleWatchBatterySnapshot) -> Bool {
        (0...100).contains(snapshot.batteryPercentage)
    }

    private static func appleWatchBatteryMessage(from snapshot: AppleWatchBatterySnapshot) -> [String: Any] {
        [
            appleWatchBatteryTypeKey: appleWatchBatteryMessageType,
            appleWatchBatteryPercentageKey: snapshot.batteryPercentage,
            appleWatchBatteryTimestampKey: snapshot.timestamp.timeIntervalSince1970
        ]
    }

    private static func decodeAppleWatchBatteryMessage(_ dictionary: [String: Any]) -> AppleWatchBatterySnapshot? {
        guard dictionary[appleWatchBatteryTypeKey] as? String == appleWatchBatteryMessageType,
              let percentage = dictionary[appleWatchBatteryPercentageKey] as? Int,
              let timestamp = dictionary[appleWatchBatteryTimestampKey] as? TimeInterval else { return nil }
        let snapshot = AppleWatchBatterySnapshot(
            batteryPercentage: percentage,
            timestamp: Date(timeIntervalSince1970: timestamp)
        )
        return isValidAppleWatchBattery(snapshot) ? snapshot : nil
    }

    private static func encodeActiveWorkoutState(_ state: PulsarActiveWorkoutSyncState) -> Data? {
        try? activeWorkoutEncoder.encode(state)
    }

    private static func decodeActiveWorkoutState(_ data: Data) -> PulsarActiveWorkoutSyncState? {
        try? activeWorkoutDecoder.decode(PulsarActiveWorkoutSyncState.self, from: data)
    }

    private static var activeWorkoutEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var activeWorkoutDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func isExpiredEndedActiveWorkout(_ state: PulsarActiveWorkoutSyncState) -> Bool {
        state.isEnded && Date().timeIntervalSince(state.updatedAt) > PulsarWorkoutSessionValidity.endedStateRetentionInterval
    }

    private static func isExpiredFinishedGymState(_ state: ActiveGymWorkoutState) -> Bool {
        state.isFinished && Date().timeIntervalSince(state.updatedAt) > PulsarWorkoutSessionValidity.endedStateRetentionInterval
    }

    private static func shouldRestoreCachedActiveWorkoutState(_ state: PulsarActiveWorkoutSyncState) -> Bool {
        if state.isEnded {
            return !isExpiredEndedActiveWorkout(state)
        }
        return state.isValidLiveRouteCandidate()
    }

    private static func shouldRestoreCachedActiveGymState(_ state: ActiveGymWorkoutState) -> Bool {
        if state.isFinished {
            return !isExpiredFinishedGymState(state)
        }
        return state.isValidLiveRouteCandidate()
    }

    private func shouldApply(activeWorkoutState incoming: PulsarActiveWorkoutSyncState) -> Bool {
        guard !Self.isExpiredEndedActiveWorkout(incoming) else { return false }
        guard incoming.isEnded || incoming.isValidLiveRouteCandidate() else { return false }
        guard let current = activeWorkoutState else { return true }

        if current.sessionId == incoming.sessionId {
            if incoming.phase == .ended, current.phase != .ended { return true }
            return incoming.updatedAt >= current.updatedAt
        }

        if current.isEnded {
            return incoming.updatedAt >= current.updatedAt || incoming.phase.isLive
        }

        if incoming.isEnded, incoming.startedAt < current.startedAt {
            return false
        }

        return incoming.startedAt >= current.startedAt || incoming.updatedAt >= current.updatedAt
    }

    private func shouldApply(activeGymState incoming: ActiveGymWorkoutState) -> Bool {
        guard !Self.isExpiredFinishedGymState(incoming) else { return false }
        guard incoming.isFinished || incoming.isValidLiveRouteCandidate() else { return false }
        guard let current = activeGymState else { return true }

        if current.sessionId == incoming.sessionId {
            if incoming.isFinished, !current.isFinished { return true }
            return incoming.updatedAt >= current.updatedAt
        }

        if current.isFinished {
            return incoming.updatedAt >= current.updatedAt || incoming.isValidLiveRouteCandidate()
        }

        if incoming.isFinished, incoming.startedAt < current.startedAt {
            return false
        }

        return incoming.startedAt >= current.startedAt || incoming.updatedAt >= current.updatedAt
    }

    #if os(iOS)
    private func syncLiveActivity(for state: ActiveGymWorkoutState) {
        if state.isFinished {
            gymLiveActivityManager.end(state: state)
            persistFinishedGymWorkoutIfNeeded(state)
        } else {
            gymLiveActivityManager.startIfPossible(state: state)
            gymLiveActivityManager.update(state: state)
        }
    }

    private func persistFinishedGymWorkoutIfNeeded(_ state: ActiveGymWorkoutState) {
        guard state.isFinished else { return }
        let historyStore = PulsarGymWorkoutHistoryStore()
        guard !historyStore.sessions.contains(where: { $0.id == state.sessionId && $0.finishedAt != nil }) else {
            PulsarSyncDebugLogger.log("Gym Activity Log skipped duplicate finished state session=\(state.sessionId.uuidString) type=\(state.workoutKind?.rawValue ?? "unknown")")
            return
        }
        PulsarSyncDebugLogger.log("Gym Activity Log persisting finished state session=\(state.sessionId.uuidString) type=\(state.workoutKind?.rawValue ?? "unknown") startedFrom=\(state.startedFrom?.rawValue ?? "unknown")")
        historyStore.save(PulsarGymWorkoutSession(activeGymState: state))
    }

    private func refreshSavedGymRoutinesFromPhoneStore(reason: String) {
        let routineStore = PulsarRoutineStore()
        let plans = routineStore.routines.map(WatchGymRoutinePlan.init(routine:))
        storeSavedGymRoutines(plans, broadcast: false, reason: reason)
    }
    #endif
}

extension PulsarWatchConnectivitySyncStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        PulsarSyncDebugLogger.log("WatchConnectivity activation state=\(activationState.rawValue) error=\(error?.localizedDescription ?? "none")")
        #if os(watchOS)
        if activationState == .activated {
            Task { @MainActor in
                self.refreshAndSendAppleWatchBattery(reason: "watchConnectivityActivated")
            }
        }
        #endif
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            receive(dictionary: applicationContext, reason: "receivedApplicationContext")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in
            receive(dictionary: userInfo, reason: "receivedUserInfo")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            receive(dictionary: message, reason: "receivedMessage")
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
