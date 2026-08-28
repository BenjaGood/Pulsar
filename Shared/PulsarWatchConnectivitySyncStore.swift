import Combine
import Foundation
import HealthKit
import OSLog
import WatchConnectivity
#if os(watchOS)
import WatchKit
#endif

struct AppleWatchBatterySnapshot: nonisolated Codable, Equatable, Sendable {
    var batteryPercentage: Int
    var timestamp: Date
}

struct AppleWatchHeartbeatSnapshot: nonisolated Codable, Equatable, Sendable {
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
        rawIsWatchAppInstalled
    }

    var isReachable: Bool {
        rawIsReachable
    }

    /// HealthKit can wake the Watch app independently of an interactive
    /// WatchConnectivity session. Use this for the Watch-first launch decision.
    var canAttemptWatchAppLaunch: Bool {
        isSupported &&
            activationStateRawValue == WCSessionActivationState.activated.rawValue &&
            isPaired &&
            isWatchAppInstalled
    }

    /// `isReachable` is useful for choosing a real-time transport, but must
    /// never prevent a HealthKit Watch-app launch attempt.
    var isWatchInteractivelyReachable: Bool {
        isReachable
    }

    /// Diagnostic-only signal; must not promote current installation/reachability.
    var hasDiagnosticRecentWatchHeartbeat: Bool {
        hasRecentWatchHeartbeat
    }

    var derivedReachabilityDescription: String {
        if rawIsReachable { return "rawReachable" }
        if hasRecentWatchHeartbeat { return "recentHeartbeatDiagnosticOnly" }
        return "notReachable"
    }

    var canStartOnWatch: Bool {
        canAttemptWatchAppLaunch && isWatchInteractivelyReachable
    }

    var fallbackReason: PulsarWatchRecorderFallbackReason? {
        guard isSupported else { return .unsupported }
        guard activationStateRawValue == WCSessionActivationState.activated.rawValue else { return .activationPending }
        guard isPaired else { return .noPairedWatch }
        guard isWatchAppInstalled else {
            return hasEverReceivedWatchPayload ? .notReachable : .watchAppNotInstalled
        }
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
    @Published private(set) var lastFinishedGymState: ActiveGymWorkoutState?
    @Published private(set) var lastConfirmedGymFinish: GymWorkoutFinishConfirmation?
    @Published private(set) var savedGymRoutines: [WatchGymRoutinePlan]
    @Published private(set) var savedGymRoutinesRevision: Int
    @Published private(set) var lastWatchRecorderAvailability: PulsarWatchRecorderAvailabilitySnapshot?
    @Published private(set) var lastWatchSeenAt: Date?
    @Published private(set) var hasEverReceivedWatchPayload: Bool
    @Published private(set) var latestWatchHeartbeat: AppleWatchHeartbeatSnapshot?
    @Published private(set) var sourceCacheRevision: Int = 0

    /// Unverified Watch launch state retained only long enough to correlate an
    /// existing HealthKit recovery. It is never published and cannot authorize
    /// creation of a new `HKWorkoutSession`.
    private(set) var gymRestorationCandidate: ActiveGymWorkoutState?
    private(set) var restoredActiveWorkoutCandidate: PulsarActiveWorkoutSyncState?

    private let defaults: UserDefaults
    private let payloadFileCache: PulsarSyncPayloadFileCache
    private let codecActor = PulsarWatchConnectivityCodecActor.shared
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
    private let savedGymRoutinesRevisionCacheKey = "pulsar.sync.savedGymRoutines.revision.v1"
    private let lastWatchSeenAtCacheKey = "pulsar.sync.lastWatchSeenAt.v1"
    private let hasEverReceivedWatchPayloadCacheKey = "pulsar.sync.hasEverReceivedWatchPayload.v1"
    private let watchHeartbeatCacheKey = "pulsar.sync.watchHeartbeat.v1"
    private static let activeWorkoutTombstoneRetentionLimit = 512
    private static let watchSeenPublishInterval: TimeInterval = 30
    #if os(watchOS)
    nonisolated static let dailyCacheRetentionLimit = 14
    #else
    nonisolated static let dailyCacheRetentionLimit = 120
    #endif
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
    private var gymStartAcknowledgementHandler: ((GymWorkoutStartAcknowledgement, String) -> Void)?
    private var gymRoutineSnapshotHandler: ((GymRoutineSnapshotEnvelope, String) -> Void)?
    private var runTransportEnvelopeHandler: ((PulsarRunTransportEnvelope, String) -> Void)?
    private var lastActivationErrorMessage: String?
    private var lastActiveWorkoutLiveApplicationContextAt = Date.distantPast
    private var lastActiveGymLiveApplicationContextAt = Date.distantPast
    private var pendingActiveGymPersistence: ActiveGymWorkoutState?
    private var activeGymPersistenceTask: Task<Void, Never>?
    private var activeGymPersistenceGeneration = 0
    private var lastPersistedGymFingerprint: String?
    private var lastTransmittedGymFingerprint: String?
    private var activeWorkoutPersistenceGeneration = 0
    private var recentTerminalActiveWorkoutState: PulsarActiveWorkoutSyncState?
    private var recentTerminalGymState: ActiveGymWorkoutState?
    private var committedTerminalGymSessionID: UUID?
    private var pendingGymFinishHealthKitSessionStateRawValue: Int?
    private var terminalGymPersistenceTask: Task<Void, Never>?
    private(set) var lastGymTerminalCommit: PulsarGymTerminalCommitRecord?
    private(set) var acceptedGymTerminalCount = 0
    private(set) var rejectedGymTerminalCount = 0
    private var receivedWorkoutSyncMessageIDs = Set<String>()
    private var handledGymActionIDs = Set<UUID>()
    private var payloadFilePersistenceRevision: UInt64 = 0
    private var deferredNonWorkoutReceiveTask: Task<Void, Never>?
    private var pendingDeferredNonWorkoutPayloads: [(payload: PulsarWatchConnectivityDecodedPayload, reason: String)] = []
    private var lastQueuedSavedGymRoutinesRevision: Int?
    private var lastQueuedSavedGymRoutinesData: Data?
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

    nonisolated static func retainedDailyPayloads(
        _ cache: [String: PulsarDailyMetricsSyncPayload],
        limit: Int = dailyCacheRetentionLimit
    ) -> [String: PulsarDailyMetricsSyncPayload] {
        guard limit > 0, cache.count > limit else { return limit > 0 ? cache : [:] }
        return Dictionary(
            uniqueKeysWithValues: cache
                .sorted { lhs, rhs in
                    if lhs.value.date == rhs.value.date { return lhs.key > rhs.key }
                    return lhs.value.date > rhs.value.date
                }
                .prefix(limit)
                .map { ($0.key, $0.value) }
        )
    }

    nonisolated static func retainedSourcePayloads(
        _ cache: [String: [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload]],
        limit: Int = dailyCacheRetentionLimit
    ) -> [String: [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload]] {
        guard limit > 0, cache.count > limit else { return limit > 0 ? cache : [:] }
        return Dictionary(
            uniqueKeysWithValues: cache
                .sorted { lhs, rhs in
                    let lhsDate = lhs.value.values.map(\.date).max() ?? .distantPast
                    let rhsDate = rhs.value.values.map(\.date).max() ?? .distantPast
                    if lhsDate == rhsDate { return lhs.key > rhs.key }
                    return lhsDate > rhsDate
                }
                .prefix(limit)
                .map { ($0.key, $0.value) }
        )
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
        let payloadFileCache = PulsarSyncPayloadFileCache.shared
        self.payloadFileCache = payloadFileCache
        self.session = WCSession.isSupported() ? WCSession.default : nil
        let latestPayloadData = payloadFileCache.migrateLegacyData(
            from: defaults,
            key: cacheKey,
            to: .latestPayload,
            validating: { data in
                PulsarSyncPayloadCodec.decode(data: data)?.isValidPayload == true
            }
        )
        let dailyPayloadData = payloadFileCache.migrateLegacyData(
            from: defaults,
            key: dailyCacheKey,
            to: .dailyPayloads,
            validating: { data in
                (try? JSONDecoder().decode([String: PulsarDailyMetricsSyncPayload].self, from: data)) != nil
            }
        )
        let sleepPayloadData = payloadFileCache.migrateLegacyData(
            from: defaults,
            key: sleepCacheKey,
            to: .sleepPayloads,
            validating: { data in
                (try? JSONDecoder().decode([String: PulsarDailyMetricsSyncPayload].self, from: data)) != nil
            }
        )
        let sourceDailyPayloadData = payloadFileCache.migrateLegacyData(
            from: defaults,
            key: sourceDailyCacheKey,
            to: .sourceDailyPayloads,
            validating: { data in
                (try? JSONDecoder().decode(
                    [String: [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload]].self,
                    from: data
                )) != nil
            }
        )
        let sourceSleepPayloadData = payloadFileCache.migrateLegacyData(
            from: defaults,
            key: sourceSleepCacheKey,
            to: .sourceSleepPayloads,
            validating: { data in
                (try? JSONDecoder().decode(
                    [String: [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload]].self,
                    from: data
                )) != nil
            }
        )
        let savedGymRoutinesData = payloadFileCache.migrateLegacyData(
            from: defaults,
            key: savedGymRoutinesCacheKey,
            to: .savedGymRoutines,
            validating: { SavedGymRoutinesSyncCodec.decode($0) != nil }
        )
        let restoredTerminatedActiveWorkoutSessions = Self.prunedActiveWorkoutTombstones(
            Self.decodeActiveWorkoutTombstones(defaults.data(forKey: activeWorkoutTombstoneCacheKey))
        )
        self.locallyTerminatedActiveWorkoutSessions = restoredTerminatedActiveWorkoutSessions
        if let data = dailyPayloadData,
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
        if let data = sleepPayloadData,
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
            sourceDailyPayloadData,
            fallbackPayloads: self.dailyPayloadsByDateKey,
            isUsable: { $0.hasCompleteDailyScores || $0.hasValidStrain || $0.hasValidRecovery || $0.hasValidStress || $0.hasValidHealthMonitor }
        )
        self.sourceSleepPayloadsByDateKey = Self.decodeSourcePayloadCache(
            sourceSleepPayloadData,
            fallbackPayloads: self.sleepPayloadsByDateKey,
            isUsable: { $0.sleep?.isValid == true }
        )
        if let data = latestPayloadData,
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
        if let data = defaults.data(forKey: activeWorkoutCacheKey),
           let state = Self.decodeActiveWorkoutState(data) {
            let isTombstoned = Self.isActiveWorkoutSessionTombstoned(
                state.sessionId,
                tombstones: restoredTerminatedActiveWorkoutSessions
            )
            if Self.shouldRestoreCachedActiveWorkoutState(state), !isTombstoned {
                self.activeWorkoutState = nil
                self.restoredActiveWorkoutCandidate = state
                defaults.removeObject(forKey: activeWorkoutCacheKey)
                PulsarWorkoutStartupTrace.lifecycle(
                    "[WorkoutRestore] workoutID=\(state.sessionId.uuidString) phase=\(state.phase.rawValue) source=UserDefaults decision=candidate"
                )
            } else {
                self.activeWorkoutState = nil
                self.restoredActiveWorkoutCandidate = nil
                defaults.removeObject(forKey: activeWorkoutCacheKey)
                PulsarSyncDebugLogger.log("active workout restore rejected: \(Self.cachedActiveWorkoutRestoreRejectionReason(state, isTombstoned: isTombstoned)) session=\(state.sessionId.uuidString)")
                PulsarSyncDebugLogger.log("active workout state cleared on launch session=\(state.sessionId.uuidString)")
            }
        } else {
            self.activeWorkoutState = nil
            self.restoredActiveWorkoutCandidate = nil
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
            if PulsarWatchSynchronizedGymReconciliation.shouldRestoreCachedActiveGym(
                state,
                platform: Self.synchronizedGymPlatform,
                isTombstoned: isTombstoned
            ) {
                // Kept for source compatibility if platform policy changes,
                // but persisted presentation state is never published here.
                self.activeGymState = nil
                self.gymRestorationCandidate = state
                defaults.removeObject(forKey: activeGymCacheKey)
            } else {
                self.activeGymState = nil
                let retainsRecoveryCandidate =
                    !isTombstoned &&
                    !state.isFinished &&
                    state.isValidActiveWorkoutPresentationCandidate()
                self.gymRestorationCandidate = retainsRecoveryCandidate ? state : nil
                defaults.removeObject(forKey: activeGymCacheKey)
                PulsarWorkoutStartupTrace.lifecycle(
                    "[GymRestore] workoutID=\(state.sessionId.uuidString) phase=\(state.isFinished ? "finished" : "active") revision=\(state.lifecycleGeneration ?? 0) source=UserDefaults decision=\(retainsRecoveryCandidate ? "candidate" : "stale")"
                )
                if !retainsRecoveryCandidate {
                    PulsarSyncDebugLogger.log("active workout restore rejected: \(Self.cachedActiveGymRestoreRejectionReason(state, isTombstoned: isTombstoned)) session=\(state.sessionId.uuidString)")
                    PulsarSyncDebugLogger.log("active workout state cleared on launch session=\(state.sessionId.uuidString)")
                }
            }
        } else {
            self.activeGymState = nil
            self.gymRestorationCandidate = nil
            if defaults.data(forKey: activeGymCacheKey) != nil {
                PulsarSyncDebugLogger.log("active workout restore rejected: active gym decode failed")
                PulsarSyncDebugLogger.log("active workout state cleared on launch session=unknown")
            }
            defaults.removeObject(forKey: activeGymCacheKey)
        }
        let restoredSavedGymRoutinesRevision = max(0, defaults.integer(forKey: savedGymRoutinesRevisionCacheKey))
        if let data = savedGymRoutinesData,
           let payload = SavedGymRoutinesSyncCodec.decode(data) {
            self.savedGymRoutines = payload.routines.sorted { $0.updatedAt > $1.updatedAt }
            self.savedGymRoutinesRevision = max(restoredSavedGymRoutinesRevision, payload.revision)
        } else {
            self.savedGymRoutines = []
            self.savedGymRoutinesRevision = restoredSavedGymRoutinesRevision
        }
        super.init()
        #if os(iOS)
        // Candidates loaded from disk have no runtime authority on iPhone.
        // Quarantine them only long enough to diagnose the restore, then discard
        // before any observer can treat them as a live workout.
        discardRestoredWorkoutCandidates(reason: "startupPersistedStateHasNoRuntimeAuthority")
        #endif
        pruneDailyCaches()
        if let latestPayload {
            persist(latestPayload)
        } else {
            removePayloadFileCacheEntry(.latestPayload)
        }
        persistDailyPayloadCache()
        persistSleepPayloadCache()
        persistSourcePayloadCache(sourceDailyPayloadsByDateKey, entry: .sourceDailyPayloads)
        persistSourcePayloadCache(sourceSleepPayloadsByDateKey, entry: .sourceSleepPayloads)
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
            removePayloadFileCacheEntry(.latestPayload)
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
            persistSourcePayloadCache(sourceDailyPayloadsByDateKey, entry: .sourceDailyPayloads)
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
            persistSourcePayloadCache(sourceSleepPayloadsByDateKey, entry: .sourceSleepPayloads)
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
        let hasLiveWorkout = (activeGymState?.isFinished == false) || (activeWorkoutState?.phase.isLive == true)
        if hasLiveWorkout {
            PulsarSyncDebugLogger.log("Watch heartbeat skipped because live workout already proves liveness reason=\(reason)")
            return
        }
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
        let previousTimestamp = lastWatchSeenAt
        let resolvedTimestamp = max(timestamp, previousTimestamp ?? .distantPast)
        let wasFirstPayload = !hasEverReceivedWatchPayload
        if !wasFirstPayload,
           let previousTimestamp,
           resolvedTimestamp.timeIntervalSince(previousTimestamp) < Self.watchSeenPublishInterval {
            return
        }
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

    func waitForWatchAppLaunchAvailability(
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

        while !latest.canAttemptWatchAppLaunch && Date() < deadline {
            let remaining = deadline.timeIntervalSinceNow
            let sleepSeconds = min(max(0.05, pollIntervalSeconds), max(0.05, remaining))
            try? await Task.sleep(for: .seconds(sleepSeconds))
            latest = watchRecorderAvailabilitySnapshot(reason: "\(reason).retry")
            guard latest.fallbackReason != .unsupported,
                  latest.fallbackReason != .noPairedWatch,
                  latest.fallbackReason != .watchAppNotInstalled else {
                return latest
            }
        }

        PulsarSyncDebugLogger.log("Watch recorder preflight completed reason=\(reason) canAttemptLaunch=\(latest.canAttemptWatchAppLaunch) interactiveReachable=\(latest.isWatchInteractivelyReachable) activation=\(latest.activationStateDescription) paired=\(latest.isPaired) rawInstalled=\(latest.rawIsWatchAppInstalled) rawReachable=\(latest.rawIsReachable) lastWatchSeenAt=\(latest.lastWatchSeenAt?.description ?? "none") fallback=\(latest.fallbackReason?.logValue ?? "none")")
        return latest
    }

    /// Backwards-compatible spelling for call sites outside the workout flows.
    func waitForReachableWatchRecorder(
        reason: String,
        timeoutSeconds: TimeInterval = 2.0,
        pollIntervalSeconds: TimeInterval = 0.25
    ) async -> PulsarWatchRecorderAvailabilitySnapshot {
        await waitForWatchAppLaunchAvailability(
            reason: reason,
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds
        )
    }

    func hydrateReceivedApplicationContext(reason: String) {
        activateSessionIfNeeded()
        guard let session,
              session.activationState == .activated,
              !session.receivedApplicationContext.isEmpty else { return }
        let snapshot = PulsarWatchConnectivityIncomingSnapshot(
            dictionary: session.receivedApplicationContext
        )
        Task { [weak self] in
            await self?.decodeAndReceive(snapshot, reason: "activationHydration.\(reason)")
        }
    }

    @discardableResult
    func requestSavedGymRoutinesRefresh(reason: String) -> Bool {
        sendGymAction(.requestSavedRoutines())
    }

    func registerGymStartAcknowledgementHandler(_ handler: @escaping (GymWorkoutStartAcknowledgement, String) -> Void) {
        gymStartAcknowledgementHandler = handler
    }

    func registerGymRoutineSnapshotHandler(_ handler: @escaping (GymRoutineSnapshotEnvelope, String) -> Void) {
        gymRoutineSnapshotHandler = handler
    }

    @discardableResult
    func sendGymStartPrelaunchHint(_ request: GymWorkoutStartRequest, reason: String) -> Bool {
        activateSessionIfNeeded()
        guard let session = counterpartSession(for: "Gym prelaunch hint") else { return false }
        var message = request.compactPrelaunchHint
        message[Self.gymCrossDeviceMessageTypeKey] = Self.gymStartPrelaunchHintMessageType
        logOutstandingUserInfoTransfers(context: "prelaunchHint.\(reason)")
        if session.isReachable {
            let messageID = UUID()
            PulsarWatchConnectivitySendTrace.logSend(
                messageType: Self.gymStartPrelaunchHintMessageType,
                messageID: messageID,
                workoutID: request.candidateSessionID,
                requestID: request.requestID,
                source: reason,
                attempt: 1,
                reachable: true
            )
            session.sendMessage(message, replyHandler: nil) { error in
                PulsarWatchConnectivitySendTrace.logFailure(
                    messageType: Self.gymStartPrelaunchHintMessageType,
                    messageID: messageID,
                    workoutID: request.candidateSessionID,
                    requestID: request.requestID,
                    source: reason,
                    attempt: 1,
                    error: error
                )
                PulsarSyncDebugLogger.log("Gym prelaunch hint send failed request=\(request.requestID.uuidString) error=\(error.localizedDescription)")
            }
            PulsarWorkoutLifecycleLogger.log(
                .wcSend,
                sessionID: request.candidateSessionID,
                requestID: request.requestID,
                source: reason,
                messageType: Self.gymStartPrelaunchHintMessageType,
                transport: "sendMessage"
            )
        } else {
            session.transferUserInfo(message)
            PulsarWorkoutLifecycleLogger.log(
                .watchPrelaunchDurablyQueued,
                sessionID: request.candidateSessionID,
                requestID: request.requestID,
                source: reason,
                messageType: Self.gymStartPrelaunchHintMessageType,
                transport: "transferUserInfo"
            )
            PulsarSyncDebugLogger.log("Gym prelaunch hint queued durably while watch is not reachable request=\(request.requestID.uuidString)")
        }
        return true
    }

    @discardableResult
    func sendGymStartAcknowledgement(_ acknowledgement: GymWorkoutStartAcknowledgement, reason: String) -> Bool {
        activateSessionIfNeeded()
        guard let session = counterpartSession(for: "Gym start acknowledgement"),
              let data = GymCrossDeviceCodec.encodeAcknowledgement(acknowledgement) else { return false }
        let message: [String: Any] = [
            Self.gymCrossDeviceMessageTypeKey: Self.gymStartAcknowledgementMessageType,
            GymCrossDevicePayloadKey.acknowledgement: data
        ]
        logOutstandingUserInfoTransfers(context: "gymStartAck.\(reason)")
        if session.isReachable {
            let messageID = UUID()
            PulsarWatchConnectivitySendTrace.logSend(
                messageType: Self.gymStartAcknowledgementMessageType,
                messageID: messageID,
                workoutID: acknowledgement.authoritativeSessionID,
                requestID: acknowledgement.requestID,
                source: reason,
                attempt: 1,
                reachable: true
            )
            session.sendMessage(message, replyHandler: nil) { error in
                PulsarWatchConnectivitySendTrace.logFailure(
                    messageType: Self.gymStartAcknowledgementMessageType,
                    messageID: messageID,
                    workoutID: acknowledgement.authoritativeSessionID,
                    requestID: acknowledgement.requestID,
                    source: reason,
                    attempt: 1,
                    error: error
                )
                PulsarSyncDebugLogger.log("Gym start acknowledgement sendMessage failed request=\(acknowledgement.requestID.uuidString) error=\(error.localizedDescription)")
            }
            PulsarWorkoutLifecycleLogger.log(
                .wcSend,
                sessionID: acknowledgement.authoritativeSessionID,
                requestID: acknowledgement.requestID,
                source: reason,
                messageType: Self.gymStartAcknowledgementMessageType,
                transport: "sendMessage"
            )
        } else {
            session.transferUserInfo(message)
            PulsarWorkoutLifecycleLogger.log(
                .watchPrelaunchDurablyQueued,
                sessionID: acknowledgement.authoritativeSessionID,
                requestID: acknowledgement.requestID,
                source: reason,
                messageType: Self.gymStartAcknowledgementMessageType,
                transport: "transferUserInfo"
            )
        }
        return true
    }

    @discardableResult
    func transferGymRoutineSnapshot(_ envelope: GymRoutineSnapshotEnvelope, reason: String) -> Bool {
        activateSessionIfNeeded()
        guard let session = counterpartSession(for: "Gym routine snapshot"),
              let data = GymCrossDeviceCodec.encodeRoutineSnapshot(envelope) else { return false }
        PulsarSyncDebugLogger.log(
            "[PulsarRoutineSync] source=encodedRoutineSnapshot routineID=\(envelope.routineID.uuidString) name=\(envelope.routinePlan.name) exerciseCount=\(envelope.routinePlan.exercises.count) totalSetCount=\(envelope.routinePlan.totalSetCount) revision=\(envelope.revision) bytes=\(data.count)"
        )
        let payload: [String: Any] = [
            Self.gymCrossDeviceMessageTypeKey: Self.gymRoutineSnapshotMessageType,
            GymCrossDevicePayloadKey.routineSnapshot: data
        ]
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                PulsarSyncDebugLogger.log(
                    "Gym routine snapshot realtime send failed request=\(envelope.requestID.uuidString) error=\(error.localizedDescription)"
                )
            }
            PulsarWorkoutLifecycleLogger.log(
                .wcSend,
                sessionID: envelope.sessionID,
                requestID: envelope.requestID,
                source: reason,
                messageType: Self.gymRoutineSnapshotMessageType,
                transport: "sendMessage"
            )
        }
        let outstandingPayloads = session.outstandingUserInfoTransfers.compactMap { transfer in
            transfer.userInfo[GymCrossDevicePayloadKey.routineSnapshot] as? Data
        }
        if !Self.shouldQueueGymRoutineSnapshotPayload(
            requestID: envelope.requestID,
            checksum: envelope.checksum,
            outstandingPayloads: outstandingPayloads
        ) {
            PulsarSyncDebugLogger.log(
                "Gym start metadata durable queue skipped duplicate request=\(envelope.requestID.uuidString) checksum=\(envelope.checksum)"
            )
        } else {
            session.transferUserInfo(payload)
            logOutstandingUserInfoTransfers(context: "routineSnapshot.\(reason)")
            PulsarWorkoutLifecycleLogger.log(
                .wcSend,
                sessionID: envelope.sessionID,
                requestID: envelope.requestID,
                source: reason,
                messageType: Self.gymRoutineSnapshotMessageType,
                transport: "transferUserInfo"
            )
        }
        return true
    }

    static func shouldQueueGymRoutineSnapshotPayload(
        requestID: UUID,
        checksum: String,
        outstandingPayloads: [Data]
    ) -> Bool {
        !outstandingPayloads.contains { data in
            guard let outstanding = GymCrossDeviceCodec.decodeRoutineSnapshot(data) else {
                return false
            }
            return outstanding.requestID == requestID && outstanding.checksum == checksum
        }
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

    func clearFinishedGymPresentationState(sessionID: UUID, reason: String) {
        var didClear = false
        if lastFinishedGymState?.sessionId == sessionID {
            lastFinishedGymState = nil
            didClear = true
        }
        if recentTerminalGymState?.sessionId == sessionID {
            recentTerminalGymState = nil
            didClear = true
        }
        if recentTerminalActiveWorkoutState?.sessionId == sessionID {
            recentTerminalActiveWorkoutState = nil
            didClear = true
        }
        if lastConfirmedGymFinish?.sessionID == sessionID {
            lastConfirmedGymFinish = nil
            didClear = true
        }
        if activeGymState?.sessionId == sessionID, activeGymState?.isFinished == true {
            activeGymState = nil
            defaults.removeObject(forKey: activeGymCacheKey)
            didClear = true
        }
        if activeWorkoutState?.sessionId == sessionID, activeWorkoutState?.isEnded == true {
            activeWorkoutState = nil
            defaults.removeObject(forKey: activeWorkoutCacheKey)
            didClear = true
        }
        guard didClear else { return }
        PulsarSyncDebugLogger.log("Finished gym presentation state cleared reason=\(reason) session=\(sessionID.uuidString)")
        publishCurrentApplicationContext(reason: "\(reason).finishedGymPresentationCleared")
    }

    func hasConfirmedGymFinish(sessionID: UUID) -> Bool {
        lastConfirmedGymFinish?.sessionID == sessionID
    }

    /// Publishes mirrored HealthKit terminal evidence before the runtime mirror
    /// is released. A stopped/ended mirrored session is successful completion,
    /// not a missing active connection.
    func confirmGymFinishFromMirroredHealthKit(
        sessionID: UUID,
        healthKitSessionStateRawValue: Int,
        confirmedAt: Date,
        source: String
    ) {
        if hasCommittedTerminalGymSession(sessionID) {
            enrichConfirmedGymFinishHealthKitState(
                sessionID: sessionID,
                healthKitSessionStateRawValue: healthKitSessionStateRawValue
            )
            PulsarWorkoutStartupTrace.diag(
                "[WorkoutLifecycle] terminalAccepted source=\(source) phase=ended->ended workoutID=\(sessionID.uuidString) accepted=false reason=duplicateMirroredHealthKit"
            )
            return
        }

        pendingGymFinishHealthKitSessionStateRawValue = healthKitSessionStateRawValue
        defer { pendingGymFinishHealthKitSessionStateRawValue = nil }

        if var finished = activeGymState, finished.sessionId == sessionID {
            finished.isFinished = true
            finished.isLaunchPlaceholder = false
            finished.updatedAt = max(finished.updatedAt, confirmedAt)
            let didApply = apply(
                activeGymState: finished,
                broadcast: false,
                reason: source,
                isIncomingFromCounterpart: false
            )
            #if os(iOS)
            if didApply {
                schedulePostTerminalGymPersistence(finished)
            }
            #endif
        } else if lastFinishedGymState?.sessionId == sessionID {
            PulsarWorkoutStartupTrace.diag(
                "[WorkoutLifecycle] terminalAccepted source=\(source) phase=ended->ended workoutID=\(sessionID.uuidString) accepted=false reason=alreadyFinishedWithoutLiveState"
            )
        } else {
            lastConfirmedGymFinish = GymWorkoutFinishConfirmation(
                sessionID: sessionID,
                confirmedAt: confirmedAt,
                healthKitWorkoutUUID: nil,
                source: source,
                healthKitSessionStateRawValue: healthKitSessionStateRawValue
            )
            committedTerminalGymSessionID = sessionID
            #if os(iOS)
            PulsarWorkoutStartCoordinator.shared.markSessionEnded(
                sessionID: sessionID,
                reason: "confirmedMirroredHealthKitTerminal.\(source)"
            )
            #endif
        }

        enrichConfirmedGymFinishHealthKitState(
            sessionID: sessionID,
            healthKitSessionStateRawValue: healthKitSessionStateRawValue
        )
        PulsarWorkoutStartupTrace.lifecycle(
            "[GymFinish] workoutID=\(sessionID.uuidString) HKState=\(healthKitSessionStateRawValue) terminalKnown=true mirrorReleased=false finishResult=success source=\(source)"
        )
    }

    private func enrichConfirmedGymFinishHealthKitState(
        sessionID: UUID,
        healthKitSessionStateRawValue: Int
    ) {
        guard var confirmation = lastConfirmedGymFinish,
              confirmation.sessionID == sessionID,
              confirmation.healthKitSessionStateRawValue != healthKitSessionStateRawValue else {
            return
        }
        confirmation.healthKitSessionStateRawValue = healthKitSessionStateRawValue
        lastConfirmedGymFinish = confirmation
    }

    func hasCommittedTerminalGymSession(_ sessionID: UUID) -> Bool {
        committedTerminalGymSessionID == sessionID ||
            lastConfirmedGymFinish?.sessionID == sessionID ||
            lastFinishedGymState?.sessionId == sessionID
    }

    func flushTerminalGymPersistenceForTesting() async {
        await terminalGymPersistenceTask?.value
    }

    func prepareForNewGymStart(sessionID: UUID, reason: String) {
        var staleSessionIDs = [UUID]()
        if let previousSessionID = lastFinishedGymState?.sessionId,
           previousSessionID != sessionID {
            staleSessionIDs.append(previousSessionID)
        }
        if let previousSessionID = recentTerminalGymState?.sessionId,
           previousSessionID != sessionID {
            staleSessionIDs.append(previousSessionID)
        }
        if let previousSessionID = lastConfirmedGymFinish?.sessionID,
           previousSessionID != sessionID {
            staleSessionIDs.append(previousSessionID)
        }
        if case .gym? = recentTerminalActiveWorkoutState?.kind,
           let previousSessionID = recentTerminalActiveWorkoutState?.sessionId,
           previousSessionID != sessionID {
            staleSessionIDs.append(previousSessionID)
        }
        if let previousSessionID = committedTerminalGymSessionID,
           previousSessionID != sessionID {
            staleSessionIDs.append(previousSessionID)
        }

        guard !staleSessionIDs.isEmpty else { return }
        lastFinishedGymState = nil
        recentTerminalGymState = nil
        lastConfirmedGymFinish = nil
        committedTerminalGymSessionID = nil
        if case .gym? = recentTerminalActiveWorkoutState?.kind {
            recentTerminalActiveWorkoutState = nil
        }
        PulsarWorkoutLifecycleLogger.log(
            .staleFinishedIgnored,
            sessionID: sessionID,
            source: reason,
            detail: "clearedSessionIDs=\(Set(staleSessionIDs).map(\.uuidString).sorted().joined(separator: ","))"
        )
        publishCurrentApplicationContext(reason: "\(reason).newGymStartClearedFinishedState")
    }

    /// Test hook: application context must not re-embed finished workouts when live state is nil.
    func applicationContextOmitsTerminalStandInsWhenLiveStateNilForTesting() -> Bool {
        let context = makeApplicationContext(
            metricPayload: nil,
            sleepPreferences: nil,
            activeWorkoutState: nil,
            activeGymState: nil,
            savedGymRoutines: []
        )
        return context[Self.activeGymStatePayloadKey] == nil &&
            context[Self.activeWorkoutStatePayloadKey] == nil
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
        let signpostState = PulsarPerformanceSignposts.gym.beginInterval(
            "publish_state",
            "reason=\(reason, privacy: .public)"
        )
        defer {
            PulsarPerformanceSignposts.gym.endInterval("publish_state", signpostState)
        }
        return apply(activeGymState: state, broadcast: broadcast, reason: reason, isIncomingFromCounterpart: false)
    }

    func pruneStaleActiveWorkoutState(reason: String) {
        if let activeWorkoutState,
           let staleReason = activeWorkoutState.staleRouteReason() {
            if Self.shouldProtectSessionFromPrune(sessionID: activeWorkoutState.sessionId) {
                PulsarSyncDebugLogger.log(
                    "Prune skipped for in-flight workout start session=\(activeWorkoutState.sessionId.uuidString) source=\(reason) staleReason=\(staleReason)"
                )
            } else {
                PulsarSyncDebugLogger.log("active workout restore rejected: \(staleReason) source=\(reason) session=\(activeWorkoutState.sessionId.uuidString)")
                clearActiveWorkoutState(reason: "\(reason).\(staleReason)", broadcastEndedState: false)
            }
        }

        if let activeGymState,
           let staleReason = activeGymState.staleRouteReason() {
            if Self.shouldProtectSessionFromPrune(sessionID: activeGymState.sessionId) {
                PulsarSyncDebugLogger.log(
                    "Prune skipped for in-flight gym start session=\(activeGymState.sessionId.uuidString) source=\(reason) staleReason=\(staleReason)"
                )
            } else {
                PulsarSyncDebugLogger.log("active workout restore rejected: \(staleReason) source=\(reason) session=\(activeGymState.sessionId.uuidString)")
                clearActiveGymState(reason: "\(reason).\(staleReason)", broadcastEndedState: false)
            }
        }
    }

    private static func shouldProtectSessionFromPrune(sessionID: UUID) -> Bool {
        #if os(iOS)
        let coordinator = PulsarWorkoutStartCoordinator.shared
        guard coordinator.phase.isInProgress,
              let transaction = coordinator.currentTransaction else {
            return false
        }
        return transaction.sessionID == sessionID ||
            transaction.authoritativeSessionID == sessionID
        #else
        return false
        #endif
    }

    func isRoutableActiveWorkoutState(_ state: PulsarActiveWorkoutSyncState) -> Bool {
        state.isValidActiveWorkoutPresentationCandidate()
    }

    func isRoutableActiveGymState(_ state: ActiveGymWorkoutState) -> Bool {
        state.isValidActiveWorkoutPresentationCandidate()
    }

    func consumeGymRestorationCandidate(matching sessionStartDate: Date?) -> ActiveGymWorkoutState? {
        guard let candidate = gymRestorationCandidate else { return nil }
        gymRestorationCandidate = nil
        guard PulsarWatchSynchronizedGymReconciliation.isHealthKitRecoveryCandidate(
            candidate,
            sessionStartDate: sessionStartDate,
            platform: Self.synchronizedGymPlatform,
            isTombstoned: isActiveWorkoutSessionTombstoned(candidate.sessionId)
        ) else {
            PulsarWorkoutStartupTrace.lifecycle(
                "[GymRestore] workoutID=\(candidate.sessionId.uuidString) phase=active revision=\(candidate.lifecycleGeneration ?? 0) source=healthKitRecovery decision=stale"
            )
            return nil
        }
        return candidate
    }

    /// Drops launch metadata without ever publishing it as active. A fresh WC
    /// delegate delivery may still reintroduce the same session if it passes
    /// runtime-authority validation.
    func discardRestoredWorkoutCandidates(reason: String) {
        let workoutID = restoredActiveWorkoutCandidate?.sessionId
        let gymID = gymRestorationCandidate?.sessionId
        restoredActiveWorkoutCandidate = nil
        #if os(iOS)
        gymRestorationCandidate = nil
        #endif
        defaults.removeObject(forKey: activeWorkoutCacheKey)
        #if os(iOS)
        defaults.removeObject(forKey: activeGymCacheKey)
        #endif
        guard workoutID != nil || gymID != nil else { return }
        PulsarWorkoutStartupTrace.lifecycle(
            "[WorkoutRestore] candidate discarded before presentation reason=\(reason) workoutID=\(workoutID?.uuidString ?? "none") gymID=\(gymID?.uuidString ?? "none")"
        )
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
            lastFinishedGymState = ended
            storeActiveGymState(ended, broadcast: true, reason: "\(reason).finishedBroadcast")
        }

        cancelPendingActiveGymPersistence()
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
        if let previous {
            #if os(iOS)
            let transaction = PulsarWorkoutStartCoordinator.shared.currentTransaction
            let hasLocalLaunchContext = transaction?.sessionID == previous.sessionId ||
                transaction?.authoritativeSessionID == previous.sessionId
            #else
            let hasLocalLaunchContext = false
            #endif
            PulsarWorkoutStartupTrace.lifecycle(
                "[GymTerminalCleanup] source=\(reason) expectedWorkoutID=\(previous.sessionId.uuidString) actualCurrentWorkoutID=\(previous.sessionId.uuidString) requestID=\(previous.requestID?.uuidString ?? "none") generation=\(previous.lifecycleGeneration ?? 0) localLaunchContextExists=\(hasLocalLaunchContext) canonicalActiveGymStateExists=true routineID=\(previous.routineId.uuidString) exerciseCount=\(previous.exercises.count) decision=allowed reason=explicitCleanup clearedLocal=true clearedPersistent=true publishedTerminal=\(broadcastEndedState)"
            )
        }
        publishCurrentApplicationContext(reason: "\(reason).activeGymCleared")
    }

    @discardableResult
    func sendGymAction(_ action: ActiveGymWorkoutAction, retryAttempt: Int = 0) -> Bool {
        let hasLiveWorkout = (activeGymState?.isFinished == false) || (activeWorkoutState?.phase.isLive == true)
        if action.kind == .requestSavedRoutines, hasLiveWorkout {
            PulsarSyncDebugLogger.log("Saved routine refresh skipped because a live workout already proves Watch liveness")
            return false
        }
        if action.kind == .metricsUpdated {
            PulsarSyncDebugLogger.log("Gym metricsUpdated action dropped; latest gym state uses applicationContext")
            return false
        }
        guard let session = counterpartSession(
            for: "Active Gym action",
            verifiedWorkoutSessionID: action.sessionId
        ) else { return false }
        var action = action
        if action.actionId == nil {
            action.actionId = UUID()
        }
        Task { @MainActor [weak self, codecActor] in
            guard let data = await codecActor.encodeActiveGymAction(action),
                  let self,
                  self.counterpartSession(
                    for: "Active Gym action encoded send",
                    verifiedWorkoutSessionID: action.sessionId
                  ) === session else { return }
            var payload: [String: Any] = [Self.activeGymActionPayloadKey: data]
            let messageID = action.actionId ?? UUID()
            payload = self.workoutSyncEnvelope(
                payload,
                messageID: messageID,
                category: "activeGymAction",
                sessionID: action.sessionId,
                phase: action.kind.rawValue,
                reason: "sendGymAction.\(action.kind.rawValue)",
                retryAttempt: retryAttempt
            )
            if session.isReachable {
                PulsarWatchConnectivitySendTrace.logSend(
                    messageType: "activeGymAction",
                    messageID: messageID,
                    workoutID: action.sessionId,
                    requestID: action.actionId,
                    source: "sendGymAction.\(action.kind.rawValue)",
                    attempt: retryAttempt + 1,
                    reachable: true
                )
                session.sendMessage(payload) { reply in
                    Self.logWorkoutSyncAcknowledgement(reply, context: "Active Gym action", fallbackSessionID: action.sessionId)
                } errorHandler: { error in
                    PulsarWatchConnectivitySendTrace.logFailure(
                        messageType: "activeGymAction",
                        messageID: messageID,
                        workoutID: action.sessionId,
                        requestID: action.actionId,
                        source: "sendGymAction.\(action.kind.rawValue)",
                        attempt: retryAttempt + 1,
                        error: error
                    )
                    PulsarSyncDebugLogger.log("[PulsarWatchConnectivity] Active Gym action sendMessage failed kind=\(action.kind.rawValue) session=\(action.sessionId?.uuidString ?? "none") attempt=\(retryAttempt) error=\(error.localizedDescription)")
                    Task { @MainActor [weak self] in
                        self?.scheduleGymActionRetryIfNeeded(action, retryAttempt: retryAttempt, errorDescription: error.localizedDescription)
                    }
                }
            } else if !action.shouldQueueOverWatchConnectivity {
                PulsarSyncDebugLogger.log("[PulsarWatchConnectivity] Active Gym realtime action dropped because counterpart is not reachable kind=\(action.kind.rawValue) session=\(action.sessionId?.uuidString ?? "none")")
                return
            } else {
                PulsarSyncDebugLogger.log("[PulsarWatchConnectivity] Active Gym action reachable=false fallback=transferUserInfo kind=\(action.kind.rawValue) session=\(action.sessionId?.uuidString ?? "none") attempt=\(retryAttempt)")
                self.scheduleGymActionRetryIfNeeded(action, retryAttempt: retryAttempt, errorDescription: "counterpart not reachable")
            }
            guard action.shouldQueueOverWatchConnectivity else {
                PulsarSyncDebugLogger.log("[PulsarWatchConnectivity] Active Gym realtime action sent kind=\(action.kind.rawValue) session=\(action.sessionId?.uuidString ?? "none")")
                return
            }
            session.transferUserInfo(payload)
            PulsarSyncDebugLogger.log("[PulsarWatchConnectivity] Active Gym action queued kind=\(action.kind.rawValue) session=\(action.sessionId?.uuidString ?? "none") attempt=\(retryAttempt)")
        }
        return true
    }

    func setRunTransportEnvelopeHandler(_ handler: ((PulsarRunTransportEnvelope, String) -> Void)?) {
        runTransportEnvelopeHandler = handler
    }

    func sendRunTransportEnvelope(
        _ envelope: PulsarRunTransportEnvelope,
        reason: String,
        retryAttempt: Int = 0,
        queueIfUnreachable: Bool = false
    ) {
        guard let session = counterpartSession(for: "Run transport envelope") else { return }
        let metadata = Self.runTransportEnvelopeMetadata(envelope)
        Task { @MainActor [weak self, codecActor] in
            guard let data = await codecActor.encodeRunTransportEnvelope(envelope),
                  let self,
                  self.counterpartSession(for: "Run transport encoded send") === session else { return }
            var payload: [String: Any] = [Self.runTransportEnvelopePayloadKey: data]
            payload = self.workoutSyncEnvelope(
                payload,
                messageID: metadata.messageID,
                category: metadata.category,
                sessionID: metadata.sessionID,
                phase: metadata.phase,
                reason: reason,
                retryAttempt: retryAttempt
            )

            if session.isReachable {
                session.sendMessage(payload) { reply in
                    Self.logWorkoutSyncAcknowledgement(reply, context: "Run transport envelope", fallbackSessionID: metadata.sessionID)
                } errorHandler: { error in
                    PulsarSyncDebugLogger.log("[PulsarWatchConnectivity] Run transport sendMessage failed category=\(metadata.category) session=\(metadata.sessionID?.uuidString ?? "none") phase=\(metadata.phase ?? "none") reason=\(reason) attempt=\(retryAttempt) error=\(error.localizedDescription)")
                }
                PulsarSyncDebugLogger.log("[PulsarWatchConnectivity] Run transport sendMessage sent category=\(metadata.category) session=\(metadata.sessionID?.uuidString ?? "none") phase=\(metadata.phase ?? "none") reason=\(reason) reachable=true attempt=\(retryAttempt)")
            } else if !queueIfUnreachable {
                PulsarSyncDebugLogger.log("[PulsarWatchConnectivity] Run transport dropped because counterpart is not reachable category=\(metadata.category) session=\(metadata.sessionID?.uuidString ?? "none") phase=\(metadata.phase ?? "none") reason=\(reason)")
                return
            } else {
                PulsarSyncDebugLogger.log("[PulsarWatchConnectivity] Run transport reachable=false fallback=transferUserInfo category=\(metadata.category) session=\(metadata.sessionID?.uuidString ?? "none") phase=\(metadata.phase ?? "none") reason=\(reason) attempt=\(retryAttempt)")
            }

            guard queueIfUnreachable else { return }
            session.transferUserInfo(payload)
            PulsarSyncDebugLogger.log("[PulsarWatchConnectivity] Run transport queued category=\(metadata.category) session=\(metadata.sessionID?.uuidString ?? "none") phase=\(metadata.phase ?? "none") reason=\(reason) attempt=\(retryAttempt)")
        }
    }

    @discardableResult
    func storeSavedGymRoutines(
        _ routines: [WatchGymRoutinePlan],
        revision incomingRevision: Int? = nil,
        deletedRoutineIds: [UUID] = [],
        broadcast: Bool,
        reason: String
    ) -> Bool {
        let signpostState = PulsarPerformanceSignposts.watchConnectivity.beginInterval(
            "apply",
            "kind=savedGymRoutines reason=\(reason, privacy: .public) broadcast=\(broadcast)"
        )
        defer {
            PulsarPerformanceSignposts.watchConnectivity.endInterval("apply", signpostState)
        }
        let deletedRoutineIDSet = Set(deletedRoutineIds)
        let mergedRoutines = SavedGymRoutineDefinitionMerge.preservingCompleteDefinitions(
            incoming: routines,
            current: savedGymRoutines,
            deletedRoutineIDs: deletedRoutineIDSet
        )
        let sortedRoutines = mergedRoutines.sorted { $0.updatedAt > $1.updatedAt }
        let resolvedRevision = incomingRevision.map { max(0, $0) } ?? (savedGymRoutinesRevision + 1)

        if let incomingRevision {
            guard incomingRevision >= savedGymRoutinesRevision || savedGymRoutinesRevision == 0 else {
                PulsarSyncDebugLogger.log("Skipped saved Gym routines via \(reason) because incoming revision was not newer incoming=\(incomingRevision) current=\(savedGymRoutinesRevision)")
                return false
            }
            if incomingRevision == savedGymRoutinesRevision, sortedRoutines == savedGymRoutines {
                return false
            }
        } else if sortedRoutines == savedGymRoutines {
            PulsarSyncDebugLogger.log("Skipped saved Gym routines via \(reason) because definitions were unchanged revision=\(savedGymRoutinesRevision)")
            return false
        }

        savedGymRoutines = sortedRoutines
        savedGymRoutinesRevision = max(savedGymRoutinesRevision, resolvedRevision)
        persistSavedGymRoutines(
            SavedGymRoutinesSyncPayload(
                revision: savedGymRoutinesRevision,
                routines: sortedRoutines,
                deletedRoutineIds: deletedRoutineIds
            )
        )
        PulsarSyncDebugLogger.log("Saved Gym routines updated via \(reason) count=\(sortedRoutines.count) revision=\(savedGymRoutinesRevision) deleted=\(deletedRoutineIds.count)")
        #if os(watchOS)
        let routineLogSource = "WatchRoutineStore"
        #else
        let routineLogSource = "iPhoneSyncCache"
        #endif
        for routine in sortedRoutines {
            PulsarSyncDebugLogger.log("[PulsarRoutineSync] source=\(routineLogSource) reason=\(reason) routineID=\(routine.routineId.uuidString) name=\(routine.name) exerciseCount=\(routine.exercises.count) totalSetCount=\(routine.totalSetCount) revision=\(savedGymRoutinesRevision)")
        }

        if broadcast {
            sendSavedGymRoutinesToCounterpart(sortedRoutines, reason: reason)
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

    private func logOutstandingUserInfoTransfers(context: String) {
        guard let session else { return }
        let transfers = session.outstandingUserInfoTransfers
        let types = transfers.map { transfer -> String in
            Self.userInfoTransferDescriptor(transfer.userInfo)
        }
        PulsarWorkoutStartupTrace.lifecycle(
            "WC outstandingUserInfoTransfers count=\(transfers.count) context=\(context) entries=\(types.joined(separator: ";"))"
        )
    }

    nonisolated static func userInfoTransferDescriptor(_ info: [String: Any]) -> String {
        let type: String
        if let explicit = info["pulsar.gymCrossDevice.messageType.v1"] as? String {
            type = explicit
        } else if let category = info["pulsar.workoutSync.category.v1"] as? String {
            type = "workout.\(category)"
        } else if info["pulsar.run.transportEnvelope.v1"] != nil {
            type = "runTransport"
        } else if info["pulsar.activeGymWorkout.action.v1"] != nil {
            type = "gymAction"
        } else if info["pulsar.activeGymWorkout.state.v1"] != nil {
            type = "activeGymState"
        } else if info["pulsar.activeWorkout.state.v1"] != nil {
            type = "activeWorkoutState"
        } else if info["pulsar.savedGymRoutines.payload.v1"] != nil {
            type = "savedGymRoutines"
        } else if info["pulsar.dailyMetricsPayload"] != nil {
            type = "dailyMetrics"
        } else if info["pulsar.sleepPreferences.payload.v1"] != nil {
            type = "sleepPreferences"
        } else if info["pulsar.appleWatchBattery.payload.v1"] != nil || info["type"] as? String == "appleWatchBattery" {
            type = "watchBattery"
        } else if info["pulsar.watchHeartbeat.payload.v1"] != nil {
            type = "watchHeartbeat"
        } else {
            type = "unknown(keys=\(info.keys.sorted().joined(separator: ",")))"
        }
        let requestID = info["requestID"] as? String ?? "none"
        let workoutID = (info["candidateSessionID"] as? String)
            ?? (info["pulsar.workoutSync.sessionId.v1"] as? String)
            ?? "none"
        let bytes = info.values.reduce(into: 0) { total, value in
            total += (value as? Data)?.count ?? 0
        }
        return "\(type)/workoutID=\(workoutID)/requestID=\(requestID)/dataBytes=\(bytes)"
    }

    static func shouldQueueSavedGymRoutinesPayload(
        data: Data,
        revision: Int,
        lastQueuedData: Data?,
        lastQueuedRevision: Int?,
        hasOutstandingMatchingPayload: Bool,
        respondingToVerifiedInboundRequest: Bool
    ) -> Bool {
        guard !hasOutstandingMatchingPayload else { return false }
        if respondingToVerifiedInboundRequest {
            return true
        }
        guard lastQueuedRevision == revision, let lastQueuedData else { return true }
        return !SavedGymRoutinesSyncCodec.semanticallyEquivalent(lastQueuedData, data)
    }

    private func counterpartSession(
        for reason: String,
        verifiedWorkoutSessionID: UUID? = nil,
        respondingToVerifiedInboundRequest: Bool = false
    ) -> WCSession? {
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
        let hasVerifiedWorkoutAuthority = verifiedWorkoutSessionID.map(hasVerifiedRuntimeWorkoutAuthority) == true
        guard Self.canUseiPhoneWatchCounterpart(
            isActivated: session.activationState == .activated,
            isPaired: session.isPaired,
            isWatchAppInstalled: availability.rawIsWatchAppInstalled
        ) || hasVerifiedWorkoutAuthority || respondingToVerifiedInboundRequest else {
            PulsarSyncDebugLogger.log("Skipped \(reason) transfer because the Watch app is not installed rawReachable=\(availability.rawIsReachable) lastWatchSeenAt=\(availability.lastWatchSeenAt?.description ?? "none") everWatchPayload=\(availability.hasEverReceivedWatchPayload)")
            return nil
        }
        if (hasVerifiedWorkoutAuthority || respondingToVerifiedInboundRequest),
           !availability.rawIsWatchAppInstalled {
            PulsarSyncDebugLogger.log("Allowed \(reason) transfer because verified runtime Watch authority supersedes stale rawIsWatchAppInstalled=false session=\(verifiedWorkoutSessionID?.uuidString ?? "none") inboundRequest=\(respondingToVerifiedInboundRequest)")
        }
        #endif
        return session
    }

    private func hasVerifiedRuntimeWorkoutAuthority(sessionID: UUID) -> Bool {
        #if os(iOS)
        if let transaction = PulsarWorkoutStartCoordinator.shared.currentTransaction,
           (transaction.sessionID == sessionID || transaction.authoritativeSessionID == sessionID),
           transaction.didReachActive {
            return true
        }
        if let state = activeGymState,
           state.sessionId == sessionID,
           !state.isPrelaunchPlaceholder,
           state.startedFrom?.isAppleWatchRecorder == true,
           state.isFreshRestoreConfirmation() {
            return true
        }
        return false
        #else
        return false
        #endif
    }

    private func deferredRoutineCatalogSession(
        for reason: String,
        respondingToVerifiedInboundRequest: Bool = false
    ) -> WCSession? {
        counterpartSession(
            for: reason,
            respondingToVerifiedInboundRequest: respondingToVerifiedInboundRequest
        )
    }

    private nonisolated static func isRuntimeCounterpartDelivery(reason: String) -> Bool {
        reason.hasPrefix("receivedApplicationContext") ||
            reason.hasPrefix("receivedUserInfo") ||
            reason.hasPrefix("receivedMessage")
    }

    nonisolated static func canUseiPhoneWatchCounterpart(
        isActivated: Bool,
        isPaired: Bool,
        isWatchAppInstalled: Bool
    ) -> Bool {
        isActivated && isPaired && isWatchAppInstalled
    }

    nonisolated static func shouldAcceptFreshCounterpartWorkout(
        _ state: PulsarActiveWorkoutSyncState,
        reason: String,
        now: Date = Date()
    ) -> Bool {
        guard isRuntimeCounterpartDelivery(reason: reason),
              state.lastUpdatedFrom == .appleWatch else { return false }
        return state.isFreshRestoreConfirmation(now: now)
    }

    nonisolated static func shouldAcceptFreshCounterpartGym(
        _ state: ActiveGymWorkoutState,
        reason: String,
        now: Date = Date()
    ) -> Bool {
        guard isRuntimeCounterpartDelivery(reason: reason),
              state.startedFrom?.isAppleWatchRecorder == true else { return false }
        return state.isFreshRestoreConfirmation(now: now)
    }

    private func shouldRejectUncorrelatedCounterpartWorkout(
        _ state: PulsarActiveWorkoutSyncState,
        reason: String
    ) -> Bool {
        #if os(iOS)
        let coordinator = PulsarWorkoutStartCoordinator.shared
        guard coordinator.phase.isInProgress,
              let transaction = coordinator.currentTransaction,
              case .watchGym = transaction.kind else {
            return false
        }
        let canonicalSessionID = transaction.authoritativeSessionID ?? transaction.sessionID
        guard state.sessionId != canonicalSessionID else { return false }
        let mirror = GymMirroredSessionBridge.shared.snapshot
        let hasCanonicalMirror = mirror.hasAttachedLiveMirror && mirror.sessionID == canonicalSessionID
        guard hasCanonicalMirror || state.startedFrom == .iPhoneRequestedWatchStart else {
            return false
        }
        PulsarWorkoutStartupTrace.lifecycle(
            "[WorkoutReconcile] incomingWorkoutID=\(state.sessionId.uuidString) canonicalWorkoutID=\(canonicalSessionID.uuidString) incomingRequestID=none canonicalRequestID=\(transaction.requestID?.uuidString ?? "none") source=\(reason) decision=rejectAdvisory reason=uncorrelatedGenericWatchState"
        )
        return true
        #else
        return false
        #endif
    }

    #if os(iOS)
    private func currentGymAuthorityDecision(
        for incoming: ActiveGymWorkoutState
    ) -> (canonicalSessionID: UUID, canonicalRequestID: UUID?, decision: PulsarIncomingGymAuthorityDecision)? {
        let coordinator = PulsarWorkoutStartCoordinator.shared
        guard coordinator.phase.isInProgress,
              let transaction = coordinator.currentTransaction,
              case .watchGym = transaction.kind else {
            return nil
        }
        let canonicalSessionID = transaction.authoritativeSessionID ?? transaction.sessionID
        let mirror = GymMirroredSessionBridge.shared.snapshot
        let hasCanonicalMirror = mirror.hasAttachedLiveMirror && mirror.sessionID == canonicalSessionID
        return (
            canonicalSessionID,
            transaction.requestID,
            PulsarWatchSynchronizedGymReconciliation.incomingAuthorityDecision(
                incoming: incoming,
                canonicalSessionID: canonicalSessionID,
                canonicalRequestID: transaction.requestID,
                hasAuthoritativeMirror: hasCanonicalMirror
            )
        )
    }

    private func logRejectedGymAuthority(
        incoming: ActiveGymWorkoutState,
        canonicalSessionID: UUID,
        canonicalRequestID: UUID?,
        reason: String,
        decisionReason: String
    ) {
        PulsarWorkoutStartupTrace.lifecycle(
            "[WorkoutReconcile] incomingWorkoutID=\(incoming.sessionId.uuidString) canonicalWorkoutID=\(canonicalSessionID.uuidString) incomingRequestID=\(incoming.requestID?.uuidString ?? "none") canonicalRequestID=\(canonicalRequestID?.uuidString ?? "none") source=\(reason) decision=rejectAdvisory reason=\(decisionReason)"
        )
    }
    #endif

    private func shouldRejectUncorrelatedCounterpartGym(
        _ state: ActiveGymWorkoutState,
        reason: String
    ) -> Bool {
        #if os(iOS)
        guard let authority = currentGymAuthorityDecision(for: state),
              case .rejectAdvisory(let decisionReason) = authority.decision else {
            return false
        }
        logRejectedGymAuthority(
            incoming: state,
            canonicalSessionID: authority.canonicalSessionID,
            canonicalRequestID: authority.canonicalRequestID,
            reason: reason,
            decisionReason: decisionReason
        )
        return true
        #else
        return false
        #endif
    }

    private func hasRuntimeWorkoutAuthority(sessionID: UUID) -> Bool {
        if currentActiveWorkoutSessionID == sessionID ||
            activeWorkoutState?.sessionId == sessionID ||
            activeGymState?.sessionId == sessionID {
            return true
        }
        #if os(iOS)
        let transaction = PulsarWorkoutStartCoordinator.shared.currentTransaction
        return transaction?.sessionID == sessionID || transaction?.authoritativeSessionID == sessionID
        #else
        return false
        #endif
    }

    private func logWatchRecorderAvailability(_ snapshot: PulsarWatchRecorderAvailabilitySnapshot, reason: String) {
        PulsarSyncDebugLogger.log("Watch recorder availability reason=\(reason) activation=\(snapshot.activationStateDescription)(\(snapshot.activationStateRawValue)) paired=\(snapshot.isPaired) rawInstalled=\(snapshot.rawIsWatchAppInstalled) rawReachable=\(snapshot.rawIsReachable) lastWatchSeenAt=\(snapshot.lastWatchSeenAt?.description ?? "none") everWatchPayload=\(snapshot.hasEverReceivedWatchPayload) canAttemptLaunch=\(snapshot.canAttemptWatchAppLaunch) interactiveReachable=\(snapshot.isWatchInteractivelyReachable) error=\(snapshot.activationErrorMessage ?? "none") fallback=\(snapshot.fallbackReason?.logValue ?? "none")")
    }

    private func workoutSyncEnvelope(
        _ payload: [String: Any],
        messageID: UUID,
        category: String,
        sessionID: UUID?,
        phase: String?,
        reason: String,
        retryAttempt: Int
    ) -> [String: Any] {
        var envelope = payload
        envelope[Self.workoutSyncMessageIDKey] = messageID.uuidString
        envelope[Self.workoutSyncCategoryKey] = category
        envelope[Self.workoutSyncSentAtKey] = Date().timeIntervalSince1970
        envelope[Self.workoutSyncRetryAttemptKey] = retryAttempt
        if let sessionID {
            envelope[Self.workoutSyncSessionIDKey] = sessionID.uuidString
        }
        if let phase {
            envelope[Self.workoutSyncPhaseKey] = phase
        }
        PulsarSyncDebugLogger.log("[PulsarWorkoutSync] envelope prepared category=\(category) session=\(sessionID?.uuidString ?? "none") phase=\(phase ?? "none") reason=\(reason) message=\(messageID.uuidString) attempt=\(retryAttempt)")
        return envelope
    }

    private static func logWorkoutSyncAcknowledgement(
        _ reply: [String: Any],
        context: String,
        fallbackSessionID: UUID?
    ) {
        let messageID = reply[workoutSyncAcknowledgementMessageIDKey] as? String ?? "unknown"
        let sessionID = reply[workoutSyncSessionIDKey] as? String ?? fallbackSessionID?.uuidString ?? "none"
        let category = reply[workoutSyncCategoryKey] as? String ?? "unknown"
        let phase = reply[workoutSyncPhaseKey] as? String ?? "none"
        let accepted = reply[workoutSyncAcknowledgementAcceptedKey] as? Bool ?? false
        PulsarSyncDebugLogger.log("[PulsarWatchConnectivity] \(context) acknowledged accepted=\(accepted) category=\(category) session=\(sessionID) phase=\(phase) message=\(messageID)")
    }

    private func workoutSyncAcknowledgement(for dictionary: [String: Any], reason: String) -> [String: Any] {
        var acknowledgement: [String: Any] = [
            Self.workoutSyncAcknowledgementAcceptedKey: true,
            Self.workoutSyncAcknowledgementReasonKey: reason,
            Self.workoutSyncSentAtKey: Date().timeIntervalSince1970
        ]
        if let messageID = dictionary[Self.workoutSyncMessageIDKey] as? String {
            acknowledgement[Self.workoutSyncAcknowledgementMessageIDKey] = messageID
        }
        if let category = dictionary[Self.workoutSyncCategoryKey] as? String {
            acknowledgement[Self.workoutSyncCategoryKey] = category
        }
        if let sessionID = dictionary[Self.workoutSyncSessionIDKey] as? String {
            acknowledgement[Self.workoutSyncSessionIDKey] = sessionID
        }
        if let phase = dictionary[Self.workoutSyncPhaseKey] as? String {
            acknowledgement[Self.workoutSyncPhaseKey] = phase
        }
        return acknowledgement
    }

    private static func workoutSyncAcknowledgement(
        for snapshot: PulsarWatchConnectivityIncomingSnapshot,
        reason: String
    ) -> [String: Any] {
        var acknowledgement: [String: Any] = [
            workoutSyncAcknowledgementAcceptedKey: true,
            workoutSyncAcknowledgementReasonKey: reason,
            workoutSyncSentAtKey: Date().timeIntervalSince1970
        ]
        if let messageID = snapshot.messageID {
            acknowledgement[workoutSyncAcknowledgementMessageIDKey] = messageID
        }
        if let category = snapshot.category {
            acknowledgement[workoutSyncCategoryKey] = category
        }
        if let sessionID = snapshot.sessionID {
            acknowledgement[workoutSyncSessionIDKey] = sessionID
        }
        if let phase = snapshot.phase {
            acknowledgement[workoutSyncPhaseKey] = phase
        }
        return acknowledgement
    }

    private func scheduleGymActionRetryIfNeeded(
        _ action: ActiveGymWorkoutAction,
        retryAttempt: Int,
        errorDescription: String
    ) {
        guard action.shouldQueueOverWatchConnectivity,
              action.kind == .finishWorkout,
              retryAttempt < 2 else {
            if retryAttempt >= 2 {
                PulsarWorkoutStartupTrace.lifecycle(
                    "WC retry bounded kind=\(action.kind.rawValue) session=\(action.sessionId?.uuidString ?? "none") attempt=\(retryAttempt + 1) max=2"
                )
            }
            return
        }
        let nextAttempt = retryAttempt + 1
        PulsarWorkoutStartupTrace.lifecycle(
            "WC retry scheduled messageType=activeGymAction kind=\(action.kind.rawValue) session=\(action.sessionId?.uuidString ?? "none") nextAttempt=\(nextAttempt) max=2 reason=\(errorDescription)"
        )
        PulsarSyncDebugLogger.log("[PulsarWorkoutSync] scheduling gym action retry kind=\(action.kind.rawValue) session=\(action.sessionId?.uuidString ?? "none") nextAttempt=\(nextAttempt) reason=\(errorDescription)")
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(nextAttempt * 1_500))
            _ = await MainActor.run {
                self?.sendGymAction(action, retryAttempt: nextAttempt)
            }
        }
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
        let signpostState = PulsarPerformanceSignposts.watchConnectivity.beginInterval(
            "apply",
            "kind=daily reason=\(reason, privacy: .public) broadcast=\(broadcast)"
        )
        defer {
            PulsarPerformanceSignposts.watchConnectivity.endInterval("apply", signpostState)
        }
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
        let signpostState = PulsarPerformanceSignposts.watchConnectivity.beginInterval(
            "apply",
            "kind=sleepPreferences reason=\(reason, privacy: .public) broadcast=\(broadcast)"
        )
        defer {
            PulsarPerformanceSignposts.watchConnectivity.endInterval("apply", signpostState)
        }
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
        let signpostState = PulsarPerformanceSignposts.watchConnectivity.beginInterval(
            "apply",
            "kind=watchBattery reason=\(reason, privacy: .public) broadcast=\(broadcast)"
        )
        defer {
            PulsarPerformanceSignposts.watchConnectivity.endInterval("apply", signpostState)
        }
        guard Self.isValidAppleWatchBattery(incoming) else {
            PulsarSyncDebugLogger.log("Skipped \(reason) Apple Watch battery because payload was invalid")
            return false
        }

        #if os(iOS)
        if Self.isRuntimeCounterpartDelivery(reason: reason) {
            recordAppleWatchSeen(reason: reason, timestamp: incoming.timestamp, payloadKind: "appleWatchBattery")
        }
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
        let signpostState = PulsarPerformanceSignposts.watchConnectivity.beginInterval(
            "apply",
            "kind=activeWorkout reason=\(reason, privacy: .public) broadcast=\(broadcast)"
        )
        defer {
            PulsarPerformanceSignposts.watchConnectivity.endInterval("apply", signpostState)
        }
        let incoming = canonicalizedActiveWorkoutState(incoming, reason: reason)
        if incoming.isEnded, case .gym = incoming.kind, committedTerminalGymSessionID == incoming.sessionId {
            let decision = ActiveWorkoutUpdateDecision.ignoredHistoricalOnly
            lastActiveWorkoutUpdateDecision = decision
            PulsarWorkoutStartupTrace.diag(
                "[WorkoutLifecycle] terminalAccepted source=\(reason) phase=ended->ended workoutID=\(incoming.sessionId.uuidString) accepted=false reason=duplicateActiveWorkoutTerminal"
            )
            PulsarSyncDebugLogger.log(
                "Terminal active workout state skipped via \(reason) session=\(incoming.sessionId.uuidString) type=\(incoming.kind.workoutTypeRawValue) phase=\(incoming.phase.rawValue) action=noop"
            )
            return decision
        }
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
            if case .gym = incoming.kind,
               var finished = activeGymState,
               finished.sessionId == incoming.sessionId {
                finished.isFinished = true
                finished.updatedAt = max(finished.updatedAt, incoming.updatedAt)
                _ = commitTerminalGymFinish(
                    finished,
                    broadcast: false,
                    reason: "\(reason).gymFromActiveWorkout"
                )
                if broadcast {
                    sendActiveWorkoutStateToCounterpart(incoming, reason: reason)
                }
                return decision
            }
            rememberTerminatedActiveWorkoutSession(incoming.sessionId, reason: reason)
            recentTerminalActiveWorkoutState = incoming
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
            if case .gym = incoming.kind {
                lastConfirmedGymFinish = GymWorkoutFinishConfirmation(
                    sessionID: incoming.sessionId,
                    confirmedAt: incoming.updatedAt,
                    healthKitWorkoutUUID: incoming.healthKitWorkoutUUID,
                    source: reason
                )
                committedTerminalGymSessionID = incoming.sessionId
                #if os(iOS)
                PulsarWorkoutStartCoordinator.shared.markSessionEnded(
                    sessionID: incoming.sessionId,
                    reason: "confirmedActiveWorkoutTerminal.\(reason)"
                )
                #endif
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
    private func apply(activeGymState incoming: ActiveGymWorkoutState, broadcast: Bool, reason: String, isIncomingFromCounterpart: Bool = false) -> Bool {
        let signpostState = PulsarPerformanceSignposts.watchConnectivity.beginInterval(
            "apply",
            "kind=activeGym reason=\(reason, privacy: .public) broadcast=\(broadcast)"
        )
        defer {
            PulsarPerformanceSignposts.watchConnectivity.endInterval("apply", signpostState)
        }
        guard shouldApply(activeGymState: incoming, reason: reason, isIncomingFromCounterpart: isIncomingFromCounterpart) else {
            #if os(iOS)
            logGymRemoteConflictIfNeeded(incoming, applied: false, reason: reason)
            #endif
            PulsarSyncDebugLogger.log("Active Gym state skipped via \(reason) session=\(incoming.sessionId.uuidString) type=\(incoming.workoutKind?.rawValue ?? "unknown") updatedAt=\(incoming.updatedAt) finished=\(incoming.isFinished)")
            return false
        }

        #if os(iOS)
        logGymRemoteConflictIfNeeded(incoming, applied: true, reason: reason)
        #endif

        if incoming.isFinished {
            return commitTerminalGymFinish(incoming, broadcast: broadcast, reason: reason)
        }

        let resolvedIncoming = incoming.preservingRoutineDefinition(from: activeGymState)
        activeGymState = resolvedIncoming
        PulsarWorkoutStartupTrace.count("[PublishRate] activeGymState")
        if isIncomingFromCounterpart {
            PulsarWorkoutStartupTrace.count("[WCRate] activeGymState.receive", bytes: 0)
        }
        scheduleActiveGymPersistence(resolvedIncoming, reason: reason)
        let activeState = PulsarActiveWorkoutSyncState(gymState: resolvedIncoming)
        _ = apply(activeWorkoutState: activeState, broadcast: false, reason: "\(reason).gymBridge", isIncomingFromCounterpart: false)
        PulsarSyncDebugLogger.log("Active Gym state updated via \(reason) session=\(resolvedIncoming.sessionId.uuidString) type=\(resolvedIncoming.workoutKind?.rawValue ?? "unknown") startedFrom=\(resolvedIncoming.startedFrom?.rawValue ?? "unknown") progress=\(resolvedIncoming.completedSets)/\(resolvedIncoming.totalSets) finished=\(resolvedIncoming.isFinished)")
        #if os(iOS)
        if isIncomingFromCounterpart {
            PulsarWorkoutStartupTrace.diag(
                "[GymState] received session=\(resolvedIncoming.sessionId.uuidString) finished=\(resolvedIncoming.isFinished) progress=\(resolvedIncoming.completedSets)/\(resolvedIncoming.totalSets) reason=\(reason) \(PulsarWorkoutStartupTrace.threadTag())"
            )
        }
        #endif

        if broadcast {
            sendGymStateToCounterpart(resolvedIncoming, reason: reason)
        }
        return true
    }

    @discardableResult
    private func commitTerminalGymFinish(
        _ incoming: ActiveGymWorkoutState,
        broadcast: Bool,
        reason: String
    ) -> Bool {
        let phaseBefore: String
        #if os(iOS)
        phaseBefore = PulsarWorkoutStartCoordinator.shared.phase.name
        let endTransactionID = PulsarWorkoutStartCoordinator.shared.ensureEndTransactionID(
            sessionID: incoming.sessionId
        )
        let requestID = PulsarWorkoutStartCoordinator.shared.currentTransaction?.requestID
            ?? incoming.requestID
        #else
        phaseBefore = activeGymState == nil ? "idle" : "active"
        let endTransactionID = incoming.requestID ?? incoming.sessionId
        let requestID = incoming.requestID
        #endif

        if committedTerminalGymSessionID == incoming.sessionId {
            recordGymTerminalCommit(
                endTransactionID: endTransactionID,
                workoutID: incoming.sessionId,
                requestID: requestID,
                source: reason,
                phaseBefore: "ended",
                phaseAfter: "ended",
                accepted: false,
                reason: "duplicateTerminal"
            )
            return false
        }

        cancelPendingActiveGymPersistence()
        let activeState = PulsarActiveWorkoutSyncState(gymState: incoming)
        if broadcast {
            sendGymStateToCounterpart(incoming, reason: reason)
        }

        committedTerminalGymSessionID = incoming.sessionId
        recentTerminalGymState = incoming
        recentTerminalActiveWorkoutState = activeState
        lastFinishedGymState = incoming
        lastConfirmedGymFinish = GymWorkoutFinishConfirmation(
            sessionID: incoming.sessionId,
            confirmedAt: incoming.updatedAt,
            healthKitWorkoutUUID: incoming.healthKitWorkoutUUID,
            source: reason,
            healthKitSessionStateRawValue: pendingGymFinishHealthKitSessionStateRawValue
        )

        PulsarWorkoutStartupTrace.lifecycle(
            "[GymTerminalCleanup] begin workoutID=\(incoming.sessionId.uuidString) requestID=\(requestID?.uuidString ?? "none") source=\(reason)"
        )

        #if os(iOS)
        PulsarWorkoutStartCoordinator.shared.markSessionEnded(
            sessionID: incoming.sessionId,
            reason: "confirmedGymTerminal.\(reason)"
        )
        #endif

        rememberTerminatedActiveWorkoutSession(incoming.sessionId, reason: reason)
        if activeGymState?.sessionId == incoming.sessionId {
            activeGymState = nil
        }
        defaults.removeObject(forKey: activeGymCacheKey)
        if activeWorkoutState?.sessionId == incoming.sessionId {
            activeWorkoutState = nil
            defaults.removeObject(forKey: activeWorkoutCacheKey)
        }

        PulsarSyncDebugLogger.log(
            "Active Gym terminal state cleared active cache via \(reason) session=\(incoming.sessionId.uuidString) type=\(incoming.workoutKind?.rawValue ?? "unknown")"
        )
        PulsarWorkoutStartupTrace.lifecycle(
            "[GymTerminalCleanup] end workoutID=\(incoming.sessionId.uuidString) clearedLocal=true clearedPersistent=true publishedTerminal=\(broadcast) source=\(reason)"
        )
        publishCurrentApplicationContext(reason: "\(reason).finishedGymCleared")

        #if os(iOS)
        let phaseAfter = PulsarWorkoutStartCoordinator.shared.phase.name
        #else
        let phaseAfter = "ended"
        #endif
        recordGymTerminalCommit(
            endTransactionID: endTransactionID,
            workoutID: incoming.sessionId,
            requestID: requestID,
            source: reason,
            phaseBefore: phaseBefore,
            phaseAfter: phaseAfter,
            accepted: true,
            reason: "canonicalTerminal"
        )
        return true
    }

    private func recordGymTerminalCommit(
        endTransactionID: UUID,
        workoutID: UUID,
        requestID: UUID?,
        source: String,
        phaseBefore: String,
        phaseAfter: String,
        accepted: Bool,
        reason: String
    ) {
        let record = PulsarGymTerminalCommitRecord(
            endTransactionID: endTransactionID,
            workoutID: workoutID,
            requestID: requestID,
            source: source,
            phaseBefore: phaseBefore,
            phaseAfter: phaseAfter,
            accepted: accepted,
            reason: reason
        )
        lastGymTerminalCommit = record
        if accepted {
            acceptedGymTerminalCount += 1
        } else {
            rejectedGymTerminalCount += 1
        }
        PulsarWorkoutStartupTrace.diag(
            "[WorkoutLifecycle] terminalAccepted source=\(source) phase=\(phaseBefore)->\(phaseAfter) endTransactionID=\(endTransactionID.uuidString) workoutID=\(workoutID.uuidString) requestID=\(requestID?.uuidString ?? "none") accepted=\(accepted) reason=\(reason)"
        )
    }

    #if os(iOS)
    private func schedulePostTerminalGymPersistence(_ state: ActiveGymWorkoutState) {
        terminalGymPersistenceTask?.cancel()
        terminalGymPersistenceTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            let startedAt = Date()
            self.syncLiveActivity(for: state)
            PulsarWorkoutStartupTrace.diag(
                "[MainActor] postTerminalGymPersistence elapsedMs=\(PulsarWorkoutStartupTrace.elapsedMs(since: startedAt)) workoutID=\(state.sessionId.uuidString) \(PulsarWorkoutStartupTrace.threadTag())"
            )
        }
    }
    #endif

    @discardableResult
    private func apply(watchHeartbeat incoming: AppleWatchHeartbeatSnapshot, broadcast: Bool, reason: String) -> Bool {
        let signpostState = PulsarPerformanceSignposts.watchConnectivity.beginInterval(
            "apply",
            "kind=watchHeartbeat reason=\(reason, privacy: .public) broadcast=\(broadcast)"
        )
        defer {
            PulsarPerformanceSignposts.watchConnectivity.endInterval("apply", signpostState)
        }
        guard incoming.appInstalled else {
            PulsarSyncDebugLogger.log("Skipped \(reason) Watch heartbeat because appInstalled=false")
            return false
        }

        if let latestWatchHeartbeat,
           incoming.timestamp < latestWatchHeartbeat.timestamp {
            #if os(iOS)
            if Self.isRuntimeCounterpartDelivery(reason: reason) {
                recordAppleWatchSeen(reason: reason, payloadKind: "staleWatchHeartbeat")
            }
            #endif
            PulsarSyncDebugLogger.log("Skipped \(reason) Watch heartbeat because cached heartbeat was newer incoming=\(incoming.timestamp) cached=\(latestWatchHeartbeat.timestamp)")
            return false
        }

        latestWatchHeartbeat = incoming
        persistWatchHeartbeat(incoming)
        #if os(iOS)
        if Self.isRuntimeCounterpartDelivery(reason: reason) {
            recordAppleWatchSeen(reason: reason, timestamp: incoming.timestamp, payloadKind: "watchHeartbeat")
        }
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

    private func nextPayloadFilePersistenceRevision() -> UInt64 {
        payloadFilePersistenceRevision &+= 1
        return payloadFilePersistenceRevision
    }

    private func removePayloadFileCacheEntry(_ entry: PulsarSyncPayloadFileCache.Entry) {
        let revision = nextPayloadFilePersistenceRevision()
        Task { [payloadFileCache] in
            await payloadFileCache.remove(entry, revision: revision)
        }
    }

    private func setDefaultsData(_ data: Data, forKey key: String) {
        #if DEBUG
        let warningThreshold = 100 * 1_024
        if data.count > warningThreshold {
            PulsarSyncDebugLogger.log(
                "Oversized UserDefaults write key=\(key) bytes=\(data.count) threshold=\(warningThreshold)"
            )
            assertionFailure(
                "UserDefaults Data write exceeded \(warningThreshold) bytes for key \(key)"
            )
        }
        #endif
        let writeStartedAt = Date()
        defaults.set(data, forKey: key)
        PulsarWorkoutStartupTrace.recordDefaultsWrite(
            key: key,
            bytes: data.count,
            elapsedMs: PulsarWorkoutStartupTrace.elapsedMs(since: writeStartedAt)
        )
    }

    private func persist(_ payload: PulsarDailyMetricsSyncPayload) {
        let revision = nextPayloadFilePersistenceRevision()
        Task { [payloadFileCache] in
            await payloadFileCache.save(payload, for: .latestPayload, revision: revision)
        }
    }

    private func persistDailyPayloadCache() {
        dailyPayloadsByDateKey = Self.retainedDailyPayloads(dailyPayloadsByDateKey)
        let payloads = dailyPayloadsByDateKey
        let revision = nextPayloadFilePersistenceRevision()
        Task { [payloadFileCache] in
            await payloadFileCache.save(payloads, for: .dailyPayloads, revision: revision)
        }
    }

    private func persistSleepPayloadCache() {
        sleepPayloadsByDateKey = Self.retainedDailyPayloads(sleepPayloadsByDateKey)
        let payloads = sleepPayloadsByDateKey
        let revision = nextPayloadFilePersistenceRevision()
        Task { [payloadFileCache] in
            await payloadFileCache.save(payloads, for: .sleepPayloads, revision: revision)
        }
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
                entry: .sourceDailyPayloads,
                isUsable: { $0.hasCompleteDailyScores || $0.hasValidStrain || $0.hasValidRecovery || $0.hasValidStress || $0.hasValidHealthMonitor }
            ) || didUpdate
        }
        if let sleep = payload.sleep, sleep.isValid {
            didUpdate = persistSourcePayload(
                payload,
                dateKey: sleep.sleepDateKey,
                cache: &sourceSleepPayloadsByDateKey,
                entry: .sourceSleepPayloads,
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
        entry: PulsarSyncPayloadFileCache.Entry,
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
        cache = Self.retainedSourcePayloads(cache)
        persistSourcePayloadCache(cache, entry: entry)
        sourceCacheRevision &+= 1
        PulsarSyncDebugLogger.log("Source cache updated dateKey=\(dateKey) source=\(source.rawValue) session=\(payload.syncSessionID?.uuidString ?? "none")")
        return true
    }

    private func pruneDailyCaches() {
        dailyPayloadsByDateKey = Self.retainedDailyPayloads(dailyPayloadsByDateKey)
        sleepPayloadsByDateKey = Self.retainedDailyPayloads(sleepPayloadsByDateKey)
        sourceDailyPayloadsByDateKey = Self.retainedSourcePayloads(sourceDailyPayloadsByDateKey)
        sourceSleepPayloadsByDateKey = Self.retainedSourcePayloads(sourceSleepPayloadsByDateKey)
    }

    private func persistSourcePayloadCache(
        _ cache: [String: [PulsarSyncSourceDevice: PulsarDailyMetricsSyncPayload]],
        entry: PulsarSyncPayloadFileCache.Entry
    ) {
        let revision = nextPayloadFilePersistenceRevision()
        Task { [payloadFileCache] in
            await payloadFileCache.save(cache, for: entry, revision: revision)
        }
    }

    private func persistSleepPreferences(_ payload: PulsarSleepPreferencesSyncPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        setDefaultsData(data, forKey: sleepPreferencesCacheKey)
    }

    private func persistAppleWatchBattery(_ snapshot: AppleWatchBatterySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        setDefaultsData(data, forKey: appleWatchBatteryCacheKey)
    }

    private func persistWatchHeartbeat(_ snapshot: AppleWatchHeartbeatSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        setDefaultsData(data, forKey: watchHeartbeatCacheKey)
    }

    private func persistActiveWorkoutState(_ state: PulsarActiveWorkoutSyncState) {
        activeWorkoutPersistenceGeneration += 1
        let generation = activeWorkoutPersistenceGeneration
        Task { [weak self, codecActor] in
            guard let data = await codecActor.encodeActiveWorkoutState(state) else { return }
            guard let self,
                  generation == self.activeWorkoutPersistenceGeneration,
                  self.activeWorkoutState?.sessionId == state.sessionId,
                  self.activeWorkoutState?.updatedAt == state.updatedAt else { return }
            self.setDefaultsData(data, forKey: self.activeWorkoutCacheKey)
        }
    }

    private func scheduleActiveGymPersistence(_ state: ActiveGymWorkoutState, reason: String) {
        pendingActiveGymPersistence = state
        activeGymPersistenceGeneration += 1
        let generation = activeGymPersistenceGeneration

        guard ActiveGymSyncCadencePolicy.isVolatile(reason: reason, isFinished: state.isFinished) else {
            activeGymPersistenceTask?.cancel()
            activeGymPersistenceTask = nil
            pendingActiveGymPersistence = nil
            persistActiveGymState(state, generation: generation)
            return
        }

        guard activeGymPersistenceTask == nil else { return }
        activeGymPersistenceTask = Task { [weak self] in
            try? await Task.sleep(for: ActiveGymSyncCadencePolicy.persistenceDebounceInterval)
            guard !Task.isCancelled, let self else { return }
            let pending = self.pendingActiveGymPersistence
            let pendingGeneration = self.activeGymPersistenceGeneration
            self.pendingActiveGymPersistence = nil
            self.activeGymPersistenceTask = nil
            guard let pending else { return }
            self.persistActiveGymState(pending, generation: pendingGeneration)
        }
    }

    private func persistActiveGymState(_ state: ActiveGymWorkoutState, generation: Int) {
        let fingerprint = Self.gymStateFingerprint(state)
        guard fingerprint != lastPersistedGymFingerprint else { return }
        let codecActor = codecActor
        Task.detached { [fingerprint] in
            guard let data = await codecActor.encodeActiveGymState(state) else { return }
            await MainActor.run {
                PulsarWatchConnectivitySyncStore.shared.commitPersistedActiveGymState(
                    data,
                    state: state,
                    generation: generation,
                    fingerprint: fingerprint
                )
            }
        }
    }

    private func commitPersistedActiveGymState(
        _ data: Data,
        state: ActiveGymWorkoutState,
        generation: Int,
        fingerprint: String
    ) {
        guard generation == activeGymPersistenceGeneration,
              activeGymState?.sessionId == state.sessionId,
              activeGymState?.isFinished == false else { return }
        lastPersistedGymFingerprint = fingerprint
        setDefaultsData(data, forKey: activeGymCacheKey)
    }

    private static func gymStateFingerprint(_ state: ActiveGymWorkoutState) -> String {
        [
            state.sessionId.uuidString,
            String(state.updatedAt.timeIntervalSince1970),
            String(state.elapsedSeconds),
            String(state.completedSets),
            String(state.currentExerciseIndex),
            String(state.currentSetIndex),
            String(Int(state.currentHeartRate ?? -1)),
            String(state.restRemainingSeconds ?? -1),
            state.isFinished ? "1" : "0"
        ].joined(separator: "|")
    }

    private func cancelPendingActiveGymPersistence() {
        activeGymPersistenceGeneration += 1
        pendingActiveGymPersistence = nil
        activeGymPersistenceTask?.cancel()
        activeGymPersistenceTask = nil
        lastPersistedGymFingerprint = nil
        lastTransmittedGymFingerprint = nil
    }

    private func persistSavedGymRoutines(_ payload: SavedGymRoutinesSyncPayload) {
        guard let data = SavedGymRoutinesSyncCodec.encode(payload) else { return }
        let revision = nextPayloadFilePersistenceRevision()
        Task { [payloadFileCache] in
            await payloadFileCache.saveEncodedData(data, for: .savedGymRoutines, revision: revision)
        }
        defaults.set(payload.revision, forKey: savedGymRoutinesRevisionCacheKey)
    }

    private func sendToCounterpart(metricPayload: PulsarDailyMetricsSyncPayload? = nil, sleepPreferences: PulsarSleepPreferencesSyncPayload? = nil) {
        guard let session = counterpartSession(for: "daily metrics") else { return }
        let metric = metricPayload ?? latestPayload
        let sleepPreferences = sleepPreferences ?? latestSleepPreferences
        let source = applicationContextSource(
            metricPayload: metric,
            sleepPreferences: sleepPreferences,
            activeWorkoutState: activeWorkoutState,
            activeGymState: activeGymState,
            savedGymRoutines: savedGymRoutines
        )

        Task { @MainActor [weak self, codecActor] in
            let encoded = await codecActor.encodeApplicationContext(source)
            guard let self,
                  self.counterpartSession(for: "daily metrics encoded send") === session else { return }
            let applicationContext = self.makeApplicationContext(encoded: encoded)
            guard !applicationContext.isEmpty else { return }

            if self.isApplicationContextSourceCurrent(source) {
                do {
                    try session.updateApplicationContext(applicationContext)
                    PulsarSyncDebugLogger.log("WatchConnectivity applicationContext updated metricSession=\(metric?.syncSessionID?.uuidString ?? "none") alarmEnabled=\(sleepPreferences?.alarmEnabled == true)")
                } catch {
                    PulsarSyncDebugLogger.log("Failed to update applicationContext: \(error.localizedDescription)")
                }
            }

            var durablePayload = applicationContext
            durablePayload.removeValue(forKey: Self.activeWorkoutStatePayloadKey)
            durablePayload.removeValue(forKey: Self.activeGymStatePayloadKey)
            session.transferUserInfo(durablePayload)
            PulsarSyncDebugLogger.log("WatchConnectivity payload queued for transfer metricSession=\(metric?.syncSessionID?.uuidString ?? "none") alarmEnabled=\(sleepPreferences?.alarmEnabled == true)")
        }
    }

    private func publishCurrentApplicationContext(reason: String) {
        guard let session = counterpartSession(for: "cleared active workout context") else { return }
        let source = applicationContextSource(
            metricPayload: latestPayload,
            sleepPreferences: latestSleepPreferences,
            activeWorkoutState: activeWorkoutState,
            activeGymState: activeGymState,
            savedGymRoutines: savedGymRoutines
        )

        Task { @MainActor [weak self, codecActor] in
            let encoded = await codecActor.encodeApplicationContext(source)
            guard let self,
                  self.counterpartSession(for: "cleared active workout encoded send") === session,
                  self.isApplicationContextSourceCurrent(source) else { return }
            let applicationContext = self.makeApplicationContext(encoded: encoded)
            do {
                try session.updateApplicationContext(applicationContext)
                PulsarSyncDebugLogger.log("Active workout applicationContext refreshed after clear reason=\(reason) activeSession=\(source.activeWorkout?.sessionId.uuidString ?? "none") activeGym=\(source.activeGym?.sessionId.uuidString ?? "none")")
            } catch {
                PulsarSyncDebugLogger.log("Active workout applicationContext clear failed reason=\(reason) error=\(error.localizedDescription)")
            }
        }
    }

    private func sendGymStateToCounterpart(_ state: ActiveGymWorkoutState, reason: String) {
        guard counterpartSession(for: "Active Gym state") != nil else { return }
        let isVolatile = isVolatileActiveGymUpdate(reason: reason, state: state)
        let now = Date()
        let updatesApplicationContext = !isVolatile ||
            now.timeIntervalSince(lastActiveGymLiveApplicationContextAt) >= ActiveGymSyncCadencePolicy.applicationContextLiveInterval

        guard updatesApplicationContext else {
            PulsarSyncDebugLogger.log("Active Gym latest-state applicationContext throttled session=\(state.sessionId.uuidString) reason=\(reason)")
            PulsarWorkoutStartupTrace.count("[WCRate] activeGymState.sendThrottled")
            return
        }

        lastActiveGymLiveApplicationContextAt = now

        let compactState = isVolatile ? state.compactedForLiveSync : state
        let fingerprint = Self.gymStateFingerprint(compactState)
        guard fingerprint != lastTransmittedGymFingerprint else {
            PulsarWorkoutStartupTrace.count("[WCRate] activeGymState.sendDuplicate")
            return
        }
        lastTransmittedGymFingerprint = fingerprint

        let activeWorkout = PulsarActiveWorkoutSyncState(gymState: state)
        let applicationContextSource = PulsarWatchConnectivityApplicationContextSource(
            dailyMetrics: latestPayload,
            sleepPreferences: latestSleepPreferences,
            appleWatchBattery: latestAppleWatchBattery,
            watchHeartbeat: latestWatchHeartbeat,
            activeWorkout: activeWorkoutState,
            activeGym: compactState,
            savedGymRoutines: SavedGymRoutinesSyncPayload(
                revision: savedGymRoutinesRevision,
                routines: savedGymRoutines
            )
        )
        let source = PulsarWatchConnectivityGymTransmissionSource(
            state: compactState,
            activeWorkout: activeWorkout,
            sendsDelta: false,
            applicationContext: applicationContextSource
        )

        let codecActor = codecActor
        Task.detached {
            let encoded = await codecActor.encodeGymTransmission(source)
            await MainActor.run {
                PulsarWatchConnectivitySyncStore.shared.commitEncodedGymTransmission(
                    encoded,
                    state: state,
                    reason: reason
                )
            }
        }
    }

    private func commitEncodedGymTransmission(
        _ encoded: PulsarWatchConnectivityEncodedGymTransmission,
        state: ActiveGymWorkoutState,
        reason: String
    ) {
        guard let session = counterpartSession(for: "Active Gym encoded send") else { return }
        let encodedBytes = (encoded.activeGymStateData?.count ?? 0)
            + (encoded.activeGymDeltaData?.count ?? 0)
            + (encoded.activeWorkoutData?.count ?? 0)
        PulsarWorkoutStartupTrace.count("[WCRate] activeGymState.send", bytes: encodedBytes)
        if !state.isFinished {
            guard let current = activeGymState,
                  current.sessionId == state.sessionId,
                  current.updatedAt <= state.updatedAt else {
                PulsarSyncDebugLogger.log("Active Gym stale encoded transmission dropped session=\(state.sessionId.uuidString) reason=\(reason)")
                return
            }
        }
        if state.isFinished {
            var payload: [String: Any] = [:]
            if let data = encoded.activeGymStateData {
                payload[Self.activeGymStatePayloadKey] = data
            }
            if let data = encoded.activeWorkoutData {
                payload[Self.activeWorkoutStatePayloadKey] = data
            }
            guard !payload.isEmpty else { return }
            payload = workoutSyncEnvelope(
                payload,
                messageID: UUID(),
                category: "activeGymTerminal",
                sessionID: state.sessionId,
                phase: "finished",
                reason: reason,
                retryAttempt: 0
            )
            session.transferUserInfo(payload)
            PulsarSyncDebugLogger.log(
                "Active Gym terminal queued session=\(state.sessionId.uuidString) reason=\(reason) transport=durable"
            )
            return
        }
        guard let encodedApplicationContext = encoded.applicationContext else { return }
        let applicationContext = makeApplicationContext(encoded: encodedApplicationContext)
        do {
            try session.updateApplicationContext(applicationContext)
            PulsarSyncDebugLogger.log("Active Gym applicationContext updated session=\(state.sessionId.uuidString) compact=\(isVolatileActiveGymUpdate(reason: reason, state: state)) reason=\(reason) transport=latestState")
        } catch {
            PulsarSyncDebugLogger.log("Failed to update Active Gym applicationContext: \(error.localizedDescription)")
        }
    }

    private func isVolatileActiveGymUpdate(reason: String, state: ActiveGymWorkoutState) -> Bool {
        ActiveGymSyncCadencePolicy.isVolatile(reason: reason, isFinished: state.isFinished)
    }

    private func makeApplicationContext(
        encoded: PulsarWatchConnectivityEncodedApplicationContext
    ) -> [String: Any] {
        var context: [String: Any] = [:]
        if let data = encoded.dailyMetricsData {
            context[PulsarSyncPayloadCodec.payloadKey] = data
        }
        if let data = encoded.sleepPreferencesData {
            context[Self.sleepPreferencesPayloadKey] = data
        }
        if let data = encoded.appleWatchBatteryData {
            context[Self.appleWatchBatteryPayloadKey] = data
        }
        if let data = encoded.watchHeartbeatData {
            context[Self.watchHeartbeatPayloadKey] = data
        }
        if let data = encoded.activeWorkoutData {
            context[Self.activeWorkoutStatePayloadKey] = data
        }
        if let data = encoded.activeGymData {
            context[Self.activeGymStatePayloadKey] = data
        }
        if let data = encoded.savedGymRoutinesData {
            context[Self.savedGymRoutinesPayloadKey] = data
        }
        return context
    }

    private func sendSavedGymRoutinesToCounterpart(
        _ routines: [WatchGymRoutinePlan]? = nil,
        respondingToVerifiedInboundRequest: Bool = false,
        reason: String = "savedGymRoutinesSync"
    ) {
        let routines = routines ?? savedGymRoutines
        guard let session = deferredRoutineCatalogSession(
            for: "saved Gym routines",
            respondingToVerifiedInboundRequest: respondingToVerifiedInboundRequest
        ) else { return }
        let source = applicationContextSource(
            metricPayload: latestPayload,
            sleepPreferences: latestSleepPreferences,
            activeWorkoutState: activeWorkoutState,
            activeGymState: activeGymState,
            savedGymRoutines: routines
        )

        Task { @MainActor [weak self, codecActor] in
            let encoded = await codecActor.encodeApplicationContext(source)
            guard let self,
                  self.counterpartSession(
                    for: "saved Gym routines encoded send",
                    respondingToVerifiedInboundRequest: respondingToVerifiedInboundRequest
                  ) === session,
                  source.savedGymRoutines.revision == self.savedGymRoutinesRevision,
                  source.savedGymRoutines.routines == self.savedGymRoutines,
                  let data = encoded.savedGymRoutinesData else { return }
            let payload = [Self.savedGymRoutinesPayloadKey: data]
            PulsarSyncDebugLogger.log(
                "[GymRoutineSync] source=\(reason) revision=\(source.savedGymRoutines.revision) routineCount=\(routines.count) exerciseCount=\(routines.reduce(0) { $0 + $1.exercises.count }) setCount=\(routines.reduce(0) { $0 + $1.totalSetCount }) bytes=\(data.count)"
            )
            if session.isReachable {
                session.sendMessage(payload, replyHandler: nil) { error in
                    PulsarSyncDebugLogger.log("Saved Gym routines sendMessage failed error=\(error.localizedDescription)")
                }
            } else {
                PulsarSyncDebugLogger.log("Saved Gym routines sendMessage skipped reachable=false fallback=applicationContext+transferUserInfo revision=\(source.savedGymRoutines.revision)")
            }

            if self.isApplicationContextSourceCurrent(source) {
                let applicationContext = self.makeApplicationContext(encoded: encoded)
                do {
                    try session.updateApplicationContext(applicationContext)
                    PulsarSyncDebugLogger.log("Saved Gym routines applicationContext updated count=\(routines.count) revision=\(source.savedGymRoutines.revision)")
                } catch {
                    PulsarSyncDebugLogger.log("Failed to update saved Gym routines applicationContext: \(error.localizedDescription)")
                }
            }
            let alreadyOutstanding = session.outstandingUserInfoTransfers.contains { transfer in
                guard let outstandingData = transfer.userInfo[Self.savedGymRoutinesPayloadKey] as? Data else {
                    return false
                }
                return SavedGymRoutinesSyncCodec.semanticallyEquivalent(outstandingData, data)
            }
            let shouldQueue = Self.shouldQueueSavedGymRoutinesPayload(
                data: data,
                revision: source.savedGymRoutines.revision,
                lastQueuedData: self.lastQueuedSavedGymRoutinesData,
                lastQueuedRevision: self.lastQueuedSavedGymRoutinesRevision,
                hasOutstandingMatchingPayload: alreadyOutstanding,
                respondingToVerifiedInboundRequest: respondingToVerifiedInboundRequest
            )
            if !shouldQueue {
                PulsarSyncDebugLogger.log(
                    "[GymRoutineSync] source=\(reason) revision=\(source.savedGymRoutines.revision) durableQueue=skippedDuplicate bytes=\(data.count) outstanding=\(alreadyOutstanding)"
                )
            } else {
                session.transferUserInfo(payload)
                self.lastQueuedSavedGymRoutinesRevision = source.savedGymRoutines.revision
                self.lastQueuedSavedGymRoutinesData = data
            }
        }
    }

    private func applicationContextSource(
        metricPayload: PulsarDailyMetricsSyncPayload?,
        sleepPreferences: PulsarSleepPreferencesSyncPayload?,
        activeWorkoutState: PulsarActiveWorkoutSyncState?,
        activeGymState: ActiveGymWorkoutState?,
        savedGymRoutines: [WatchGymRoutinePlan],
        watchHeartbeat: AppleWatchHeartbeatSnapshot? = nil
    ) -> PulsarWatchConnectivityApplicationContextSource {
        PulsarWatchConnectivityApplicationContextSource(
            dailyMetrics: metricPayload,
            sleepPreferences: sleepPreferences,
            appleWatchBattery: latestAppleWatchBattery,
            watchHeartbeat: watchHeartbeat ?? latestWatchHeartbeat,
            activeWorkout: activeWorkoutState,
            activeGym: activeGymState,
            savedGymRoutines: SavedGymRoutinesSyncPayload(
                revision: savedGymRoutinesRevision,
                routines: savedGymRoutines
            )
        )
    }

    private func isApplicationContextSourceCurrent(
        _ source: PulsarWatchConnectivityApplicationContextSource
    ) -> Bool {
        source.activeWorkout?.sessionId == activeWorkoutState?.sessionId &&
            source.activeWorkout?.updatedAt == activeWorkoutState?.updatedAt &&
            source.activeGym?.sessionId == activeGymState?.sessionId &&
            source.activeGym?.updatedAt == activeGymState?.updatedAt &&
            source.savedGymRoutines.revision == savedGymRoutinesRevision &&
            source.savedGymRoutines.routines == savedGymRoutines
    }

    private func makeApplicationContext(
        metricPayload: PulsarDailyMetricsSyncPayload?,
        sleepPreferences: PulsarSleepPreferencesSyncPayload?,
        activeWorkoutState: PulsarActiveWorkoutSyncState?,
        activeGymState: ActiveGymWorkoutState?,
        savedGymRoutines: [WatchGymRoutinePlan]
    ) -> [String: Any] {
        var applicationContext: [String: Any] = [:]
        // Only publish live session state. Finished/terminal snapshots stay local
        // (lastFinishedGymState / recentTerminal*) and are delivered via explicit
        // finish messages — never re-embedded as an active stand-in.
        let contextActiveWorkoutState = activeWorkoutState
        let contextActiveGymState = activeGymState
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
        if let contextActiveWorkoutState,
           let data = Self.encodeActiveWorkoutState(contextActiveWorkoutState) {
            applicationContext[Self.activeWorkoutStatePayloadKey] = data
        }
        if let contextActiveGymState,
           let data = ActiveGymWorkoutCodec.encodeState(contextActiveGymState) {
            applicationContext[Self.activeGymStatePayloadKey] = data
        }
        let savedGymRoutinesPayload = SavedGymRoutinesSyncPayload(
            revision: savedGymRoutinesRevision,
            routines: savedGymRoutines
        )
        if let data = SavedGymRoutinesSyncCodec.encode(savedGymRoutinesPayload) {
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
        guard let session = counterpartSession(for: "Watch heartbeat") else { return }
        let source = applicationContextSource(
            metricPayload: latestPayload,
            sleepPreferences: latestSleepPreferences,
            activeWorkoutState: activeWorkoutState,
            activeGymState: activeGymState,
            savedGymRoutines: savedGymRoutines,
            watchHeartbeat: heartbeat
        )

        Task { @MainActor [weak self, codecActor] in
            let encoded = await codecActor.encodeApplicationContext(source)
            guard let self,
                  self.counterpartSession(for: "Watch heartbeat encoded send") === session,
                  let _ = encoded.watchHeartbeatData else { return }

            if self.isApplicationContextSourceCurrent(source) {
                let applicationContext = self.makeApplicationContext(encoded: encoded)
                do {
                    try session.updateApplicationContext(applicationContext)
                    PulsarSyncDebugLogger.log("Watch heartbeat applicationContext updated reason=\(reason) transport=latestState")
                } catch {
                    PulsarSyncDebugLogger.log("Watch heartbeat applicationContext failed reason=\(reason) error=\(error.localizedDescription)")
                }
            }
        }
    }

    private func sendActiveWorkoutStateToCounterpart(_ state: PulsarActiveWorkoutSyncState, reason: String) {
        guard let session = counterpartSession(for: "Active workout state") else { return }
        let isLiveMetricsUpdate = state.phase == .active || state.phase == .resumed || state.phase == .paused
        let now = Date()
        let updatesApplicationContext = !isLiveMetricsUpdate ||
            now.timeIntervalSince(lastActiveWorkoutLiveApplicationContextAt) >= 2

        if updatesApplicationContext {
            lastActiveWorkoutLiveApplicationContextAt = now
        }

        let contextSource: PulsarWatchConnectivityApplicationContextSource? = updatesApplicationContext
            ? PulsarWatchConnectivityApplicationContextSource(
                dailyMetrics: latestPayload,
                sleepPreferences: latestSleepPreferences,
                appleWatchBattery: latestAppleWatchBattery,
                watchHeartbeat: latestWatchHeartbeat,
                activeWorkout: state,
                activeGym: activeGymState?.compactedForLiveSync,
                savedGymRoutines: SavedGymRoutinesSyncPayload(
                    revision: savedGymRoutinesRevision,
                    routines: savedGymRoutines
                )
            )
            : nil

        Task { @MainActor [weak self, codecActor] in
            guard let data = await codecActor.encodeActiveWorkoutState(state),
                  let self,
                  self.counterpartSession(for: "Active workout encoded send") === session else { return }
            if isLiveMetricsUpdate {
                guard let current = self.activeWorkoutState,
                      current.sessionId == state.sessionId,
                      current.updatedAt <= state.updatedAt else {
                    PulsarSyncDebugLogger.log("Active workout stale encoded transmission dropped session=\(state.sessionId.uuidString) reason=\(reason)")
                    return
                }
            }
            let encodedContext: PulsarWatchConnectivityEncodedApplicationContext?
            if let contextSource {
                encodedContext = await codecActor.encodeApplicationContext(contextSource)
            } else {
                encodedContext = nil
            }
            var payload: [String: Any] = [Self.activeWorkoutStatePayloadKey: data]
            payload = self.workoutSyncEnvelope(
                payload,
                messageID: UUID(),
                category: "activeWorkoutState",
                sessionID: state.sessionId,
                phase: state.phase.rawValue,
                reason: reason,
                retryAttempt: 0
            )

            if let context = encodedContext {
                let applicationContext = self.makeApplicationContext(encoded: context)
                do {
                    try session.updateApplicationContext(applicationContext)
                    PulsarSyncDebugLogger.log("Active workout applicationContext updated session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) phase=\(state.phase.rawValue) reason=\(reason) transport=latestState")
                } catch {
                    PulsarSyncDebugLogger.log("Active workout live applicationContext failed session=\(state.sessionId.uuidString) error=\(error.localizedDescription)")
                }
            }

            if !isLiveMetricsUpdate {
                session.transferUserInfo(payload)
                PulsarSyncDebugLogger.log("Active workout state queued session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) phase=\(state.phase.rawValue) reason=\(reason) transport=durable")
            } else if !updatesApplicationContext {
                PulsarSyncDebugLogger.log("Active workout latest-state transmission throttled session=\(state.sessionId.uuidString) phase=\(state.phase.rawValue) reason=\(reason)")
            }
        }
    }

    @discardableResult
    private func decodeAndReceive(
        _ snapshot: PulsarWatchConnectivityIncomingSnapshot,
        reason: String
    ) async -> [ActiveWorkoutUpdateDecision] {
        let perfToken = PulsarPerformanceDiagnostics.begin(reason)
        defer { PulsarPerformanceDiagnostics.end(perfToken) }
        let decoded = await codecActor.decode(snapshot)
        if reason.hasPrefix("activationHydration") {
            if let state = decoded.activeWorkout, state.phase.isLive {
                restoredActiveWorkoutCandidate = state
            }
            if let state = decoded.activeGym, !state.isFinished {
                gymRestorationCandidate = state
            }
            let decisions = receive(
                decoded: decoded.activationHydrationSafeOnly(),
                reason: reason
            )
            #if os(iOS)
            let availability = watchRecorderAvailabilitySnapshot(reason: "\(reason).candidateValidation")
            discardRestoredWorkoutCandidates(
                reason: availability.rawIsWatchAppInstalled
                    ? "activationContextIsPersistedNotLive"
                    : "watchAppUnavailable"
            )
            #else
            restoredActiveWorkoutCandidate = nil
            #endif
            return decisions
        }
        if decoded.hasWorkoutCriticalPayload, decoded.hasNonWorkoutPayload {
            let decisions = receive(
                decoded: decoded.workoutCriticalOnly(),
                reason: "\(reason).workoutPriority"
            )
            deferNonWorkoutReceive(
                decoded.nonWorkoutOnly(),
                reason: "\(reason).deferredNonWorkout"
            )
            return decisions
        }
        return receive(decoded: decoded, reason: reason)
    }

    private func deferNonWorkoutReceive(
        _ payload: PulsarWatchConnectivityDecodedPayload,
        reason: String
    ) {
        pendingDeferredNonWorkoutPayloads.append((payload, reason))
        guard deferredNonWorkoutReceiveTask == nil else { return }
        deferredNonWorkoutReceiveTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            while !self.pendingDeferredNonWorkoutPayloads.isEmpty {
                let pending = self.pendingDeferredNonWorkoutPayloads
                self.pendingDeferredNonWorkoutPayloads.removeAll(keepingCapacity: true)
                for item in pending {
                    _ = self.receive(decoded: item.payload, reason: item.reason)
                }
                await Task.yield()
            }
            self.deferredNonWorkoutReceiveTask = nil
        }
    }

    @discardableResult
    private func receive(
        decoded: PulsarWatchConnectivityDecodedPayload,
        reason: String
    ) -> [ActiveWorkoutUpdateDecision] {
        let snapshot = decoded.snapshot
        var didApplyAnyPayload = false
        var activeWorkoutDecisions: [ActiveWorkoutUpdateDecision] = []

        #if os(iOS)
        if Self.isRuntimeCounterpartDelivery(reason: reason) {
            recordAppleWatchSeen(reason: reason, payloadKind: "watchConnectivity")
        }
        #endif

        if let messageID = snapshot.messageID {
            guard receivedWorkoutSyncMessageIDs.insert(messageID).inserted else {
                PulsarSyncDebugLogger.log("[PulsarWorkoutSync] duplicate message ignored reason=\(reason) message=\(messageID) category=\(snapshot.category ?? "unknown") session=\(snapshot.sessionID ?? "none")")
                return []
            }
            if receivedWorkoutSyncMessageIDs.count > 250 {
                receivedWorkoutSyncMessageIDs = [messageID]
            }
            PulsarSyncDebugLogger.log("[PulsarWorkoutSync] message received reason=\(reason) message=\(messageID) category=\(snapshot.category ?? "unknown") session=\(snapshot.sessionID ?? "none")")
        }

        if let heartbeat = decoded.heartbeat {
            didApplyAnyPayload = apply(watchHeartbeat: heartbeat, broadcast: false, reason: reason) || didApplyAnyPayload
        } else if snapshot.heartbeatData != nil {
            PulsarSyncDebugLogger.log("Skipped \(reason) Watch heartbeat because decoding failed")
        }

        if let payload = decoded.dailyMetrics {
            didApplyAnyPayload = apply(payload: payload, broadcast: false, reason: reason) || didApplyAnyPayload
        } else if snapshot.dailyMetricsData != nil {
            PulsarSyncDebugLogger.log("Skipped \(reason) metrics payload because decoding failed")
        }

        if let payload = decoded.sleepPreferences {
            didApplyAnyPayload = apply(sleepPreferences: payload, broadcast: false, reason: reason) || didApplyAnyPayload
        } else if snapshot.sleepPreferencesData != nil {
            PulsarSyncDebugLogger.log("Skipped \(reason) sleep preferences because decoding failed")
        }

        if let battery = decoded.appleWatchBattery, Self.isValidAppleWatchBattery(battery) {
            didApplyAnyPayload = apply(appleWatchBattery: battery, broadcast: false, reason: reason) || didApplyAnyPayload
        } else if snapshot.appleWatchBatteryData != nil || snapshot.batteryMessageType == Self.appleWatchBatteryMessageType {
            PulsarSyncDebugLogger.log("Skipped \(reason) Apple Watch battery because decoding failed")
        }

        if let state = decoded.activeWorkout {
            let canApplyGymDelta = decoded.activeGymDelta?.sessionID == activeGymState?.sessionId
            if snapshot.containsActiveGym || canApplyGymDelta {
                PulsarSyncDebugLogger.log("Skipped \(reason) derived active workout state because Active Gym state is in the same payload")
            } else if shouldRejectUncorrelatedCounterpartWorkout(state, reason: reason) {
                PulsarSyncDebugLogger.log("Rejected uncorrelated counterpart workout before publication source=\(reason) session=\(state.sessionId.uuidString) phase=\(state.phase.rawValue)")
            } else if state.phase.isLive,
                      !hasRuntimeWorkoutAuthority(sessionID: state.sessionId),
                      !Self.shouldAcceptFreshCounterpartWorkout(state, reason: reason) {
                PulsarSyncDebugLogger.log("Rejected unverified counterpart workout before publication source=\(reason) session=\(state.sessionId.uuidString) phase=\(state.phase.rawValue)")
            } else {
                let decision = apply(activeWorkoutState: state, broadcast: false, reason: reason, isIncomingFromCounterpart: true)
                activeWorkoutDecisions.append(decision)
                didApplyAnyPayload = decision.didApplySyncState || didApplyAnyPayload
            }
        } else if snapshot.containsActiveWorkout {
            PulsarSyncDebugLogger.log("Skipped \(reason) active workout state because decoding failed")
        }

        if let state = decoded.activeGym,
           shouldRejectUncorrelatedCounterpartGym(state, reason: reason) {
            PulsarSyncDebugLogger.log("Rejected uncorrelated counterpart gym before publication source=\(reason) session=\(state.sessionId.uuidString)")
        } else if let state = decoded.activeGym,
           !state.isFinished,
           !hasRuntimeWorkoutAuthority(sessionID: state.sessionId),
           !Self.shouldAcceptFreshCounterpartGym(state, reason: reason) {
            PulsarSyncDebugLogger.log("Rejected unverified counterpart gym before publication source=\(reason) session=\(state.sessionId.uuidString)")
        } else if let state = decoded.activeGym {
            let didApplyGymState = apply(activeGymState: state, broadcast: false, reason: reason, isIncomingFromCounterpart: true)
            didApplyAnyPayload = didApplyGymState || didApplyAnyPayload
            PulsarSyncDebugLogger.log("Active Gym state received via \(reason) session=\(state.sessionId.uuidString) progress=\(state.completedSets)/\(state.totalSets) finished=\(state.isFinished)")
            #if os(iOS)
            if didApplyGymState {
                if state.isFinished {
                    schedulePostTerminalGymPersistence(state)
                } else {
                    syncLiveActivity(for: state)
                }
            }
            #endif
        } else if snapshot.containsActiveGym {
            PulsarSyncDebugLogger.log("Skipped \(reason) Active Gym state because decoding failed")
        }

        if let delta = decoded.activeGymDelta,
           let currentState = activeGymState,
           let state = delta.applying(to: currentState) {
            let didApplyGymState = apply(activeGymState: state, broadcast: false, reason: reason, isIncomingFromCounterpart: true)
            didApplyAnyPayload = didApplyGymState || didApplyAnyPayload
            PulsarSyncDebugLogger.log("Active Gym live delta received via \(reason) session=\(state.sessionId.uuidString) progress=\(state.completedSets)/\(state.totalSets)")
            #if os(iOS)
            if didApplyGymState {
                if state.isFinished {
                    schedulePostTerminalGymPersistence(state)
                } else {
                    syncLiveActivity(for: state)
                }
            }
            #endif
        } else if snapshot.containsActiveGymDelta {
            PulsarSyncDebugLogger.log("Skipped \(reason) Active Gym live delta because baseline state or decoding was unavailable")
        }

        if let payload = decoded.savedGymRoutines {
            didApplyAnyPayload = storeSavedGymRoutines(
                payload.routines,
                revision: payload.revision,
                deletedRoutineIds: payload.deletedRoutineIds,
                broadcast: false,
                reason: reason
            ) || didApplyAnyPayload
        } else if snapshot.containsSavedGymRoutines {
            PulsarSyncDebugLogger.log("Skipped \(reason) saved Gym routines because decoding failed")
        }

        if let envelope = decoded.runTransportEnvelope {
            didApplyAnyPayload = true
            PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Run transport envelope received via \(reason) category=\(Self.runTransportEnvelopeMetadata(envelope).category)")
            runTransportEnvelopeHandler?(envelope, reason)
        } else if snapshot.containsRunTransportEnvelope {
            PulsarSyncDebugLogger.log("Skipped \(reason) run transport envelope because decoding failed")
        }

        if let messageType = snapshot.messageType {
            switch messageType {
            case Self.gymStartPrelaunchHintMessageType:
                didApplyAnyPayload = handleGymStartPrelaunchHint(snapshot, reason: reason) || didApplyAnyPayload
            case Self.gymStartAcknowledgementMessageType:
                didApplyAnyPayload = handleGymStartAcknowledgement(decoded.gymStartAcknowledgement, reason: reason) || didApplyAnyPayload
            case Self.gymRoutineSnapshotMessageType:
                didApplyAnyPayload = handleGymRoutineSnapshot(decoded.gymRoutineSnapshot, reason: reason) || didApplyAnyPayload
            default:
                break
            }
        }

        if let action = decoded.activeGymAction {
            didApplyAnyPayload = true
            PulsarSyncDebugLogger.log("Active Gym action received via \(reason) kind=\(action.kind.rawValue) session=\(action.sessionId?.uuidString ?? "none")")
            if let actionId = action.actionId {
                guard handledGymActionIDs.insert(actionId).inserted else {
                    PulsarSyncDebugLogger.log("[PulsarWorkoutSync] duplicate Active Gym action ignored kind=\(action.kind.rawValue) session=\(action.sessionId?.uuidString ?? "none") action=\(actionId.uuidString)")
                    return activeWorkoutDecisions
                }
                if handledGymActionIDs.count > 250 {
                    handledGymActionIDs = [actionId]
                }
            }
            if action.kind == .requestSavedRoutines {
                #if os(iOS)
                refreshSavedGymRoutinesFromPhoneStore(reason: "watchRequestedSavedRoutines")
                #endif
                sendSavedGymRoutinesToCounterpart(
                    respondingToVerifiedInboundRequest: true,
                    reason: "watchRequestedSavedRoutines"
                )
            }
            gymActionHandler?(action)
        } else if snapshot.containsGymAction {
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
    private static let activeGymLiveDeltaPayloadKey = "pulsar.activeGymWorkout.liveDelta.v2"
    private static let activeGymActionPayloadKey = "pulsar.activeGymWorkout.action.v1"
    private static let savedGymRoutinesPayloadKey = "pulsar.savedGymRoutines.payload.v1"
    private static let runTransportEnvelopePayloadKey = "pulsar.run.transportEnvelope.v1"
    private static let workoutSyncMessageIDKey = "pulsar.workoutSync.messageId.v1"
    private static let workoutSyncAcknowledgementMessageIDKey = "pulsar.workoutSync.ack.messageId.v1"
    private static let workoutSyncAcknowledgementAcceptedKey = "pulsar.workoutSync.ack.accepted.v1"
    private static let workoutSyncAcknowledgementReasonKey = "pulsar.workoutSync.ack.reason.v1"
    private static let workoutSyncCategoryKey = "pulsar.workoutSync.category.v1"
    private static let workoutSyncSessionIDKey = "pulsar.workoutSync.sessionId.v1"
    private static let workoutSyncPhaseKey = "pulsar.workoutSync.phase.v1"
    private static let workoutSyncSentAtKey = "pulsar.workoutSync.sentAt.v1"
    private static let workoutSyncRetryAttemptKey = "pulsar.workoutSync.retryAttempt.v1"
    private static let gymCrossDeviceMessageTypeKey = "pulsar.gymCrossDevice.messageType.v1"
    private static let gymStartPrelaunchHintMessageType = "gymWorkoutStartPrelaunchHint"
    private static let gymStartAcknowledgementMessageType = "gymWorkoutStartAcknowledgement"
    private static let gymRoutineSnapshotMessageType = "gymRoutineSnapshotEnvelope"

    @discardableResult
    private func handleGymStartPrelaunchHint(
        _ snapshot: PulsarWatchConnectivityIncomingSnapshot,
        reason: String
    ) -> Bool {
        guard let requestIDString = snapshot.prelaunchRequestID,
              let requestID = UUID(uuidString: requestIDString),
              let candidateSessionIDString = snapshot.prelaunchCandidateSessionID,
              let candidateSessionID = UUID(uuidString: candidateSessionIDString),
              let routineIDString = snapshot.prelaunchRoutineID,
              let routineID = UUID(uuidString: routineIDString),
              let requestedAt = snapshot.prelaunchRequestedAt.map({ Date(timeIntervalSince1970: $0) }) else {
            return false
        }
        let routineRevision = snapshot.prelaunchRoutineRevision ?? 0
        let workoutKindRaw = snapshot.prelaunchWorkoutKind ?? PulsarGymWorkoutKind.routine.rawValue
        let workoutKind = PulsarGymWorkoutKind(rawValue: workoutKindRaw) ?? .routine
        let request = GymWorkoutStartRequest(
            requestID: requestID,
            candidateSessionID: candidateSessionID,
            idempotencyKey: snapshot.prelaunchIdempotencyKey,
            routineID: routineID,
            routineRevision: routineRevision,
            workoutKind: workoutKind,
            activityTypeRawValue: UInt(HKWorkoutActivityType.traditionalStrengthTraining.rawValue),
            locationTypeRawValue: HKWorkoutSessionLocationType.indoor.rawValue,
            requestedAt: requestedAt,
            requestedFrom: .iPhoneRequestedWatchStart,
            requestState: .prelaunchHintSent
        )
        PulsarWorkoutLifecycleLogger.log(
            .wcReceive,
            sessionID: candidateSessionID,
            requestID: requestID,
            source: reason,
            messageType: Self.gymStartPrelaunchHintMessageType,
            transport: "watchConnectivity"
        )
        #if os(watchOS)
        Task { @MainActor in
            await WatchGymSessionManager.shared.handlePrelaunchHint(request)
        }
        #endif
        return true
    }

    @discardableResult
    private func handleGymStartAcknowledgement(
        _ acknowledgement: GymWorkoutStartAcknowledgement?,
        reason: String
    ) -> Bool {
        guard let acknowledgement else { return false }
        PulsarWorkoutLifecycleLogger.log(
            .wcReceive,
            sessionID: acknowledgement.authoritativeSessionID,
            requestID: acknowledgement.requestID,
            source: reason,
            messageType: Self.gymStartAcknowledgementMessageType,
            transport: "watchConnectivity"
        )
        gymStartAcknowledgementHandler?(acknowledgement, reason)
        return true
    }

    @discardableResult
    private func handleGymRoutineSnapshot(
        _ envelope: GymRoutineSnapshotEnvelope?,
        reason: String
    ) -> Bool {
        guard let envelope, envelope.isChecksumValid else { return false }
        let isTombstoned = isActiveWorkoutSessionTombstoned(envelope.sessionID)
        guard Self.shouldAcceptEmbeddedGymRoutineSnapshot(
            envelope,
            now: Date(),
            isTombstoned: isTombstoned
        ) else {
            PulsarSyncDebugLogger.log(
                "Rejected Gym routine snapshot with stale or mismatched start authority session=\(envelope.sessionID.uuidString) request=\(envelope.requestID.uuidString) tombstoned=\(isTombstoned)"
            )
            return false
        }
        PulsarWorkoutLifecycleLogger.log(
            .routineSnapshotReceived,
            sessionID: envelope.sessionID,
            requestID: envelope.requestID,
            source: reason,
            transport: "watchConnectivity"
        )
        gymRoutineSnapshotHandler?(envelope, reason)
        #if os(watchOS)
        Task { @MainActor in
            if let startRequest = envelope.startRequest {
                await WatchGymSessionManager.shared.handlePrelaunchHint(startRequest)
            }
            await WatchGymSessionManager.shared.hydrateRoutineSnapshot(envelope)
        }
        #endif
        return true
    }

    nonisolated static func shouldAcceptEmbeddedGymRoutineSnapshot(
        _ envelope: GymRoutineSnapshotEnvelope,
        now: Date,
        isTombstoned: Bool
    ) -> Bool {
        guard let request = envelope.startRequest else {
            // Legacy envelopes are correlated against an already-admitted
            // compact prelaunch request by WatchGymSessionManager.
            return true
        }
        guard request.requestID == envelope.requestID,
              request.candidateSessionID == envelope.sessionID,
              request.routineID == envelope.routineID,
              request.routineRevision == envelope.revision else {
            return false
        }
        return GymWorkoutStartRequestAdmission.accepts(
            requestedAt: request.requestedAt,
            now: now,
            isTombstoned: isTombstoned
        )
    }

    nonisolated static func shouldReplacePendingGymRoutineSnapshot(
        _ existing: GymRoutineSnapshotEnvelope?,
        with incoming: GymRoutineSnapshotEnvelope
    ) -> Bool {
        guard let existing else { return true }
        let hasSameIdentity = existing.sessionID == incoming.sessionID &&
            existing.requestID == incoming.requestID &&
            existing.routineID == incoming.routineID
        return !hasSameIdentity || incoming.revision >= existing.revision
    }

    private static func isValidAppleWatchBattery(_ snapshot: AppleWatchBatterySnapshot) -> Bool {
        (0...100).contains(snapshot.batteryPercentage)
    }

    private static func runTransportEnvelopeMetadata(
        _ envelope: PulsarRunTransportEnvelope
    ) -> (messageID: UUID, category: String, sessionID: UUID?, phase: String?) {
        switch envelope {
        case .startAcknowledgement(let acknowledgement):
            return (acknowledgement.requestID, "runStartAcknowledgement", acknowledgement.authoritativeSessionID, "running")
        case .sessionCommand(let command):
            return (command.commandId, "runSessionCommand", command.sessionId, command.command.rawValue)
        case .commandAcknowledgement(let acknowledgement):
            return (acknowledgement.commandId, "runCommandAcknowledgement", acknowledgement.sessionId, acknowledgement.phase.rawValue)
        case .identity(let identity):
            return (identity.sessionId, "runIdentity", identity.sessionId, identity.workoutKind.rawValue)
        case .summary(let summary):
            return (summary.id, "runSummary", summary.pulsarWorkoutSessionId, summary.workoutKind.rawValue)
        case .metrics(let snapshot):
            return (snapshot.pulsarWorkoutSessionId ?? UUID(), "runMetrics", snapshot.pulsarWorkoutSessionId, snapshot.phase.rawValue)
        case .routeDelta(let delta):
            return (delta.sessionId, "runRouteDelta", delta.sessionId, delta.workoutKind.rawValue)
        case .command(let command):
            return (UUID(), "runLegacyCommand", nil, command.rawValue)
        case .options:
            return (UUID(), "runOptions", nil, nil)
        }
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
        PulsarPerformanceSignposts.measure(
            PulsarPerformanceSignposts.watchConnectivity,
            name: "encode"
        ) {
            try? activeWorkoutEncoder.encode(state)
        }
    }

    private static func decodeActiveWorkoutState(_ data: Data) -> PulsarActiveWorkoutSyncState? {
        PulsarPerformanceSignposts.measure(
            PulsarPerformanceSignposts.watchConnectivity,
            name: "decode"
        ) {
            try? activeWorkoutDecoder.decode(PulsarActiveWorkoutSyncState.self, from: data)
        }
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
        now _: Date = Date()
    ) -> [UUID: Date] {
        Dictionary(
            uniqueKeysWithValues: tombstones
                .sorted { $0.value > $1.value }
                .prefix(activeWorkoutTombstoneRetentionLimit)
                .map { ($0.key, $0.value) }
        )
    }

    private static func isActiveWorkoutSessionTombstoned(
        _ sessionID: UUID,
        tombstones: [UUID: Date],
        now _: Date = Date()
    ) -> Bool {
        tombstones[sessionID] != nil
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
        setDefaultsData(data, forKey: activeWorkoutTombstoneCacheKey)
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

    private static var synchronizedGymPlatform: PulsarSynchronizedGymPlatform {
        #if os(watchOS)
        .watch
        #else
        .iPhone
        #endif
    }

    private static func shouldRestoreCachedActiveGymState(_ state: ActiveGymWorkoutState) -> Bool {
        PulsarWatchSynchronizedGymReconciliation.shouldRestoreCachedActiveGym(
            state,
            platform: synchronizedGymPlatform,
            isTombstoned: false
        )
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
                if current.phase == .ending {
                    PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Accepted terminal active workout update for pending finish source=\(reason) session=\(incoming.sessionId.uuidString) incomingUpdatedAt=\(incoming.updatedAt) currentUpdatedAt=\(current.updatedAt)")
                    return .endedCurrent(incoming.sessionId)
                }
                guard incoming.updatedAt >= current.updatedAt else {
                    PulsarSyncDebugLogger.log("Ignored stale terminal active workout update source=\(reason) session=\(incoming.sessionId.uuidString) phase=\(incoming.phase.rawValue) incomingUpdatedAt=\(incoming.updatedAt) currentUpdatedAt=\(current.updatedAt) action=noop")
                    return .ignoredHistoricalOnly
                }
                return .endedCurrent(incoming.sessionId)
            }
            if current.phase == .ending,
               incoming.phase.mergePriority < PulsarActiveWorkoutSyncPhase.ending.mergePriority {
                PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Ignored live phase downgrade while finish is pending source=\(reason) session=\(incoming.sessionId.uuidString) incomingPhase=\(incoming.phase.rawValue) currentPhase=\(current.phase.rawValue) action=noop")
                return .ignoredHistoricalOnly
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

        // Never let an ended update for a different session replace a live one.
        if incoming.isEnded, incoming.sessionId != current.sessionId {
            PulsarSyncDebugLogger.log(
                "Ignored ended active workout update for different live session live=\(current.sessionId.uuidString) incoming=\(incoming.sessionId.uuidString) source=\(reason) action=noop"
            )
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

    private func shouldApply(activeGymState incoming: ActiveGymWorkoutState, reason: String, isIncomingFromCounterpart: Bool) -> Bool {
        if incoming.isFinished, committedTerminalGymSessionID == incoming.sessionId {
            PulsarSyncDebugLogger.log(
                "Rejected duplicate terminal Active Gym update source=\(reason) session=\(incoming.sessionId.uuidString) action=noop"
            )
            return false
        }
        guard !Self.isExpiredFinishedGymState(incoming) else { return false }
        pruneActiveWorkoutTombstones()
        if Self.isActiveWorkoutSessionTombstoned(
                incoming.sessionId,
                tombstones: locallyTerminatedActiveWorkoutSessions
           ) {
            PulsarSyncDebugLogger.log("Rejected tombstoned Active Gym update source=activeGymState session=\(incoming.sessionId.uuidString) action=noop")
            return false
        }
        #if os(iOS)
        if isIncomingFromCounterpart,
           let authority = currentGymAuthorityDecision(for: incoming),
           case .rejectAdvisory(let decisionReason) = authority.decision {
            logRejectedGymAuthority(
                incoming: incoming,
                canonicalSessionID: authority.canonicalSessionID,
                canonicalRequestID: authority.canonicalRequestID,
                reason: reason,
                decisionReason: decisionReason
            )
            return false
        }
        #endif
        guard incoming.isFinished || incoming.isPrelaunchPlaceholder || incoming.isValidActiveWorkoutPresentationCandidate() else {
            PulsarSyncDebugLogger.log("active workout restore rejected: \(incoming.activeWorkoutPresentationRejectionReason() ?? incoming.staleRouteReason() ?? "invalid active gym state") session=\(incoming.sessionId.uuidString)")
            return false
        }
        if !PulsarWatchSynchronizedGymReconciliation.shouldAdoptIncomingGymState(
            incoming: incoming,
            current: activeGymState,
            platform: Self.synchronizedGymPlatform,
            isIncomingFromCounterpart: isIncomingFromCounterpart
        ) {
            PulsarSyncDebugLogger.log(
                "Watch rejected synchronized gym without primary session=\(incoming.sessionId.uuidString) source=\(reason) startedFrom=\(incoming.startedFrom?.rawValue ?? "unknown")"
            )
            return false
        }
        guard let current = activeGymState else { return true }

        if current.sessionId == incoming.sessionId {
            if current.isFinished, !incoming.isFinished {
                PulsarSyncDebugLogger.log("Rejected live Active Gym update for finished session session=\(incoming.sessionId.uuidString) incomingUpdatedAt=\(incoming.updatedAt) currentUpdatedAt=\(current.updatedAt) action=noop")
                return false
            }
            if incoming.isFinished, !current.isFinished { return true }
            if incoming.updatedAt == current.updatedAt {
                return incoming != current
            }
            return incoming.updatedAt > current.updatedAt
        }

        if current.isFinished {
            return incoming.updatedAt >= current.updatedAt || incoming.isValidActiveWorkoutPresentationCandidate()
        }

        // Never let a finished update for a different session replace a live one.
        if incoming.isFinished, incoming.sessionId != current.sessionId {
            PulsarSyncDebugLogger.log(
                "Rejected finished Active Gym update for different live session live=\(current.sessionId.uuidString) incoming=\(incoming.sessionId.uuidString) action=noop"
            )
            return false
        }

        if incoming.isFinished, incoming.startedAt < current.startedAt {
            return false
        }

        return incoming.startedAt >= current.startedAt || incoming.updatedAt >= current.updatedAt
    }

    #if os(iOS)
    private func logGymRemoteConflictIfNeeded(
        _ incoming: ActiveGymWorkoutState,
        applied: Bool,
        reason: String
    ) {
        guard !incoming.isFinished else { return }
        let expected = PulsarWorkoutStartCoordinator.shared.currentTransaction
        let expectedID = expected?.sessionID ?? activeGymState?.sessionId
        let expectedRequestID = expected?.requestID
        guard let expectedID, expectedID != incoming.sessionId else { return }
        guard stateStartedFromWatch(incoming) || reason.contains("received") else { return }
        PulsarWorkoutStartupTrace.remoteConflict(
            expectedWorkoutID: expectedID,
            expectedRequestID: expectedRequestID,
            watchWorkoutID: incoming.sessionId,
            watchRequestID: incoming.requestID,
            watchHKState: incoming.isFinished ? "finished" : "running",
            action: applied ? "reconcile" : "ignored"
        )
    }

    private func stateStartedFromWatch(_ state: ActiveGymWorkoutState) -> Bool {
        state.startedFrom?.isAppleWatchRecorder == true
    }
    #endif

    #if os(iOS)
    private func syncLiveActivity(for state: ActiveGymWorkoutState) {
        if state.isFinished {
            gymLiveActivityManager.end(state: state)
            persistFinishedGymWorkoutIfNeeded(state)
        } else {
            gymLiveActivityManager.startIfPossible(state: state)
        }
    }

    private func persistFinishedGymWorkoutIfNeeded(_ state: ActiveGymWorkoutState) {
        guard state.isFinished else { return }
        let historyStore = PulsarGymWorkoutHistoryStore.shared
        guard !historyStore.sessions.contains(where: { $0.id == state.sessionId && $0.finishedAt != nil }) else {
            PulsarSyncDebugLogger.log("Gym Activity Log skipped duplicate finished state session=\(state.sessionId.uuidString) type=\(state.workoutKind?.rawValue ?? "unknown")")
            return
        }
        PulsarSyncDebugLogger.log("Gym Activity Log persisting finished state session=\(state.sessionId.uuidString) type=\(state.workoutKind?.rawValue ?? "unknown") startedFrom=\(state.startedFrom?.rawValue ?? "unknown")")
            let startedAt = Date()
            historyStore.save(PulsarGymWorkoutSession(activeGymState: state))
            PulsarWorkoutStartupTrace.diag(
                "[MainActor] gymHistorySave elapsedMs=\(PulsarWorkoutStartupTrace.elapsedMs(since: startedAt)) workoutID=\(state.sessionId.uuidString) \(PulsarWorkoutStartupTrace.threadTag())"
            )
    }

    private func refreshSavedGymRoutinesFromPhoneStore(reason: String) {
        let routineStore = PulsarRoutineStore.shared
        routineStore.syncRoutinesToWatch(reason: reason, broadcast: false)
    }
    #endif
}

extension PulsarWatchConnectivitySyncStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        PulsarSyncDebugLogger.log("WatchConnectivity activation state=\(activationState.rawValue) error=\(error?.localizedDescription ?? "none")")
        let activationSnapshot = activationState == .activated && !session.receivedApplicationContext.isEmpty
            ? PulsarWatchConnectivityIncomingSnapshot(dictionary: session.receivedApplicationContext)
            : nil
        Task { @MainActor in
            self.lastActivationErrorMessage = error?.localizedDescription
            _ = self.watchRecorderAvailabilitySnapshot(reason: "activationDidComplete")
            if let activationSnapshot {
                await self.decodeAndReceive(activationSnapshot, reason: "activationHydration")
            }
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
        let snapshot = PulsarWatchConnectivityIncomingSnapshot(dictionary: applicationContext)
        Task { @MainActor in
            await decodeAndReceive(snapshot, reason: "receivedApplicationContext")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard !userInfo.isEmpty else {
            PulsarSyncDebugLogger.log("Skipped receivedUserInfo because payload was empty")
            return
        }

        let snapshot = PulsarWatchConnectivityIncomingSnapshot(dictionary: userInfo)
        Task { @MainActor in
            await decodeAndReceive(snapshot, reason: "receivedUserInfo")
        }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
        let info = userInfoTransfer.userInfo
        let descriptor = Self.userInfoTransferDescriptor(info)
        let message: String
        if let error {
            let nsError = error as NSError
            let missingFile = nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError
            message = "WC transferUserInfo finished error descriptor=\(descriptor) missingFile=\(missingFile) domain=\(nsError.domain) code=\(nsError.code) error=\(error.localizedDescription)"
        } else {
            message = "WC transferUserInfo finished success descriptor=\(descriptor)"
        }
        Task { @MainActor in
            PulsarWorkoutStartupTrace.lifecycle(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let snapshot = PulsarWatchConnectivityIncomingSnapshot(dictionary: message)
        Task { @MainActor in
            await decodeAndReceive(snapshot, reason: "receivedMessage")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let snapshot = PulsarWatchConnectivityIncomingSnapshot(dictionary: message)
        let acknowledgement = snapshot.acknowledgement(reason: "receivedMessageWithReply")
        replyHandler(acknowledgement)
        Task { @MainActor in
            await decodeAndReceive(snapshot, reason: "receivedMessageWithReply")
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            _ = self.watchRecorderAvailabilitySnapshot(reason: "sessionReachabilityDidChange")
            PulsarSyncDebugLogger.log("WatchConnectivity reachability changed reachable=\(session.isReachable)")
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            _ = self.watchRecorderAvailabilitySnapshot(reason: "sessionWatchStateDidChange")
            PulsarSyncDebugLogger.log("WatchConnectivity watch state changed paired=\(session.isPaired) installed=\(session.isWatchAppInstalled)")
        }
    }
    #endif

    #if os(watchOS)
    nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        Task { @MainActor in
            _ = self.watchRecorderAvailabilitySnapshot(reason: "sessionCompanionAppInstalledDidChange")
            PulsarSyncDebugLogger.log("WatchConnectivity companion installed changed installed=\(session.isCompanionAppInstalled)")
        }
    }
    #endif
}
