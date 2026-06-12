//
//  PulsarRunCoordinator.swift
//  Pulsar
//

import ActivityKit
import Combine
import CoreLocation
import CoreMotion
import HealthKit
import MapKit
import SwiftUI

struct PulsarRunLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var distanceMeters: Double
        var elapsedTime: TimeInterval
        var paceSecondsPerKilometer: Double?
        var heartRate: Double?
        var phase: PulsarRunPhase
    }

    var runID: UUID
}

enum PulsarRunRecorderStartMode {
    case automatic
    case iPhoneOnly
}

enum PulsarRunRecorderStartResult: Equatable {
    case started(PulsarRunRecordingSource)
    case needsFallback(PulsarWatchRecorderFallbackPrompt)
}

@MainActor
final class PulsarRunCoordinator: NSObject, ObservableObject {
    @Published private(set) var snapshot = PulsarRunMetricSnapshot.empty
    @Published private(set) var summary: PulsarRunSummary?
    @Published private(set) var authorizationMessage: String?
    @Published private(set) var preferredSource: PulsarRunRecordingSource = .iPhone
    @Published private(set) var isWatchAvailable = false
    @Published private(set) var activeWorkoutKind: PulsarOutdoorWorkoutKind = .running
    @Published private(set) var heartRateSourceStatus: WorkoutHeartRateFallbackStatus?
    @Published private(set) var heartRateSourceBanner: String?
    @Published private(set) var adaptiveWorkoutCoaching: AdaptiveWorkoutCoaching?
    @Published var liveWatchFallbackPrompt: PulsarWatchRecorderFallbackPrompt?

    private let healthStore = HKHealthStore()
    private let historyStore = PulsarRunHistoryStore()
    private let pedometer = CMPedometer()
    private let syncStore = PulsarWatchConnectivitySyncStore.shared

    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var locationManager: CLLocationManager?
    private var liveActivity: Activity<PulsarRunLiveActivityAttributes>?
    private var lastLiveActivityContentState: PulsarRunLiveActivityAttributes.ContentState?
    private var lastLiveActivityContentUpdateAt: Date?
    private var tickTask: Task<Void, Never>?
    private var mirrorFallbackTask: Task<Void, Never>?
    private var pendingMirroredSessionVerificationTask: Task<Void, Never>?
    private var finishRetryTask: Task<Void, Never>?
    private lazy var heartRateFallbackMonitor = WorkoutHeartRateFallbackMonitor(healthStore: healthStore)
    private var heartRateSourceBannerTask: Task<Void, Never>?
    private var adaptiveCoachingBannerTask: Task<Void, Never>?
    private var syncStoreCancellables = Set<AnyCancellable>()

    private var options = PulsarRunOptions.default
    private var startDate: Date?
    private var pauseBeganAt: Date?
    private var accumulatedPausedTime: TimeInterval = 0
    private var gpsDistanceFilter = PulsarRunGPSDistanceFilter()
    private var lastAcceptedAltitude: Double?
    private var recentMovingSamples: [(date: Date, distanceMeters: Double)] = []
    private var splitStartDistance: Double = 0
    private var splitStartMovingTime: TimeInterval = 0
    private var splitElevationGain: Double = 0
    private var splitElevationLoss: Double = 0
    private var splitHeartRates: [Double] = []
    private var heartRates: [Double] = []
    private var autoPauseCandidateSince: Date?
    private var activeWorkoutStartedFrom: PulsarWorkoutStartedFrom?
    private var heartRateSourceHistory: [WorkoutHeartRateSourceSegment] = []
    private var fallbackEnergyEstimator = WorkoutHeartRateFallbackEnergyEstimator()
    private var adaptiveStrainPlan: AdaptiveStrainPlan?
    private var adaptiveHeartRateSamples: [AdaptiveHeartRateSample] = []
    private var lastAdaptiveCoachingID: String?
    private var lastAdaptiveCoachingAt: Date?
    private var isFinishing = false
    private var didChooseIPhoneFallbackAfterWatchAttempt = false
    private var lastIPhoneMetricsPublishedAt = Date.distantPast
    private static let liveActivityElapsedOnlyUpdateInterval: TimeInterval = 10

    override init() {
        super.init()
        registerWorkoutMirroringHandler()
        configureHeartRateFallbackMonitor()
        syncStore.setRunTransportEnvelopeHandler { [weak self] envelope, reason in
            self?.receiveRemoteEnvelope(envelope, reason: "watchConnectivity.\(reason)")
        }
        syncStore.$lastWatchRecorderAvailability
            .compactMap { $0 }
            .sink { [weak self] availability in
                Task { @MainActor in
                    self?.applyPreferredSource(availability)
                }
            }
            .store(in: &syncStoreCancellables)
        updatePreferredSource()
    }

    func refreshAvailability() {
        updatePreferredSource()
    }

    func setAdaptiveStrainPlan(_ plan: AdaptiveStrainPlan?, reason: String) {
        adaptiveStrainPlan = plan
        PulsarSyncDebugLogger.log("[PulsarAdaptiveStrainGuard] run plan updated reason=\(reason) target=\(plan?.recommendedRange.displayText ?? "nil") priority=\(plan?.recoveryPriority.rawValue ?? "nil")")
    }

    func watchRecorderAvailability(for workoutKind: PulsarOutdoorWorkoutKind) async -> PulsarWatchRecorderAvailabilitySnapshot {
        let availability = await syncStore.waitForReachableWatchRecorder(
            reason: "iPhoneOutdoorStart.\(workoutKind.rawValue)"
        )
        applyPreferredSource(availability)
        PulsarSyncDebugLogger.log("Workout recorder preflight type=\(workoutKind.rawValue) activation=\(availability.activationStateDescription) paired=\(availability.isPaired) rawInstalled=\(availability.rawIsWatchAppInstalled) rawReachable=\(availability.rawIsReachable) lastWatchSeenAt=\(availability.lastWatchSeenAt?.description ?? "none") derivedInstalled=\(availability.isWatchAppInstalled) derivedReachable=\(availability.derivedReachabilityDescription) selected=\(availability.canStartOnWatch ? "AppleWatch" : "prompt") fallback=\(availability.fallbackReason?.logValue ?? "none")")
        return availability
    }

    var hasAnyValidatedLiveWorkoutSession: Bool {
        guard let sessionID = snapshot.pulsarWorkoutSessionId else { return false }
        return hasValidatedLiveWorkoutSession(sessionID: sessionID)
    }

    func hasValidatedLiveWorkoutSession(sessionID: UUID) -> Bool {
        guard snapshot.pulsarWorkoutSessionId == sessionID,
              let workoutSession else { return false }
        switch workoutSession.state {
        case .prepared, .running, .paused:
            return snapshot.phase.isLiveRunPhase
        case .notStarted, .stopped, .ended:
            return false
        @unknown default:
            return false
        }
    }

    @discardableResult
    func ensureActiveWorkoutSessionID(reason: String) -> UUID? {
        if let sessionID = snapshot.pulsarWorkoutSessionId {
            return sessionID
        }

        guard snapshot.phase.isLiveRunPhase else { return nil }
        let sessionID = UUID()
        snapshot.pulsarWorkoutSessionId = sessionID
        PulsarSyncDebugLogger.log("Run active session repaired reason=\(reason) session=\(sessionID.uuidString) type=\(activeWorkoutKind.rawValue)")
        publishActiveWorkoutState(
            updatedFrom: snapshot.source == .appleWatch ? .appleWatch : .iPhone,
            reason: "activeRunSessionRepair.\(reason)"
        )
        return sessionID
    }

    func requestPermissions(for workoutKind: PulsarOutdoorWorkoutKind = .running) async {
        snapshot.phase = .requestingPermissions
        authorizationMessage = nil

        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationMessage = "Apple Health is not available on this device."
            snapshot.phase = .idle
            return
        }

        do {
            try await healthStore.requestAuthorization(toShare: Self.healthShareTypes, read: Self.healthReadTypes)
            ensureLocationManager()
            if locationManager?.authorizationStatus == .notDetermined {
                locationManager?.requestWhenInUseAuthorization()
            }
            snapshot.phase = .idle
        } catch {
            authorizationMessage = "Pulsar needs Health and Location access to record outdoor \(workoutKind.actionName)s."
            snapshot.phase = .idle
        }
    }

    func startRun(options: PulsarRunOptions) async {
        await startOutdoorWorkout(.running, options: options)
    }

    @discardableResult
    func startOutdoorWorkout(
        _ workoutKind: PulsarOutdoorWorkoutKind,
        options: PulsarRunOptions,
        startMode: PulsarRunRecorderStartMode = .automatic
    ) async -> PulsarRunRecorderStartResult {
        PulsarStateDebugLogger.log("Workout start requested type=\(workoutKind.rawValue)")
        self.options = options
        summary = nil
        activeWorkoutKind = workoutKind
        let sessionId = UUID()
        let shouldTryWatch = options.prefersWatchRecorder && startMode == .automatic
        if shouldTryWatch {
            let availability = await watchRecorderAvailability(for: workoutKind)
            guard availability.canStartOnWatch else {
                let prompt = availability.fallbackPrompt(workoutName: workoutKind.displayName)
                PulsarSyncDebugLogger.log("Workout recorder selected=iPhoneFallbackPrompt type=\(workoutKind.rawValue) reason=\(prompt.reason.logValue) session=\(sessionId.uuidString)")
                return .needsFallback(prompt)
            }

            let requestedStart = Date()
            resetRuntimeState(
                source: .appleWatch,
                workoutKind: workoutKind,
                pulsarWorkoutSessionId: sessionId,
                startedFrom: .iPhoneRequestedWatchStart
            )
            didChooseIPhoneFallbackAfterWatchAttempt = false
            snapshot.phase = .connectingToWatch
            snapshot.startedAt = requestedStart
            startDate = requestedStart
            snapshot.statusMessage = watchStartStatusMessage(for: availability)
            PulsarSyncDebugLogger.log("Run start selectedType=\(workoutKind.rawValue) hkType=\(workoutKind.healthKitActivityType.rawValue) session=\(sessionId.uuidString) startedFrom=\(PulsarWorkoutStartedFrom.iPhoneRequestedWatchStart.rawValue) selectedRecorder=AppleWatch activation=\(availability.activationStateDescription) paired=\(availability.isPaired) rawInstalled=\(availability.rawIsWatchAppInstalled) rawReachable=\(availability.rawIsReachable) lastWatchSeenAt=\(availability.lastWatchSeenAt?.description ?? "none") derivedInstalled=\(availability.isWatchAppInstalled) derivedReachable=\(availability.derivedReachabilityDescription)")
            publishActiveWorkoutState(phase: .starting, updatedFrom: .iPhone, reason: "iPhoneRunStartingWatch")

            do {
                try await healthStore.startWatchApp(toHandle: Self.outdoorWorkoutConfiguration(for: workoutKind))
                beginMirrorConnectionWatchdog()
                return .started(.appleWatch)
            } catch {
                if shouldKeepQueuedWatchStart(for: availability) {
                    snapshot.statusMessage = "Waiting for Apple Watch..."
                    beginMirrorConnectionWatchdog()
                    PulsarSyncDebugLogger.log("Run Watch start queued after launch failure type=\(workoutKind.rawValue) session=\(sessionId.uuidString) rawReachable=\(availability.rawIsReachable) derivedReachable=\(availability.derivedReachabilityDescription) error=\(error.localizedDescription)")
                    return .started(.appleWatch)
                }
                let prompt = availability.fallbackPrompt(
                    workoutName: workoutKind.displayName,
                    reason: .watchLaunchFailed,
                    errorMessage: error.localizedDescription
                )
                authorizationMessage = prompt.message
                snapshot.phase = .idle
                snapshot.statusMessage = nil
                syncStore.clearActiveWorkoutState(reason: "iPhoneRunWatchLaunchFailed", broadcastEndedState: false)
                PulsarSyncDebugLogger.log("Workout recorder selected=iPhoneFallbackPrompt type=\(workoutKind.rawValue) reason=\(prompt.reason.logValue) session=\(sessionId.uuidString) error=\(error.localizedDescription)")
                return .needsFallback(prompt)
            }
        }

        resetRuntimeState(
            source: .iPhone,
            workoutKind: workoutKind,
            pulsarWorkoutSessionId: sessionId,
            startedFrom: .iPhone
        )
        didChooseIPhoneFallbackAfterWatchAttempt = startMode == .iPhoneOnly
        PulsarSyncDebugLogger.log("Run start selectedType=\(workoutKind.rawValue) hkType=\(workoutKind.healthKitActivityType.rawValue) session=\(sessionId.uuidString) startedFrom=iPhone selectedRecorder=iPhone fallbackReason=\(startMode == .iPhoneOnly ? "userSelectedIPhone" : "watchPreferenceDisabled")")
        do {
            try await startIPhoneWorkout()
            return .started(.iPhone)
        } catch {
            snapshot.phase = .failed
            snapshot.statusMessage = error.localizedDescription
            authorizationMessage = "Pulsar could not start a \(workoutKind.displayName.lowercased()) workout. Check Health and Location permissions."
            let prompt = PulsarWatchRecorderFallbackPrompt(
                reason: .watchLaunchFailed,
                title: "Workout could not start",
                message: authorizationMessage ?? "Pulsar could not start this workout."
            )
            return .needsFallback(prompt)
        }
    }

    func pause() {
        if snapshot.source == .appleWatch {
            sendRemoteCommand(.pause, reason: "iPhoneRunPauseRemote")
        }
        pauseWorkoutSessionIfRunning(reason: "iPhoneRunPause")
        applyPausedState(date: Date())
        publishActiveWorkoutState(phase: .paused, updatedFrom: .iPhone, reason: "iPhoneRunPaused")
    }

    func resume() {
        if snapshot.source == .appleWatch {
            sendRemoteCommand(.resume, reason: "iPhoneRunResumeRemote")
        }
        guard resumeWorkoutSessionIfPaused(reason: "iPhoneRunResume") || snapshot.phase == .paused else {
            PulsarSyncDebugLogger.log("Run resume skipped because workout is not paused session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") phase=\(snapshot.phase.rawValue)")
            return
        }
        applyRunningState(date: Date())
        publishActiveWorkoutState(phase: .resumed, updatedFrom: .iPhone, reason: "iPhoneRunResumed")
    }

    func finish() {
        if snapshot.phase == .finishing, snapshot.source == .appleWatch {
            sendRemoteCommand(.finish, reason: "iPhoneRunFinishRetryTap")
            publishActiveWorkoutState(phase: .ending, updatedFrom: .iPhone, reason: "iPhoneRunEndingRetryTap")
            return
        }
        guard snapshot.phase == .running || snapshot.phase == .paused || snapshot.phase == .connectingToWatch else { return }
        snapshot.phase = .finishing
        snapshot.statusMessage = "Finishing workout..."
        publishActiveWorkoutState(phase: .ending, updatedFrom: .iPhone, reason: "iPhoneRunEnding")
        if snapshot.source == .appleWatch {
            sendRemoteCommand(.finish, reason: "iPhoneRunFinishRemote")
            beginRemoteFinishRetryWatchdog()
            return
        }
        guard workoutSession != nil else {
            finalizeWorkoutWithoutHealthKitSession(reason: "iPhoneRunFinishNoHealthKitSession")
            return
        }
        endWorkoutSessionIfNeeded(reason: "iPhoneRunFinish")
    }

    func resetAfterSummary() {
        summary = nil
        snapshot = .empty
        adaptiveWorkoutCoaching = nil
        adaptiveHeartRateSamples = []
        lastAdaptiveCoachingID = nil
        lastAdaptiveCoachingAt = nil
        cleanupRuntime()
    }

    func history() async -> [PulsarRunSummary] {
        await historyStore.loadRuns(healthStore: healthStore)
    }

    func history(for workoutKind: PulsarOutdoorWorkoutKind) async -> [PulsarRunSummary] {
        await historyStore.loadRuns(healthStore: healthStore).filter { $0.workoutKind == workoutKind }
    }

    func reconcileActiveWorkoutSyncState(_ state: PulsarActiveWorkoutSyncState) {
        guard let workoutKind = state.kind.outdoorWorkoutKind else { return }
        guard state.isEnded || !syncStore.isActiveWorkoutSessionTombstoned(state.sessionId) else {
            PulsarSyncDebugLogger.log("Run sync state ignored because session is tombstoned session=\(state.sessionId.uuidString) phase=\(state.phase.rawValue)")
            return
        }
        guard state.lastUpdatedFrom != .iPhone || snapshot.pulsarWorkoutSessionId != state.sessionId else { return }

        if state.isEnded {
            if snapshot.pulsarWorkoutSessionId != state.sessionId {
                resetRuntimeState(
                    source: state.startedFrom.isAppleWatchRecorder ? .appleWatch : .iPhone,
                    workoutKind: workoutKind,
                    pulsarWorkoutSessionId: state.sessionId,
                    startedFrom: state.startedFrom
                )
                snapshot.startedAt = state.startedAt
                startDate = state.startedAt
            }
            snapshot.phase = state.phase.runPhase
            snapshot.endedAt = state.endedAt ?? Date()
            snapshot.elapsedTime = TimeInterval(state.elapsedSeconds)
            snapshot.currentHeartRate = state.currentHeartRate ?? snapshot.currentHeartRate
            snapshot.activeEnergyKilocalories = state.activeEnergyKilocalories ?? snapshot.activeEnergyKilocalories
            applySyncedRunMetrics(from: state, reason: "endedActiveWorkoutSync")
            activeWorkoutKind = workoutKind
            finishRetryTask?.cancel()
            finishRetryTask = nil
            if summary == nil {
                let finishedSummary = makeSummary(workoutUUID: nil)
                summary = finishedSummary
                Task { await historyStore.save(finishedSummary) }
            }
            endLiveActivity(reason: "endedActiveWorkoutSync")
            PulsarSyncDebugLogger.log("Run UI reconciled ended sync state session=\(state.sessionId.uuidString) type=\(workoutKind.rawValue) phase=\(state.phase.rawValue)")
            return
        }

        if snapshot.pulsarWorkoutSessionId != state.sessionId {
            resetRuntimeState(
                source: state.startedFrom.isAppleWatchRecorder ? .appleWatch : .iPhone,
                workoutKind: workoutKind,
                pulsarWorkoutSessionId: state.sessionId,
                startedFrom: state.startedFrom
            )
            snapshot.startedAt = state.startedAt
            startDate = state.startedAt
            PulsarSyncDebugLogger.log("Run data attached from sync state session=\(state.sessionId.uuidString) type=\(workoutKind.rawValue) phase=\(state.phase.rawValue) startedFrom=\(state.startedFrom.rawValue)")
        }

        let previousPhase = snapshot.phase
        if previousPhase == .finishing,
           snapshot.pulsarWorkoutSessionId == state.sessionId,
           state.phase.mergePriority < PulsarActiveWorkoutSyncPhase.ending.mergePriority,
           summary == nil {
            snapshot.elapsedTime = TimeInterval(state.elapsedSeconds)
            snapshot.currentHeartRate = state.currentHeartRate ?? snapshot.currentHeartRate
            snapshot.activeEnergyKilocalories = state.activeEnergyKilocalories ?? snapshot.activeEnergyKilocalories
            applySyncedRunMetrics(from: state, reason: "activeWorkoutSyncWhileFinishing")
            activeWorkoutKind = workoutKind
            PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Ignored active workout phase downgrade while finish is pending session=\(state.sessionId.uuidString) incomingPhase=\(state.phase.rawValue) currentPhase=\(previousPhase.rawValue)")
            return
        }
        snapshot.phase = state.phase.runPhase
        snapshot.elapsedTime = TimeInterval(state.elapsedSeconds)
        snapshot.currentHeartRate = state.currentHeartRate ?? snapshot.currentHeartRate
        snapshot.activeEnergyKilocalories = state.activeEnergyKilocalories ?? snapshot.activeEnergyKilocalories
        applySyncedRunMetrics(from: state, reason: "activeWorkoutSync")
        activeWorkoutKind = workoutKind
        if snapshot.phase.isLiveRunPhase {
            startLiveActivityIfPossible()
        }

        if state.lastUpdatedFrom == .appleWatch {
            switch state.phase {
            case .paused:
                if previousPhase != .paused {
                    pauseWorkoutSessionIfRunning(reason: "watchRunSyncPaused")
                    applyPausedState(date: state.updatedAt)
                }
            case .active, .resumed:
                if previousPhase == .paused {
                    _ = resumeWorkoutSessionIfPaused(reason: "watchRunSyncResumed")
                    applyRunningState(date: state.updatedAt)
                } else {
                    logResumeSkippedIfAlreadyRunning(reason: "watchRunSyncActive")
                }
            case .ending, .ended:
                finish()
            case .starting, .failed, .cancelled:
                break
            }
        }
    }

    private func applySyncedRunMetrics(from state: PulsarActiveWorkoutSyncState, reason: String) {
        guard state.runMetricsUpdatedAt != nil else { return }
        if state.lastUpdatedFrom == .appleWatch,
           state.currentHeartRate != nil {
            heartRateFallbackMonitor.recordExternalPrimaryHeartRate(sourceKind: .appleWatch, sampledAt: state.runMetricsUpdatedAt ?? state.updatedAt)
        }
        snapshot.movingTime = TimeInterval(state.movingSeconds ?? Int(snapshot.movingTime.rounded()))
        if let distanceMeters = state.distanceMeters {
            snapshot.distanceMeters = max(0, distanceMeters)
        }
        snapshot.currentPaceSecondsPerKilometer = state.currentPaceSecondsPerKilometer
        snapshot.averagePaceSecondsPerKilometer = state.averagePaceSecondsPerKilometer
        snapshot.splitPaceSecondsPerKilometer = state.splitPaceSecondsPerKilometer
        snapshot.activeSplitIndex = state.activeSplitIndex ?? snapshot.activeSplitIndex
        snapshot.elevationGainMeters = max(0, state.elevationGainMeters ?? snapshot.elevationGainMeters)
        snapshot.elevationLossMeters = max(0, state.elevationLossMeters ?? snapshot.elevationLossMeters)
        snapshot.currentElevationMeters = state.currentElevationMeters
        snapshot.averageHeartRate = state.averageHeartRate
        snapshot.maxHeartRate = state.maxHeartRate
        snapshot.stepCount = state.stepCount
        snapshot.cadenceStepsPerMinute = state.cadenceStepsPerMinute
        if let currentHeartRate = state.currentHeartRate {
            recordAdaptiveWorkoutHeartRate(
                currentHeartRate,
                sampledAt: state.runMetricsUpdatedAt ?? state.updatedAt,
                workoutKind: state.kind.outdoorWorkoutKind ?? activeWorkoutKind,
                reason: reason
            )
        }
        appendLastSyncedRoutePointIfNeeded(from: state)
        PulsarSyncDebugLogger.log("Run live metrics applied from \(reason) session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) recorderSource=\(state.lastUpdatedFrom.rawValue) distanceMeters=\(state.distanceMeters ?? -1) elapsedSeconds=\(state.elapsedSeconds) movingSeconds=\(state.movingSeconds ?? -1) pace=\(state.currentPaceSecondsPerKilometer ?? -1) calories=\(state.activeEnergyKilocalories ?? -1) heartRate=\(state.currentHeartRate ?? -1) sampleTimestamp=\(state.runMetricsUpdatedAt?.description ?? "none")")
    }

    private func appendLastSyncedRoutePointIfNeeded(from state: PulsarActiveWorkoutSyncState) {
        guard let latitude = state.lastLatitude,
              let longitude = state.lastLongitude,
              let timestamp = state.lastLocationUpdatedAt else { return }
        guard snapshot.route.last?.timestamp != timestamp else { return }
        if let lastPoint = snapshot.route.last,
           timestamp < lastPoint.timestamp {
            return
        }
        snapshot.route.append(
            PulsarRunCoordinate(
                latitude: latitude,
                longitude: longitude,
                altitude: state.currentElevationMeters,
                timestamp: timestamp
            )
        )
        if let routePointCount = state.routePointCount,
           snapshot.route.count > routePointCount {
            snapshot.route = Array(snapshot.route.suffix(routePointCount))
        }
    }

    private func appendRouteDelta(_ points: [PulsarRunCoordinate]) {
        guard !points.isEmpty else { return }
        let existingIDs = Set(snapshot.route.map(\.id))
        let newPoints = points
            .filter { !existingIDs.contains($0.id) }
            .sorted { $0.timestamp < $1.timestamp }
        guard !newPoints.isEmpty else { return }
        snapshot.route.append(contentsOf: newPoints)
        snapshot.route.sort { $0.timestamp < $1.timestamp }
        PulsarSyncDebugLogger.log("Run route delta appended session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") count=\(newPoints.count) total=\(snapshot.route.count)")
    }

    private func startIPhoneWorkout() async throws {
        snapshot.source = .iPhone
        snapshot.phase = .running
        snapshot.startedAt = Date()
        startDate = snapshot.startedAt

        let configuration = Self.outdoorWorkoutConfiguration(for: activeWorkoutKind)
        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self

        workoutSession = session
        workoutBuilder = builder
        routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)

        let start = snapshot.startedAt ?? Date()
        startWorkoutSessionIfNeeded(session, at: start, reason: "iPhoneRunHealthKitStart")
        try await builder.beginCollection(at: start)
        addMetadata(
            workoutMetadata(startedFrom: .iPhone),
            to: builder,
            context: "iPhone outdoor workout"
        )
        startHeartRateFallbackMonitoring(primarySource: .unknown, startedAt: start)
        publishActiveWorkoutState(phase: .active, updatedFrom: .iPhone, reason: "iPhoneRunHealthKitStarted")

        startLocationUpdates()
        startPedometerUpdates(from: start)
        startTicking()
        startLiveActivityIfPossible()
    }

    private func startWorkoutSessionIfNeeded(_ session: HKWorkoutSession, at start: Date, reason: String) {
        switch session.state {
        case .notStarted, .prepared:
            session.startActivity(with: start)
            PulsarSyncDebugLogger.log("Run HealthKit startActivity applied reason=\(reason) state=\(Self.describe(session.state)) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
        case .running, .paused:
            PulsarSyncDebugLogger.log("Run HealthKit startActivity skipped because session already started reason=\(reason) state=\(Self.describe(session.state)) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
        case .stopped, .ended:
            PulsarSyncDebugLogger.log("Run HealthKit startActivity skipped because session is terminal reason=\(reason) state=\(Self.describe(session.state)) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
        @unknown default:
            PulsarSyncDebugLogger.log("Run HealthKit startActivity skipped for unknown state reason=\(reason) state=\(session.state.rawValue) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
        }
    }

    @discardableResult
    private func pauseWorkoutSessionIfRunning(reason: String) -> Bool {
        guard let workoutSession else {
            PulsarSyncDebugLogger.log("Run HealthKit pause skipped because session is nil reason=\(reason) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return false
        }

        switch workoutSession.state {
        case .running:
            workoutSession.pause()
            PulsarSyncDebugLogger.log("Run HealthKit pause applied reason=\(reason) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return true
        case .paused:
            PulsarSyncDebugLogger.log("Run HealthKit pause skipped because session already paused reason=\(reason) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return false
        default:
            PulsarSyncDebugLogger.log("Run HealthKit pause skipped because session is not running reason=\(reason) state=\(Self.describe(workoutSession.state)) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return false
        }
    }

    @discardableResult
    private func resumeWorkoutSessionIfPaused(reason: String) -> Bool {
        guard let workoutSession else {
            PulsarSyncDebugLogger.log("Run HealthKit resume skipped because session is nil reason=\(reason) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return false
        }

        switch workoutSession.state {
        case .paused:
            workoutSession.resume()
            PulsarSyncDebugLogger.log("Run HealthKit resume applied reason=\(reason) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return true
        case .running:
            PulsarSyncDebugLogger.log("Run HealthKit resume skipped because session already running reason=\(reason) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return false
        default:
            PulsarSyncDebugLogger.log("Run HealthKit resume skipped because session is not paused reason=\(reason) state=\(Self.describe(workoutSession.state)) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return false
        }
    }

    private func logResumeSkippedIfAlreadyRunning(reason: String) {
        guard let workoutSession else { return }
        if workoutSession.state == .running {
            PulsarSyncDebugLogger.log("Run HealthKit resume skipped because session already running reason=\(reason) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
        }
    }

    private func endWorkoutSessionIfNeeded(reason: String) {
        guard let workoutSession else {
            PulsarSyncDebugLogger.log("Run HealthKit end skipped because session is nil reason=\(reason) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return
        }

        switch workoutSession.state {
        case .ended, .stopped:
            PulsarSyncDebugLogger.log("Run HealthKit end skipped because session is already terminal reason=\(reason) state=\(Self.describe(workoutSession.state)) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
        default:
            let end = Date()
            workoutSession.stopActivity(with: end)
            scheduleLocalFinishFallback(reason: reason, requestedAt: end)
            PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Run HealthKit stopActivity requested reason=\(reason) state=\(Self.describe(workoutSession.state)) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
        }
    }

    private func scheduleLocalFinishFallback(reason: String, requestedAt: Date) {
        finishRetryTask?.cancel()
        finishRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                guard let self,
                      self.snapshot.source == .iPhone,
                      self.snapshot.phase == .finishing,
                      self.summary == nil,
                      !self.isFinishing else { return }
                PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Run HealthKit stopped callback timed out; finishing builder fallback reason=\(reason) session=\(self.snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") requestedAt=\(requestedAt)")
                Task { @MainActor in
                    await self.finishIPhoneWorkout()
                }
            }
        }
    }

    private func beginRemoteFinishRetryWatchdog() {
        finishRetryTask?.cancel()
        finishRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                guard let self,
                      self.snapshot.source == .appleWatch,
                      self.snapshot.phase == .finishing,
                      self.summary == nil else { return }
                self.snapshot.statusMessage = "Still finishing on Apple Watch..."
                self.sendRemoteCommand(.finish, reason: "iPhoneRunFinishRetry")
                self.publishActiveWorkoutState(phase: .ending, updatedFrom: .iPhone, reason: "iPhoneRunEndingRetry")
            }
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            await MainActor.run {
                guard let self,
                      self.snapshot.source == .appleWatch,
                      self.snapshot.phase == .finishing,
                      self.summary == nil else { return }
                self.snapshot.statusMessage = "Open Pulsar on Apple Watch to recover finish."
                PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Run remote finish still pending session=\(self.snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            }
        }
    }

    private func attachMirroredSession(_ session: HKWorkoutSession) {
        mirrorFallbackTask?.cancel()
        pendingMirroredSessionVerificationTask?.cancel()
        if didChooseIPhoneFallbackAfterWatchAttempt,
           snapshot.source == .iPhone,
           snapshot.phase.isLiveRunPhase {
            PulsarSyncDebugLogger.log("Late Apple Watch mirror rejected because iPhone fallback is already recording type=\(PulsarOutdoorWorkoutKind(activityType: session.workoutConfiguration.activityType).rawValue) currentSession=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            session.end()
            return
        }
        let workoutKind = PulsarOutdoorWorkoutKind(activityType: session.workoutConfiguration.activityType)
        let shouldPreservePhoneRequestedSession =
            activeWorkoutStartedFrom == .iPhoneRequestedWatchStart ||
            snapshot.phase == .connectingToWatch
        let phoneStartedSessionId = shouldPreservePhoneRequestedSession ? snapshot.pulsarWorkoutSessionId : nil
        let syncedState = matchingMirroredActiveWorkoutState(for: workoutKind)
        if phoneStartedSessionId == nil, syncedState == nil {
            waitForMirroredSessionIdentity(session, workoutKind: workoutKind)
            return
        }
        let mirroredSessionId = phoneStartedSessionId ?? syncedState?.sessionId
        let startedFrom: PulsarWorkoutStartedFrom = phoneStartedSessionId == nil
            ? (syncedState?.startedFrom ?? .appleWatch)
            : .iPhoneRequestedWatchStart
        cleanupRuntime(keepsSnapshot: true)
        resetRuntimeState(
            source: .appleWatch,
            workoutKind: workoutKind,
            pulsarWorkoutSessionId: mirroredSessionId,
            startedFrom: startedFrom
        )
        workoutSession = session
        session.delegate = self
        snapshot.phase = session.state == .paused ? .paused : .running
        snapshot.startedAt = syncedState?.startedAt ?? Date()
        startDate = snapshot.startedAt
        snapshot.statusMessage = "Apple Watch recording"
        if let phoneStartedSessionId {
            sendRemoteIdentity(sessionId: phoneStartedSessionId, workoutKind: workoutKind, startedFrom: .iPhoneRequestedWatchStart)
        }
        startHeartRateFallbackMonitoring(primarySource: .appleWatch, startedAt: snapshot.startedAt ?? Date())
        PulsarSyncDebugLogger.log("Run mirrored session attached selectedType=\(workoutKind.rawValue) hkType=\(session.workoutConfiguration.activityType.rawValue) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "pending-watch") startedFrom=\(startedFrom.rawValue)")
        publishActiveWorkoutState(phase: snapshot.phase == .paused ? .paused : .active, updatedFrom: .iPhone, reason: "iPhoneRunMirroredSessionAttached")
        startTicking()
        startLiveActivityIfPossible()
    }

    private func matchingMirroredActiveWorkoutState(for workoutKind: PulsarOutdoorWorkoutKind) -> PulsarActiveWorkoutSyncState? {
        guard let state = syncStore.activeWorkoutState,
              state.kind.outdoorWorkoutKind == workoutKind,
              state.startedFrom.isAppleWatchRecorder,
              state.phase.isLive,
              !state.isEnded,
              !syncStore.isActiveWorkoutSessionTombstoned(state.sessionId) else {
            return nil
        }
        return state
    }

    private func waitForMirroredSessionIdentity(_ session: HKWorkoutSession, workoutKind: PulsarOutdoorWorkoutKind) {
        pendingMirroredSessionVerificationTask?.cancel()
        pendingMirroredSessionVerificationTask = Task { [weak self, session] in
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                let didAttach = await MainActor.run { () -> Bool in
                    guard let self,
                          self.workoutSession == nil,
                          self.matchingMirroredActiveWorkoutState(for: workoutKind) != nil else {
                        return false
                    }
                    self.attachMirroredSession(session)
                    return true
                }
                if didAttach { return }
            }
            await MainActor.run {
                PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Ignored unverified mirrored run session on app launch type=\(workoutKind.rawValue); waiting for Pulsar Watch active state before presenting")
            }
        }
    }

    private func beginMirrorConnectionWatchdog() {
        mirrorFallbackTask?.cancel()
        mirrorFallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            await MainActor.run {
                guard let self, self.snapshot.phase == .connectingToWatch else { return }
                let availability = self.syncStore.watchRecorderAvailabilitySnapshot(reason: "iPhoneRunMirrorWatchdog")
                let prompt = availability.fallbackPrompt(
                    workoutName: self.activeWorkoutKind.displayName,
                    reason: .mirroringTimedOut
                )
                self.authorizationMessage = prompt.message
                self.snapshot.statusMessage = "Apple Watch connection pending"
                self.liveWatchFallbackPrompt = prompt
                PulsarSyncDebugLogger.log("Watch recorder mirror timeout type=\(self.activeWorkoutKind.rawValue) session=\(self.snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") selectedRecorder=prompt reason=\(prompt.reason.logValue)")
            }
        }
    }

    func retryLiveWatchStart() async {
        guard snapshot.phase == .connectingToWatch else {
            liveWatchFallbackPrompt = nil
            return
        }
        liveWatchFallbackPrompt = nil
        let availability = await watchRecorderAvailability(for: activeWorkoutKind)
        guard availability.canStartOnWatch else {
            liveWatchFallbackPrompt = availability.fallbackPrompt(workoutName: activeWorkoutKind.displayName)
            return
        }
        do {
            try await healthStore.startWatchApp(toHandle: Self.outdoorWorkoutConfiguration(for: activeWorkoutKind))
            snapshot.statusMessage = watchStartStatusMessage(for: availability)
            beginMirrorConnectionWatchdog()
            PulsarSyncDebugLogger.log("Watch recorder retry requested type=\(activeWorkoutKind.rawValue) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") selectedRecorder=AppleWatch rawInstalled=\(availability.rawIsWatchAppInstalled) rawReachable=\(availability.rawIsReachable) derivedReachable=\(availability.derivedReachabilityDescription)")
        } catch {
            if shouldKeepQueuedWatchStart(for: availability) {
                snapshot.statusMessage = "Waiting for Apple Watch..."
                beginMirrorConnectionWatchdog()
                PulsarSyncDebugLogger.log("Watch recorder retry kept queued request type=\(activeWorkoutKind.rawValue) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") rawReachable=\(availability.rawIsReachable) derivedReachable=\(availability.derivedReachabilityDescription) error=\(error.localizedDescription)")
                return
            }
            let prompt = availability.fallbackPrompt(
                workoutName: activeWorkoutKind.displayName,
                reason: .watchLaunchFailed,
                errorMessage: error.localizedDescription
            )
            liveWatchFallbackPrompt = prompt
            PulsarSyncDebugLogger.log("Watch recorder retry failed type=\(activeWorkoutKind.rawValue) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") reason=\(prompt.reason.logValue) error=\(error.localizedDescription)")
        }
    }

    func startIPhoneFallbackFromLiveWatchPrompt() async {
        let previousSessionId = snapshot.pulsarWorkoutSessionId
        let workoutKind = activeWorkoutKind
        liveWatchFallbackPrompt = nil
        mirrorFallbackTask?.cancel()
        if let previousSessionId {
            syncStore.tombstoneActiveWorkoutSession(previousSessionId, reason: "iPhoneRunUserSelectedFallback")
        }
        didChooseIPhoneFallbackAfterWatchAttempt = true
        _ = await startOutdoorWorkout(
            workoutKind,
            options: PulsarRunOptions(
                prefersWatchRecorder: false,
                autoPauseEnabled: options.autoPauseEnabled,
                audioCuesEnabled: options.audioCuesEnabled
            ),
            startMode: .iPhoneOnly
        )
    }

    private func registerWorkoutMirroringHandler() {
        healthStore.workoutSessionMirroringStartHandler = { [weak self] mirroredSession in
            guard let coordinator = self else { return }
            Task { @MainActor [coordinator] in
                coordinator.attachMirroredSession(mirroredSession)
            }
        }
    }

    private func updatePreferredSource() {
        let availability = syncStore.watchRecorderAvailabilitySnapshot(reason: "runCoordinatorRefresh")
        applyPreferredSource(availability)
    }

    private func applyPreferredSource(_ availability: PulsarWatchRecorderAvailabilitySnapshot) {
        isWatchAvailable = availability.canStartOnWatch
        preferredSource = availability.canStartOnWatch ? .appleWatch : .iPhone
    }

    private func configureHeartRateFallbackMonitor() {
        heartRateFallbackMonitor.onStateChanged = { [weak self] state in
            self?.applyHeartRateFallbackState(state)
        }
        heartRateFallbackMonitor.onFallbackHeartRateSample = { [weak self] sample in
            self?.applyFallbackHeartRateSample(sample)
        }
        heartRateFallbackMonitor.onStatusBanner = { [weak self] message in
            self?.showHeartRateSourceBanner(message)
        }
    }

    private func startHeartRateFallbackMonitoring(
        primarySource: WorkoutHeartRateSourceKind,
        startedAt: Date
    ) {
        heartRateFallbackMonitor.start(
            primarySource: primarySource,
            workoutStartedAt: startedAt,
            isWorkoutActive: { [weak self] in
                guard let self else { return false }
                return self.snapshot.phase == .running || self.snapshot.phase == .paused || self.snapshot.phase == .finishing
            }
        )
    }

    private func applyHeartRateFallbackState(_ state: WorkoutHeartRateFallbackState) {
        heartRateSourceStatus = state.status
        heartRateSourceHistory = state.sourceHistory
        snapshot.heartRateSourceStatusMessage = state.status?.message
        snapshot.heartRateSourceHistory = state.sourceHistory.isEmpty ? nil : state.sourceHistory

        if state.status == .airPodsUnavailableHeartRatePaused {
            snapshot.currentHeartRate = nil
        }
    }

    private func applyFallbackHeartRateSample(_ sample: WorkoutHeartRateFallbackSample) {
        guard snapshot.phase == .running || snapshot.phase == .paused || snapshot.phase == .finishing else { return }
        var next = snapshot
        next.currentHeartRate = sample.beatsPerMinute
        heartRates.append(sample.beatsPerMinute)
        splitHeartRates.append(sample.beatsPerMinute)
        next.averageHeartRate = heartRates.isEmpty ? next.averageHeartRate : heartRates.reduce(0, +) / Double(heartRates.count)
        next.maxHeartRate = max(next.maxHeartRate ?? 0, sample.beatsPerMinute)
        next.activeEnergyKilocalories = fallbackEnergyEstimator.update(
            heartRate: sample.beatsPerMinute,
            sampledAt: sample.sampledAt,
            currentEnergyKilocalories: next.activeEnergyKilocalories
        )
        assignSnapshotIfChanged(next)
        recordAdaptiveWorkoutHeartRate(
            sample.beatsPerMinute,
            sampledAt: sample.sampledAt,
            workoutKind: activeWorkoutKind,
            reason: "airPodsHeartRateFallback"
        )
        publishActiveWorkoutState(updatedFrom: .iPhone, reason: "airPodsHeartRateFallback")
        updateLiveActivity()
    }

    private func recordAdaptiveWorkoutHeartRate(_ bpm: Double, sampledAt: Date, workoutKind: PulsarOutdoorWorkoutKind, reason: String) {
        guard let adaptiveStrainPlan, bpm > 0 else { return }
        adaptiveHeartRateSamples.append(AdaptiveHeartRateSample(timestamp: sampledAt, bpm: bpm))
        adaptiveHeartRateSamples = adaptiveHeartRateSamples.filter { sampledAt.timeIntervalSince($0.timestamp) <= 12 * 60 }
        let coaching = RealTimeWorkoutAdaptationEngine().evaluate(
            RealTimeWorkoutAdaptationInput(
                plan: adaptiveStrainPlan,
                workoutKind: workoutKind,
                elapsedTime: snapshot.elapsedTime,
                currentHeartRate: bpm,
                averageHeartRate: snapshot.averageHeartRate,
                maxObservedHeartRate: snapshot.maxHeartRate,
                recentHeartRates: adaptiveHeartRateSamples,
                sampledAt: sampledAt
            )
        )
        guard let coaching else { return }
        showAdaptiveWorkoutCoaching(coaching, reason: reason)
    }

    private func showAdaptiveWorkoutCoaching(_ coaching: AdaptiveWorkoutCoaching, reason: String) {
        let now = Date()
        if coaching.id == lastAdaptiveCoachingID,
           let lastAdaptiveCoachingAt,
           now.timeIntervalSince(lastAdaptiveCoachingAt) < 8 * 60 {
            return
        }
        lastAdaptiveCoachingID = coaching.id
        lastAdaptiveCoachingAt = now
        adaptiveWorkoutCoaching = coaching
        PulsarSyncDebugLogger.log("[PulsarAdaptiveStrainGuard] run coaching reason=\(reason) severity=\(coaching.severity.rawValue) message=\(coaching.message)")
        adaptiveCoachingBannerTask?.cancel()
        adaptiveCoachingBannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            await MainActor.run {
                if self?.adaptiveWorkoutCoaching?.id == coaching.id {
                    self?.adaptiveWorkoutCoaching = nil
                }
            }
        }
    }

    private func showHeartRateSourceBanner(_ message: String) {
        heartRateSourceBanner = message
        heartRateSourceBannerTask?.cancel()
        heartRateSourceBannerTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            await MainActor.run {
                if self?.heartRateSourceBanner == message {
                    self?.heartRateSourceBanner = nil
                }
            }
        }
    }

    private func watchStartStatusMessage(for availability: PulsarWatchRecorderAvailabilitySnapshot) -> String {
        availability.rawIsReachable ? "Opening on Apple Watch..." : "Waiting for Apple Watch..."
    }

    private func shouldKeepQueuedWatchStart(for availability: PulsarWatchRecorderAvailabilitySnapshot) -> Bool {
        availability.isPaired &&
            availability.isWatchAppInstalled &&
            availability.hasRecentWatchHeartbeat &&
            !availability.rawIsReachable
    }

    private func resetRuntimeState(
        source: PulsarRunRecordingSource,
        workoutKind: PulsarOutdoorWorkoutKind,
        pulsarWorkoutSessionId: UUID?,
        startedFrom: PulsarWorkoutStartedFrom?
    ) {
        cleanupRuntime()
        snapshot = .empty
        snapshot.pulsarWorkoutSessionId = pulsarWorkoutSessionId
        snapshot.source = source
        snapshot.workoutKind = workoutKind
        activeWorkoutStartedFrom = startedFrom
        activeWorkoutKind = workoutKind
        snapshot.statusMessage = source == .appleWatch ? "Preparing Apple Watch" : nil
        accumulatedPausedTime = 0
        isFinishing = false
        gpsDistanceFilter.reset()
        lastAcceptedAltitude = nil
        recentMovingSamples = []
        splitStartDistance = 0
        splitStartMovingTime = 0
        splitElevationGain = 0
        splitElevationLoss = 0
        splitHeartRates = []
        heartRates = []
        heartRateSourceStatus = nil
        heartRateSourceBanner = nil
        heartRateSourceHistory = []
        adaptiveWorkoutCoaching = nil
        adaptiveHeartRateSamples = []
        lastAdaptiveCoachingID = nil
        lastAdaptiveCoachingAt = nil
        fallbackEnergyEstimator.reset()
        autoPauseCandidateSince = nil
        lastIPhoneMetricsPublishedAt = .distantPast
    }

    private func cleanupRuntime(keepsSnapshot: Bool = false) {
        tickTask?.cancel()
        tickTask = nil
        mirrorFallbackTask?.cancel()
        mirrorFallbackTask = nil
        pendingMirroredSessionVerificationTask?.cancel()
        pendingMirroredSessionVerificationTask = nil
        finishRetryTask?.cancel()
        finishRetryTask = nil
        lastLiveActivityContentState = nil
        lastLiveActivityContentUpdateAt = nil
        heartRateFallbackMonitor.stop()
        heartRateSourceBannerTask?.cancel()
        heartRateSourceBannerTask = nil
        adaptiveCoachingBannerTask?.cancel()
        adaptiveCoachingBannerTask = nil
        locationManager?.stopUpdatingLocation()
        pedometer.stopUpdates()
        if !keepsSnapshot {
            workoutSession = nil
            workoutBuilder = nil
            routeBuilder = nil
            activeWorkoutStartedFrom = nil
        }
    }

    private func ensureLocationManager() {
        if locationManager != nil { return }
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 4
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        locationManager = manager
    }

    private func startLocationUpdates() {
        guard activeWorkoutKind.isOutdoorDistanceWorkout else { return }
        ensureLocationManager()
        guard let manager = locationManager else { return }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            if Self.isBackgroundLocationModeEnabled {
                manager.allowsBackgroundLocationUpdates = true
            }
            manager.startUpdatingLocation()
        }
    }

    private func startPedometerUpdates(from start: Date) {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: start) { [weak self] data, _ in
            guard let data else { return }
            Task { @MainActor in
                guard let self else { return }
                var next = self.snapshot
                next.stepCount = data.numberOfSteps.intValue
                if let currentCadence = data.currentCadence?.doubleValue, currentCadence > 0 {
                    next.cadenceStepsPerMinute = currentCadence * 60
                }
                self.assignSnapshotIfChanged(next)
                self.publishIPhoneMetricsIfNeeded()
            }
        }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    self?.updateTimeMetrics(date: Date())
                    self?.updateLiveActivity()
                }
            }
        }
    }

    private func updateTimeMetrics(date: Date) {
        guard let startDate else { return }
        var next = snapshot
        next.elapsedTime = max(0, date.timeIntervalSince(startDate))
        let activePausedTime = pauseBeganAt.map { date.timeIntervalSince($0) } ?? 0
        if next.source == .iPhone, activeWorkoutKind.isOutdoorDistanceWorkout {
            next.movingTime = gpsDistanceFilter.totalMovingTime
        } else {
            next.movingTime = max(0, next.elapsedTime - accumulatedPausedTime - activePausedTime)
        }
        next.averagePaceSecondsPerKilometer = PulsarRunDerivedMetrics.averagePace(distanceMeters: next.distanceMeters, movingTime: next.movingTime)
        next.activeSplitIndex = PulsarRunDerivedMetrics.splitIndex(distanceMeters: next.distanceMeters)
        assignSnapshotIfChanged(next)
    }

    private func assignSnapshotIfChanged(_ next: PulsarRunMetricSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }

    private func processLocations(_ locations: [CLLocation]) {
        guard snapshot.source == .iPhone else { return }
        let receivedAt = Date()
        guard let startDate else { return }
        for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
            let decision = gpsDistanceFilter.process(
                location: location,
                startDate: startDate,
                receivedAt: receivedAt,
                workoutKind: activeWorkoutKind,
                isRunning: snapshot.phase == .running
            )
            snapshot.distanceMeters = decision.totalAcceptedDistance
            snapshot.movingTime = decision.totalMovingTime
            if decision.acceptedDistanceDelta > 0 {
                applyAcceptedDistanceSideEffects(decision.acceptedDistanceDelta, at: location)
            } else {
                updateVisibleLocationContext(location)
            }
            appendAcceptedRouteLocations(decision.routeLocationsToAppend)
            logDistanceUpdate(source: "iPhoneLocation", decision: decision)
            updateAutoPause(with: location)
        }
        updatePaceFromRecentSamples()
        updateSplitsIfNeeded()
        publishIPhoneMetricsIfNeeded()
    }

    private func applyAcceptedDistanceSideEffects(_ acceptedDistanceDelta: Double, at location: CLLocation) {
        recentMovingSamples.append((location.timestamp, snapshot.distanceMeters))
        recentMovingSamples.removeAll { location.timestamp.timeIntervalSince($0.date) > 24 }

        let elevationChange = PulsarRunDerivedMetrics.elevationChange(
            previousAltitude: lastAcceptedAltitude,
            nextAltitude: location.altitude,
            verticalAccuracy: location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil
        )
        if snapshot.phase == .running {
            if elevationChange.gain > 0 {
                snapshot.elevationGainMeters += elevationChange.gain
                splitElevationGain += elevationChange.gain
            }
            if elevationChange.loss > 0 {
                snapshot.elevationLossMeters += elevationChange.loss
                splitElevationLoss += elevationChange.loss
            }
        }
        updateVisibleLocationContext(location)
    }

    private func updateVisibleLocationContext(_ location: CLLocation) {
        snapshot.currentElevationMeters = location.verticalAccuracy >= 0 ? location.altitude : nil
        if location.verticalAccuracy >= 0 && location.verticalAccuracy <= 18 {
            lastAcceptedAltitude = location.altitude
        }
    }

    private func appendAcceptedRouteLocations(_ locations: [CLLocation]) {
        guard !locations.isEmpty else { return }
        for location in locations {
            snapshot.route.append(
                PulsarRunCoordinate(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
                    horizontalAccuracy: location.horizontalAccuracy,
                    verticalAccuracy: location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil,
                    timestamp: location.timestamp
                )
            )
        }
        let sessionID = snapshot.pulsarWorkoutSessionId?.uuidString ?? "none"
        routeBuilder?.insertRouteData(locations) { success, error in
            if let error {
                PulsarSyncDebugLogger.log("Run HealthKit route insert failed session=\(sessionID) error=\(error.localizedDescription)")
            } else if !success {
                PulsarSyncDebugLogger.log("Run HealthKit route insert returned false session=\(sessionID)")
            }
        }
    }

    private func logDistanceUpdate(source: String, decision: PulsarRunGPSDistanceFilter.Decision) {
        PulsarSyncDebugLogger.log(
            "Run GPS distance update session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") workoutType=\(activeWorkoutKind.rawValue) source=\(source) rawDistanceDelta=\(Self.formatMetric(decision.rawDistanceDelta)) acceptedDistanceDelta=\(Self.formatMetric(decision.acceptedDistanceDelta)) totalAcceptedDistance=\(Self.formatMetric(decision.totalAcceptedDistance)) speed=\(Self.formatMetric(decision.speedMetersPerSecond)) horizontalAccuracy=\(Self.formatMetric(decision.horizontalAccuracy)) timestamp=\(decision.timestamp) stationaryLock=\(decision.stationaryLock) movementConfidence=\(decision.movementConfidence) rejectedReason=\(decision.rejectedReason ?? "none")"
        )
    }

    private func updateAutoPause(with location: CLLocation) {
        guard options.autoPauseEnabled, snapshot.source == .iPhone else { return }
        let shouldPause = PulsarRunDerivedMetrics.shouldAutoPause(
            speedMetersPerSecond: location.speed >= 0 ? location.speed : nil,
            horizontalAccuracy: location.horizontalAccuracy,
            workoutKind: activeWorkoutKind
        )

        if shouldPause {
            if autoPauseCandidateSince == nil {
                autoPauseCandidateSince = location.timestamp
            }
            if let candidate = autoPauseCandidateSince,
               location.timestamp.timeIntervalSince(candidate) >= 8,
               snapshot.phase == .running {
                pauseWorkoutSessionIfRunning(reason: "iPhoneRunAutoPause")
                applyPausedState(date: location.timestamp)
            }
        } else {
            autoPauseCandidateSince = nil
            if snapshot.phase == .paused, pauseBeganAt != nil {
                _ = resumeWorkoutSessionIfPaused(reason: "iPhoneRunAutoResume")
                applyRunningState(date: location.timestamp)
            }
        }
    }

    private func updatePaceFromRecentSamples() {
        guard let first = recentMovingSamples.first,
              let last = recentMovingSamples.last,
              last.distanceMeters > first.distanceMeters,
              last.date > first.date else {
            snapshot.currentPaceSecondsPerKilometer = nil
            return
        }
        snapshot.currentPaceSecondsPerKilometer = last.date.timeIntervalSince(first.date) / ((last.distanceMeters - first.distanceMeters) / 1_000)
    }

    private func publishIPhoneMetricsIfNeeded(force: Bool = false) {
        guard snapshot.source == .iPhone,
              snapshot.phase == .running || snapshot.phase == .paused else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastIPhoneMetricsPublishedAt) >= 1.5 else { return }
        lastIPhoneMetricsPublishedAt = now
        publishActiveWorkoutState(updatedFrom: .iPhone, reason: "iPhoneRunMetricsTick")
    }

    private func updateSplitsIfNeeded() {
        let completedSplitCount = Int(snapshot.distanceMeters / 1_000)
        while snapshot.splits.count < completedSplitCount {
            let index = snapshot.splits.count + 1
            let splitEndDistance = Double(index) * 1_000
            let splitDistance = min(1_000, splitEndDistance - splitStartDistance)
            let splitMovingTime = max(0, snapshot.movingTime - splitStartMovingTime)
            let averageHeartRate = splitHeartRates.isEmpty ? nil : splitHeartRates.reduce(0, +) / Double(splitHeartRates.count)
            snapshot.splits.append(
                PulsarRunSplit(
                    index: index,
                    distanceMeters: splitDistance,
                    movingTime: splitMovingTime,
                    elevationGainMeters: splitElevationGain,
                    elevationLossMeters: splitElevationLoss,
                    averageHeartRate: averageHeartRate
                )
            )
            splitStartDistance = splitEndDistance
            splitStartMovingTime = snapshot.movingTime
            splitElevationGain = 0
            splitElevationLoss = 0
            splitHeartRates = []
        }
        let activeDistance = max(0, snapshot.distanceMeters - splitStartDistance)
        let activeTime = max(0, snapshot.movingTime - splitStartMovingTime)
        snapshot.splitPaceSecondsPerKilometer = PulsarRunDerivedMetrics.averagePace(distanceMeters: activeDistance, movingTime: activeTime)
    }

    private func applyPausedState(date: Date) {
        guard snapshot.phase != .paused else { return }
        pauseBeganAt = date
        snapshot.phase = .paused
        gpsDistanceFilter.resetBaselineKeepingTotals()
        recentMovingSamples.removeAll()
        autoPauseCandidateSince = nil
    }

    private func applyRunningState(date: Date) {
        if let pauseBeganAt {
            accumulatedPausedTime += date.timeIntervalSince(pauseBeganAt)
        }
        pauseBeganAt = nil
        snapshot.phase = .running
        gpsDistanceFilter.resetBaselineKeepingTotals()
        recentMovingSamples.removeAll()
        autoPauseCandidateSince = nil
    }

    private func updateBuilderStatistics(for collectedTypes: Set<HKSampleType>) {
        guard let builder = workoutBuilder else { return }
        var next = snapshot
        let sampledAt = Date()
        var adaptiveHeartRate: Double?
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let statistics = builder.statistics(for: quantityType)
            switch quantityType.identifier {
            case HKQuantityTypeIdentifier.heartRate.rawValue:
                let unit = HKUnit.count().unitDivided(by: .minute())
                let current = statistics?.mostRecentQuantity()?.doubleValue(for: unit)
                let average = statistics?.averageQuantity()?.doubleValue(for: unit)
                let max = statistics?.maximumQuantity()?.doubleValue(for: unit)
                next.currentHeartRate = current
                next.averageHeartRate = average
                next.maxHeartRate = max
                if let current {
                    heartRates.append(current)
                    splitHeartRates.append(current)
                    if next.source == .appleWatch {
                        heartRateFallbackMonitor.recordExternalPrimaryHeartRate(sourceKind: .appleWatch, sampledAt: sampledAt)
                    }
                    adaptiveHeartRate = current
                }
            case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                next.activeEnergyKilocalories = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie())
            case HKQuantityTypeIdentifier.stepCount.rawValue:
                if let steps = statistics?.sumQuantity()?.doubleValue(for: .count()) {
                    next.stepCount = Int(steps.rounded())
                }
            case HKQuantityTypeIdentifier.runningPower.rawValue:
                next.runningPowerWatts = statistics?.mostRecentQuantity()?.doubleValue(for: .watt())
            case HKQuantityTypeIdentifier.runningStrideLength.rawValue:
                next.strideLengthMeters = statistics?.mostRecentQuantity()?.doubleValue(for: .meter())
            case HKQuantityTypeIdentifier.runningGroundContactTime.rawValue:
                next.groundContactTimeMilliseconds = statistics?.mostRecentQuantity()?.doubleValue(for: .secondUnit(with: .milli))
            case HKQuantityTypeIdentifier.runningVerticalOscillation.rawValue:
                next.verticalOscillationCentimeters = statistics?.mostRecentQuantity()?.doubleValue(for: .meterUnit(with: .centi))
            default:
                break
            }
        }
        let didChange = next != snapshot
        assignSnapshotIfChanged(next)
        if didChange, let adaptiveHeartRate {
            recordAdaptiveWorkoutHeartRate(adaptiveHeartRate, sampledAt: sampledAt, workoutKind: activeWorkoutKind, reason: "liveWorkoutBuilder")
        }
        if didChange {
            publishIPhoneMetricsIfNeeded()
        }
    }

    private func finishIPhoneWorkout() async {
        guard !isFinishing, summary == nil else { return }
        isFinishing = true
        let session = workoutSession
        let builder = workoutBuilder
        let routeBuilder = routeBuilder
        snapshot.phase = .finishing
        snapshot.statusMessage = "Finishing workout..."
        cleanupRuntime(keepsSnapshot: true)
        let end = Date()
        snapshot.endedAt = end
        updateTimeMetrics(date: end)

        defer {
            session?.end()
            workoutSession = nil
            workoutBuilder = nil
            self.routeBuilder = nil
            isFinishing = false
            PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Run HealthKit session ended after builder finish session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
        }

        do {
            try await builder?.endCollection(at: end)
            let workout = try await builder?.finishWorkout()
            if let workout, !snapshot.route.isEmpty {
                var routeMetadata = workoutMetadata(startedFrom: .iPhone)
                routeMetadata["PulsarRouteSource"] = "iPhone GPS"
                do {
                    _ = try await routeBuilder?.finishRoute(with: workout, metadata: routeMetadata)
                    PulsarSyncDebugLogger.log("Run HealthKit route saved source=iPhone session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") points=\(snapshot.route.count)")
                } catch {
                    PulsarSyncDebugLogger.log("Run HealthKit route save failed source=iPhone session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") error=\(error.localizedDescription)")
                }
            }
            let finishedSummary = makeSummary(workoutUUID: workout?.uuid)
            summary = finishedSummary
            await historyStore.save(finishedSummary)
            snapshot.phase = .finished
            snapshot.statusMessage = nil
            publishActiveWorkoutState(phase: .ended, updatedFrom: .iPhone, reason: "iPhoneRunFinished")
            endLiveActivity(reason: "iPhoneRunFinished")
        } catch {
            snapshot.phase = .failed
            snapshot.statusMessage = "Workout saved locally, but HealthKit finish failed: \(error.localizedDescription)"
            let finishedSummary = makeSummary(workoutUUID: nil)
            summary = finishedSummary
            await historyStore.save(finishedSummary)
            publishActiveWorkoutState(phase: .failed, updatedFrom: .iPhone, reason: "iPhoneRunFinishFailed")
            endLiveActivity(reason: "iPhoneRunFinishFailed")
        }
    }

    private func finalizeWorkoutWithoutHealthKitSession(reason: String) {
        guard !isFinishing || snapshot.phase == .finishing else { return }
        isFinishing = true
        let sessionID = snapshot.pulsarWorkoutSessionId
        let end = Date()
        snapshot.endedAt = end
        updateTimeMetrics(date: end)
        snapshot.phase = .finished
        let finishedSummary = makeSummary(workoutUUID: nil)
        summary = finishedSummary
        Task { await historyStore.save(finishedSummary) }
        publishActiveWorkoutState(phase: .ended, updatedFrom: .iPhone, reason: reason)
        if let sessionID {
            syncStore.tombstoneActiveWorkoutSession(sessionID, reason: reason)
        }
        endLiveActivity(reason: reason)
        cleanupRuntime()
        PulsarSyncDebugLogger.log("Run finish finalized locally because HealthKit session was nil reason=\(reason) session=\(sessionID?.uuidString ?? "none")")
    }

    private func makeMirroredSummaryIfNeeded() {
        guard summary == nil else { return }
        let finishedSummary = makeSummary(workoutUUID: nil)
        summary = finishedSummary
        if finishedSummary.pulsarWorkoutSessionId != nil {
            Task { await historyStore.save(finishedSummary) }
        } else {
            PulsarSyncDebugLogger.log("Run Activity Log skipped mirrored provisional save because session id is still pending")
        }
        snapshot.phase = .finished
        publishActiveWorkoutState(phase: .ended, updatedFrom: .iPhone, reason: "iPhoneRunMirroredFinished")
        endLiveActivity(reason: "iPhoneRunMirroredFinished")
    }

    private func makeSummary(workoutUUID: UUID?) -> PulsarRunSummary {
        let start = snapshot.startedAt ?? startDate ?? Date()
        let end = snapshot.endedAt ?? Date()
        return PulsarRunSummary(
            id: workoutUUID ?? UUID(),
            pulsarWorkoutSessionId: snapshot.pulsarWorkoutSessionId,
            workoutUUID: workoutUUID,
            workoutKind: snapshot.workoutKind,
            startedAt: start,
            endedAt: end,
            source: snapshot.source,
            heartRateSourceHistory: heartRateSourceHistory,
            heartRateSourceStatusMessage: heartRateSourceStatus?.message,
            distanceMeters: snapshot.distanceMeters,
            elapsedTime: snapshot.elapsedTime,
            movingTime: snapshot.movingTime,
            activeEnergyKilocalories: snapshot.activeEnergyKilocalories,
            elevationGainMeters: snapshot.elevationGainMeters,
            elevationLossMeters: snapshot.elevationLossMeters,
            minimumElevationMeters: GPSWorkoutRoute(runCoordinates: snapshot.route).elevationMetrics.minimumElevationMeters,
            maximumElevationMeters: GPSWorkoutRoute(runCoordinates: snapshot.route).elevationMetrics.maximumElevationMeters,
            averageHeartRate: snapshot.averageHeartRate,
            maxHeartRate: snapshot.maxHeartRate,
            steps: snapshot.stepCount,
            averageCadenceStepsPerMinute: snapshot.cadenceStepsPerMinute,
            route: snapshot.route,
            splits: snapshot.splits
        )
    }

    private func sendRemoteCommand(
        _ command: PulsarRunControlCommand,
        reason: String = "iPhoneRunCommand",
        retryAttempt: Int = 0
    ) {
        let sessionCommand = PulsarRunSessionCommand(
            sessionId: snapshot.pulsarWorkoutSessionId,
            command: command,
            commandId: UUID(),
            sentAt: Date(),
            retryAttempt: retryAttempt
        )
        syncStore.sendRunTransportEnvelope(
            .sessionCommand(sessionCommand),
            reason: reason,
            retryAttempt: retryAttempt,
            queueIfUnreachable: command == .finish
        )
        guard let data = PulsarRunTransportCodec.encode(.sessionCommand(sessionCommand)) else { return }
        guard let workoutSession else {
            PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Run command sent through WatchConnectivity only because mirrored HealthKit session is nil command=\(command.rawValue) reason=\(reason) session=\(sessionCommand.sessionId?.uuidString ?? "none")")
            return
        }
        workoutSession.sendToRemoteWorkoutSession(data: data) { _, error in
            if let error {
                PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Run command send failed command=\(command.rawValue) reason=\(reason) session=\(sessionCommand.sessionId?.uuidString ?? "none") commandId=\(sessionCommand.commandId.uuidString) error=\(error.localizedDescription)")
            } else {
                PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Run command sent command=\(command.rawValue) reason=\(reason) session=\(sessionCommand.sessionId?.uuidString ?? "none") commandId=\(sessionCommand.commandId.uuidString) attempt=\(retryAttempt)")
            }
        }
    }

    private func sendRemoteIdentity(
        sessionId: UUID,
        workoutKind: PulsarOutdoorWorkoutKind,
        startedFrom: PulsarWorkoutStartedFrom
    ) {
        let identity = PulsarRunSessionIdentity(
            sessionId: sessionId,
            workoutKind: workoutKind,
            startedFrom: startedFrom,
            sentAt: Date()
        )
        guard let data = PulsarRunTransportCodec.encode(.identity(identity)) else { return }
        workoutSession?.sendToRemoteWorkoutSession(data: data) { _, error in
            if let error {
                PulsarSyncDebugLogger.log("Run identity send failed session=\(sessionId.uuidString) error=\(error.localizedDescription)")
            }
        }
    }

    private func workoutMetadata(startedFrom: PulsarWorkoutStartedFrom) -> [String: Any] {
        let sessionId = snapshot.pulsarWorkoutSessionId ?? UUID()
        if snapshot.pulsarWorkoutSessionId == nil {
            snapshot.pulsarWorkoutSessionId = sessionId
        }
        var metadata = PulsarWorkoutMetadata.base(
            sessionId: sessionId,
            workoutType: activeWorkoutKind.rawValue,
            startedFrom: startedFrom
        )
        metadata["PulsarWorkoutKind"] = activeWorkoutKind.rawValue
        metadata["PulsarWorkoutDisplayName"] = activeWorkoutKind.displayName
        metadata["PulsarWorkoutCategory"] = "Outdoor"
        metadata[PulsarWorkoutMetadata.legacySessionIdKey] = sessionId.uuidString
        return metadata
    }

    private func addMetadata(_ metadata: [String: Any], to builder: HKLiveWorkoutBuilder, context: String) {
        builder.addMetadata(metadata) { success, error in
            if success {
                PulsarSyncDebugLogger.log("Run HealthKit metadata added context=\(context) session=\(metadata[PulsarWorkoutMetadata.sessionIdKey] as? String ?? "none") type=\(metadata[PulsarWorkoutMetadata.workoutTypeKey] as? String ?? "unknown") startedFrom=\(metadata[PulsarWorkoutMetadata.startedFromKey] as? String ?? "unknown")")
            } else if let error {
                PulsarSyncDebugLogger.log("Run HealthKit metadata failed context=\(context) error=\(error.localizedDescription)")
            }
        }
    }

    private func publishActiveWorkoutState(
        phase: PulsarActiveWorkoutSyncPhase? = nil,
        updatedFrom: PulsarWorkoutStartedFrom,
        reason: String
    ) {
        guard let sessionId = snapshot.pulsarWorkoutSessionId else { return }
        let startedFrom = activeWorkoutStartedFrom ?? updatedFrom
        var state = PulsarActiveWorkoutSyncState(
            runSnapshot: snapshot,
            startedFrom: startedFrom,
            lastUpdatedFrom: updatedFrom
        )
        state.sessionId = sessionId
        state.kind = .outdoor(activeWorkoutKind)
        state.displayName = activeWorkoutKind.displayName
        state.phase = phase ?? state.phase
        state.updatedAt = Date()
        state.endedAt = state.phase.isLive ? nil : (snapshot.endedAt ?? Date())
        if state.phase.isLive,
           syncStore.isActiveWorkoutSessionTombstoned(sessionId) {
            PulsarSyncDebugLogger.log("Skipped live active workout publish for tombstoned session reason=\(reason) session=\(sessionId.uuidString) phase=\(state.phase.rawValue)")
            return
        }
        syncStore.storeActiveWorkoutState(state, broadcast: true, reason: reason)
    }

    private func receiveRemoteEnvelope(_ envelope: PulsarRunTransportEnvelope, reason: String = "healthKitMirror") {
        switch envelope {
        case .identity:
            break
        case .metrics(let metrics):
            if let metricsSessionID = metrics.pulsarWorkoutSessionId,
               syncStore.isActiveWorkoutSessionTombstoned(metricsSessionID) {
                PulsarSyncDebugLogger.log("Ignored remote run metrics for tombstoned session session=\(metricsSessionID.uuidString)")
                return
            }
            let wasAwaitingRemoteFinish = snapshot.source == .appleWatch &&
                snapshot.phase == .finishing &&
                summary == nil
            let currentSessionId = snapshot.pulsarWorkoutSessionId
            let currentStartedFrom = activeWorkoutStartedFrom
            let incomingSessionId = metrics.pulsarWorkoutSessionId
            if metrics.phase.isLiveRunPhase,
               let currentSessionId,
               let incomingSessionId,
               currentSessionId != incomingSessionId,
               currentStartedFrom != .iPhoneRequestedWatchStart {
                PulsarSyncDebugLogger.log("Ignored remote run metrics for mismatched session current=\(currentSessionId.uuidString) incoming=\(incomingSessionId.uuidString) phase=\(metrics.phase.rawValue)")
                return
            }
            let preservedRoute = snapshot.route
            let preservedStatusMessage = snapshot.statusMessage
            snapshot = metrics
            if currentStartedFrom == .iPhone || currentStartedFrom == .iPhoneRequestedWatchStart,
               let currentSessionId {
                snapshot.pulsarWorkoutSessionId = currentSessionId
            } else if snapshot.pulsarWorkoutSessionId == nil {
                snapshot.pulsarWorkoutSessionId = currentSessionId
            }
            if metrics.route.isEmpty {
                snapshot.route = preservedRoute
            }
            if metrics.currentHeartRate != nil {
                heartRateFallbackMonitor.recordExternalPrimaryHeartRate(sourceKind: .appleWatch, sampledAt: Date())
            }
            activeWorkoutKind = metrics.workoutKind
            if startDate == nil {
                startDate = metrics.startedAt
            }
            PulsarSyncDebugLogger.log("Run metrics payload received session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") incomingSession=\(incomingSessionId?.uuidString ?? "none") workoutType=\(metrics.workoutKind.rawValue) recorderSource=AppleWatch distanceMeters=\(metrics.distanceMeters) elapsedSeconds=\(Int(metrics.elapsedTime.rounded())) movingSeconds=\(Int(metrics.movingTime.rounded())) pace=\(metrics.currentPaceSecondsPerKilometer ?? -1) calories=\(metrics.activeEnergyKilocalories ?? -1) heartRate=\(metrics.currentHeartRate ?? -1) sampleTimestamp=\(metrics.route.last?.timestamp.description ?? metrics.startedAt?.description ?? "none")")
            if wasAwaitingRemoteFinish,
               let currentSessionId,
               snapshot.pulsarWorkoutSessionId == currentSessionId {
                snapshot.phase = .finishing
                snapshot.statusMessage = preservedStatusMessage ?? "Finishing workout..."
                updateLiveActivity()
                publishActiveWorkoutState(phase: .ending, updatedFrom: .iPhone, reason: "iPhoneRunMetricsReceivedWhileFinishing")
                PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Preserved iPhone finishing state while applying late Watch metrics session=\(currentSessionId.uuidString) incomingPhase=\(metrics.phase.rawValue)")
                return
            }
            updateLiveActivity()
            publishActiveWorkoutState(updatedFrom: .appleWatch, reason: "iPhoneRunMetricsReceived")
        case .routeDelta(let delta):
            guard !syncStore.isActiveWorkoutSessionTombstoned(delta.sessionId) else {
                PulsarSyncDebugLogger.log("Ignored remote route delta for tombstoned session session=\(delta.sessionId.uuidString)")
                return
            }
            if snapshot.pulsarWorkoutSessionId == nil {
                snapshot.pulsarWorkoutSessionId = delta.sessionId
            }
            guard snapshot.pulsarWorkoutSessionId == delta.sessionId else {
                PulsarSyncDebugLogger.log("Ignored remote route delta for mismatched session current=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") incoming=\(delta.sessionId.uuidString)")
                return
            }
            activeWorkoutKind = delta.workoutKind
            appendRouteDelta(delta.points)
        case .summary(let receivedSummary):
            finishRetryTask?.cancel()
            finishRetryTask = nil
            var resolvedSummary = receivedSummary
            if activeWorkoutStartedFrom == .iPhone || activeWorkoutStartedFrom == .iPhoneRequestedWatchStart,
               let currentSessionId = snapshot.pulsarWorkoutSessionId {
                resolvedSummary.pulsarWorkoutSessionId = currentSessionId
            }
            if !heartRateSourceHistory.isEmpty {
                resolvedSummary.heartRateSourceHistory = heartRateSourceHistory
                resolvedSummary.heartRateSourceStatusMessage = heartRateSourceStatus?.message
            }
            summary = resolvedSummary
            activeWorkoutKind = resolvedSummary.workoutKind
            snapshot.pulsarWorkoutSessionId = resolvedSummary.pulsarWorkoutSessionId ?? snapshot.pulsarWorkoutSessionId
            snapshot.phase = .finished
            snapshot.statusMessage = nil
            Task { await historyStore.save(resolvedSummary) }
            publishActiveWorkoutState(phase: .ended, updatedFrom: .appleWatch, reason: "iPhoneRunSummaryReceived")
            workoutSession?.end()
            workoutSession = nil
            workoutBuilder = nil
            routeBuilder = nil
            isFinishing = false
            endLiveActivity(reason: "iPhoneRunSummaryReceived")
        case .sessionCommand(let command):
            handleRemoteSessionCommand(command, reason: "iPhoneRunRemoteCommand")
        case .commandAcknowledgement(let acknowledgement):
            PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Run command acknowledged command=\(acknowledgement.command.rawValue) accepted=\(acknowledgement.accepted) source=\(reason) session=\(acknowledgement.sessionId?.uuidString ?? "none") commandId=\(acknowledgement.commandId.uuidString) phase=\(acknowledgement.phase.rawValue) message=\(acknowledgement.message ?? "none")")
            if acknowledgement.command == .finish,
               acknowledgement.accepted,
               acknowledgement.phase == .finished,
               summary == nil,
               snapshot.phase == .finishing,
               acknowledgement.sessionId == nil || acknowledgement.sessionId == snapshot.pulsarWorkoutSessionId {
                PulsarSyncDebugLogger.log("[PulsarSummary] Creating provisional mirrored summary from finished Watch acknowledgement session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
                makeMirroredSummaryIfNeeded()
            }
        case .command(let command):
            applyRemoteControlCommand(command, reason: "iPhoneRunLegacyRemoteCommand")
        case .options:
            break
        }
    }

    private func handleRemoteSessionCommand(_ command: PulsarRunSessionCommand, reason: String) {
        let currentSessionId = snapshot.pulsarWorkoutSessionId
        guard command.sessionId == nil || command.sessionId == currentSessionId else {
            sendRunCommandAcknowledgement(
                command,
                accepted: false,
                message: "Session mismatch current=\(currentSessionId?.uuidString ?? "none")",
                reason: reason
            )
            return
        }
        applyRemoteControlCommand(command.command, reason: reason)
        sendRunCommandAcknowledgement(command, accepted: true, message: nil, reason: reason)
    }

    private func applyRemoteControlCommand(_ command: PulsarRunControlCommand, reason: String) {
        switch command {
        case .pause:
            pauseWorkoutSessionIfRunning(reason: reason)
            applyPausedState(date: Date())
            publishActiveWorkoutState(phase: .paused, updatedFrom: .appleWatch, reason: reason)
        case .resume:
            guard resumeWorkoutSessionIfPaused(reason: reason) || snapshot.phase == .paused else { return }
            applyRunningState(date: Date())
            publishActiveWorkoutState(phase: .resumed, updatedFrom: .appleWatch, reason: reason)
        case .finish:
            finish()
        }
    }

    private func sendRunCommandAcknowledgement(
        _ command: PulsarRunSessionCommand,
        accepted: Bool,
        message: String?,
        reason: String
    ) {
        let acknowledgement = PulsarRunCommandAcknowledgement(
            commandId: command.commandId,
            sessionId: snapshot.pulsarWorkoutSessionId ?? command.sessionId,
            command: command.command,
            accepted: accepted,
            phase: snapshot.phase,
            message: message,
            acknowledgedAt: Date()
        )
        guard let data = PulsarRunTransportCodec.encode(.commandAcknowledgement(acknowledgement)) else { return }
        workoutSession?.sendToRemoteWorkoutSession(data: data) { _, error in
            if let error {
                PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Run command acknowledgement failed command=\(command.command.rawValue) reason=\(reason) session=\(acknowledgement.sessionId?.uuidString ?? "none") commandId=\(command.commandId.uuidString) error=\(error.localizedDescription)")
            } else {
                PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Run command acknowledgement sent command=\(command.command.rawValue) accepted=\(accepted) reason=\(reason) session=\(acknowledgement.sessionId?.uuidString ?? "none") commandId=\(command.commandId.uuidString)")
            }
        }
    }

    private func startLiveActivityIfPossible() {
        guard snapshot.phase.isLiveRunPhase,
              snapshot.pulsarWorkoutSessionId != nil else {
            PulsarSyncDebugLogger.log("Live Activity not started because workout restore was unverified")
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard liveActivity == nil else {
            updateLiveActivity()
            return
        }
        let attributes = PulsarRunLiveActivityAttributes(runID: UUID())
        let state = PulsarRunLiveActivityAttributes.ContentState(
            distanceMeters: snapshot.distanceMeters,
            elapsedTime: snapshot.elapsedTime,
            paceSecondsPerKilometer: snapshot.averagePaceSecondsPerKilometer,
            heartRate: snapshot.currentHeartRate,
            phase: snapshot.phase
        )
        liveActivity = try? Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
        if liveActivity != nil {
            rememberLiveActivityContentState(state)
        }
    }

    private func updateLiveActivity() {
        guard snapshot.phase.isLiveRunPhase,
              snapshot.pulsarWorkoutSessionId != nil else {
            PulsarSyncDebugLogger.log("Live Activity update skipped because no validated active workout exists")
            return
        }
        guard let liveActivity else { return }
        let state = PulsarRunLiveActivityAttributes.ContentState(
            distanceMeters: snapshot.distanceMeters,
            elapsedTime: snapshot.elapsedTime,
            paceSecondsPerKilometer: snapshot.averagePaceSecondsPerKilometer,
            heartRate: snapshot.currentHeartRate,
            phase: snapshot.phase
        )
        guard shouldUpdateLiveActivity(state) else { return }
        rememberLiveActivityContentState(state)
        Task {
            await liveActivity.update(.init(state: state, staleDate: nil))
        }
    }

    private func shouldUpdateLiveActivity(_ next: PulsarRunLiveActivityAttributes.ContentState) -> Bool {
        guard let previous = lastLiveActivityContentState else { return true }
        guard next != previous else { return false }

        var previousWithUpdatedElapsed = previous
        previousWithUpdatedElapsed.elapsedTime = next.elapsedTime
        if previousWithUpdatedElapsed == next {
            guard let lastLiveActivityContentUpdateAt else { return true }
            return Date().timeIntervalSince(lastLiveActivityContentUpdateAt) >= Self.liveActivityElapsedOnlyUpdateInterval
        }
        return true
    }

    private func rememberLiveActivityContentState(_ state: PulsarRunLiveActivityAttributes.ContentState) {
        lastLiveActivityContentState = state
        lastLiveActivityContentUpdateAt = Date()
    }

    func endStaleLiveActivities(reason: String) async {
        let state = liveActivityContentState(phase: .finished)
        if let liveActivity {
            await liveActivity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
            self.liveActivity = nil
        }
        for activity in Activity<PulsarRunLiveActivityAttributes>.activities {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
        lastLiveActivityContentState = nil
        lastLiveActivityContentUpdateAt = nil
        PulsarSyncDebugLogger.log("Live Activity ended because \(reason)")
    }

    func discardRestoredActiveWorkout(sessionID: UUID, reason: String) async {
        if snapshot.pulsarWorkoutSessionId == sessionID {
            cleanupRuntime()
            snapshot = .empty
        }
        await endStaleLiveActivities(reason: reason)
    }

    private func endLiveActivity(reason: String) {
        let currentLiveActivity = liveActivity
        let state = liveActivityContentState(phase: snapshot.phase == .failed ? .failed : .finished)
        Task {
            if let currentLiveActivity {
                await currentLiveActivity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
            }
            for activity in Activity<PulsarRunLiveActivityAttributes>.activities
            where activity.id != currentLiveActivity?.id {
                await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate)
            }
        }
        self.liveActivity = nil
        lastLiveActivityContentState = nil
        lastLiveActivityContentUpdateAt = nil
        PulsarSyncDebugLogger.log("Live Activity ended because \(reason)")
    }

    private func liveActivityContentState(phase: PulsarRunPhase? = nil) -> PulsarRunLiveActivityAttributes.ContentState {
        PulsarRunLiveActivityAttributes.ContentState(
            distanceMeters: snapshot.distanceMeters,
            elapsedTime: snapshot.elapsedTime,
            paceSecondsPerKilometer: snapshot.averagePaceSecondsPerKilometer,
            heartRate: snapshot.currentHeartRate,
            phase: phase ?? snapshot.phase
        )
    }

    private static func outdoorWorkoutConfiguration(for workoutKind: PulsarOutdoorWorkoutKind) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = workoutKind.healthKitActivityType
        configuration.locationType = workoutKind.defaultLocationType
        return configuration
    }

    private static func formatMetric(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "nil" }
        return String(format: "%.3f", value)
    }

    private static func describe(_ state: HKWorkoutSessionState) -> String {
        switch state {
        case .notStarted:
            "notStarted"
        case .prepared:
            "prepared"
        case .running:
            "running"
        case .paused:
            "paused"
        case .stopped:
            "stopped"
        case .ended:
            "ended"
        @unknown default:
            "unknown(\(state.rawValue))"
        }
    }

    private static var healthShareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        [
            HKQuantityTypeIdentifier.activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming
        ].compactMap { HKObjectType.quantityType(forIdentifier: $0) }.forEach { types.insert($0) }
        return types
    }

    private static var healthReadTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = healthShareTypes
        [
            HKQuantityTypeIdentifier.heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
            .stepCount,
            .runningPower,
            .runningStrideLength,
            .runningGroundContactTime,
            .runningVerticalOscillation
        ].compactMap { HKObjectType.quantityType(forIdentifier: $0) }.forEach { types.insert($0) }
        return types
    }

    private static var isBackgroundLocationModeEnabled: Bool {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        return modes?.contains("location") == true
    }
}

extension PulsarRunCoordinator: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.processLocations(locations)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationMessage = manager.authorizationStatus == .denied ? "Location access is required for route maps and pace." : nil
            if self.snapshot.source == .iPhone,
               self.snapshot.phase.isLiveRunPhase,
               self.activeWorkoutKind.isOutdoorDistanceWorkout,
               (manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse) {
                manager.startUpdatingLocation()
                PulsarSyncDebugLogger.log("Run GPS location updates started after authorization type=\(self.activeWorkoutKind.rawValue) session=\(self.snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            }
        }
    }
}

extension PulsarRunCoordinator: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            switch toState {
            case .running:
                self.applyRunningState(date: date)
            case .paused:
                self.applyPausedState(date: date)
            case .stopped:
                if self.snapshot.source == .iPhone {
                    await self.finishIPhoneWorkout()
                } else {
                    self.snapshot.statusMessage = "Waiting for Apple Watch summary..."
                    PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Mirrored run session stopped; waiting for Watch summary session=\(self.snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
                }
            case .ended:
                PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Run HealthKit session ended state callback source=\(self.snapshot.source.rawValue) session=\(self.snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.snapshot.endedAt = Date()
            self.snapshot.phase = .failed
            self.snapshot.statusMessage = error.localizedDescription
            self.publishActiveWorkoutState(phase: .failed, updatedFrom: self.snapshot.source == .appleWatch ? .appleWatch : .iPhone, reason: "RunHealthKitSessionFailed")
            if let sessionID = self.snapshot.pulsarWorkoutSessionId {
                self.syncStore.tombstoneActiveWorkoutSession(sessionID, reason: "RunHealthKitSessionFailed")
            }
            self.endLiveActivity(reason: "RunHealthKitSessionFailed")
            self.cleanupRuntime()
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in
            for item in data {
                if let envelope = PulsarRunTransportCodec.decode(item) {
                    self.receiveRemoteEnvelope(envelope)
                }
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor in
            self.snapshot.statusMessage = error.map { "Apple Watch disconnected: \($0.localizedDescription)" } ?? "Apple Watch disconnected"
            self.heartRateFallbackMonitor.markPrimaryUnavailable()
        }
    }
}

extension PulsarRunCoordinator: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            self.updateBuilderStatistics(for: collectedTypes)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        Task { @MainActor in
            self.updateTimeMetrics(date: Date())
        }
    }
}

private extension PulsarRunPhase {
    var isLiveRunPhase: Bool {
        switch self {
        case .connectingToWatch, .running, .paused, .finishing:
            true
        case .idle, .requestingPermissions, .countingDown, .finished, .failed:
            false
        }
    }
}
