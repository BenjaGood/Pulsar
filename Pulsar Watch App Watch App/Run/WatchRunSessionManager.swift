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

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var locationManager: CLLocationManager?
    private var tickTask: Task<Void, Never>?

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
    private var isFinishing = false
    private var lastMetricsSentAt = Date.distantPast

    private override init() {
        super.init()
    }

    func requestAuthorization() async {
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
            message = "Allow Health and Location to record a run."
        }
    }

    func startRunFromWatch(options: PulsarRunOptions) async {
        await requestAuthorization()
        guard message == nil else { return }
        do {
            try await startWorkout(configuration: Self.outdoorRunConfiguration)
        } catch {
            snapshot.phase = .failed
            message = error.localizedDescription
        }
    }

    func startRunFromCompanion(configuration: HKWorkoutConfiguration) async {
        await requestAuthorization()
        guard message == nil else { return }
        do {
            try await startWorkout(configuration: configuration)
        } catch {
            snapshot.phase = .failed
            message = error.localizedDescription
        }
    }

    func pause() {
        workoutSession?.pause()
        applyPausedState(date: Date())
    }

    func resume() {
        workoutSession?.resume()
        applyRunningState(date: Date())
    }

    func finish() {
        guard snapshot.phase == .running || snapshot.phase == .paused else { return }
        snapshot.phase = .finishing
        workoutSession?.end()
    }

    func reset() {
        cleanupRuntime()
        snapshot = .empty
        summary = nil
        message = nil
    }

    private func startWorkout(configuration: HKWorkoutConfiguration) async throws {
        reset()
        snapshot.source = .appleWatch
        snapshot.phase = .running
        snapshot.startedAt = Date()
        startDate = snapshot.startedAt

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
        try? await session.startMirroringToCompanionDevice()

        startLocationUpdates()
        startTicking()
        sendMetricsIfNeeded(force: true)
        WKInterfaceDevice.current().play(.start)
    }

    private func cleanupRuntime(keepsWorkoutObjects: Bool = false) {
        tickTask?.cancel()
        tickTask = nil
        locationManager?.stopUpdatingLocation()
        if !keepsWorkoutObjects {
            workoutSession = nil
            workoutBuilder = nil
            routeBuilder = nil
        }
        startDate = nil
        pauseBeganAt = nil
        accumulatedPausedTime = 0
        lastLocation = nil
        lastAcceptedAltitude = nil
        recentMovingSamples = []
        splitStartDistance = 0
        splitStartMovingTime = 0
        splitElevationGain = 0
        splitHeartRates = []
        isFinishing = false
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

    private func updateTimeMetrics(date: Date) {
        guard let startDate else { return }
        snapshot.elapsedTime = max(0, date.timeIntervalSince(startDate))
        let activePausedTime = pauseBeganAt.map { date.timeIntervalSince($0) } ?? 0
        snapshot.movingTime = max(0, snapshot.elapsedTime - accumulatedPausedTime - activePausedTime)
        snapshot.averagePaceSecondsPerKilometer = PulsarRunDerivedMetrics.averagePace(distanceMeters: snapshot.distanceMeters, movingTime: snapshot.movingTime)
        snapshot.activeSplitIndex = PulsarRunDerivedMetrics.splitIndex(distanceMeters: snapshot.distanceMeters)
        updateSplitsIfNeeded()
    }

    private func processLocations(_ locations: [CLLocation]) {
        for location in locations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 35 {
            guard location.timestamp >= (startDate ?? .distantPast) else { continue }
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
            snapshot.currentElevationMeters = location.verticalAccuracy >= 0 ? location.altitude : nil

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
        }
        updateCurrentPace()
        updateSplitsIfNeeded()
        sendMetricsIfNeeded()
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
                    averageHeartRate: averageHeartRate
                )
            )
            splitStartDistance = Double(index) * 1_000
            splitStartMovingTime = snapshot.movingTime
            splitElevationGain = 0
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
        sendMetricsIfNeeded(force: true)
        WKInterfaceDevice.current().play(.stop)
    }

    private func applyRunningState(date: Date) {
        if let pauseBeganAt {
            accumulatedPausedTime += date.timeIntervalSince(pauseBeganAt)
        }
        pauseBeganAt = nil
        snapshot.phase = .running
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
        guard !isFinishing else { return }
        isFinishing = true
        cleanupRuntime(keepsWorkoutObjects: true)
        let end = Date()
        snapshot.endedAt = end
        updateTimeMetrics(date: end)
        do {
            try await workoutBuilder?.endCollection(at: end)
            let workout = try await workoutBuilder?.finishWorkout()
            if let workout, !snapshot.route.isEmpty {
                _ = try? await routeBuilder?.finishRoute(with: workout, metadata: ["PulsarRouteSource": "Apple Watch GPS"])
            }
            let finishedSummary = makeSummary(workoutUUID: workout?.uuid)
            summary = finishedSummary
            snapshot.phase = .finished
            sendEnvelope(.summary(finishedSummary))
            WKInterfaceDevice.current().play(.success)
        } catch {
            snapshot.phase = .failed
            message = error.localizedDescription
            sendMetricsIfNeeded(force: true)
        }
    }

    private func makeSummary(workoutUUID: UUID?) -> PulsarRunSummary {
        let start = snapshot.startedAt ?? Date()
        let end = snapshot.endedAt ?? Date()
        return PulsarRunSummary(
            id: workoutUUID ?? UUID(),
            workoutUUID: workoutUUID,
            startedAt: start,
            endedAt: end,
            source: .appleWatch,
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

    private func sendMetricsIfNeeded(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastMetricsSentAt) >= 1.5 else { return }
        lastMetricsSentAt = now
        sendEnvelope(.metrics(snapshot))
    }

    private func sendEnvelope(_ envelope: PulsarRunTransportEnvelope) {
        guard let data = PulsarRunTransportCodec.encode(envelope) else { return }
        workoutSession?.sendToRemoteWorkoutSession(data: data) { _, _ in }
    }

    private static let outdoorRunConfiguration: HKWorkoutConfiguration = {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor
        return configuration
    }()

    private static var healthShareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        [
            HKQuantityTypeIdentifier.activeEnergyBurned,
            .distanceWalkingRunning
        ].compactMap { HKObjectType.quantityType(forIdentifier: $0) }.forEach { types.insert($0) }
        return types
    }

    private static var healthReadTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = healthShareTypes
        [
            HKQuantityTypeIdentifier.heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning,
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
}

extension WatchRunSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            switch toState {
            case .running:
                self.applyRunningState(date: date)
            case .paused:
                self.applyPausedState(date: date)
            case .ended:
                await self.finishWorkout()
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
                if case .command(let command) = envelope {
                    switch command {
                    case .pause: self.pause()
                    case .resume: self.resume()
                    case .finish: self.finish()
                    }
                }
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
