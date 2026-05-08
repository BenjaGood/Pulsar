import Combine
import Foundation
import WatchConnectivity

@MainActor
final class PulsarWatchConnectivitySyncStore: NSObject, ObservableObject {
    static let shared = PulsarWatchConnectivitySyncStore()

    @Published private(set) var latestPayload: PulsarDailyMetricsSyncPayload?
    @Published private(set) var latestSleepPreferences: PulsarSleepPreferencesSyncPayload?

    private let defaults: UserDefaults
    private let cacheKey = "pulsar.sync.cachedDailyMetricsPayload.v1"
    private let dailyCacheKey = "pulsar.sync.cachedDailyMetricPayloadsByDateKey.v1"
    private let sleepCacheKey = "pulsar.sync.cachedSleepPayloadsByDateKey.v1"
    private let sleepPreferencesCacheKey = "pulsar.sync.cachedSleepPreferencesPayload.v1"
    private let session: WCSession?
    private var dailyPayloadsByDateKey: [String: PulsarDailyMetricsSyncPayload]
    private var sleepPayloadsByDateKey: [String: PulsarDailyMetricsSyncPayload]

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

    private func sendToCounterpart(metricPayload: PulsarDailyMetricsSyncPayload? = nil, sleepPreferences: PulsarSleepPreferencesSyncPayload? = nil) {
        guard let session else { return }
        let metric = metricPayload ?? latestPayload
        let sleepPreferences = sleepPreferences ?? latestSleepPreferences
        var applicationContext: [String: Any] = [:]

        if let metric, let data = PulsarSyncPayloadCodec.encode(metric) {
            applicationContext[PulsarSyncPayloadCodec.payloadKey] = data
        }
        if let sleepPreferences,
           let data = try? JSONEncoder().encode(sleepPreferences) {
            applicationContext[Self.sleepPreferencesPayloadKey] = data
        }
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
}

extension PulsarWatchConnectivitySyncStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        PulsarSyncDebugLogger.log("WatchConnectivity activation state=\(activationState.rawValue) error=\(error?.localizedDescription ?? "none")")
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

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
