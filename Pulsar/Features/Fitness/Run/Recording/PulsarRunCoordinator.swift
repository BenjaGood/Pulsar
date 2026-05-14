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
import WatchConnectivity

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

@MainActor
final class PulsarRunCoordinator: NSObject, ObservableObject {
    @Published private(set) var snapshot = PulsarRunMetricSnapshot.empty
    @Published private(set) var summary: PulsarRunSummary?
    @Published private(set) var authorizationMessage: String?
    @Published private(set) var preferredSource: PulsarRunRecordingSource = .iPhone
    @Published private(set) var isWatchAvailable = false
    @Published private(set) var activeWorkoutKind: PulsarOutdoorWorkoutKind = .running

    private let healthStore = HKHealthStore()
    private let historyStore = PulsarRunHistoryStore()
    private let pedometer = CMPedometer()
    private let watchSession: WCSession? = WCSession.isSupported() ? .default : nil
    private let syncStore = PulsarWatchConnectivitySyncStore.shared

    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var locationManager: CLLocationManager?
    private var liveActivity: Activity<PulsarRunLiveActivityAttributes>?
    private var tickTask: Task<Void, Never>?
    private var mirrorFallbackTask: Task<Void, Never>?

    private var options = PulsarRunOptions.default
    private var startDate: Date?
    private var pauseBeganAt: Date?
    private var accumulatedPausedTime: TimeInterval = 0
    private var lastLocation: CLLocation?
    private var lastAcceptedAltitude: Double?
    private var recentMovingSamples: [(date: Date, distanceMeters: Double)] = []
    private var splitStartDistance: Double = 0
    private var splitStartMovingTime: TimeInterval = 0
    private var splitElevationGain: Double = 0
    private var splitHeartRates: [Double] = []
    private var heartRates: [Double] = []
    private var autoPauseCandidateSince: Date?
    private var activeWorkoutStartedFrom: PulsarWorkoutStartedFrom?
    private var isFinishing = false

    override init() {
        super.init()
        registerWorkoutMirroringHandler()
        syncStore.registerActiveWorkoutStateHandler { [weak self] state in
            Task { @MainActor in
                self?.reconcileActiveWorkoutSyncState(state)
            }
        }
        updatePreferredSource()
    }

    func refreshAvailability() {
        updatePreferredSource()
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

    func startOutdoorWorkout(_ workoutKind: PulsarOutdoorWorkoutKind, options: PulsarRunOptions) async {
        self.options = options
        summary = nil
        activeWorkoutKind = workoutKind
        let sessionId = UUID()
        let expectedSource: PulsarRunRecordingSource = options.prefersWatchRecorder && isWatchAvailable ? .appleWatch : .iPhone
        resetRuntimeState(
            source: expectedSource,
            workoutKind: workoutKind,
            pulsarWorkoutSessionId: sessionId,
            startedFrom: .iPhone
        )
        PulsarSyncDebugLogger.log("Run start selectedType=\(workoutKind.rawValue) hkType=\(workoutKind.healthKitActivityType.rawValue) session=\(sessionId.uuidString) startedFrom=iPhone expectedSource=\(expectedSource.rawValue)")
        publishActiveWorkoutState(phase: .starting, updatedFrom: .iPhone, reason: "iPhoneRunStartPrepared")

        if options.prefersWatchRecorder && isWatchAvailable {
            do {
                snapshot.phase = .connectingToWatch
                publishActiveWorkoutState(phase: .starting, updatedFrom: .iPhone, reason: "iPhoneRunStartingWatch")
                try await healthStore.startWatchApp(toHandle: Self.outdoorWorkoutConfiguration(for: workoutKind))
                beginMirrorFallbackTimer()
                return
            } catch {
                authorizationMessage = "Apple Watch could not start the \(workoutKind.actionName), so Pulsar switched to iPhone recording."
            }
        }

        do {
            try await startIPhoneWorkout()
        } catch {
            snapshot.phase = .failed
            snapshot.statusMessage = error.localizedDescription
            authorizationMessage = "Pulsar could not start a \(workoutKind.displayName.lowercased()) workout. Check Health and Location permissions."
        }
    }

    func pause() {
        if snapshot.source == .appleWatch {
            sendRemoteCommand(.pause)
        }
        workoutSession?.pause()
        applyPausedState(date: Date())
        publishActiveWorkoutState(phase: .paused, updatedFrom: .iPhone, reason: "iPhoneRunPaused")
    }

    func resume() {
        if snapshot.source == .appleWatch {
            sendRemoteCommand(.resume)
        }
        workoutSession?.resume()
        applyRunningState(date: Date())
        publishActiveWorkoutState(phase: .resumed, updatedFrom: .iPhone, reason: "iPhoneRunResumed")
    }

    func finish() {
        guard snapshot.phase == .running || snapshot.phase == .paused || snapshot.phase == .connectingToWatch else { return }
        snapshot.phase = .finishing
        publishActiveWorkoutState(phase: .ending, updatedFrom: .iPhone, reason: "iPhoneRunEnding")
        if snapshot.source == .appleWatch {
            sendRemoteCommand(.finish)
            workoutSession?.end()
            makeMirroredSummaryIfNeeded()
        } else {
            workoutSession?.end()
        }
    }

    func resetAfterSummary() {
        summary = nil
        snapshot = .empty
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
        guard state.lastUpdatedFrom != .iPhone || snapshot.pulsarWorkoutSessionId != state.sessionId else { return }

        if state.isEnded {
            guard snapshot.pulsarWorkoutSessionId == state.sessionId else { return }
            snapshot.phase = state.phase.runPhase
            snapshot.endedAt = state.endedAt ?? Date()
            endLiveActivity()
            PulsarSyncDebugLogger.log("Run UI reconciled ended sync state session=\(state.sessionId.uuidString) type=\(workoutKind.rawValue) phase=\(state.phase.rawValue)")
            return
        }

        if snapshot.pulsarWorkoutSessionId != state.sessionId {
            resetRuntimeState(
                source: state.startedFrom == .appleWatch ? .appleWatch : .iPhone,
                workoutKind: workoutKind,
                pulsarWorkoutSessionId: state.sessionId,
                startedFrom: state.startedFrom
            )
            snapshot.startedAt = state.startedAt
            startDate = state.startedAt
            startLiveActivityIfPossible()
            PulsarSyncDebugLogger.log("Run UI opened from sync state session=\(state.sessionId.uuidString) type=\(workoutKind.rawValue) phase=\(state.phase.rawValue) startedFrom=\(state.startedFrom.rawValue)")
        }

        snapshot.phase = state.phase.runPhase
        snapshot.elapsedTime = TimeInterval(state.elapsedSeconds)
        snapshot.currentHeartRate = state.currentHeartRate ?? snapshot.currentHeartRate
        snapshot.activeEnergyKilocalories = state.activeEnergyKilocalories ?? snapshot.activeEnergyKilocalories
        activeWorkoutKind = workoutKind

        if state.lastUpdatedFrom == .appleWatch {
            switch state.phase {
            case .paused:
                workoutSession?.pause()
                applyPausedState(date: state.updatedAt)
            case .active, .resumed:
                workoutSession?.resume()
                applyRunningState(date: state.updatedAt)
            case .ending, .ended:
                finish()
            case .starting, .failed:
                break
            }
        }
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
        session.startActivity(with: start)
        try await builder.beginCollection(at: start)
        addMetadata(
            workoutMetadata(startedFrom: .iPhone),
            to: builder,
            context: "iPhone outdoor workout"
        )
        publishActiveWorkoutState(phase: .active, updatedFrom: .iPhone, reason: "iPhoneRunHealthKitStarted")

        startLocationUpdates()
        startPedometerUpdates(from: start)
        startTicking()
        startLiveActivityIfPossible()
    }

    private func attachMirroredSession(_ session: HKWorkoutSession) {
        mirrorFallbackTask?.cancel()
        let phoneStartedSessionId = snapshot.phase == .connectingToWatch ? snapshot.pulsarWorkoutSessionId : nil
        let startedFrom: PulsarWorkoutStartedFrom = phoneStartedSessionId == nil ? .appleWatch : .iPhone
        cleanupRuntime(keepsSnapshot: true)
        let workoutKind = PulsarOutdoorWorkoutKind(activityType: session.workoutConfiguration.activityType)
        resetRuntimeState(
            source: .appleWatch,
            workoutKind: workoutKind,
            pulsarWorkoutSessionId: phoneStartedSessionId,
            startedFrom: startedFrom
        )
        workoutSession = session
        session.delegate = self
        snapshot.phase = session.state == .paused ? .paused : .running
        snapshot.startedAt = Date()
        startDate = snapshot.startedAt
        snapshot.statusMessage = "Recording on Apple Watch"
        if let phoneStartedSessionId {
            sendRemoteIdentity(sessionId: phoneStartedSessionId, workoutKind: workoutKind, startedFrom: .iPhone)
        }
        PulsarSyncDebugLogger.log("Run mirrored session attached selectedType=\(workoutKind.rawValue) hkType=\(session.workoutConfiguration.activityType.rawValue) session=\(snapshot.pulsarWorkoutSessionId?.uuidString ?? "pending-watch") startedFrom=\(startedFrom.rawValue)")
        publishActiveWorkoutState(phase: snapshot.phase == .paused ? .paused : .active, updatedFrom: .iPhone, reason: "iPhoneRunMirroredSessionAttached")
        startTicking()
        startLiveActivityIfPossible()
    }

    private func beginMirrorFallbackTimer() {
        mirrorFallbackTask?.cancel()
        mirrorFallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            await MainActor.run {
                guard let self, self.snapshot.phase == .connectingToWatch else { return }
                self.authorizationMessage = "Apple Watch did not connect in time, so Pulsar started an iPhone run."
                Task { try? await self.startIPhoneWorkout() }
            }
        }
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
        guard let watchSession else {
            isWatchAvailable = false
            preferredSource = .iPhone
            return
        }
        isWatchAvailable = watchSession.isPaired && watchSession.isWatchAppInstalled
        preferredSource = isWatchAvailable ? .appleWatch : .iPhone
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
        lastLocation = nil
        lastAcceptedAltitude = nil
        recentMovingSamples = []
        splitStartDistance = 0
        splitStartMovingTime = 0
        splitElevationGain = 0
        splitHeartRates = []
        heartRates = []
        autoPauseCandidateSince = nil
    }

    private func cleanupRuntime(keepsSnapshot: Bool = false) {
        tickTask?.cancel()
        tickTask = nil
        mirrorFallbackTask?.cancel()
        mirrorFallbackTask = nil
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
                self?.snapshot.stepCount = data.numberOfSteps.intValue
                if let currentCadence = data.currentCadence?.doubleValue, currentCadence > 0 {
                    self?.snapshot.cadenceStepsPerMinute = currentCadence * 60
                }
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
        snapshot.elapsedTime = max(0, date.timeIntervalSince(startDate))
        let activePausedTime = pauseBeganAt.map { date.timeIntervalSince($0) } ?? 0
        snapshot.movingTime = max(0, snapshot.elapsedTime - accumulatedPausedTime - activePausedTime)
        snapshot.averagePaceSecondsPerKilometer = PulsarRunDerivedMetrics.averagePace(distanceMeters: snapshot.distanceMeters, movingTime: snapshot.movingTime)
        snapshot.activeSplitIndex = PulsarRunDerivedMetrics.splitIndex(distanceMeters: snapshot.distanceMeters)
    }

    private func processLocations(_ locations: [CLLocation]) {
        guard snapshot.source == .iPhone else { return }
        for location in locations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 35 {
            guard location.timestamp >= (startDate ?? .distantPast) else { continue }

            let coordinate = PulsarRunCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
                horizontalAccuracy: location.horizontalAccuracy,
                verticalAccuracy: location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil,
                timestamp: location.timestamp
            )
            snapshot.route.append(coordinate)
            snapshot.currentElevationMeters = coordinate.altitude

            if let lastLocation {
                let delta = location.distance(from: lastLocation)
                if delta >= 2.5, snapshot.phase == .running {
                    snapshot.distanceMeters += delta
                    recentMovingSamples.append((location.timestamp, snapshot.distanceMeters))
                    recentMovingSamples.removeAll { location.timestamp.timeIntervalSince($0.date) > 24 }
                }
            }

            let gain = PulsarRunDerivedMetrics.elevationGain(
                previousAltitude: lastAcceptedAltitude,
                nextAltitude: location.altitude,
                verticalAccuracy: location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil
            )
            if gain > 0, snapshot.phase == .running {
                snapshot.elevationGainMeters += gain
                splitElevationGain += gain
            }
            if location.verticalAccuracy >= 0 && location.verticalAccuracy <= 18 {
                lastAcceptedAltitude = location.altitude
            }

            routeBuilder?.insertRouteData([location]) { _, _ in }
            lastLocation = location
            updateAutoPause(with: location)
        }
        updatePaceFromRecentSamples()
        updateSplitsIfNeeded()
    }

    private func updateAutoPause(with location: CLLocation) {
        guard options.autoPauseEnabled, snapshot.source == .iPhone else { return }
        let shouldPause = PulsarRunDerivedMetrics.shouldAutoPause(
            speedMetersPerSecond: location.speed >= 0 ? location.speed : nil,
            horizontalAccuracy: location.horizontalAccuracy
        )

        if shouldPause {
            if autoPauseCandidateSince == nil {
                autoPauseCandidateSince = location.timestamp
            }
            if let candidate = autoPauseCandidateSince,
               location.timestamp.timeIntervalSince(candidate) >= 8,
               snapshot.phase == .running {
                workoutSession?.pause()
                applyPausedState(date: location.timestamp)
            }
        } else {
            autoPauseCandidateSince = nil
            if snapshot.phase == .paused, pauseBeganAt != nil {
                workoutSession?.resume()
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
                    averageHeartRate: averageHeartRate
                )
            )
            splitStartDistance = splitEndDistance
            splitStartMovingTime = snapshot.movingTime
            splitElevationGain = 0
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
    }

    private func applyRunningState(date: Date) {
        if let pauseBeganAt {
            accumulatedPausedTime += date.timeIntervalSince(pauseBeganAt)
        }
        pauseBeganAt = nil
        snapshot.phase = .running
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
                let average = statistics?.averageQuantity()?.doubleValue(for: unit)
                let max = statistics?.maximumQuantity()?.doubleValue(for: unit)
                snapshot.currentHeartRate = current
                snapshot.averageHeartRate = average
                snapshot.maxHeartRate = max
                if let current {
                    heartRates.append(current)
                    splitHeartRates.append(current)
                }
            case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                snapshot.activeEnergyKilocalories = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie())
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
    }

    private func finishIPhoneWorkout() async {
        guard !isFinishing else { return }
        isFinishing = true
        snapshot.phase = .finishing
        cleanupRuntime(keepsSnapshot: true)
        let end = Date()
        snapshot.endedAt = end
        updateTimeMetrics(date: end)

        do {
            try await workoutBuilder?.endCollection(at: end)
            let workout = try await workoutBuilder?.finishWorkout()
            if let workout, !snapshot.route.isEmpty {
                var routeMetadata = workoutMetadata(startedFrom: .iPhone)
                routeMetadata["PulsarRouteSource"] = "iPhone GPS"
                _ = try? await routeBuilder?.finishRoute(with: workout, metadata: routeMetadata)
            }
            let finishedSummary = makeSummary(workoutUUID: workout?.uuid)
            summary = finishedSummary
            await historyStore.save(finishedSummary)
            snapshot.phase = .finished
            publishActiveWorkoutState(phase: .ended, updatedFrom: .iPhone, reason: "iPhoneRunFinished")
            endLiveActivity()
        } catch {
            snapshot.phase = .failed
            snapshot.statusMessage = "Workout saved locally, but HealthKit finish failed: \(error.localizedDescription)"
            let finishedSummary = makeSummary(workoutUUID: nil)
            summary = finishedSummary
            await historyStore.save(finishedSummary)
            publishActiveWorkoutState(phase: .failed, updatedFrom: .iPhone, reason: "iPhoneRunFinishFailed")
            endLiveActivity()
        }
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
        endLiveActivity()
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
            distanceMeters: snapshot.distanceMeters,
            elapsedTime: snapshot.elapsedTime,
            movingTime: snapshot.movingTime,
            activeEnergyKilocalories: snapshot.activeEnergyKilocalories,
            elevationGainMeters: snapshot.elevationGainMeters,
            averageHeartRate: snapshot.averageHeartRate,
            maxHeartRate: snapshot.maxHeartRate,
            steps: snapshot.stepCount,
            averageCadenceStepsPerMinute: snapshot.cadenceStepsPerMinute,
            route: snapshot.route,
            splits: snapshot.splits
        )
    }

    private func sendRemoteCommand(_ command: PulsarRunControlCommand) {
        guard let data = PulsarRunTransportCodec.encode(.command(command)) else { return }
        workoutSession?.sendToRemoteWorkoutSession(data: data) { _, _ in }
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
        syncStore.storeActiveWorkoutState(state, broadcast: true, reason: reason)
    }

    private func receiveRemoteEnvelope(_ envelope: PulsarRunTransportEnvelope) {
        switch envelope {
        case .identity:
            break
        case .metrics(let metrics):
            let currentSessionId = snapshot.pulsarWorkoutSessionId
            let currentStartedFrom = activeWorkoutStartedFrom
            snapshot = metrics
            if currentStartedFrom == .iPhone, let currentSessionId {
                snapshot.pulsarWorkoutSessionId = currentSessionId
            } else if snapshot.pulsarWorkoutSessionId == nil {
                snapshot.pulsarWorkoutSessionId = currentSessionId
            }
            activeWorkoutKind = metrics.workoutKind
            if startDate == nil {
                startDate = metrics.startedAt
            }
            updateLiveActivity()
            publishActiveWorkoutState(updatedFrom: .appleWatch, reason: "iPhoneRunMetricsReceived")
        case .summary(let receivedSummary):
            var resolvedSummary = receivedSummary
            if activeWorkoutStartedFrom == .iPhone,
               let currentSessionId = snapshot.pulsarWorkoutSessionId {
                resolvedSummary.pulsarWorkoutSessionId = currentSessionId
            }
            summary = resolvedSummary
            activeWorkoutKind = resolvedSummary.workoutKind
            snapshot.phase = .finished
            Task { await historyStore.save(resolvedSummary) }
            publishActiveWorkoutState(phase: .ended, updatedFrom: .appleWatch, reason: "iPhoneRunSummaryReceived")
            endLiveActivity()
        case .command:
            break
        case .options:
            break
        }
    }

    private func startLiveActivityIfPossible() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = PulsarRunLiveActivityAttributes(runID: UUID())
        let state = PulsarRunLiveActivityAttributes.ContentState(
            distanceMeters: snapshot.distanceMeters,
            elapsedTime: snapshot.elapsedTime,
            paceSecondsPerKilometer: snapshot.averagePaceSecondsPerKilometer,
            heartRate: snapshot.currentHeartRate,
            phase: snapshot.phase
        )
        liveActivity = try? Activity.request(attributes: attributes, content: .init(state: state, staleDate: nil))
    }

    private func updateLiveActivity() {
        guard let liveActivity else { return }
        let state = PulsarRunLiveActivityAttributes.ContentState(
            distanceMeters: snapshot.distanceMeters,
            elapsedTime: snapshot.elapsedTime,
            paceSecondsPerKilometer: snapshot.averagePaceSecondsPerKilometer,
            heartRate: snapshot.currentHeartRate,
            phase: snapshot.phase
        )
        Task {
            await liveActivity.update(.init(state: state, staleDate: nil))
        }
    }

    private func endLiveActivity() {
        guard let liveActivity else { return }
        let state = PulsarRunLiveActivityAttributes.ContentState(
            distanceMeters: snapshot.distanceMeters,
            elapsedTime: snapshot.elapsedTime,
            paceSecondsPerKilometer: snapshot.averagePaceSecondsPerKilometer,
            heartRate: snapshot.currentHeartRate,
            phase: snapshot.phase
        )
        Task {
            await liveActivity.end(.init(state: state, staleDate: nil), dismissalPolicy: .default)
        }
        self.liveActivity = nil
    }

    private static func outdoorWorkoutConfiguration(for workoutKind: PulsarOutdoorWorkoutKind) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = workoutKind.healthKitActivityType
        configuration.locationType = workoutKind.defaultLocationType
        return configuration
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
            case .ended:
                if self.snapshot.source == .iPhone {
                    await self.finishIPhoneWorkout()
                } else {
                    self.makeMirroredSummaryIfNeeded()
                }
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.snapshot.phase = .failed
            self.snapshot.statusMessage = error.localizedDescription
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
