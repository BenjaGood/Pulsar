import Combine
import Foundation
import WatchConnectivity

@MainActor
final class PulsarWatchConnectivitySyncStore: NSObject, ObservableObject {
    static let shared = PulsarWatchConnectivitySyncStore()

    @Published private(set) var latestPayload: PulsarDailyMetricsSyncPayload?

    private let defaults: UserDefaults
    private let cacheKey = "pulsar.sync.cachedDailyMetricsPayload.v1"
    private let dailyCacheKey = "pulsar.sync.cachedDailyMetricPayloadsByDateKey.v1"
    private let sleepCacheKey = "pulsar.sync.cachedSleepPayloadsByDateKey.v1"
    private let session: WCSession?
    private var dailyPayloadsByDateKey: [String: PulsarDailyMetricsSyncPayload]
    private var sleepPayloadsByDateKey: [String: PulsarDailyMetricsSyncPayload]

    private override init() {
        self.defaults = .standard
        self.session = WCSession.isSupported() ? WCSession.default : nil
        if let data = defaults.data(forKey: dailyCacheKey),
           let payloads = try? JSONDecoder().decode([String: PulsarDailyMetricsSyncPayload].self, from: data) {
            self.dailyPayloadsByDateKey = payloads.filter { key, payload in
                key == payload.resolvedDateKey && payload.isValidPayload && payload.hasCompleteDailyScores
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
              payload.hasCompleteDailyScores else { return nil }
        return payload
    }

    func cachedSleepPayload(forSleepDateKey sleepDateKey: String) -> PulsarDailyMetricsSyncPayload? {
        guard !sleepDateKey.isEmpty,
              let payload = sleepPayloadsByDateKey[sleepDateKey],
              payload.isValidPayload,
              payload.sleep?.isValid == true else { return nil }
        return payload
    }

    @discardableResult
    func storeLocalPayload(_ payload: PulsarDailyMetricsSyncPayload, broadcast: Bool, reason: String) -> Bool {
        apply(payload: payload, broadcast: broadcast, reason: reason)
    }

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
            sendToCounterpart(merged)
        }
        return true
    }

    private func persist(_ payload: PulsarDailyMetricsSyncPayload) {
        guard let data = PulsarSyncPayloadCodec.encode(payload) else { return }
        defaults.set(data, forKey: cacheKey)
    }

    private func persistDailyPayloadIfNeeded(_ payload: PulsarDailyMetricsSyncPayload) {
        guard payload.hasCompleteDailyScores,
              let dailyComputedAt = payload.dailyMetricsComputedAt else { return }
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

    private func sendToCounterpart(_ payload: PulsarDailyMetricsSyncPayload) {
        guard let session else { return }
        guard let data = PulsarSyncPayloadCodec.encode(payload) else { return }

        do {
            try session.updateApplicationContext([PulsarSyncPayloadCodec.payloadKey: data])
            PulsarSyncDebugLogger.log("WatchConnectivity applicationContext updated session=\(payload.syncSessionID?.uuidString ?? "none") source=\(payload.sourceDevice.rawValue)")
        } catch {
            PulsarSyncDebugLogger.log("Failed to update applicationContext: \(error.localizedDescription)")
        }

        session.transferUserInfo([PulsarSyncPayloadCodec.payloadKey: data])
        PulsarSyncDebugLogger.log("WatchConnectivity payload queued for transfer session=\(payload.syncSessionID?.uuidString ?? "none") source=\(payload.sourceDevice.rawValue)")
    }

    private func receive(dictionary: [String: Any], reason: String) {
        guard let data = dictionary[PulsarSyncPayloadCodec.payloadKey] as? Data,
              let payload = PulsarSyncPayloadCodec.decode(data: data) else {
            PulsarSyncDebugLogger.log("Skipped \(reason) payload because decoding failed")
            return
        }
        apply(payload: payload, broadcast: false, reason: reason)
    }

    private func incomingCanFillMissingMetric(_ incoming: PulsarDailyMetricsSyncPayload, current: PulsarDailyMetricsSyncPayload) -> Bool {
        (current.hasCompleteDailyScores == false && incoming.hasCompleteDailyScores) ||
        (current.sleep?.isValid != true && incoming.sleep?.isValid == true)
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
        return false
    }
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
