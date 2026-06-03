//
//  WatchRunSessionManager.swift
//  Pulsar Watch App Watch App
//

import Combine
import CoreLocation
import HealthKit
import SwiftUI
import WatchKit

@MainActor
final class WatchRunSessionManager: NSObject, ObservableObject {
    static let shared = WatchRunSessionManager()

    @Published private(set) var snapshot = PulsarRunMetricSnapshot.empty
    @Published private(set) var summary: PulsarRunSummary?
    @Published private(set) var message: String?
    @Published private(set) var activeWorkoutKind: PulsarOutdoorWorkoutKind = .running

    private let healthStore = HKHealthStore()
    private let syncStore = PulsarWatchConnectivitySyncStore.shared
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var locationManager: CLLocationManager?
    private var tickTask: Task<Void, Never>?
    private var finishFallbackTask: Task<Void, Never>?

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
    private var isFinishing = false
    private var lastMetricsSentAt = Date.distantPast
    private var lastRoutePointSentCount = 0
    private var activeWorkoutStartedFrom: PulsarWorkoutStartedFrom?
    private var handledRemoteCommandIDs = Set<UUID>()

    private override init() {
        super.init()
        syncStore.setRunTransportEnvelopeHandler { [weak self] envelope, reason in
            self?.handleRunTransportEnvelope(envelope, reason: "watchConnectivity.\(reason)")
        }
    }

    func requestAuthorization(for workoutKind: PulsarOutdoorWorkoutKind = .running) async {
        guard HKHealthStore.isHealthDataAvailable() else {
            message = "Health is unavailable on this Apple Watch."
            return
        }
        do {
            try await healthStore.requestAuthorization(toShare: Self.healthShareTypes, read: Self.healthReadTypes)
            ensureLocationManager()
            if locationManager?.authorizationStatus == .notDetermined {
                locationManager?.requestWhenInUseAuthorization()
            }
            message = nil
        } catch {
            message = "Allow Health and Location to record a \(workoutKind.actionName)."
        }
    }

    func startRunFromWatch(options: PulsarRunOptions) async {
        await startOutdoorWorkoutFromWatch(.running, options: options)
    }

    func startOutdoorWorkoutFromWatch(_ workoutKind: PulsarOutdoorWorkoutKind, options: PulsarRunOptions) async {
        await requestAuthorization(for: workoutKind)
        guard message == nil else { return }
        do {
            try await startWorkout(configuration: Self.outdoorWorkoutConfiguration(for: workoutKind), workoutKind: workoutKind)
        } catch {
            snapshot.phase = .failed
            message = error.localizedDescription
        }
    }

    func startRunFromCompanion(configuration: HKWorkoutConfiguration) async {
        let workoutKind = PulsarOutdoorWorkoutKind(activityType: configuration.activityType)
        await requestAuthorization(for: workoutKind)
        guard message == nil else { return }
        do {
            let companionState = await waitForCompanionRequestedStart(workoutKind: workoutKind)
            try await startWorkout(
                configuration: configuration,
                workoutKind: workoutKind,
                companionStateOverride: companionState
            )
        } catch {
            snapshot.phase = .failed
            message = error.localizedDescription
        }
    }

    func pause() {
        guard snapshot.phase == .running else {
            PulsarSyncDebugLogger.log("Watch run pause skipped because phase is not running session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") phase=\(snapshot.phase.rawValue)")
            return
        }
        pauseWorkoutSessionIfRunning(reason: "watchRunPause")
        applyPausedState(date: Date())
        publishActiveWorkoutState(phase: .paused, updatedFrom: .appleWatch, reason: "watchRunPaused")
    }

    func resume() {
        guard snapshot.phase == .paused else {
            PulsarSyncDebugLogger.log("Watch run resume skipped because phase is not paused session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") phase=\(snapshot.phase.rawValue)")
            return
        }
        guard resumeWorkoutSessionIfPaused(reason: "watchRunResume") || snapshot.phase == .paused else {
            PulsarSyncDebugLogger.log("Watch run resume skipped because workout is not paused session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") phase=\(snapshot.phase.rawValue)")
            return
        }
        applyRunningState(date: Date())
        publishActiveWorkoutState(phase: .resumed, updatedFrom: .appleWatch, reason: "watchRunResumed")
    }

    func finish() {
        if snapshot.phase == .finishing {
            publishActiveWorkoutState(phase: .ending, updatedFrom: .appleWatch, reason: "watchRunFinishAlreadyInProgress")
            PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Watch run finish ignored because finish is already in progress session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return
        }
        guard snapshot.phase == .running || snapshot.phase == .paused else { return }
        snapshot.phase = .finishing
        message = "Finishing workout..."
        publishActiveWorkoutState(phase: .ending, updatedFrom: .appleWatch, reason: "watchRunEnding")
        endWorkoutSessionIfNeeded(reason: "watchRunFinish")
        scheduleFinishFallback(reason: "watchRunFinish")
    }

    func reset() {
        cleanupRuntime()
        snapshot = .empty
        activeWorkoutKind = .running
        summary = nil
        message = nil
    }

    func recoverActiveWorkoutSession(_ session: HKWorkoutSession) {
        guard workoutSession == nil else {
            PulsarSyncDebugLogger.log("Watch run recovery skipped because an active session is already attached session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return
        }

        let configuration = session.workoutConfiguration
        let workoutKind = PulsarOutdoorWorkoutKind(activityType: configuration.activityType)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self

        workoutSession = session
        workoutBuilder = builder
        routeBuilder = workoutKind.isOutdoorDistanceWorkout ? HKWorkoutRouteBuilder(healthStore: healthStore, device: nil) : nil

        let recoveredState = syncStore.activeWorkoutState.flatMap { state -> PulsarActiveWorkoutSyncState? in
            guard state.kind.outdoorWorkoutKind == workoutKind,
                  state.phase.isLive,
                  !state.isEnded else { return nil }
            return state
        }
        let startedFrom = recoveredState?.startedFrom ?? .appleWatch
        let recoveredStart = session.startDate ?? recoveredState?.startedAt ?? Date()
        let sessionId = recoveredState?.sessionId ?? snapshot.pulsarWorkoutSessionId ?? UUID()
        let recoveredPhase = Self.runPhase(for: session.state)

        cleanupRuntime(keepsWorkoutObjects: true)
        activeWorkoutKind = workoutKind
        activeWorkoutStartedFrom = startedFrom
        startDate = recoveredStart
        snapshot = .empty
        snapshot.pulsarWorkoutSessionId = sessionId
        snapshot.source = .appleWatch
        snapshot.workoutKind = workoutKind
        snapshot.startedAt = recoveredStart
        snapshot.phase = recoveredPhase
        snapshot.elapsedTime = max(0, Date().timeIntervalSince(recoveredStart))
        if let recoveredState {
            snapshot.currentHeartRate = recoveredState.currentHeartRate
            snapshot.averageHeartRate = recoveredState.averageHeartRate
            snapshot.maxHeartRate = recoveredState.maxHeartRate
            snapshot.activeEnergyKilocalories = recoveredState.activeEnergyKilocalories
            applySyncedRunMetrics(from: recoveredState, reason: "watchRunRecovery")
        }
        if recoveredPhase == .paused {
            pauseBeganAt = Date()
        }

        if recoveredPhase == .finishing {
            publishActiveWorkoutState(
                phase: .ending,
                updatedFrom: .appleWatch,
                reason: "watchRunRecoveredFinishing"
            )
            Task { await finishWorkout() }
        } else {
            startLocationUpdates()
            startTicking()
            sendMetricsIfNeeded(force: true)
            publishActiveWorkoutState(
                phase: recoveredPhase == .paused ? .paused : .active,
                updatedFrom: .appleWatch,
                reason: "watchRunRecovered"
            )
        }
        message = nil
        PulsarSyncDebugLogger.log("Watch run recovered active HealthKit workout session=\(sessionId.uuidString) type=\(workoutKind.rawValue) state=\(Self.describe(session.state))")
    }

    func reconcileActiveWorkoutSyncState(_ state: PulsarActiveWorkoutSyncState) {
        guard let workoutKind = state.kind.outdoorWorkoutKind else { return }
        guard state.lastUpdatedFrom != .appleWatch || snapshot.pulsarWorkoutSessionId != state.sessionId else { return }

        if state.isEnded {
            guard snapshot.pulsarWorkoutSessionId == state.sessionId else { return }
            if state.lastUpdatedFrom == .iPhone,
               workoutSession != nil || workoutBuilder != nil,
               snapshot.phase == .running || snapshot.phase == .paused || snapshot.phase == .finishing {
                PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Watch run received terminal iPhone state while HealthKit session is local; finishing locally session=\(state.sessionId.uuidString) phase=\(state.phase.rawValue)")
                finish()
                return
            }
            snapshot.phase = state.phase.runPhase
            snapshot.endedAt = state.endedAt ?? Date()
            PulsarSyncDebugLogger.log("Watch run reconciled ended sync state session=\(state.sessionId.uuidString) type=\(workoutKind.rawValue)")
            return
        }

        if snapshot.pulsarWorkoutSessionId != state.sessionId {
            snapshot = .empty
            snapshot.pulsarWorkoutSessionId = state.sessionId
            snapshot.source = .appleWatch
            snapshot.workoutKind = workoutKind
            snapshot.startedAt = state.startedAt
            snapshot.phase = state.phase.runPhase
            snapshot.elapsedTime = TimeInterval(state.elapsedSeconds)
            snapshot.currentHeartRate = state.currentHeartRate
            snapshot.activeEnergyKilocalories = state.activeEnergyKilocalories
            activeWorkoutKind = workoutKind
            startDate = state.startedAt
            PulsarSyncDebugLogger.log("Watch run UI opened from sync state session=\(state.sessionId.uuidString) type=\(workoutKind.rawValue) phase=\(state.phase.rawValue) startedFrom=\(state.startedFrom.rawValue)")
        }

        let previousPhase = snapshot.phase
        if state.phase == .ending,
           state.lastUpdatedFrom == .iPhone,
           snapshot.pulsarWorkoutSessionId == state.sessionId {
            snapshot.elapsedTime = TimeInterval(state.elapsedSeconds)
            snapshot.currentHeartRate = state.currentHeartRate ?? snapshot.currentHeartRate
            snapshot.activeEnergyKilocalories = state.activeEnergyKilocalories ?? snapshot.activeEnergyKilocalories
            applySyncedRunMetrics(from: state, reason: "iPhoneRunSyncEnding")
            activeWorkoutKind = workoutKind

            if workoutSession != nil || workoutBuilder != nil {
                if previousPhase == .finishing {
                    message = "Finishing workout..."
                    publishActiveWorkoutState(phase: .ending, updatedFrom: .appleWatch, reason: "watchRunEndingAlreadyAcceptedFromIPhone")
                    scheduleFinishFallback(reason: "iPhoneRunSyncEndingAlreadyFinishing")
                    PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Watch run kept local finish alive after repeated iPhone ending state session=\(state.sessionId.uuidString)")
                } else if previousPhase == .running || previousPhase == .paused {
                    PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Watch run accepted iPhone ending state as finish command session=\(state.sessionId.uuidString) previousPhase=\(previousPhase.rawValue)")
                    finish()
                } else {
                    snapshot.phase = .finishing
                    message = "Finishing workout..."
                    publishActiveWorkoutState(phase: .ending, updatedFrom: .appleWatch, reason: "watchRunEndingAcceptedFromIPhone")
                    endWorkoutSessionIfNeeded(reason: "iPhoneRunSyncEnding")
                    scheduleFinishFallback(reason: "iPhoneRunSyncEnding")
                    PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Watch run forced local HealthKit finish from iPhone ending state session=\(state.sessionId.uuidString) previousPhase=\(previousPhase.rawValue)")
                }
                return
            }
        }
        snapshot.phase = state.phase.runPhase
        snapshot.elapsedTime = TimeInterval(state.elapsedSeconds)
        snapshot.currentHeartRate = state.currentHeartRate ?? snapshot.currentHeartRate
        snapshot.activeEnergyKilocalories = state.activeEnergyKilocalories ?? snapshot.activeEnergyKilocalories
        applySyncedRunMetrics(from: state, reason: "activeWorkoutSync")
        activeWorkoutKind = workoutKind

        guard state.lastUpdatedFrom == .iPhone else { return }
        switch state.phase {
        case .paused:
            if previousPhase != .paused {
                pauseWorkoutSessionIfRunning(reason: "iPhoneRunSyncPaused")
                applyPausedState(date: state.updatedAt)
            }
        case .active, .resumed:
            if previousPhase == .paused {
                _ = resumeWorkoutSessionIfPaused(reason: "iPhoneRunSyncResumed")
                applyRunningState(date: state.updatedAt)
            } else {
                logResumeSkippedIfAlreadyRunning(reason: "iPhoneRunSyncActive")
            }
        case .ending:
            if previousPhase == .running || previousPhase == .paused {
                finish()
            }
        case .starting, .ended, .failed, .cancelled:
            break
        }
    }

    private func startWorkout(
        configuration: HKWorkoutConfiguration,
        workoutKind: PulsarOutdoorWorkoutKind,
        companionStateOverride: PulsarActiveWorkoutSyncState? = nil
    ) async throws {
        reset()
        let companionState = companionStateOverride ?? syncStore.activeWorkoutState
        let adoptedCompanionState = companionState?.kind.outdoorWorkoutKind == workoutKind &&
            companionState?.startedFrom == .iPhoneRequestedWatchStart &&
            companionState?.isEnded == false
        let sessionId = adoptedCompanionState ? (companionState?.sessionId ?? UUID()) : UUID()
        let startedFrom: PulsarWorkoutStartedFrom = adoptedCompanionState ? (companionState?.startedFrom ?? .iPhoneRequestedWatchStart) : .appleWatch
        activeWorkoutStartedFrom = startedFrom
        activeWorkoutKind = workoutKind
        snapshot.pulsarWorkoutSessionId = sessionId
        snapshot.source = .appleWatch
        snapshot.workoutKind = workoutKind
        snapshot.phase = .running
        snapshot.startedAt = adoptedCompanionState ? companionState?.startedAt : Date()
        snapshot.distanceMeters = 0
        snapshot.elapsedTime = 0
        snapshot.movingTime = 0
        snapshot.currentPaceSecondsPerKilometer = nil
        snapshot.averagePaceSecondsPerKilometer = nil
        snapshot.splitPaceSecondsPerKilometer = nil
        snapshot.activeEnergyKilocalories = 0
        snapshot.cadenceStepsPerMinute = nil
        snapshot.route = []
        resetDistanceTrackingState()
        startDate = snapshot.startedAt
        PulsarSyncDebugLogger.log("Watch run start selectedType=\(workoutKind.rawValue) hkType=\(workoutKind.healthKitActivityType.rawValue) session=\(sessionId.uuidString) startedFrom=\(startedFrom.rawValue)")
        publishActiveWorkoutState(phase: .starting, updatedFrom: .appleWatch, reason: "watchRunStartPrepared")

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self
        workoutSession = session
        workoutBuilder = builder
        routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)

        let start = snapshot.startedAt ?? Date()
        startWorkoutSessionIfNeeded(session, at: start, reason: "watchRunHealthKitStart")
        try await builder.beginCollection(at: start)
        addMetadata(
            workoutMetadata(startedFrom: startedFrom),
            to: builder,
            context: "Apple Watch outdoor workout"
        )
        do {
            try await session.startMirroringToCompanionDevice()
            PulsarSyncDebugLogger.log("Watch run mirroring started session=\(sessionId.uuidString) type=\(workoutKind.rawValue)")
        } catch {
            PulsarSyncDebugLogger.log("Watch run mirroring failed session=\(sessionId.uuidString) type=\(workoutKind.rawValue) error=\(error.localizedDescription)")
        }

        startLocationUpdates()
        startTicking()
        sendMetricsIfNeeded(force: true)
        publishActiveWorkoutState(phase: .active, updatedFrom: .appleWatch, reason: "watchRunHealthKitStarted")
        WKInterfaceDevice.current().play(.start)
    }

    private func waitForCompanionRequestedStart(
        workoutKind: PulsarOutdoorWorkoutKind,
        timeoutSeconds: TimeInterval = 2.0,
        pollIntervalSeconds: TimeInterval = 0.2
    ) async -> PulsarActiveWorkoutSyncState? {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() <= deadline {
            if let state = syncStore.activeWorkoutState,
               state.kind.outdoorWorkoutKind == workoutKind,
               state.startedFrom == .iPhoneRequestedWatchStart,
               state.phase.isLive,
               !state.isEnded {
                PulsarSyncDebugLogger.log("Watch run adopted companion start session=\(state.sessionId.uuidString) type=\(workoutKind.rawValue) phase=\(state.phase.rawValue)")
                return state
            }
            try? await Task.sleep(nanoseconds: UInt64(pollIntervalSeconds * 1_000_000_000))
        }
        PulsarSyncDebugLogger.log("Watch run did not find companion start within timeout type=\(workoutKind.rawValue); starting with local session until identity arrives")
        return nil
    }

    private func startWorkoutSessionIfNeeded(_ session: HKWorkoutSession, at start: Date, reason: String) {
        switch session.state {
        case .notStarted, .prepared:
            session.startActivity(with: start)
            PulsarSyncDebugLogger.log("Watch run HealthKit startActivity applied reason=\(reason) state=\(Self.describe(session.state)) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
        case .running, .paused:
            PulsarSyncDebugLogger.log("Watch run HealthKit startActivity skipped because session already started reason=\(reason) state=\(Self.describe(session.state)) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
        case .stopped, .ended:
            PulsarSyncDebugLogger.log("Watch run HealthKit startActivity skipped because session is terminal reason=\(reason) state=\(Self.describe(session.state)) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
        @unknown default:
            PulsarSyncDebugLogger.log("Watch run HealthKit startActivity skipped for unknown state reason=\(reason) state=\(session.state.rawValue) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
        }
    }

    @discardableResult
    private func pauseWorkoutSessionIfRunning(reason: String) -> Bool {
        guard let workoutSession else {
            PulsarSyncDebugLogger.log("Watch run HealthKit pause skipped because session is nil reason=\(reason) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return false
        }

        switch workoutSession.state {
        case .running:
            workoutSession.pause()
            PulsarSyncDebugLogger.log("Watch run HealthKit pause applied reason=\(reason) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return true
        case .paused:
            PulsarSyncDebugLogger.log("Watch run HealthKit pause skipped because session already paused reason=\(reason) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return false
        default:
            PulsarSyncDebugLogger.log("Watch run HealthKit pause skipped because session is not running reason=\(reason) state=\(Self.describe(workoutSession.state)) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return false
        }
    }

    @discardableResult
    private func resumeWorkoutSessionIfPaused(reason: String) -> Bool {
        guard let workoutSession else {
            PulsarSyncDebugLogger.log("Watch run HealthKit resume skipped because session is nil reason=\(reason) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return false
        }

        switch workoutSession.state {
        case .paused:
            workoutSession.resume()
            PulsarSyncDebugLogger.log("Watch run HealthKit resume applied reason=\(reason) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return true
        case .running:
            PulsarSyncDebugLogger.log("Watch run HealthKit resume skipped because session already running reason=\(reason) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return false
        default:
            PulsarSyncDebugLogger.log("Watch run HealthKit resume skipped because session is not paused reason=\(reason) state=\(Self.describe(workoutSession.state)) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return false
        }
    }

    private func logResumeSkippedIfAlreadyRunning(reason: String) {
        guard let workoutSession else { return }
        if workoutSession.state == .running {
            PulsarSyncDebugLogger.log("Watch run HealthKit resume skipped because session already running reason=\(reason) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
        }
    }

    private func endWorkoutSessionIfNeeded(reason: String) {
        guard let workoutSession else {
            PulsarSyncDebugLogger.log("Watch run HealthKit end skipped because session is nil reason=\(reason) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            return
        }

        switch workoutSession.state {
        case .ended, .stopped:
            PulsarSyncDebugLogger.log("Watch run HealthKit end skipped because session is already terminal reason=\(reason) state=\(Self.describe(workoutSession.state)) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
        default:
            workoutSession.stopActivity(with: Date())
            PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Watch run HealthKit stopActivity requested reason=\(reason) state=\(Self.describe(workoutSession.state)) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
        }
    }

    private func cleanupRuntime(keepsWorkoutObjects: Bool = false) {
        tickTask?.cancel()
        tickTask = nil
        finishFallbackTask?.cancel()
        finishFallbackTask = nil
        locationManager?.stopUpdatingLocation()
        if !keepsWorkoutObjects {
            workoutSession = nil
            workoutBuilder = nil
            routeBuilder = nil
        }
        startDate = nil
        pauseBeganAt = nil
        accumulatedPausedTime = 0
        resetDistanceTrackingState()
        splitStartDistance = 0
        splitStartMovingTime = 0
        splitElevationGain = 0
        splitElevationLoss = 0
        splitHeartRates = []
        isFinishing = false
        lastMetricsSentAt = .distantPast
        lastRoutePointSentCount = 0
        activeWorkoutStartedFrom = nil
    }

    private func scheduleFinishFallback(reason: String) {
        finishFallbackTask?.cancel()
        finishFallbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard self.snapshot.phase == .finishing, self.summary == nil else { return }
            PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Watch run finish fallback fired reason=\(reason) session=\(self.snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            await self.finishWorkout()
        }
    }

    private func resetDistanceTrackingState() {
        gpsDistanceFilter.reset()
        lastAcceptedAltitude = nil
        recentMovingSamples = []
    }

    private func resetDistanceBaseline() {
        gpsDistanceFilter.resetBaselineKeepingTotals()
        recentMovingSamples = []
    }

    private func ensureLocationManager() {
        if locationManager != nil { return }
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 4
        manager.activityType = .fitness
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
            manager.startUpdatingLocation()
        }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    self?.updateTimeMetrics(date: Date())
                    self?.sendMetricsIfNeeded()
                }
            }
        }
    }

    private func applySyncedRunMetrics(from state: PulsarActiveWorkoutSyncState, reason: String) {
        guard state.runMetricsUpdatedAt != nil else { return }
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
        PulsarSyncDebugLogger.log("Watch live metrics applied from \(reason) session=\(state.sessionId.uuidString) type=\(state.kind.workoutTypeRawValue) recorderSource=\(state.lastUpdatedFrom.rawValue) distanceMeters=\(state.distanceMeters ?? -1) elapsedSeconds=\(state.elapsedSeconds) movingSeconds=\(state.movingSeconds ?? -1) pace=\(state.currentPaceSecondsPerKilometer ?? -1) calories=\(state.activeEnergyKilocalories ?? -1) heartRate=\(state.currentHeartRate ?? -1) sampleTimestamp=\(state.runMetricsUpdatedAt?.description ?? "none")")
    }

    private func updateTimeMetrics(date: Date) {
        guard let startDate else { return }
        snapshot.elapsedTime = max(0, date.timeIntervalSince(startDate))
        let activePausedTime = pauseBeganAt.map { date.timeIntervalSince($0) } ?? 0
        if activeWorkoutKind.isOutdoorDistanceWorkout {
            snapshot.movingTime = gpsDistanceFilter.totalMovingTime
        } else {
            snapshot.movingTime = max(0, snapshot.elapsedTime - accumulatedPausedTime - activePausedTime)
        }
        snapshot.averagePaceSecondsPerKilometer = PulsarRunDerivedMetrics.averagePace(distanceMeters: snapshot.distanceMeters, movingTime: snapshot.movingTime)
        snapshot.activeSplitIndex = PulsarRunDerivedMetrics.splitIndex(distanceMeters: snapshot.distanceMeters)
        updateSplitsIfNeeded()
    }

    private func processLocations(_ locations: [CLLocation]) {
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
            logDistanceUpdate(source: "location", decision: decision)
        }
        updateCurrentPace()
        updateSplitsIfNeeded()
        sendMetricsIfNeeded()
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
                PulsarSyncDebugLogger.log("Watch HealthKit route insert failed session=\(sessionID) error=\(error.localizedDescription)")
            } else if !success {
                PulsarSyncDebugLogger.log("Watch HealthKit route insert returned false session=\(sessionID)")
            }
        }
    }

    private func logDistanceUpdate(source: String, decision: PulsarRunGPSDistanceFilter.Decision) {
        PulsarSyncDebugLogger.log(
            "Watch distance update session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") workoutType=\(activeWorkoutKind.rawValue) source=\(source) rawDistanceDelta=\(Self.formatMetric(decision.rawDistanceDelta)) acceptedDistanceDelta=\(Self.formatMetric(decision.acceptedDistanceDelta)) totalAcceptedDistance=\(Self.formatMetric(decision.totalAcceptedDistance)) speed=\(Self.formatMetric(decision.speedMetersPerSecond)) horizontalAccuracy=\(Self.formatMetric(decision.horizontalAccuracy)) timestamp=\(decision.timestamp) stationaryLock=\(decision.stationaryLock) movementConfidence=\(decision.movementConfidence) rejectedReason=\(decision.rejectedReason ?? "none")"
        )
    }

    private func logDistanceUpdate(
        source: String,
        rawDistanceDelta: Double,
        acceptedDistanceDelta: Double,
        speed: Double?,
        horizontalAccuracy: Double?,
        timestamp: Date,
        rejectedReason: String?
    ) {
        PulsarSyncDebugLogger.log(
            "Watch distance update session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") workoutType=\(activeWorkoutKind.rawValue) source=\(source) rawDistanceDelta=\(Self.formatMetric(rawDistanceDelta)) acceptedDistanceDelta=\(Self.formatMetric(acceptedDistanceDelta)) totalAcceptedDistance=\(Self.formatMetric(snapshot.distanceMeters)) speed=\(Self.formatMetric(speed)) horizontalAccuracy=\(Self.formatMetric(horizontalAccuracy)) timestamp=\(timestamp) stationaryLock=\(gpsDistanceFilter.stationaryLockActive) movementConfidence=\(gpsDistanceFilter.movementConfidence) rejectedReason=\(rejectedReason ?? "none")"
        )
    }

    private static func formatMetric(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "nil" }
        return String(format: "%.3f", value)
    }

    private func updateCurrentPace() {
        guard let first = recentMovingSamples.first,
              let last = recentMovingSamples.last,
              last.distanceMeters > first.distanceMeters,
              last.date > first.date else {
            snapshot.currentPaceSecondsPerKilometer = nil
            return
        }
        snapshot.currentPaceSecondsPerKilometer = last.date.timeIntervalSince(first.date) / ((last.distanceMeters - first.distanceMeters) / 1_000)
    }

    private func updateSplitsIfNeeded() {
        let completedSplitCount = Int(snapshot.distanceMeters / 1_000)
        while snapshot.splits.count < completedSplitCount {
            let index = snapshot.splits.count + 1
            let splitMovingTime = max(0, snapshot.movingTime - splitStartMovingTime)
            let averageHeartRate = splitHeartRates.isEmpty ? nil : splitHeartRates.reduce(0, +) / Double(splitHeartRates.count)
            snapshot.splits.append(
                PulsarRunSplit(
                    index: index,
                    distanceMeters: 1_000,
                    movingTime: splitMovingTime,
                    elevationGainMeters: splitElevationGain,
                    elevationLossMeters: splitElevationLoss,
                    averageHeartRate: averageHeartRate
                )
            )
            splitStartDistance = Double(index) * 1_000
            splitStartMovingTime = snapshot.movingTime
            splitElevationGain = 0
            splitElevationLoss = 0
            splitHeartRates = []
        }
        snapshot.splitPaceSecondsPerKilometer = PulsarRunDerivedMetrics.averagePace(
            distanceMeters: max(0, snapshot.distanceMeters - splitStartDistance),
            movingTime: max(0, snapshot.movingTime - splitStartMovingTime)
        )
    }

    private func applyPausedState(date: Date) {
        guard snapshot.phase != .paused else { return }
        pauseBeganAt = date
        snapshot.phase = .paused
        resetDistanceBaseline()
        sendMetricsIfNeeded(force: true)
        WKInterfaceDevice.current().play(.stop)
    }

    private func applyRunningState(date: Date) {
        if let pauseBeganAt {
            accumulatedPausedTime += date.timeIntervalSince(pauseBeganAt)
        }
        pauseBeganAt = nil
        snapshot.phase = .running
        resetDistanceBaseline()
        sendMetricsIfNeeded(force: true)
        WKInterfaceDevice.current().play(.start)
    }

    private func updateBuilderStatistics(for collectedTypes: Set<HKSampleType>) {
        guard let builder = workoutBuilder else { return }
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let statistics = builder.statistics(for: quantityType)
            switch quantityType.identifier {
            case HKQuantityTypeIdentifier.heartRate.rawValue:
                let unit = HKUnit.count().unitDivided(by: .minute())
                let current = statistics?.mostRecentQuantity()?.doubleValue(for: unit)
                snapshot.currentHeartRate = current
                snapshot.averageHeartRate = statistics?.averageQuantity()?.doubleValue(for: unit)
                snapshot.maxHeartRate = statistics?.maximumQuantity()?.doubleValue(for: unit)
                if let current { splitHeartRates.append(current) }
            case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                snapshot.activeEnergyKilocalories = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie())
            case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue,
                 HKQuantityTypeIdentifier.distanceCycling.rawValue,
                 HKQuantityTypeIdentifier.distanceSwimming.rawValue:
                let healthKitDistanceMeters = statistics?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
                logDistanceUpdate(
                    source: "healthkit",
                    rawDistanceDelta: healthKitDistanceMeters,
                    acceptedDistanceDelta: 0,
                    speed: nil,
                    horizontalAccuracy: nil,
                    timestamp: Date(),
                    rejectedReason: "ignoredHealthKitDistanceUsingValidatedLocation"
                )
            case HKQuantityTypeIdentifier.stepCount.rawValue:
                if let steps = statistics?.sumQuantity()?.doubleValue(for: .count()) {
                    snapshot.stepCount = Int(steps.rounded())
                }
            case HKQuantityTypeIdentifier.runningPower.rawValue:
                snapshot.runningPowerWatts = statistics?.mostRecentQuantity()?.doubleValue(for: .watt())
            case HKQuantityTypeIdentifier.runningStrideLength.rawValue:
                snapshot.strideLengthMeters = statistics?.mostRecentQuantity()?.doubleValue(for: .meter())
            case HKQuantityTypeIdentifier.runningGroundContactTime.rawValue:
                snapshot.groundContactTimeMilliseconds = statistics?.mostRecentQuantity()?.doubleValue(for: .secondUnit(with: .milli))
            case HKQuantityTypeIdentifier.runningVerticalOscillation.rawValue:
                snapshot.verticalOscillationCentimeters = statistics?.mostRecentQuantity()?.doubleValue(for: .meterUnit(with: .centi))
            default:
                break
            }
        }
        sendMetricsIfNeeded()
    }

    private func finishWorkout() async {
        guard !isFinishing, summary == nil else { return }
        isFinishing = true
        finishFallbackTask?.cancel()
        finishFallbackTask = nil
        let end = Date()
        snapshot.endedAt = end
        updateTimeMetrics(date: end)
        let session = workoutSession
        let builder = workoutBuilder
        let routeBuilder = routeBuilder
        cleanupRuntime(keepsWorkoutObjects: true)
        isFinishing = true

        defer {
            session?.end()
            workoutSession = nil
            workoutBuilder = nil
            self.routeBuilder = nil
            isFinishing = false
            PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Watch run HealthKit session ended after builder finish session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
        }

        do {
            try await builder?.endCollection(at: end)
            let workout = try await builder?.finishWorkout()
            if let workout, !snapshot.route.isEmpty {
                var routeMetadata = workoutMetadata(startedFrom: .appleWatch)
                routeMetadata["PulsarRouteSource"] = "Apple Watch GPS"
                do {
                    _ = try await routeBuilder?.finishRoute(with: workout, metadata: routeMetadata)
                    PulsarSyncDebugLogger.log("Watch HealthKit route saved session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") points=\(snapshot.route.count)")
                } catch {
                    PulsarSyncDebugLogger.log("Watch HealthKit route save failed session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") error=\(error.localizedDescription)")
                }
            }
            let finishedSummary = makeSummary(workoutUUID: workout?.uuid)
            summary = finishedSummary
            snapshot.phase = .finished
            message = nil
            let summaryEnvelope = PulsarRunTransportEnvelope.summary(finishedSummary)
            sendEnvelope(summaryEnvelope)
            syncStore.sendRunTransportEnvelope(
                summaryEnvelope,
                reason: "watchRunSummaryFinished",
                queueIfUnreachable: true
            )
            try? await session?.stopMirroringToCompanionDevice()
            publishActiveWorkoutState(phase: .ended, updatedFrom: .appleWatch, reason: "watchRunFinished")
            WKInterfaceDevice.current().play(.success)
        } catch {
            snapshot.phase = .failed
            message = error.localizedDescription
            publishActiveWorkoutState(phase: .failed, updatedFrom: .appleWatch, reason: "watchRunFinishFailed")
            sendMetricsIfNeeded(force: true)
        }
    }

    private func makeSummary(workoutUUID: UUID?) -> PulsarRunSummary {
        let start = snapshot.startedAt ?? Date()
        let end = snapshot.endedAt ?? Date()
        return PulsarRunSummary(
            id: workoutUUID ?? UUID(),
            pulsarWorkoutSessionId: snapshot.pulsarWorkoutSessionId,
            workoutUUID: workoutUUID,
            workoutKind: snapshot.workoutKind,
            startedAt: start,
            endedAt: end,
            source: .appleWatch,
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

    private func sendMetricsIfNeeded(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastMetricsSentAt) >= 1.5 else { return }
        lastMetricsSentAt = now
        PulsarSyncDebugLogger.log("Watch run metrics payload sent session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "none") workoutType=\(snapshot.workoutKind.rawValue) recorderSource=AppleWatch distanceMeters=\(snapshot.distanceMeters) elapsedSeconds=\(Int(snapshot.elapsedTime.rounded())) movingSeconds=\(Int(snapshot.movingTime.rounded())) pace=\(snapshot.currentPaceSecondsPerKilometer ?? -1) calories=\(snapshot.activeEnergyKilocalories ?? -1) heartRate=\(snapshot.currentHeartRate ?? -1) sampleTimestamp=\(snapshot.route.last?.timestamp.description ?? now.description)")
        var liveSnapshot = snapshot
        liveSnapshot.route = []
        sendEnvelope(.metrics(liveSnapshot))
        sendRouteDeltaIfNeeded()
        publishActiveWorkoutState(updatedFrom: .appleWatch, reason: "watchRunMetricsTick")
    }

    private func sendRouteDeltaIfNeeded() {
        guard let sessionId = snapshot.pulsarWorkoutSessionId,
              snapshot.route.count > lastRoutePointSentCount else { return }
        let points = Array(snapshot.route.dropFirst(lastRoutePointSentCount))
        lastRoutePointSentCount = snapshot.route.count
        sendEnvelope(
            .routeDelta(
                PulsarRunRouteDelta(
                    sessionId: sessionId,
                    workoutKind: snapshot.workoutKind,
                    points: points,
                    sentAt: Date()
                )
            )
        )
    }

    private func sendEnvelope(_ envelope: PulsarRunTransportEnvelope) {
        guard let data = PulsarRunTransportCodec.encode(envelope) else { return }
        workoutSession?.sendToRemoteWorkoutSession(data: data) { _, error in
            if let error {
                PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Watch run envelope send failed error=\(error.localizedDescription)")
            }
        }
    }

    private func handleSessionCommand(_ command: PulsarRunSessionCommand) {
        let currentSessionId = snapshot.pulsarWorkoutSessionId
        guard command.sessionId == nil || command.sessionId == currentSessionId else {
            sendCommandAcknowledgement(
                command,
                accepted: false,
                message: "Session mismatch current=\(currentSessionId?.uuidString ?? "none")"
            )
            return
        }
        if command.sessionId == nil,
           !isFreshSessionlessCommand(command) {
            sendCommandAcknowledgement(
                command,
                accepted: false,
                message: "Sessionless command is stale"
            )
            PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Watch run stale sessionless command rejected command=\(command.command.rawValue) commandId=\(command.commandId.uuidString) sentAt=\(command.sentAt)")
            return
        }

        if !handledRemoteCommandIDs.insert(command.commandId).inserted {
            sendCommandAcknowledgement(command, accepted: true, message: "Duplicate command ignored")
            PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Watch run duplicate command ignored command=\(command.command.rawValue) session=\(command.sessionId?.uuidString ?? "none") commandId=\(command.commandId.uuidString)")
            return
        }
        if handledRemoteCommandIDs.count > 250 {
            handledRemoteCommandIDs = [command.commandId]
        }

        switch command.command {
        case .pause:
            pause()
        case .resume:
            resume()
        case .finish:
            finish()
        }
        sendCommandAcknowledgement(command, accepted: true, message: nil)
        PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Watch run command handled command=\(command.command.rawValue) session=\(command.sessionId?.uuidString ?? "none") commandId=\(command.commandId.uuidString) attempt=\(command.retryAttempt)")
    }

    private func isFreshSessionlessCommand(_ command: PulsarRunSessionCommand) -> Bool {
        guard Date().timeIntervalSince(command.sentAt) <= 120 else { return false }
        if let startedAt = snapshot.startedAt,
           command.sentAt < startedAt.addingTimeInterval(-5) {
            return false
        }
        return true
    }

    private func sendCommandAcknowledgement(
        _ command: PulsarRunSessionCommand,
        accepted: Bool,
        message: String?
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
        let envelope = PulsarRunTransportEnvelope.commandAcknowledgement(acknowledgement)
        sendEnvelope(envelope)
        syncStore.sendRunTransportEnvelope(
            envelope,
            reason: "watchRunCommandAcknowledgement",
            queueIfUnreachable: false
        )
    }

    private func handleRunTransportEnvelope(_ envelope: PulsarRunTransportEnvelope, reason: String = "healthKitMirror") {
        switch envelope {
        case .identity(let identity):
            applyIdentity(identity)
        case .sessionCommand(let command):
            handleSessionCommand(command)
        case .commandAcknowledgement(let acknowledgement):
            PulsarSyncDebugLogger.log("[PulsarWorkoutSync] Watch run command acknowledged command=\(acknowledgement.command.rawValue) accepted=\(acknowledgement.accepted) source=\(reason) session=\(acknowledgement.sessionId?.uuidString ?? "none") commandId=\(acknowledgement.commandId.uuidString) phase=\(acknowledgement.phase.rawValue) message=\(acknowledgement.message ?? "none")")
        case .command(let command):
            switch command {
            case .pause: pause()
            case .resume: resume()
            case .finish: finish()
            }
        case .metrics, .routeDelta, .summary, .options:
            break
        }
    }

    private func applyIdentity(_ identity: PulsarRunSessionIdentity) {
        snapshot.pulsarWorkoutSessionId = identity.sessionId
        snapshot.workoutKind = identity.workoutKind
        activeWorkoutStartedFrom = identity.startedFrom
        activeWorkoutKind = identity.workoutKind
        if let builder = workoutBuilder {
            addMetadata(
                workoutMetadata(startedFrom: identity.startedFrom),
                to: builder,
                context: "Apple Watch outdoor identity update"
            )
        }
        PulsarSyncDebugLogger.log("Watch run identity applied selectedType=\(identity.workoutKind.rawValue) session=\(identity.sessionId.uuidString) startedFrom=\(identity.startedFrom.rawValue)")
        publishActiveWorkoutState(updatedFrom: .appleWatch, reason: "watchRunIdentityApplied")
        sendMetricsIfNeeded(force: true)
    }

    private func publishActiveWorkoutState(
        phase: PulsarActiveWorkoutSyncPhase? = nil,
        updatedFrom: PulsarWorkoutStartedFrom,
        reason: String
    ) {
        guard let sessionId = snapshot.pulsarWorkoutSessionId else { return }
        let startedFrom = activeWorkoutStartedFrom ?? (syncStore.activeWorkoutState?.sessionId == sessionId
            ? syncStore.activeWorkoutState?.startedFrom ?? updatedFrom
            : updatedFrom)
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
        syncStore.storeActiveWorkoutState(state, broadcast: true, reason: reason)
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
                PulsarSyncDebugLogger.log("Watch run HealthKit metadata added context=\(context) session=\(metadata[PulsarWorkoutMetadata.sessionIdKey] as? String ?? "none") type=\(metadata[PulsarWorkoutMetadata.workoutTypeKey] as? String ?? "unknown") startedFrom=\(metadata[PulsarWorkoutMetadata.startedFromKey] as? String ?? "unknown")")
            } else if let error {
                PulsarSyncDebugLogger.log("Watch run HealthKit metadata failed context=\(context) error=\(error.localizedDescription)")
            }
        }
    }

    private static func outdoorWorkoutConfiguration(for workoutKind: PulsarOutdoorWorkoutKind) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = workoutKind.healthKitActivityType
        configuration.locationType = workoutKind.defaultLocationType
        return configuration
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

    private static func runPhase(for state: HKWorkoutSessionState) -> PulsarRunPhase {
        switch state {
        case .paused:
            .paused
        case .ended, .stopped:
            .finishing
        case .notStarted, .prepared, .running:
            .running
        @unknown default:
            .running
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
}

extension WatchRunSessionManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.processLocations(locations)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if self.snapshot.phase.isLiveWatchRunPhase,
               self.activeWorkoutKind.isOutdoorDistanceWorkout,
               (manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse) {
                manager.startUpdatingLocation()
                PulsarSyncDebugLogger.log("Watch GPS location updates started after authorization type=\(self.activeWorkoutKind.rawValue) session=\(self.snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            }
        }
    }
}

extension WatchRunSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            switch toState {
            case .running:
                self.applyRunningState(date: date)
            case .paused:
                self.applyPausedState(date: date)
            case .stopped:
                await self.finishWorkout()
            case .ended:
                PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Watch run HealthKit session ended callback session=\(self.snapshot.pulsarWorkoutSessionId?.uuidString ?? "none")")
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.snapshot.phase = .failed
            self.message = error.localizedDescription
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in
            for item in data {
                guard let envelope = PulsarRunTransportCodec.decode(item) else { continue }
                self.handleRunTransportEnvelope(envelope)
            }
        }
    }
}

extension WatchRunSessionManager: HKLiveWorkoutBuilderDelegate {
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
    var isLiveWatchRunPhase: Bool {
        switch self {
        case .connectingToWatch, .running, .paused, .finishing:
            true
        case .idle, .requestingPermissions, .countingDown, .finished, .failed:
            false
        }
    }
}
