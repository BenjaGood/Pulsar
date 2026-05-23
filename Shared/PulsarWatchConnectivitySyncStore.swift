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

struct AppleWatchHeartbeatSnapshot: Codable, Equatable {
    var appInstalled: Bool
    var watchAppVersion: String?
    var timestamp: Date
    var batteryPercentage: Int?
}

struct PulsarWatchRecorderAvailabilitySnapshot: Equatable {
    var isSupported: Bool
    var activationStateRawValue: Int
    var activationStateDescription: String
    var activationErrorMessage: String?
    var isPaired: Bool
    var rawIsWatchAppInstalled: Bool
    var rawIsReachable: Bool
    var lastWatchSeenAt: Date?
    var hasEverReceivedWatchPayload: Bool

    private static let recentWatchHeartbeatInterval: TimeInterval = 15 * 60

    var hasRecentWatchHeartbeat: Bool {
        guard let lastWatchSeenAt else { return false }
        return Date().timeIntervalSince(lastWatchSeenAt) <= Self.recentWatchHeartbeatInterval
    }

    var isWatchAppInstalled: Bool {
        rawIsWatchAppInstalled || rawIsReachable || (isPaired && (hasRecentWatchHeartbeat || hasEverReceivedWatchPayload))
    }

    var isReachable: Bool {
        rawIsReachable || hasRecentWatchHeartbeat
    }

    var derivedReachabilityDescription: String {
        if rawIsReachable { return "rawReachable" }
        if hasRecentWatchHeartbeat { return "recentHeartbeat" }
        return "notReachable"
    }

    var canStartOnWatch: Bool {
        isSupported &&
            activationStateRawValue == WCSessionActivationState.activated.rawValue &&
            isPaired &&
            isWatchAppInstalled &&
            isReachable
    }

    var fallbackReason: PulsarWatchRecorderFallbackReason? {
        guard isSupported else { return .unsupported }
        guard activationStateRawValue == WCSessionActivationState.activated.rawValue else { return .activationPending }
        guard isPaired else { return .noPairedWatch }
        guard isWatchAppInstalled else {
            return hasEverReceivedWatchPayload ? .notReachable : .watchAppNotInstalled
        }
        guard isReachable else { return .notReachable }
        return nil
    }

    func fallbackPrompt(
        workoutName: String,
        reason overrideReason: PulsarWatchRecorderFallbackReason? = nil,
        errorMessage: String? = nil
    ) -> PulsarWatchRecorderFallbackPrompt {
        let resolvedReason = overrideReason ?? fallbackReason ?? .notReachable
        let normalizedWorkoutName = workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayWorkoutName = normalizedWorkoutName.isEmpty ? "workout" : normalizedWorkoutName.lowercased()
        let title: String
        let message: String

        switch resolvedReason {
        case .noPairedWatch, .watchAppNotInstalled, .unsupported:
            title = "Apple Watch unavailable"
            message = "No paired Apple Watch was found, or Pulsar is not installed on Apple Watch. You can set up Pulsar on Apple Watch and try again, or continue recording from iPhone."
        case .activationPending, .notReachable:
            title = "Apple Watch not connected"
            message = "We couldn't connect to your Apple Watch. Open Pulsar on Apple Watch and try again, or continue recording this \(displayWorkoutName) from iPhone."
        case .watchLaunchFailed:
            title = "Apple Watch not connected"
            if let errorMessage, !errorMessage.isEmpty {
                message = "Apple Watch could not start this \(displayWorkoutName): \(errorMessage). Open Pulsar on Apple Watch and try again, or continue recording from iPhone."
            } else {
                message = "Apple Watch could not start this \(displayWorkoutName). Open Pulsar on Apple Watch and try again, or continue recording from iPhone."
            }
        case .mirroringTimedOut:
            title = "Apple Watch not connected"
            message = "We started the Apple Watch request, but the live recorder did not connect back to iPhone. Open Pulsar on Apple Watch and try again, or continue recording from iPhone."
        }

        return PulsarWatchRecorderFallbackPrompt(
            reason: resolvedReason,
            title: title,
            message: message
        )
    }
}

@MainActor
final class PulsarWatchConnectivitySyncStore: NSObject, ObservableObject {
    static let shared = PulsarWatchConnectivitySyncStore()

    @Published private(set) var latestPayload: PulsarDailyMetricsSyncPayload?
    @Published private(set) var latestSleepPreferences: PulsarSleepPreferencesSyncPayload?
    @Published private(set) var latestAppleWatchBattery: AppleWatchBatterySnapshot?
    @Published private(set) var activeWorkoutState: PulsarActiveWorkoutSyncState?
    @Published private(set) var lastActiveWorkoutUpdateDecision: ActiveWorkoutUpdateDecision?
    @Published private(set) var lastActiveWorkoutUpdateEvent: ActiveWorkoutUpdateEvent?
    @Published private(set) var activeGymState: ActiveGymWorkoutState?
    @Published private(set) var savedGymRoutines: [WatchGymRoutinePlan]
    @Published private(set) var lastWatchRecorderAvailability: PulsarWatchRecorderAvailabilitySnapshot?
    @Published private(set) var lastWatchSeenAt: Date?
    @Published private(set) var hasEverReceivedWatchPayload: Bool
    @Published private(set) var latestWatchHeartbeat: AppleWatchHeartbeatSnapshot?
    @Published private(set) var sourceCacheRevision: Int = 0

    private let defaults: UserDefaults
    private let cacheKey = "pulsar.sync.cachedDailyMetricsPayload.v1"
    private let dailyCacheKey = "pulsar.sync.cachedDailyMetricPayloadsByDateKey.v1"
    private let sleepCacheKey = "pulsar.sync.cachedSleepPayloadsByDateKey.v1"
    private let sourceDailyCacheKey = "pulsar.sync.cachedDailyMetricPayloadsByDateKeyAndSource.v1"
    private let sourceSleepCacheKey = "pulsar.sync.cachedSleepPayloadsByDateKeyAndSource.v1"
    private let sleepPreferencesCacheKey = "pulsar.sync.cachedSleepPreferencesPayload.v1"
    private let appleWatchBatteryCacheKey = "pulsar.sync.appleWatchBattery.v1"
    private let activeWorkoutCacheKey = "pulsar.sync.activeWorkoutState.v1"
    private let activeWorkoutTombstoneCacheKey = "pulsar.sync.terminatedActiveWorkoutSessions.v1"
    private let activeGymCacheKey = "pulsar.sync.activeGymWorkoutState.v1"
    private let savedGymRoutinesCacheKey = "pulsar.sync.savedGymRoutines.v1"
    private let lastWatchSeenAtCacheKey = "pulsar.sync.lastWatchSeenAt.v1"
    private let hasEverReceivedWatchPayloadCacheKey = "pulsar.sync.hasEverReceivedWatchPayload.v1"
    private let watchHeartbeatCacheKey = "pulsar.sync.watchHeartbeat.v1"
    private static let activeWorkoutTombstoneInterval: TimeInterval = PulsarWorkoutSessionValidity.liveHeartbeatGraceInterval
    private let session: WCSession?
    private var dailyPayloadsByDateKey: [String: PulsarDailyMetricsSyncPayload]
    private var sleepPayloadsByDateKey: [String: PulsarDailyMetricsSyncPayload]
    private var sourceDailyPayloadsByDateKey: [String: [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload]]
    private var sourceSleepPayloadsByDateKey: [String: [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload]]
    private var ignoredFailedWorkoutSessionIDs = Set<UUID>()
    private var locallyTerminatedActiveWorkoutSessions: [UUID: Date]
    private var currentActiveWorkoutSessionID: UUID?
    private var currentActiveWorkoutCanShowConnectionLostAlert = false
    private var gymActionHandler: ((ActiveGymWorkoutAction) -> Void)?
    private var lastActivationErrorMessage: String?
    private var lastActiveWorkoutLiveTransferAt = Date.distantPast
    private var lastActiveWorkoutLiveApplicationContextAt = Date.distantPast
    #if os(iOS)
    private let gymLiveActivityManager = GymLiveActivityManager()
    #endif

    nonisolated static func sanitizedSourcePayloadCache(
        _ cache: [String: [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload]],
        isUsable: (PulsarDailyMetricsSyncPayload) -> Bool
    ) -> [String: [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload]] {
        cache.reduce(into: [:]) { result, entry in
            let filtered = entry.value.reduce(into: [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload]()) { bySource, sourceEntry in
                let source = sourceEntry.key
                var payload = sourceEntry.value
                if payload.sourceDevice != source {
                    payload.sourceDevice = source
                    payload.dataFingerprint = nil
                }
                let sanitized = payload.sanitizedForDeclaredSource()
                guard sanitized.isValidPayload, isUsable(sanitized) else { return }
                bySource[source] = sanitized
            }
            if !filtered.isEmpty {
                result[entry.key] = filtered
            }
        }
    }

    private nonisolated static func decodeSourcePayloadCache(
        _ data: Data?,
        fallbackPayloads: [String: PulsarDailyMetricsSyncPayload],
        isUsable: (PulsarDailyMetricsSyncPayload) -> Bool
    ) -> [String: [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload]] {
        if let data,
           let decoded = try? JSONDecoder().decode([String: [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload]].self, from: data) {
            return sanitizedSourcePayloadCache(decoded, isUsable: isUsable)
        }

        let sourceCache = fallbackPayloads.reduce(into: [String: [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload]]()) { result, entry in
            let payload = entry.value
            guard payload.isValidPayload, isUsable(payload) else { return }
            result[entry.key] = [payload.sourceDevice: payload]
        }
        return sanitizedSourcePayloadCache(sourceCache, isUsable: isUsable)
    }

    private override init() {
        self.defaults = .standard
        self.session = WCSession.isSupported() ? WCSession.default : nil
        let restoredTerminatedActiveWorkoutSessions = Self.prunedActiveWorkoutTombstones(
            Self.decodeActiveWorkoutTombstones(defaults.data(forKey: activeWorkoutTombstoneCacheKey))
        )
        self.locallyTerminatedActiveWorkoutSessions = restoredTerminatedActiveWorkoutSessions
        if let data = defaults.data(forKey: dailyCacheKey),
           let payloads = try? JSONDecoder().decode([String: PulsarDailyMetricsSyncPayload].self, from: data) {
            self.dailyPayloadsByDateKey = payloads.reduce(into: [:]) { result, entry in
                let sanitized = entry.value.sanitizedForDeclaredSource()
                guard entry.key == sanitized.resolvedDateKey,
                      sanitized.isValidPayload,
                      sanitized.hasCompleteDailyScores || sanitized.hasValidStress else { return }
                result[entry.key] = sanitized
            }
        } else {
            self.dailyPayloadsByDateKey = [:]
        }
        if let data = defaults.data(forKey: sleepCacheKey),
           let payloads = try? JSONDecoder().decode([String: PulsarDailyMetricsSyncPayload].self, from: data) {
            self.sleepPayloadsByDateKey = payloads.reduce(into: [:]) { result, entry in
                let sanitized = entry.value.sanitizedForDeclaredSource()
                guard sanitized.isValidPayload, sanitized.sleep?.isValid == true else { return }
                result[entry.key] = sanitized
            }
        } else {
            self.sleepPayloadsByDateKey = [:]
        }
        self.sourceDailyPayloadsByDateKey = Self.decodeSourcePayloadCache(
            defaults.data(forKey: sourceDailyCacheKey),
            fallbackPayloads: self.dailyPayloadsByDateKey,
            isUsable: { $0.hasCompleteDailyScores || $0.hasValidStrain || $0.hasValidRecovery || $0.hasValidStress || $0.hasValidHealthMonitor }
        )
        self.sourceSleepPayloadsByDateKey = Self.decodeSourcePayloadCache(
            defaults.data(forKey: sourceSleepCacheKey),
            fallbackPayloads: self.sleepPayloadsByDateKey,
            isUsable: { $0.sleep?.isValid == true }
        )
        if let data = defaults.data(forKey: cacheKey),
           let payload = PulsarSyncPayloadCodec.decode(data: data),
           payload.isValidPayload {
            let sanitized = payload.sanitizedForDeclaredSource()
            self.latestPayload = sanitized.isValidPayload ? sanitized : nil
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
        let restoredAppleWatchBattery: AppleWatchBatterySnapshot?
        if let data = defaults.data(forKey: appleWatchBatteryCacheKey),
           let snapshot = try? JSONDecoder().decode(AppleWatchBatterySnapshot.self, from: data),
           Self.isValidAppleWatchBattery(snapshot) {
            restoredAppleWatchBattery = snapshot
        } else {
            restoredAppleWatchBattery = nil
        }
        self.latestAppleWatchBattery = restoredAppleWatchBattery

        let restoredWatchHeartbeat: AppleWatchHeartbeatSnapshot?
        if let data = defaults.data(forKey: watchHeartbeatCacheKey),
           let heartbeat = try? JSONDecoder().decode(AppleWatchHeartbeatSnapshot.self, from: data) {
            restoredWatchHeartbeat = heartbeat
        } else {
            restoredWatchHeartbeat = nil
        }
        self.latestWatchHeartbeat = restoredWatchHeartbeat

        let restoredLastWatchSeenAt = defaults.object(forKey: lastWatchSeenAtCacheKey) as? Date ?? restoredWatchHeartbeat?.timestamp
        self.lastWatchSeenAt = restoredLastWatchSeenAt
        self.hasEverReceivedWatchPayload = defaults.bool(forKey: hasEverReceivedWatchPayloadCacheKey) ||
            restoredLastWatchSeenAt != nil ||
            restoredAppleWatchBattery != nil ||
            restoredWatchHeartbeat != nil
        var restoredActiveWorkoutStateForLaunch: PulsarActiveWorkoutSyncState?
        if let data = defaults.data(forKey: activeWorkoutCacheKey),
           let state = Self.decodeActiveWorkoutState(data) {
            let isTombstoned = Self.isActiveWorkoutSessionTombstoned(
                state.sessionId,
                tombstones: restoredTerminatedActiveWorkoutSessions
            )
            if Self.shouldRestoreCachedActiveWorkoutState(state), !isTombstoned {
                self.activeWorkoutState = state
                restoredActiveWorkoutStateForLaunch = state
            } else {
                self.activeWorkoutState = nil
                restoredActiveWorkoutStateForLaunch = nil
                defaults.removeObject(forKey: activeWorkoutCacheKey)
                PulsarSyncDebugLogger.log("active workout restore rejected: \(Self.cachedActiveWorkoutRestoreRejectionReason(state, isTombstoned: isTombstoned)) session=\(state.sessionId.uuidString)")
                PulsarSyncDebugLogger.log("active workout state cleared on launch session=\(state.sessionId.uuidString)")
            }
        } else {
            self.activeWorkoutState = nil
            restoredActiveWorkoutStateForLaunch = nil
            if defaults.data(forKey: activeWorkoutCacheKey) != nil {
                PulsarSyncDebugLogger.log("active workout restore rejected: decode failed")
                PulsarSyncDebugLogger.log("active workout state cleared on launch session=unknown")
            }
            defaults.removeObject(forKey: activeWorkoutCacheKey)
        }
        if let data = defaults.data(forKey: activeGymCacheKey),
           let state = ActiveGymWorkoutCodec.decodeState(data) {
            let isTombstoned = Self.isActiveWorkoutSessionTombstoned(
                state.sessionId,
                tombstones: restoredTerminatedActiveWorkoutSessions
            )
            if Self.shouldRestoreCachedActiveGymState(state),
               !isTombstoned {
                self.activeGymState = state
            } else {
                self.activeGymState = nil
                defaults.removeObject(forKey: activeGymCacheKey)
                if restoredActiveWorkoutStateForLaunch?.sessionId == state.sessionId {
                    restoredActiveWorkoutStateForLaunch = nil
                    self.activeWorkoutState = nil
                    defaults.removeObject(forKey: activeWorkoutCacheKey)
                }
                PulsarSyncDebugLogger.log("active workout restore rejected: \(Self.cachedActiveGymRestoreRejectionReason(state, isTombstoned: isTombstoned)) session=\(state.sessionId.uuidString)")
                PulsarSyncDebugLogger.log("active workout state cleared on launch session=\(state.sessionId.uuidString)")
            }
        } else {
            self.activeGymState = nil
            if defaults.data(forKey: activeGymCacheKey) != nil {
                PulsarSyncDebugLogger.log("active workout restore rejected: active gym decode failed")
                PulsarSyncDebugLogger.log("active workout state cleared on launch session=unknown")
            }
            defaults.removeObject(forKey: activeGymCacheKey)
        }
        if let data = defaults.data(forKey: savedGymRoutinesCacheKey),
           let routines = try? JSONDecoder().decode([WatchGymRoutinePlan].self, from: data) {
            self.savedGymRoutines = routines.sorted { $0.updatedAt > $1.updatedAt }
        } else {
            self.savedGymRoutines = []
        }
        super.init()
        if let latestPayload {
            persist(latestPayload)
        } else {
            defaults.removeObject(forKey: cacheKey)
        }
        persistDailyPayloadCache()
        persistSleepPayloadCache()
        persistSourcePayloadCache(sourceDailyPayloadsByDateKey, defaultsKey: sourceDailyCacheKey)
        persistSourcePayloadCache(sourceSleepPayloadsByDateKey, defaultsKey: sourceSleepCacheKey)
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
        let sanitized = latestPayload.sanitizedForDeclaredSource()
        guard sanitized.isValidPayload else {
            self.latestPayload = nil
            defaults.removeObject(forKey: cacheKey)
            return nil
        }
        if sanitized != latestPayload {
            self.latestPayload = sanitized
            persist(sanitized)
        }
        return sanitized
    }

    func cachedDailyPayload(forDateKey dateKey: String) -> PulsarDailyMetricsSyncPayload? {
        guard !dateKey.isEmpty,
              let payload = dailyPayloadsByDateKey[dateKey] else { return nil }
        let sanitized = payload.sanitizedForDeclaredSource()
        guard sanitized.isValidPayload,
              sanitized.hasCompleteDailyScores || sanitized.hasValidStress else {
            dailyPayloadsByDateKey.removeValue(forKey: dateKey)
            persistDailyPayloadCache()
            return nil
        }
        if sanitized != payload {
            dailyPayloadsByDateKey[dateKey] = sanitized
            persistDailyPayloadCache()
        }
        return sanitized
    }

    func cachedSleepPayload(forSleepDateKey sleepDateKey: String) -> PulsarDailyMetricsSyncPayload? {
        guard !sleepDateKey.isEmpty,
              let payload = sleepPayloadsByDateKey[sleepDateKey] else { return nil }
        let sanitized = payload.sanitizedForDeclaredSource()
        guard sanitized.isValidPayload, sanitized.sleep?.isValid == true else {
            sleepPayloadsByDateKey.removeValue(forKey: sleepDateKey)
            persistSleepPayloadCache()
            return nil
        }
        if sanitized != payload {
            sleepPayloadsByDateKey[sleepDateKey] = sanitized
            persistSleepPayloadCache()
        }
        return sanitized
    }

    func cachedDailyPayloads() -> [PulsarDailyMetricsSyncPayload] {
        let sanitized = dailyPayloadsByDateKey.reduce(into: [String: PulsarDailyMetricsSyncPayload]()) { result, entry in
            let payload = entry.value.sanitizedForDeclaredSource()
            guard payload.isValidPayload, payload.hasCompleteDailyScores || payload.hasValidStress else { return }
            result[entry.key] = payload
        }
        if sanitized != dailyPayloadsByDateKey {
            dailyPayloadsByDateKey = sanitized
            persistDailyPayloadCache()
        }
        return sanitized.values
            .sorted { $0.resolvedDateKey < $1.resolvedDateKey }
    }

    func cachedSleepPayloads() -> [PulsarDailyMetricsSyncPayload] {
        let sanitized = sleepPayloadsByDateKey.reduce(into: [String: PulsarDailyMetricsSyncPayload]()) { result, entry in
            let payload = entry.value.sanitizedForDeclaredSource()
            guard payload.isValidPayload, payload.sleep?.isValid == true else { return }
            result[entry.key] = payload
        }
        if sanitized != sleepPayloadsByDateKey {
            sleepPayloadsByDateKey = sanitized
            persistSleepPayloadCache()
        }
        return sanitized.values
            .sorted { $0.resolvedDateKey < $1.resolvedDateKey }
    }

    func cachedDailyPayloadsBySource(forDateKey dateKey: String) -> [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload] {
        guard !dateKey.isEmpty else { return [:] }
        let sanitized = Self.sanitizedSourcePayloadCache(
            [dateKey: sourceDailyPayloadsByDateKey[dateKey] ?? [:]],
            isUsable: { $0.hasCompleteDailyScores || $0.hasValidStrain || $0.hasValidRecovery || $0.hasValidStress || $0.hasValidHealthMonitor }
        )[dateKey] ?? [:]
        let currentPayloads = sourceDailyPayloadsByDateKey[dateKey] ?? [:]
        if sanitized != currentPayloads {
            if sanitized.isEmpty {
                sourceDailyPayloadsByDateKey.removeValue(forKey: dateKey)
            } else {
                sourceDailyPayloadsByDateKey[dateKey] = sanitized
            }
            persistSourcePayloadCache(sourceDailyPayloadsByDateKey, defaultsKey: sourceDailyCacheKey)
        }
        return sanitized
    }

    func cachedSleepPayloadsBySource(forSleepDateKey sleepDateKey: String) -> [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload] {
        guard !sleepDateKey.isEmpty else { return [:] }
        let sanitized = Self.sanitizedSourcePayloadCache(
            [sleepDateKey: sourceSleepPayloadsByDateKey[sleepDateKey] ?? [:]],
            isUsable: { $0.sleep?.isValid == true }
        )[sleepDateKey] ?? [:]
        let currentPayloads = sourceSleepPayloadsByDateKey[sleepDateKey] ?? [:]
        if sanitized != currentPayloads {
            if sanitized.isEmpty {
                sourceSleepPayloadsByDateKey.removeValue(forKey: sleepDateKey)
            } else {
                sourceSleepPayloadsByDateKey[sleepDateKey] = sanitized
            }
            persistSourcePayloadCache(sourceSleepPayloadsByDateKey, defaultsKey: sourceSleepCacheKey)
        }
        return sanitized
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
    func sendWatchHeartbeat(reason: String = "watchHeartbeat") {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        let batteryLevel = device.batteryLevel
        let batteryPercentage = batteryLevel >= 0 ? min(100, max(0, Int((batteryLevel * 100).rounded()))) : nil
        let heartbeat = AppleWatchHeartbeatSnapshot(
            appInstalled: true,
            watchAppVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            timestamp: Date(),
            batteryPercentage: batteryPercentage
        )
        latestWatchHeartbeat = heartbeat
        persistWatchHeartbeat(heartbeat)
        sendWatchHeartbeatToCounterpart(heartbeat, reason: reason)
        PulsarSyncDebugLogger.log("Watch heartbeat sent reason=\(reason) version=\(heartbeat.watchAppVersion ?? "unknown") battery=\(batteryPercentage.map(String.init) ?? "unknown")")
    }

    func refreshAndSendAppleWatchBattery(reason: String = "watchBatteryRefresh") {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true

        let batteryLevel = device.batteryLevel
        guard batteryLevel >= 0 else {
            PulsarSyncDebugLogger.log("Skipped \(reason) because Apple Watch battery level is unavailable")
            sendWatchHeartbeat(reason: "\(reason).heartbeat")
            return
        }

        let percentage = min(100, max(0, Int((batteryLevel * 100).rounded())))
        let snapshot = AppleWatchBatterySnapshot(batteryPercentage: percentage, timestamp: Date())
        storeAppleWatchBattery(snapshot, broadcast: true, reason: reason)
        sendWatchHeartbeat(reason: "\(reason).heartbeat")
    }
    #endif

    func registerGymActionHandler(_ handler: @escaping (ActiveGymWorkoutAction) -> Void) {
        gymActionHandler = handler
    }

    func unregisterGymActionHandler() {
        gymActionHandler = nil
    }

    var hasRecentWatchHeartbeat: Bool {
        guard let lastWatchSeenAt else { return false }
        return Date().timeIntervalSince(lastWatchSeenAt) <= 15 * 60
    }

    func recordAppleWatchSeen(reason: String, timestamp: Date = Date(), payloadKind: String = "watchPayload") {
        let resolvedTimestamp = max(timestamp, lastWatchSeenAt ?? .distantPast)
        let wasFirstPayload = !hasEverReceivedWatchPayload
        lastWatchSeenAt = resolvedTimestamp
        hasEverReceivedWatchPayload = true
        defaults.set(resolvedTimestamp, forKey: lastWatchSeenAtCacheKey)
        defaults.set(true, forKey: hasEverReceivedWatchPayloadCacheKey)
        PulsarSyncDebugLogger.log("Apple Watch seen reason=\(reason) payload=\(payloadKind) lastWatchSeenAt=\(resolvedTimestamp) firstPayload=\(wasFirstPayload)")
        _ = watchRecorderAvailabilitySnapshot(reason: "\(reason).watchSeen")
    }

    func watchRecorderAvailabilitySnapshot(reason: String) -> PulsarWatchRecorderAvailabilitySnapshot {
        activateSessionIfNeeded()
        let snapshot: PulsarWatchRecorderAvailabilitySnapshot
        guard let session else {
            snapshot = PulsarWatchRecorderAvailabilitySnapshot(
                isSupported: false,
                activationStateRawValue: WCSessionActivationState.notActivated.rawValue,
                activationStateDescription: "unsupported",
                activationErrorMessage: lastActivationErrorMessage,
                isPaired: false,
                rawIsWatchAppInstalled: false,
                rawIsReachable: false,
                lastWatchSeenAt: lastWatchSeenAt,
                hasEverReceivedWatchPayload: hasEverReceivedWatchPayload
            )
            lastWatchRecorderAvailability = snapshot
            logWatchRecorderAvailability(snapshot, reason: reason)
            return snapshot
        }

        #if os(iOS)
        let isPaired = session.isPaired
        let isWatchAppInstalled = session.isWatchAppInstalled
        #else
        let isPaired = true
        let isWatchAppInstalled = true
        #endif

        snapshot = PulsarWatchRecorderAvailabilitySnapshot(
            isSupported: true,
            activationStateRawValue: session.activationState.rawValue,
            activationStateDescription: Self.describeActivationState(session.activationState),
            activationErrorMessage: lastActivationErrorMessage,
            isPaired: isPaired,
            rawIsWatchAppInstalled: isWatchAppInstalled,
            rawIsReachable: session.isReachable,
            lastWatchSeenAt: lastWatchSeenAt,
            hasEverReceivedWatchPayload: hasEverReceivedWatchPayload
        )
        lastWatchRecorderAvailability = snapshot
        logWatchRecorderAvailability(snapshot, reason: reason)
        return snapshot
    }

    func waitForReachableWatchRecorder(
        reason: String,
        timeoutSeconds: TimeInterval = 2.0,
        pollIntervalSeconds: TimeInterval = 0.25
    ) async -> PulsarWatchRecorderAvailabilitySnapshot {
        let deadline = Date().addingTimeInterval(max(0, timeoutSeconds))
        var latest = watchRecorderAvailabilitySnapshot(reason: "\(reason).preflight")
        guard latest.fallbackReason != .unsupported,
              latest.fallbackReason != .noPairedWatch,
              latest.fallbackReason != .watchAppNotInstalled else {
            return latest
        }

        while !latest.canStartOnWatch && Date() < deadline {
            let remaining = deadline.timeIntervalSinceNow
            let sleepSeconds = min(max(0.05, pollIntervalSeconds), max(0.05, remaining))
            try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
            latest = watchRecorderAvailabilitySnapshot(reason: "\(reason).retry")
            guard latest.fallbackReason != .unsupported,
                  latest.fallbackReason != .noPairedWatch,
                  latest.fallbackReason != .watchAppNotInstalled else {
                return latest
            }
        }

        PulsarSyncDebugLogger.log("Watch recorder preflight completed reason=\(reason) canStart=\(latest.canStartOnWatch) activation=\(latest.activationStateDescription) paired=\(latest.isPaired) rawInstalled=\(latest.rawIsWatchAppInstalled) rawReachable=\(latest.rawIsReachable) lastWatchSeenAt=\(latest.lastWatchSeenAt?.description ?? "none") derivedInstalled=\(latest.isWatchAppInstalled) derivedReachable=\(latest.derivedReachabilityDescription) fallback=\(latest.fallbackReason?.logValue ?? "none")")
        return latest
    }

    func setCurrentActiveWorkoutSessionID(_ sessionID: UUID?, reason: String) {
        setCurrentActiveWorkoutSessionContext(
            sessionID: sessionID,
            canShowConnectionLostAlert: sessionID != nil,
            reason: reason
        )
    }

    func setCurrentActiveWorkoutSessionContext(
        sessionID: UUID?,
        canShowConnectionLostAlert: Bool,
        reason: String
    ) {
        let resolvedCanShowConnectionLostAlert = sessionID != nil && canShowConnectionLostAlert
        guard currentActiveWorkoutSessionID != sessionID ||
            currentActiveWorkoutCanShowConnectionLostAlert != resolvedCanShowConnectionLostAlert else { return }
        currentActiveWorkoutSessionID = sessionID
        currentActiveWorkoutCanShowConnectionLostAlert = resolvedCanShowConnectionLostAlert
        PulsarSyncDebugLogger.log("Current active workout session context updated reason=\(reason) currentSession=\(sessionID?.uuidString ?? "none") alertEligible=\(resolvedCanShowConnectionLostAlert)")
    }

    func tombstoneActiveWorkoutSession(_ sessionID: UUID, reason: String) {
        rememberTerminatedActiveWorkoutSession(sessionID, reason: reason)
        if activeWorkoutState?.sessionId == sessionID {
            activeWorkoutState = nil
            defaults.removeObject(forKey: activeWorkoutCacheKey)
            PulsarSyncDebugLogger.log("Active workout state cleared for tombstoned session reason=\(reason) session=\(sessionID.uuidString)")
        }
    }

    func isActiveWorkoutSessionTombstoned(_ sessionID: UUID) -> Bool {
        pruneActiveWorkoutTombstones()
        return Self.isActiveWorkoutSessionTombstoned(
            sessionID,
            tombstones: locallyTerminatedActiveWorkoutSessions
        )
    }

    @discardableResult
    func storeActiveWorkoutState(_ state: PulsarActiveWorkoutSyncState, broadcast: Bool, reason: String) -> ActiveWorkoutUpdateDecision {
        apply(activeWorkoutState: state, broadcast: broadcast, reason: reason, isIncomingFromCounterpart: false)
    }

    @discardableResult
    func storeActiveGymState(_ state: ActiveGymWorkoutState, broadcast: Bool, reason: String) -> Bool {
        apply(activeGymState: state, broadcast: broadcast, reason: reason)
    }

    func pruneStaleActiveWorkoutState(reason: String) {
        if let activeWorkoutState,
           let staleReason = activeWorkoutState.staleRouteReason() {
            PulsarSyncDebugLogger.log("active workout restore rejected: \(staleReason) source=\(reason) session=\(activeWorkoutState.sessionId.uuidString)")
            clearActiveWorkoutState(reason: "\(reason).\(staleReason)", broadcastEndedState: false)
        }

        if let activeGymState,
           let staleReason = activeGymState.staleRouteReason() {
            PulsarSyncDebugLogger.log("active workout restore rejected: \(staleReason) source=\(reason) session=\(activeGymState.sessionId.uuidString)")
            clearActiveGymState(reason: "\(reason).\(staleReason)", broadcastEndedState: false)
        }
    }

    func isRoutableActiveWorkoutState(_ state: PulsarActiveWorkoutSyncState) -> Bool {
        state.isValidActiveWorkoutPresentationCandidate()
    }

    func isRoutableActiveGymState(_ state: ActiveGymWorkoutState) -> Bool {
        state.isValidActiveWorkoutPresentationCandidate()
    }

    func clearActiveWorkoutState(reason: String, broadcastEndedState: Bool = false) {
        let previous = activeWorkoutState
        if broadcastEndedState, var ended = previous, ended.phase.isLive {
            ended.phase = .ended
            ended.endedAt = Date()
            ended.updatedAt = Date()
            apply(activeWorkoutState: ended, broadcast: true, reason: "\(reason).endedBroadcast", isIncomingFromCounterpart: false)
        }

        if let previous {
            rememberTerminatedActiveWorkoutSession(previous.sessionId, reason: reason)
        }
        activeWorkoutState = nil
        defaults.removeObject(forKey: activeWorkoutCacheKey)
        PulsarSyncDebugLogger.log("Active workout state cleared reason=\(reason) session=\(previous?.sessionId.uuidString ?? "none")")
        publishCurrentApplicationContext(reason: "\(reason).activeWorkoutCleared")
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
        if let previous {
            rememberTerminatedActiveWorkoutSession(previous.sessionId, reason: reason)
            if activeWorkoutState?.sessionId == previous.sessionId {
                activeWorkoutState = nil
                defaults.removeObject(forKey: activeWorkoutCacheKey)
            }
        }
        PulsarSyncDebugLogger.log("Active Gym state cleared reason=\(reason) session=\(previous?.sessionId.uuidString ?? "none")")
        publishCurrentApplicationContext(reason: "\(reason).activeGymCleared")
    }

    func sendGymAction(_ action: ActiveGymWorkoutAction) {
        guard let session = counterpartSession(for: "Active Gym action"),
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

    nonisolated static func shouldPromotePayloadToGlobalCache(
        currentPayload: PulsarDailyMetricsSyncPayload?,
        incomingPayload: PulsarDailyMetricsSyncPayload
    ) -> Bool {
        guard let currentPayload else { return true }
        guard currentPayload.sourceDevice != incomingPayload.sourceDevice,
              currentPayload.resolvedDateKey == incomingPayload.resolvedDateKey else {
            return true
        }
        return false
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
        if session.activationState == .activated {
            return
        }
        session.activate()
        PulsarSyncDebugLogger.log("WatchConnectivity session activating state=\(Self.describeActivationState(session.activationState))")
    }

    private func counterpartSession(for reason: String) -> WCSession? {
        guard let session else { return nil }
        guard session.activationState == .activated else {
            PulsarSyncDebugLogger.log("Skipped \(reason) transfer because WatchConnectivity is not activated state=\(session.activationState.rawValue)")
            return nil
        }
        #if os(iOS)
        guard session.isPaired else {
            PulsarSyncDebugLogger.log("Skipped \(reason) transfer because no Apple Watch is paired")
            return nil
        }
        let availability = watchRecorderAvailabilitySnapshot(reason: "\(reason).counterpart")
        let canSendToCounterpart = availability.rawIsWatchAppInstalled ||
            availability.rawIsReachable ||
            availability.hasRecentWatchHeartbeat
        guard canSendToCounterpart else {
            PulsarSyncDebugLogger.log("Skipped \(reason) transfer because the Watch app is not currently installed or reachable rawInstalled=\(availability.rawIsWatchAppInstalled) rawReachable=\(availability.rawIsReachable) lastWatchSeenAt=\(availability.lastWatchSeenAt?.description ?? "none") everWatchPayload=\(availability.hasEverReceivedWatchPayload)")
            return nil
        }
        #endif
        return session
    }

    private func logWatchRecorderAvailability(_ snapshot: PulsarWatchRecorderAvailabilitySnapshot, reason: String) {
        PulsarSyncDebugLogger.log("Watch recorder availability reason=\(reason) activation=\(snapshot.activationStateDescription)(\(snapshot.activationStateRawValue)) paired=\(snapshot.isPaired) rawInstalled=\(snapshot.rawIsWatchAppInstalled) rawReachable=\(snapshot.rawIsReachable) lastWatchSeenAt=\(snapshot.lastWatchSeenAt?.description ?? "none") everWatchPayload=\(snapshot.hasEverReceivedWatchPayload) derivedInstalled=\(snapshot.isWatchAppInstalled) derivedReachable=\(snapshot.derivedReachabilityDescription) canStart=\(snapshot.canStartOnWatch) error=\(snapshot.activationErrorMessage ?? "none") fallback=\(snapshot.fallbackReason?.logValue ?? "none")")
    }

    private static func describeActivationState(_ activationState: WCSessionActivationState) -> String {
        switch activationState {
        case .notActivated:
            "notActivated"
        case .inactive:
            "inactive"
        case .activated:
            "activated"
        @unknown default:
            "unknown(\(activationState.rawValue))"
        }
    }

    @discardableResult
    private func apply(payload incoming: PulsarDailyMetricsSyncPayload, broadcast: Bool, reason: String) -> Bool {
        let incoming = incoming.sanitizedForDeclaredSource()
        guard incoming.isValidPayload else {
            PulsarSyncDebugLogger.log("Skipped \(reason) payload because it was empty, invalid, or partial daily data session=\(incoming.syncSessionID?.uuidString ?? "none") source=\(incoming.sourceDevice.rawValue) dateKey=\(incoming.resolvedDateKey.isEmpty ? "missing" : incoming.resolvedDateKey)")
            return false
        }
        let didUpdateSourceCache = persistSourcePayloadIfNeeded(incoming)

        let currentPayload = latestPayload?.isValidPayload == true ? latestPayload?.sanitizedForDeclaredSource() : nil
        let isSameSourceAsCurrent = currentPayload?.sourceDevice == incoming.sourceDevice

        if !Self.shouldPromotePayloadToGlobalCache(currentPayload: currentPayload, incomingPayload: incoming) {
            PulsarSyncDebugLogger.log("Stored \(reason) as source-specific payload without global cache replacement incomingSource=\(incoming.sourceDevice.rawValue) cachedSource=\(currentPayload?.sourceDevice.rawValue ?? "none")")
            return didUpdateSourceCache
        }

        if let latestPayload = currentPayload,
           isSameSourceAsCurrent,
           latestPayload.resolvedDateKey == incoming.resolvedDateKey,
           latestPayload.resolvedDataFingerprint == incoming.resolvedDataFingerprint {
            PulsarSyncDebugLogger.log("Skipped \(reason) payload because data fingerprint was unchanged session=\(incoming.syncSessionID?.uuidString ?? "none") source=\(incoming.sourceDevice.rawValue) fingerprint=\(incoming.resolvedDataFingerprint)")
            return didUpdateSourceCache
        }

        if let latestPayload = currentPayload,
           isSameSourceAsCurrent,
           latestPayload.resolvedDateKey == incoming.resolvedDateKey,
           incoming.syncedAt < latestPayload.syncedAt,
           !incomingCanFillMissingMetric(incoming, current: latestPayload),
           !incomingCarriesNewerMetric(incoming, current: latestPayload),
           !latestPayload.resolvedDataFingerprint.isEmpty {
            PulsarSyncDebugLogger.log("Skipped \(reason) payload because incoming data was older session=\(incoming.syncSessionID?.uuidString ?? "none") incoming=\(incoming.syncedAt) cached=\(latestPayload.syncedAt)")
            return didUpdateSourceCache
        }

        let merged: PulsarDailyMetricsSyncPayload
        if let currentPayload, isSameSourceAsCurrent {
            merged = currentPayload.merged(with: incoming).sanitizedForDeclaredSource()
        } else {
            if let currentPayload,
               currentPayload.resolvedDateKey == incoming.resolvedDateKey,
               incoming.syncedAt < currentPayload.syncedAt,
               !currentPayload.resolvedDataFingerprint.isEmpty {
                PulsarSyncDebugLogger.log("Skipped \(reason) global payload update because cached source-specific payload was newer incomingSource=\(incoming.sourceDevice.rawValue) cachedSource=\(currentPayload.sourceDevice.rawValue) incoming=\(incoming.syncedAt) cached=\(currentPayload.syncedAt)")
                return didUpdateSourceCache
            }
            if let currentPayload, currentPayload.sourceDevice != incoming.sourceDevice {
                PulsarSyncDebugLogger.log("Stored \(reason) as source-specific payload without cross-source merge incomingSource=\(incoming.sourceDevice.rawValue) cachedSource=\(currentPayload.sourceDevice.rawValue)")
            }
            merged = incoming
        }
        guard merged != latestPayload else {
            PulsarSyncDebugLogger.log("Skipped \(reason) payload because cached data was already newer or equivalent session=\(incoming.syncSessionID?.uuidString ?? "none")")
            return didUpdateSourceCache
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

        #if os(iOS)
        recordAppleWatchSeen(reason: reason, timestamp: incoming.timestamp, payloadKind: "appleWatchBattery")
        #endif

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
    private func apply(
        activeWorkoutState incoming: PulsarActiveWorkoutSyncState,
        broadcast: Bool,
        reason: String,
        isIncomingFromCounterpart: Bool
    ) -> ActiveWorkoutUpdateDecision {
        let incoming = canonicalizedActiveWorkoutState(incoming, reason: reason)
        let decision = makeActiveWorkoutUpdateDecision(
            for: incoming,
            reason: reason,
            isIncomingFromCounterpart: isIncomingFromCounterpart
        )
        lastActiveWorkoutUpdateDecision = decision
        lastActiveWorkoutUpdateEvent = ActiveWorkoutUpdateEvent(decision: decision, state: incoming, source: reason)

        if incoming.isEnded {
            guard decision.didApplySyncState else {
                PulsarSyncDebugLogger.log("Terminal active workout state skipped via \(reason) session=\(incoming.sessionId.uuidString) type=\(incoming.kind.workoutTypeRawValue) phase=\(incoming.phase.rawValue) action=noop")
                return decision
            }
            rememberTerminatedActiveWorkoutSession(incoming.sessionId, reason: reason)
            if broadcast {
                sendActiveWorkoutStateToCounterpart(incoming, reason: reason)
            }
            var clearedCachedState = false
            if activeWorkoutState?.sessionId == incoming.sessionId {
                activeWorkoutState = nil
                defaults.removeObject(forKey: activeWorkoutCacheKey)
                PulsarSyncDebugLogger.log("Terminal active workout update cleared cached active state via \(reason) session=\(incoming.sessionId.uuidString) phase=\(incoming.phase.rawValue)")
                clearedCachedState = true
            }
            if case .gym = incoming.kind,
               activeGymState?.sessionId == incoming.sessionId {
                activeGymState = nil
                defaults.removeObject(forKey: activeGymCacheKey)
                PulsarSyncDebugLogger.log("Terminal gym active workout update cleared cached Active Gym state via \(reason) session=\(incoming.sessionId.uuidString) phase=\(incoming.phase.rawValue)")
                clearedCachedState = true
            }
            if clearedCachedState {
                publishCurrentApplicationContext(reason: "\(reason).terminalActiveWorkoutCleared")
            }
            return decision
        }

        if incoming.phase == .failed {
            if case .failedCurrentAndShouldAlert = decision, broadcast {
                sendActiveWorkoutStateToCounterpart(incoming, reason: reason)
            }
            return decision
        }

        guard decision.didApplySyncState else {
            PulsarSyncDebugLogger.log("Active workout state skipped via \(reason) session=\(incoming.sessionId.uuidString) type=\(incoming.kind.workoutTypeRawValue) phase=\(incoming.phase.rawValue) updatedAt=\(incoming.updatedAt)")
            return decision
        }

        let merged = mergeActiveWorkoutState(current: activeWorkoutState, incoming: incoming, reason: reason)
        activeWorkoutState = merged
        persistActiveWorkoutState(merged)
        PulsarSyncDebugLogger.log("Active workout data updated from \(reason) session=\(merged.sessionId.uuidString) type=\(merged.kind.workoutTypeRawValue) phase=\(merged.phase.rawValue) startedFrom=\(merged.startedFrom.rawValue) updatedFrom=\(merged.lastUpdatedFrom.rawValue) distanceMeters=\(merged.distanceMeters ?? -1) elapsedSeconds=\(merged.elapsedSeconds) movingSeconds=\(merged.movingSeconds ?? -1) pace=\(merged.currentPaceSecondsPerKilometer ?? -1) calories=\(merged.activeEnergyKilocalories ?? -1) heartRate=\(merged.currentHeartRate ?? -1) sampleTimestamp=\(merged.runMetricsUpdatedAt?.description ?? "none")")

        if broadcast {
            sendActiveWorkoutStateToCounterpart(merged, reason: reason)
        }
        return decision
    }

    @discardableResult
    private func apply(activeGymState incoming: ActiveGymWorkoutState, broadcast: Bool, reason: String) -> Bool {
        guard shouldApply(activeGymState: incoming) else {
            PulsarSyncDebugLogger.log("Active Gym state skipped via \(reason) session=\(incoming.sessionId.uuidString) type=\(incoming.workoutKind?.rawValue ?? "unknown") updatedAt=\(incoming.updatedAt) finished=\(incoming.isFinished)")
            return false
        }

        if incoming.isFinished {
            let activeState = PulsarActiveWorkoutSyncState(gymState: incoming)
            _ = apply(activeWorkoutState: activeState, broadcast: false, reason: "\(reason).gymBridge", isIncomingFromCounterpart: false)
            if broadcast {
                sendGymStateToCounterpart(incoming)
            }
            rememberTerminatedActiveWorkoutSession(incoming.sessionId, reason: reason)
            if activeGymState?.sessionId == incoming.sessionId {
                activeGymState = nil
            }
            defaults.removeObject(forKey: activeGymCacheKey)
            if activeWorkoutState?.sessionId == incoming.sessionId {
                activeWorkoutState = nil
                defaults.removeObject(forKey: activeWorkoutCacheKey)
            }
            PulsarSyncDebugLogger.log("Active Gym terminal state cleared active cache via \(reason) session=\(incoming.sessionId.uuidString) type=\(incoming.workoutKind?.rawValue ?? "unknown")")
            publishCurrentApplicationContext(reason: "\(reason).finishedGymCleared")
            return true
        }

        activeGymState = incoming
        persistActiveGymState(incoming)
        let activeState = PulsarActiveWorkoutSyncState(gymState: incoming)
        _ = apply(activeWorkoutState: activeState, broadcast: false, reason: "\(reason).gymBridge", isIncomingFromCounterpart: false)
        PulsarSyncDebugLogger.log("Active Gym state updated via \(reason) session=\(incoming.sessionId.uuidString) type=\(incoming.workoutKind?.rawValue ?? "unknown") startedFrom=\(incoming.startedFrom?.rawValue ?? "unknown") progress=\(incoming.completedSets)/\(incoming.totalSets) finished=\(incoming.isFinished)")

        if broadcast {
            sendGymStateToCounterpart(incoming)
        }
        return true
    }

    @discardableResult
    private func apply(watchHeartbeat incoming: AppleWatchHeartbeatSnapshot, broadcast: Bool, reason: String) -> Bool {
        guard incoming.appInstalled else {
            PulsarSyncDebugLogger.log("Skipped \(reason) Watch heartbeat because appInstalled=false")
            return false
        }

        if let latestWatchHeartbeat,
           incoming.timestamp < latestWatchHeartbeat.timestamp {
            #if os(iOS)
            recordAppleWatchSeen(reason: reason, payloadKind: "staleWatchHeartbeat")
            #endif
            PulsarSyncDebugLogger.log("Skipped \(reason) Watch heartbeat because cached heartbeat was newer incoming=\(incoming.timestamp) cached=\(latestWatchHeartbeat.timestamp)")
            return false
        }

        latestWatchHeartbeat = incoming
        persistWatchHeartbeat(incoming)
        #if os(iOS)
        recordAppleWatchSeen(reason: reason, timestamp: incoming.timestamp, payloadKind: "watchHeartbeat")
        #endif
        PulsarSyncDebugLogger.log("Watch heartbeat received via \(reason) version=\(incoming.watchAppVersion ?? "unknown") timestamp=\(incoming.timestamp) battery=\(incoming.batteryPercentage.map(String.init) ?? "unknown")")

        if let batteryPercentage = incoming.batteryPercentage {
            let battery = AppleWatchBatterySnapshot(
                batteryPercentage: batteryPercentage,
                timestamp: incoming.timestamp
            )
            _ = apply(
                appleWatchBattery: battery,
                broadcast: false,
                reason: "\(reason).watchHeartbeatBattery"
            )
        }

        if broadcast {
            sendWatchHeartbeatToCounterpart(incoming, reason: reason)
        }
        return true
    }

    private func persist(_ payload: PulsarDailyMetricsSyncPayload) {
        guard let data = PulsarSyncPayloadCodec.encode(payload) else { return }
        defaults.set(data, forKey: cacheKey)
    }

    private func persistDailyPayloadCache() {
        guard let data = try? JSONEncoder().encode(dailyPayloadsByDateKey) else { return }
        defaults.set(data, forKey: dailyCacheKey)
    }

    private func persistSleepPayloadCache() {
        guard let data = try? JSONEncoder().encode(sleepPayloadsByDateKey) else { return }
        defaults.set(data, forKey: sleepCacheKey)
    }

    private func persistDailyPayloadIfNeeded(_ payload: PulsarDailyMetricsSyncPayload) {
        let payload = payload.sanitizedForDeclaredSource()
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
        persistDailyPayloadCache()
        PulsarSyncDebugLogger.log("Daily Recovery/Strain cache updated dateKey=\(dateKey) strain=\(dailyPayload.strain?.score ?? 0) recovery=\(dailyPayload.recovery?.score ?? 0) session=\(dailyPayload.syncSessionID?.uuidString ?? "none")")
    }

    private func persistSleepPayloadIfNeeded(_ payload: PulsarDailyMetricsSyncPayload) {
        let payload = payload.sanitizedForDeclaredSource()
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
        persistSleepPayloadCache()
        PulsarSyncDebugLogger.log("Sleep cache updated sleepDateKey=\(sleep.sleepDateKey) score=\(sleep.score) session=\(sleepPayload.syncSessionID?.uuidString ?? "none")")
    }

    @discardableResult
    private func persistSourcePayloadIfNeeded(_ payload: PulsarDailyMetricsSyncPayload) -> Bool {
        let payload = payload.sanitizedForDeclaredSource()
        var didUpdate = false
        if payload.hasCompleteDailyScores ||
            payload.hasValidStrain ||
            payload.hasValidRecovery ||
            payload.hasValidStress ||
            payload.hasValidHealthMonitor {
            didUpdate = persistSourcePayload(
                payload,
                dateKey: payload.resolvedDateKey,
                cache: &sourceDailyPayloadsByDateKey,
                defaultsKey: sourceDailyCacheKey,
                isUsable: { $0.hasCompleteDailyScores || $0.hasValidStrain || $0.hasValidRecovery || $0.hasValidStress || $0.hasValidHealthMonitor }
            ) || didUpdate
        }
        if let sleep = payload.sleep, sleep.isValid {
            didUpdate = persistSourcePayload(
                payload,
                dateKey: sleep.sleepDateKey,
                cache: &sourceSleepPayloadsByDateKey,
                defaultsKey: sourceSleepCacheKey,
                isUsable: { $0.sleep?.isValid == true }
            ) || didUpdate
        }
        return didUpdate
    }

    @discardableResult
    private func persistSourcePayload(
        _ payload: PulsarDailyMetricsSyncPayload,
        dateKey: String,
        cache: inout [String: [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload]],
        defaultsKey: String,
        isUsable: (PulsarDailyMetricsSyncPayload) -> Bool
    ) -> Bool {
        let payload = payload.sanitizedForDeclaredSource()
        guard !dateKey.isEmpty, payload.isValidPayload, isUsable(payload) else { return false }
        var bySource = cache[dateKey] ?? [:]
        let source = payload.sourceDevice
        let merged = bySource[source]
            .map { $0.sanitizedForDeclaredSource().merged(with: payload).sanitizedForDeclaredSource() } ?? payload
        guard bySource[source]?.resolvedDataFingerprint != merged.resolvedDataFingerprint ||
                bySource[source]?.syncedAt != merged.syncedAt else { return false }
        bySource[source] = merged
        cache[dateKey] = bySource
        persistSourcePayloadCache(cache, defaultsKey: defaultsKey)
        sourceCacheRevision &+= 1
        PulsarSyncDebugLogger.log("Source cache updated dateKey=\(dateKey) source=\(source.rawValue) session=\(payload.syncSessionID?.uuidString ?? "none")")
        return true
    }

    private func persistSourcePayloadCache(
        _ cache: [String: [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload]],
        defaultsKey: String
    ) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    private func persistSleepPreferences(_ payload: PulsarSleepPreferencesSyncPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: sleepPreferencesCacheKey)
    }

    private func persistAppleWatchBattery(_ snapshot: AppleWatchBatterySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: appleWatchBatteryCacheKey)
    }

    private func persistWatchHeartbeat(_ snapshot: AppleWatchHeartbeatSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: watchHeartbeatCacheKey)
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
        guard let session = counterpartSession(for: "daily metrics") else { return }
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

    private func publishCurrentApplicationContext(reason: String) {
        guard let session = counterpartSession(for: "cleared active workout context") else { return }
        let applicationContext = makeApplicationContext(
            metricPayload: latestPayload,
            sleepPreferences: latestSleepPreferences,
            activeWorkoutState: activeWorkoutState,
            activeGymState: activeGymState,
            savedGymRoutines: savedGymRoutines
        )
        do {
            try session.updateApplicationContext(applicationContext)
            PulsarSyncDebugLogger.log("Active workout applicationContext refreshed after clear reason=\(reason) activeSession=\(activeWorkoutState?.sessionId.uuidString ?? "none") activeGym=\(activeGymState?.sessionId.uuidString ?? "none")")
        } catch {
            PulsarSyncDebugLogger.log("Active workout applicationContext clear failed reason=\(reason) error=\(error.localizedDescription)")
        }
    }

    private func sendGymStateToCounterpart(_ state: ActiveGymWorkoutState) {
        guard let session = counterpartSession(for: "Active Gym state"),
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
        guard let session = counterpartSession(for: "saved Gym routines"),
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
        if let latestWatchHeartbeat,
           let data = try? JSONEncoder().encode(latestWatchHeartbeat) {
            applicationContext[Self.watchHeartbeatPayloadKey] = data
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
        guard let session = counterpartSession(for: "Apple Watch battery") else { return }
        let payload = Self.appleWatchBatteryMessage(from: snapshot)

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                PulsarSyncDebugLogger.log("Apple Watch battery sendMessage failed error=\(error.localizedDescription)")
            }
        }

        session.transferUserInfo(payload)
        PulsarSyncDebugLogger.log("Apple Watch battery queued for transfer percentage=\(snapshot.batteryPercentage)")
    }

    private func sendWatchHeartbeatToCounterpart(_ heartbeat: AppleWatchHeartbeatSnapshot, reason: String) {
        guard let session = counterpartSession(for: "Watch heartbeat"),
              let data = try? JSONEncoder().encode(heartbeat) else { return }
        let payload = [Self.watchHeartbeatPayloadKey: data]

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                PulsarSyncDebugLogger.log("Watch heartbeat sendMessage failed reason=\(reason) error=\(error.localizedDescription)")
            }
            PulsarSyncDebugLogger.log("Watch heartbeat sendMessage sent reason=\(reason) reachable=true")
        } else {
            PulsarSyncDebugLogger.log("Watch heartbeat sendMessage skipped reason=\(reason) reachable=false fallback=applicationContext+transferUserInfo")
        }

        var applicationContext = makeApplicationContext(
            metricPayload: latestPayload,
            sleepPreferences: latestSleepPreferences,
            activeWorkoutState: activeWorkoutState,
            activeGymState: activeGymState,
            savedGymRoutines: savedGymRoutines
        )
        applicationContext[Self.watchHeartbeatPayloadKey] = data
        do {
            try session.updateApplicationContext(applicationContext)
            PulsarSyncDebugLogger.log("Watch heartbeat applicationContext updated reason=\(reason)")
        } catch {
            PulsarSyncDebugLogger.log("Watch heartbeat applicationContext failed reason=\(reason) error=\(error.localizedDescription)")
        }
        session.transferUserInfo(payload)
        PulsarSyncDebugLogger.log("Watch heartbeat transferUserInfo queued reason=\(reason)")
    }

    private func sendActiveWorkoutStateToCounterpart(_ state: PulsarActiveWorkoutSyncState, reason: String) {
        guard let session = counterpartSession(for: "Active workout state"),
              let data = Self.encodeActiveWorkoutState(state) else { return }
        let payload = [Self.activeWorkoutStatePayloadKey: data]
        let isLiveMetricsUpdate = state.phase == .active || state.phase == .resumed || state.phase == .paused

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                PulsarSyncDebugLogger.log("Active workout sendMessage failed session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) phase=\(state.phase.rawValue) error=\(error.localizedDescription)")
            }
            PulsarSyncDebugLogger.log("Active workout sendMessage sent session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) phase=\(state.phase.rawValue) reason=\(reason) reachable=true distanceMeters=\(state.distanceMeters ?? -1) elapsedSeconds=\(state.elapsedSeconds) movingSeconds=\(state.movingSeconds ?? -1) pace=\(state.currentPaceSecondsPerKilometer ?? -1) calories=\(state.activeEnergyKilocalories ?? -1) heartRate=\(state.currentHeartRate ?? -1) sampleTimestamp=\(state.runMetricsUpdatedAt?.description ?? "none")")
        } else {
            PulsarSyncDebugLogger.log("Active workout sendMessage skipped session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) phase=\(state.phase.rawValue) reason=\(reason) reachable=false fallback=transferUserInfo")
        }

        let applicationContext = makeApplicationContext(
            metricPayload: latestPayload,
            sleepPreferences: latestSleepPreferences,
            activeWorkoutState: state,
            activeGymState: activeGymState,
            savedGymRoutines: savedGymRoutines
        )

        if isLiveMetricsUpdate {
            let now = Date()
            if now.timeIntervalSince(lastActiveWorkoutLiveApplicationContextAt) >= 2 {
                lastActiveWorkoutLiveApplicationContextAt = now
                do {
                    try session.updateApplicationContext(applicationContext)
                    PulsarSyncDebugLogger.log("Active workout live applicationContext updated session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) phase=\(state.phase.rawValue) reason=\(reason)")
                } catch {
                    PulsarSyncDebugLogger.log("Active workout live applicationContext failed session=\(state.sessionId.uuidString) error=\(error.localizedDescription)")
                }
            }
            guard now.timeIntervalSince(lastActiveWorkoutLiveTransferAt) >= 10 else {
                PulsarSyncDebugLogger.log("Active workout live transfer throttled session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) phase=\(state.phase.rawValue) reason=\(reason)")
                return
            }
            lastActiveWorkoutLiveTransferAt = now
            session.transferUserInfo(payload)
            PulsarSyncDebugLogger.log("Active workout live transferUserInfo queued session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) phase=\(state.phase.rawValue) reason=\(reason) distanceMeters=\(state.distanceMeters ?? -1) elapsedSeconds=\(state.elapsedSeconds) movingSeconds=\(state.movingSeconds ?? -1) sampleTimestamp=\(state.runMetricsUpdatedAt?.description ?? "none")")
            return
        }

        do {
            try session.updateApplicationContext(applicationContext)
            PulsarSyncDebugLogger.log("Active workout applicationContext updated session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) phase=\(state.phase.rawValue)")
        } catch {
            PulsarSyncDebugLogger.log("Active workout applicationContext failed session=\(state.sessionId.uuidString) error=\(error.localizedDescription)")
        }

        session.transferUserInfo(payload)
        PulsarSyncDebugLogger.log("Active workout transferUserInfo queued session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) phase=\(state.phase.rawValue) reason=\(reason)")
    }

    @discardableResult
    private func receive(dictionary: [String: Any], reason: String) -> [ActiveWorkoutUpdateDecision] {
        var didApplyAnyPayload = false
        var activeWorkoutDecisions: [ActiveWorkoutUpdateDecision] = []

        #if os(iOS)
        recordAppleWatchSeen(reason: reason, payloadKind: "watchConnectivity")
        #endif

        if let data = dictionary[Self.watchHeartbeatPayloadKey] as? Data,
           let heartbeat = try? JSONDecoder().decode(AppleWatchHeartbeatSnapshot.self, from: data) {
            didApplyAnyPayload = apply(watchHeartbeat: heartbeat, broadcast: false, reason: reason) || didApplyAnyPayload
        } else if dictionary[Self.watchHeartbeatPayloadKey] != nil {
            PulsarSyncDebugLogger.log("Skipped \(reason) Watch heartbeat because decoding failed")
        }

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
            let decision = apply(activeWorkoutState: state, broadcast: false, reason: reason, isIncomingFromCounterpart: true)
            activeWorkoutDecisions.append(decision)
            didApplyAnyPayload = decision.didApplySyncState || didApplyAnyPayload
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

        return activeWorkoutDecisions
    }

    private func incomingCanFillMissingMetric(_ incoming: PulsarDailyMetricsSyncPayload, current: PulsarDailyMetricsSyncPayload) -> Bool {
        (current.hasCompleteDailyScores == false && incoming.hasCompleteDailyScores) ||
        (current.strain?.isValid != true && incoming.strain?.isValid == true) ||
        (current.recovery?.isValid != true && incoming.recovery?.isValid == true) ||
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
        if let incomingStrain = incoming.strainComputedAt,
           let currentStrain = current.strainComputedAt,
           incomingStrain > currentStrain {
            return true
        }
        if let incomingRecovery = incoming.recoveryComputedAt,
           let currentRecovery = current.recoveryComputedAt,
           incomingRecovery > currentRecovery {
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
    private static let watchHeartbeatPayloadKey = "pulsar.watchHeartbeat.payload.v1"
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

    private static func decodeActiveWorkoutTombstones(_ data: Data?) -> [UUID: Date] {
        guard let data,
              let rawTombstones = try? activeWorkoutDecoder.decode([String: Date].self, from: data) else { return [:] }
        return rawTombstones.reduce(into: [UUID: Date]()) { partialResult, entry in
            guard let sessionID = UUID(uuidString: entry.key) else { return }
            partialResult[sessionID] = entry.value
        }
    }

    private static func encodeActiveWorkoutTombstones(_ tombstones: [UUID: Date]) -> Data? {
        let rawTombstones = Dictionary(
            uniqueKeysWithValues: tombstones.map { ($0.key.uuidString, $0.value) }
        )
        return try? activeWorkoutEncoder.encode(rawTombstones)
    }

    private static func prunedActiveWorkoutTombstones(
        _ tombstones: [UUID: Date],
        now: Date = Date()
    ) -> [UUID: Date] {
        tombstones.filter { now.timeIntervalSince($0.value) <= activeWorkoutTombstoneInterval }
    }

    private static func isActiveWorkoutSessionTombstoned(
        _ sessionID: UUID,
        tombstones: [UUID: Date],
        now: Date = Date()
    ) -> Bool {
        guard let tombstonedAt = tombstones[sessionID] else { return false }
        return now.timeIntervalSince(tombstonedAt) <= activeWorkoutTombstoneInterval
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

    private func rememberTerminatedActiveWorkoutSession(_ sessionID: UUID, reason: String) {
        pruneActiveWorkoutTombstones()
        let previous = locallyTerminatedActiveWorkoutSessions[sessionID]
        locallyTerminatedActiveWorkoutSessions[sessionID] = Date()
        persistActiveWorkoutTombstones()
        if previous == nil {
            PulsarSyncDebugLogger.log("Tombstoned active workout session reason=\(reason) session=\(sessionID.uuidString)")
        } else {
            PulsarSyncDebugLogger.log("Refreshed active workout tombstone reason=\(reason) session=\(sessionID.uuidString)")
        }
    }

    private func pruneActiveWorkoutTombstones() {
        let pruned = Self.prunedActiveWorkoutTombstones(locallyTerminatedActiveWorkoutSessions)
        guard pruned != locallyTerminatedActiveWorkoutSessions else { return }
        locallyTerminatedActiveWorkoutSessions = pruned
        persistActiveWorkoutTombstones()
    }

    private func persistActiveWorkoutTombstones() {
        if locallyTerminatedActiveWorkoutSessions.isEmpty {
            defaults.removeObject(forKey: activeWorkoutTombstoneCacheKey)
            return
        }
        guard let data = Self.encodeActiveWorkoutTombstones(locallyTerminatedActiveWorkoutSessions) else { return }
        defaults.set(data, forKey: activeWorkoutTombstoneCacheKey)
    }

    private static func isExpiredEndedActiveWorkout(_ state: PulsarActiveWorkoutSyncState) -> Bool {
        state.isEnded && Date().timeIntervalSince(state.updatedAt) > PulsarWorkoutSessionValidity.endedStateRetentionInterval
    }

    private static func isExpiredFinishedGymState(_ state: ActiveGymWorkoutState) -> Bool {
        state.isFinished && Date().timeIntervalSince(state.updatedAt) > PulsarWorkoutSessionValidity.endedStateRetentionInterval
    }

    private static func shouldRestoreCachedActiveWorkoutState(_ state: PulsarActiveWorkoutSyncState) -> Bool {
        guard state.phase != .failed else { return false }
        guard !state.isEnded else { return false }
        guard state.phase.isRestoreEligible else { return false }
        return state.isValidActiveWorkoutPresentationCandidate()
    }

    private static func shouldRestoreCachedActiveGymState(_ state: ActiveGymWorkoutState) -> Bool {
        guard !state.isFinished else { return false }
        return state.isValidActiveWorkoutPresentationCandidate()
    }

    private static func cachedActiveWorkoutRestoreRejectionReason(
        _ state: PulsarActiveWorkoutSyncState,
        isTombstoned: Bool
    ) -> String {
        if isTombstoned { return "tombstoned session" }
        if let reason = state.activeWorkoutPresentationRejectionReason() {
            return reason
        }
        if !state.phase.isRestoreEligible {
            return "phase \(state.phase.rawValue)"
        }
        return "not a valid active session"
    }

    private static func cachedActiveGymRestoreRejectionReason(
        _ state: ActiveGymWorkoutState,
        isTombstoned: Bool
    ) -> String {
        if isTombstoned { return "tombstoned session" }
        if let reason = state.activeWorkoutPresentationRejectionReason() {
            return reason
        }
        return "not a valid active gym session"
    }

    private func makeActiveWorkoutUpdateDecision(
        for incoming: PulsarActiveWorkoutSyncState,
        reason: String,
        isIncomingFromCounterpart: Bool
    ) -> ActiveWorkoutUpdateDecision {
        pruneActiveWorkoutTombstones()
        if incoming.phase.isLive,
           Self.isActiveWorkoutSessionTombstoned(
                incoming.sessionId,
                tombstones: locallyTerminatedActiveWorkoutSessions
           ) {
            PulsarSyncDebugLogger.log("Rejected tombstoned active workout update source=\(reason) session=\(incoming.sessionId.uuidString) phase=\(incoming.phase.rawValue) action=noop")
            return .ignoredHistoricalOnly
        }

        guard !Self.isExpiredEndedActiveWorkout(incoming) else { return .ignoredHistoricalOnly }
        guard incoming.isEnded || incoming.isValidLiveRouteCandidate() else {
            PulsarSyncDebugLogger.log("active workout restore rejected: \(incoming.staleRouteReason() ?? "stale updatedAt") source=\(reason) session=\(incoming.sessionId.uuidString) phase=\(incoming.phase.rawValue)")
            return .ignoredHistoricalOnly
        }
        if incoming.phase == .ending,
           activeWorkoutState?.sessionId != incoming.sessionId,
           currentActiveWorkoutSessionID != incoming.sessionId {
            PulsarSyncDebugLogger.log("Ignored unowned ending active workout update source=\(reason) session=\(incoming.sessionId.uuidString) action=noop")
            return .ignoredHistoricalOnly
        }

        if incoming.phase == .failed {
            return makeFailedActiveWorkoutUpdateDecision(
                for: incoming,
                reason: reason,
                isIncomingFromCounterpart: isIncomingFromCounterpart
            )
        }

        guard let current = activeWorkoutState else {
            return ActiveWorkoutUpdateDecision.appliedDecision(for: incoming)
        }

        if current.sessionId == incoming.sessionId {
            if incoming == current { return .ignoredHistoricalOnly }
            if incoming.isEnded, !current.isEnded {
                guard incoming.updatedAt >= current.updatedAt else {
                    PulsarSyncDebugLogger.log("Ignored stale terminal active workout update source=\(reason) session=\(incoming.sessionId.uuidString) phase=\(incoming.phase.rawValue) incomingUpdatedAt=\(incoming.updatedAt) currentUpdatedAt=\(current.updatedAt) action=noop")
                    return .ignoredHistoricalOnly
                }
                return .endedCurrent(incoming.sessionId)
            }
            guard incoming.updatedAt > current.updatedAt ||
                    (incoming.updatedAt == current.updatedAt && shouldApplySameTimestampActiveWorkoutState(current: current, incoming: incoming)) else {
                PulsarSyncDebugLogger.log("Ignored older duplicate active workout update source=\(reason) session=\(incoming.sessionId.uuidString) incomingPhase=\(incoming.phase.rawValue) currentPhase=\(current.phase.rawValue) action=noop")
                return .ignoredHistoricalOnly
            }
            return ActiveWorkoutUpdateDecision.appliedDecision(for: incoming)
        }

        if current.isEnded {
            if incoming.updatedAt >= current.updatedAt || incoming.phase.isLive {
                return ActiveWorkoutUpdateDecision.appliedDecision(for: incoming)
            }
            return .ignoredHistoricalOnly
        }

        if incoming.isEnded, incoming.startedAt < current.startedAt {
            return .ignoredHistoricalOnly
        }

        if incoming.startedAt >= current.startedAt || incoming.updatedAt >= current.updatedAt {
            return ActiveWorkoutUpdateDecision.appliedDecision(for: incoming)
        }
        return .ignoredHistoricalOnly
    }

    private func canonicalizedActiveWorkoutState(
        _ incoming: PulsarActiveWorkoutSyncState,
        reason: String
    ) -> PulsarActiveWorkoutSyncState {
        guard let current = activeWorkoutState,
              current.sessionId != incoming.sessionId,
              current.startedFrom == .iPhoneRequestedWatchStart,
              current.phase.isLive,
              incoming.startedFrom.isAppleWatchRecorder,
              current.kind == incoming.kind else {
            return incoming
        }

        let startDelta = abs(incoming.startedAt.timeIntervalSince(current.startedAt))
        guard startDelta <= 180 else { return incoming }

        var canonical = incoming
        canonical.sessionId = current.sessionId
        canonical.startedAt = current.startedAt
        canonical.startedFrom = current.startedFrom
        canonical.sessionGeneration = current.sessionGeneration
        PulsarSyncDebugLogger.log("Canonicalized active workout session reason=\(reason) incomingSession=\(incoming.sessionId.uuidString) canonicalSession=\(current.sessionId.uuidString) type=\(incoming.kind.workoutTypeRawValue) currentStartedFrom=\(current.startedFrom.rawValue) incomingStartedFrom=\(incoming.startedFrom.rawValue) startDelta=\(startDelta)")
        return canonical
    }

    private func shouldApplySameTimestampActiveWorkoutState(
        current: PulsarActiveWorkoutSyncState,
        incoming: PulsarActiveWorkoutSyncState
    ) -> Bool {
        if incoming.phase.mergePriority != current.phase.mergePriority {
            return incoming.phase.mergePriority > current.phase.mergePriority
        }
        return activeWorkoutSourcePriority(incoming.lastUpdatedFrom) >= activeWorkoutSourcePriority(current.lastUpdatedFrom)
    }

    private func activeWorkoutSourcePriority(_ source: PulsarWorkoutStartedFrom) -> Int {
        switch source {
        case .appleWatch, .iPhoneRequestedWatchStart:
            2
        case .iPhone:
            1
        }
    }

    private func mergeActiveWorkoutState(
        current: PulsarActiveWorkoutSyncState?,
        incoming: PulsarActiveWorkoutSyncState,
        reason: String
    ) -> PulsarActiveWorkoutSyncState {
        guard let current, current.sessionId == incoming.sessionId else { return incoming }
        guard !incoming.isEnded else { return incoming }
        guard !current.isEnded else { return incoming }

        var merged = incoming
        merged.startedAt = min(current.startedAt, incoming.startedAt)
        if merged.displayName.isEmpty {
            merged.displayName = current.displayName
        }
        if merged.currentHeartRate == nil {
            merged.currentHeartRate = current.currentHeartRate
        }
        if merged.activeEnergyKilocalories == nil {
            merged.activeEnergyKilocalories = current.activeEnergyKilocalories
        }
        if merged.healthKitWorkoutUUID == nil {
            merged.healthKitWorkoutUUID = current.healthKitWorkoutUUID
        }
        if merged.sessionGeneration == nil {
            merged.sessionGeneration = current.sessionGeneration
        }
        if merged.runMetricsUpdatedAt == nil {
            merged.runMetricsUpdatedAt = current.runMetricsUpdatedAt
            merged.movingSeconds = current.movingSeconds
            merged.distanceMeters = current.distanceMeters
            merged.currentPaceSecondsPerKilometer = current.currentPaceSecondsPerKilometer
            merged.averagePaceSecondsPerKilometer = current.averagePaceSecondsPerKilometer
            merged.splitPaceSecondsPerKilometer = current.splitPaceSecondsPerKilometer
            merged.activeSplitIndex = current.activeSplitIndex
            merged.elevationGainMeters = current.elevationGainMeters
            merged.elevationLossMeters = current.elevationLossMeters
            merged.currentElevationMeters = current.currentElevationMeters
            merged.averageHeartRate = current.averageHeartRate
            merged.maxHeartRate = current.maxHeartRate
            merged.stepCount = current.stepCount
            merged.cadenceStepsPerMinute = current.cadenceStepsPerMinute
            merged.routePointCount = current.routePointCount
            merged.lastLatitude = current.lastLatitude
            merged.lastLongitude = current.lastLongitude
            merged.lastLocationUpdatedAt = current.lastLocationUpdatedAt
        }
        return merged
    }

    private func makeFailedActiveWorkoutUpdateDecision(
        for incoming: PulsarActiveWorkoutSyncState,
        reason: String,
        isIncomingFromCounterpart: Bool
    ) -> ActiveWorkoutUpdateDecision {
        let priorCurrentSessionID = currentActiveWorkoutSessionID
        let priorCurrentWorkoutCanShowConnectionLostAlert = currentActiveWorkoutCanShowConnectionLostAlert
        let priorSyncedSessionID = activeWorkoutState?.sessionId
        PulsarSyncDebugLogger.log("Incoming failed update source=\(reason) failedSession=\(incoming.sessionId.uuidString) priorCurrentSession=\(priorCurrentSessionID?.uuidString ?? "none") alertEligible=\(priorCurrentWorkoutCanShowConnectionLostAlert)")

        let decision = ActiveWorkoutUpdateDecision.syncStoreFailedDecision(
            for: incoming,
            priorCurrentSessionID: priorCurrentSessionID,
            priorCurrentWorkoutCanShowConnectionLostAlert: priorCurrentWorkoutCanShowConnectionLostAlert,
            priorSyncedSessionID: priorSyncedSessionID,
            ignoredFailedSessionIDs: ignoredFailedWorkoutSessionIDs,
            isIncomingFromCounterpart: isIncomingFromCounterpart
        )

        switch decision {
        case .ignoredDuplicateStaleFailed:
            PulsarSyncDebugLogger.log("Duplicate stale failed session ignored session=\(incoming.sessionId.uuidString) action=noop")
            return decision
        case .ignoredStaleFailed:
            ignoredFailedWorkoutSessionIDs.insert(incoming.sessionId)
            if let priorCurrentSessionID {
                PulsarSyncDebugLogger.log("Ignored stale failed workout update failedSession=\(incoming.sessionId.uuidString) currentSession=\(priorCurrentSessionID.uuidString) alertEligible=\(priorCurrentWorkoutCanShowConnectionLostAlert) action=noop")
            } else {
                PulsarSyncDebugLogger.log("Ignored stale failed workout because there is no current active session failedSession=\(incoming.sessionId.uuidString)")
            }
            PulsarSyncDebugLogger.log("Rejected failed update before activeWorkout mutation failedSession=\(incoming.sessionId.uuidString) action=noop")
            PulsarSyncDebugLogger.log("Cached ignored failed session session=\(incoming.sessionId.uuidString)")
            return decision
        case .failedCurrentAndShouldAlert:
            PulsarSyncDebugLogger.log("Current active workout failed session=\(incoming.sessionId.uuidString) action=clearAndAlert")
            return decision
        case .appliedActive, .appliedPaused, .endedCurrent, .ignoredInvalidNoSession, .ignoredHistoricalOnly:
            return decision
        }
    }

    private func shouldApply(activeGymState incoming: ActiveGymWorkoutState) -> Bool {
        guard !Self.isExpiredFinishedGymState(incoming) else { return false }
        pruneActiveWorkoutTombstones()
        if !incoming.isFinished,
           Self.isActiveWorkoutSessionTombstoned(
                incoming.sessionId,
                tombstones: locallyTerminatedActiveWorkoutSessions
           ) {
            PulsarSyncDebugLogger.log("Rejected tombstoned Active Gym update source=activeGymState session=\(incoming.sessionId.uuidString) action=noop")
            return false
        }
        guard incoming.isFinished || incoming.isValidActiveWorkoutPresentationCandidate() else {
            PulsarSyncDebugLogger.log("active workout restore rejected: \(incoming.activeWorkoutPresentationRejectionReason() ?? incoming.staleRouteReason() ?? "invalid active gym state") session=\(incoming.sessionId.uuidString)")
            return false
        }
        guard let current = activeGymState else { return true }

        if current.sessionId == incoming.sessionId {
            if current.isFinished, !incoming.isFinished {
                PulsarSyncDebugLogger.log("Rejected live Active Gym update for finished session session=\(incoming.sessionId.uuidString) incomingUpdatedAt=\(incoming.updatedAt) currentUpdatedAt=\(current.updatedAt) action=noop")
                return false
            }
            if incoming.isFinished, !current.isFinished { return true }
            return incoming.updatedAt >= current.updatedAt
        }

        if current.isFinished {
            return incoming.updatedAt >= current.updatedAt || incoming.isValidActiveWorkoutPresentationCandidate()
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
        Task { @MainActor in
            self.lastActivationErrorMessage = error?.localizedDescription
            _ = self.watchRecorderAvailabilitySnapshot(reason: "activationDidComplete")
        }
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
        guard !userInfo.isEmpty else {
            PulsarSyncDebugLogger.log("Skipped receivedUserInfo because payload was empty")
            return
        }

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
