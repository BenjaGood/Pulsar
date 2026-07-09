//
//  PersonalizedWorkoutSessionViewModel.swift
//  Pulsar
//

import Combine
import Foundation
import HealthKit
import SwiftUI

struct PersonalizedWorkoutLiveMetrics: Equatable {
    var elapsedTime: TimeInterval = 0
    var activeEnergyKilocalories: Double?
    var distanceMeters: Double?
    var stepCount: Double?
    var paceSecondsPerKilometer: Double?
    var speedMetersPerSecond: Double?
    var currentHeartRate: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var savedWorkoutUUID: UUID?
}

@MainActor
final class PersonalizedWorkoutHealthKitManager: NSObject, ObservableObject {
    @Published private(set) var metrics = PersonalizedWorkoutLiveMetrics()
    @Published private(set) var phase: PulsarLiveWorkoutDashboardPhase = .preparing
    @Published private(set) var statusMessage = "Ready for Apple Health"
    @Published private(set) var healthAccessMessage: String?
    @Published private(set) var watchConnectionMessage: String?
    @Published private(set) var isHealthKitEnabled = false

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var workoutSessionId = UUID()
    private var startedAt: Date?
    private var pausedAt: Date?
    private var accumulatedPausedTime: TimeInterval = 0
    private var tickTask: Task<Void, Never>?
    private var isFinishing = false
    private var sessionStoppedContinuation: CheckedContinuation<Void, Never>?
    private var sessionStopFallbackTask: Task<Void, Never>?

    func start(workout: PersonalizedWorkoutKind) async {
        guard phase != .running, phase != .finishing else { return }

        let sessionID = UUID()
        let workoutType = workout.rawValue
        switch PulsarWorkoutStartCoordinator.shared.requestStart(
            sessionID: sessionID,
            kind: .run(workout.outdoorWorkoutKind ?? .indoorRunning),
            source: "PersonalizedWorkoutStart",
            workoutType: workoutType
        ) {
        case .granted, .duplicateStart:
            break
        case .alreadyActive:
            return
        case .rejectedConflict:
            healthAccessMessage = "Another workout is already active. Finish it before starting a new one."
            statusMessage = "Workout Unavailable"
            return
        }

        resetRuntime()
        phase = .preparing
        statusMessage = "Requesting Apple Health"
        healthAccessMessage = nil
        watchConnectionMessage = nil
        workoutSessionId = sessionID

        guard await requestAuthorization() else {
            PulsarWorkoutStartCoordinator.shared.markStartFailed(
                sessionID: sessionID,
                workoutType: workoutType,
                source: "PersonalizedWorkoutStart",
                error: healthAccessMessage ?? "authorizationDenied"
            )
            return
        }

        PulsarHealthKitWorkoutSessionTeardown.stopAndEnd(
            workoutSession,
            reason: "PersonalizedWorkoutStartReplaceExisting"
        )
        workoutSession = nil
        workoutBuilder = nil

        do {
            let configuration = Self.workoutConfiguration(for: workout)
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            PulsarWorkoutLifecycleLogger.log(
                .workoutHealthKitSessionCreated,
                sessionID: sessionID,
                workoutType: workoutType,
                source: "PersonalizedWorkoutStart"
            )
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self

            workoutSession = session
            workoutBuilder = builder

            let start = Date()
            startedAt = start
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            PulsarWorkoutLifecycleLogger.log(
                .workoutBuilderStarted,
                sessionID: sessionID,
                workoutType: workoutType,
                source: "PersonalizedWorkoutStart"
            )
            addMetadata(Self.metadata(for: workout, sessionId: workoutSessionId), to: builder)

            isHealthKitEnabled = true
            phase = .running
            statusMessage = "Apple Health Live"
            updateElapsedTime(at: start, phase: .running)
            startTicking()
            PulsarWorkoutStartCoordinator.shared.markActivated(
                sessionID: sessionID,
                workoutType: workoutType,
                source: "PersonalizedWorkoutStart"
            )
            PulsarSyncDebugLogger.log("Personalized workout started type=\(workout.rawValue) session=\(workoutSessionId.uuidString)")
        } catch {
            phase = .preparing
            isHealthKitEnabled = false
            statusMessage = "Apple Health Unavailable"
            healthAccessMessage = "Apple Health could not start this workout: \(error.localizedDescription)"
            PulsarWorkoutStartCoordinator.shared.markStartFailed(
                sessionID: sessionID,
                workoutType: workoutType,
                source: "PersonalizedWorkoutStart",
                error: error.localizedDescription
            )
            cleanup(keepsMetrics: true)
        }
    }

    func pause() {
        guard phase == .running else { return }
        pausedAt = Date()
        workoutSession?.pause()
        tickTask?.cancel()
        updateElapsedTime(at: pausedAt ?? Date(), phase: .paused)
        phase = .paused
        statusMessage = "Paused"
    }

    func resume() {
        guard phase == .paused else { return }
        let now = Date()
        if let pausedAt {
            accumulatedPausedTime += max(0, now.timeIntervalSince(pausedAt))
        }
        pausedAt = nil
        workoutSession?.resume()
        phase = .running
        statusMessage = "Apple Health Live"
        updateElapsedTime(at: now, phase: .running)
        startTicking()
    }

    func finish() async {
        guard phase == .running || phase == .paused || phase == .preparing else { return }
        guard !isFinishing else { return }
        isFinishing = true
        tickTask?.cancel()
        phase = .finishing
        statusMessage = "Saving to Apple Health"

        let endedAt = Date()
        updateElapsedTime(at: endedAt, phase: .finishing)

        guard let builder = workoutBuilder else {
            workoutSession?.end()
            cleanup(keepsMetrics: true)
            phase = .finished
            statusMessage = healthAccessMessage == nil ? "Workout Ended" : "Workout Not Saved"
            return
        }

        stopWorkoutSessionIfNeeded(endedAt: endedAt)
        await waitForStoppedStateIfNeeded(endedAt: endedAt)

        do {
            try await builder.endCollection(at: endedAt)
            let workout = try await builder.finishWorkout()
            metrics.savedWorkoutUUID = workout?.uuid
            statusMessage = workout?.uuid == nil ? "Workout Saved" : "Saved to Apple Health"
            phase = .finished
            PulsarSyncDebugLogger.log("Personalized workout saved session=\(workoutSessionId.uuidString) workout=\(workout?.uuid.uuidString ?? "none")")
        } catch {
            healthAccessMessage = "Workout ended, but Apple Health save failed: \(error.localizedDescription)"
            statusMessage = "Save Failed"
            phase = .finished
        }

        workoutSession?.end()
        cleanup(keepsMetrics: true)
        PulsarWorkoutStartCoordinator.shared.markSessionEnded(
            sessionID: workoutSessionId,
            reason: "personalizedWorkoutFinished"
        )
    }

    func stopWithoutSaving() {
        tickTask?.cancel()
        stopWorkoutSessionIfNeeded(endedAt: Date())
        workoutSession?.end()
        cleanup(keepsMetrics: true)
        phase = .finished
        statusMessage = "Workout Discarded"
        PulsarWorkoutStartCoordinator.shared.markSessionEnded(
            sessionID: workoutSessionId,
            reason: "personalizedWorkoutDiscarded"
        )
    }

    private func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            isHealthKitEnabled = false
            statusMessage = "Apple Health Unavailable"
            healthAccessMessage = "Apple Health is not available on this device."
            return false
        }

        do {
            try await healthStore.requestAuthorization(toShare: Self.healthShareTypes, read: Self.healthReadTypes)
            let workoutStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
            guard workoutStatus != .sharingDenied else {
                isHealthKitEnabled = false
                statusMessage = "Health Access Denied"
                healthAccessMessage = "Apple Health workout permission is off. Enable it in Settings to record and save workouts."
                return false
            }
            isHealthKitEnabled = true
            return true
        } catch {
            isHealthKitEnabled = false
            statusMessage = "Health Permission Needed"
            healthAccessMessage = "Apple Health permission is needed for live heart rate, calories, distance, steps, and workout saving."
            return false
        }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.tick()
            }
        }
    }

    private func tick() {
        guard phase == .running else { return }
        updateElapsedTime(at: Date(), phase: .running)
    }

    private func updateElapsedTime(at date: Date, phase: PulsarLiveWorkoutDashboardPhase) {
        var nextMetrics = metrics
        nextMetrics.elapsedTime = activeElapsedTime(at: date, phase: phase)
        nextMetrics = Self.recomputeDerivedMetrics(nextMetrics)
        guard nextMetrics != metrics else { return }
        metrics = nextMetrics
    }

    private func activeElapsedTime(at date: Date, phase: PulsarLiveWorkoutDashboardPhase) -> TimeInterval {
        guard let startedAt else { return 0 }
        let referenceDate = phase == .paused ? (pausedAt ?? date) : date
        return max(0, referenceDate.timeIntervalSince(startedAt) - accumulatedPausedTime)
    }

    private func updateBuilderStatistics(for collectedTypes: Set<HKSampleType>) {
        guard let builder = workoutBuilder else { return }

        var nextMetrics = metrics
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let statistics = builder.statistics(for: quantityType)
            switch quantityType.identifier {
            case HKQuantityTypeIdentifier.heartRate.rawValue:
                let unit = HKUnit.count().unitDivided(by: .minute())
                nextMetrics.currentHeartRate = statistics?.mostRecentQuantity()?.doubleValue(for: unit)
                nextMetrics.averageHeartRate = statistics?.averageQuantity()?.doubleValue(for: unit)
                nextMetrics.maxHeartRate = statistics?.maximumQuantity()?.doubleValue(for: unit)
            case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                nextMetrics.activeEnergyKilocalories = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie())
            case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
                nextMetrics.distanceMeters = statistics?.sumQuantity()?.doubleValue(for: .meter())
            case HKQuantityTypeIdentifier.stepCount.rawValue:
                nextMetrics.stepCount = statistics?.sumQuantity()?.doubleValue(for: .count())
            default:
                break
            }
        }

        nextMetrics = Self.recomputeDerivedMetrics(nextMetrics)
        guard nextMetrics != metrics else { return }
        metrics = nextMetrics
    }

    private static func recomputeDerivedMetrics(_ metrics: PersonalizedWorkoutLiveMetrics) -> PersonalizedWorkoutLiveMetrics {
        var updated = metrics
        if let distanceMeters = updated.distanceMeters,
           distanceMeters > 0,
           updated.elapsedTime > 0 {
            updated.speedMetersPerSecond = distanceMeters / updated.elapsedTime
            updated.paceSecondsPerKilometer = updated.elapsedTime / (distanceMeters / 1_000)
        } else {
            updated.speedMetersPerSecond = nil
            updated.paceSecondsPerKilometer = nil
        }
        return updated
    }

    private func addMetadata(_ metadata: [String: Any], to builder: HKLiveWorkoutBuilder) {
        builder.addMetadata(metadata) { success, error in
            if success {
                PulsarSyncDebugLogger.log("Personalized HealthKit metadata added session=\(metadata[PulsarWorkoutMetadata.sessionIdKey] as? String ?? "none")")
            } else if let error {
                PulsarSyncDebugLogger.log("Personalized HealthKit metadata failed: \(error.localizedDescription)")
            }
        }
    }

    private func stopWorkoutSessionIfNeeded(endedAt: Date) {
        guard let workoutSession else { return }
        switch workoutSession.state {
        case .ended, .stopped:
            break
        default:
            workoutSession.stopActivity(with: endedAt)
        }
    }

    private func waitForStoppedStateIfNeeded(endedAt: Date) async {
        guard let workoutSession else { return }
        switch workoutSession.state {
        case .stopped, .ended:
            return
        default:
            break
        }

        await withCheckedContinuation { continuation in
            sessionStoppedContinuation = continuation
            sessionStopFallbackTask?.cancel()
            sessionStopFallbackTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                self.resumeStoppedWait(reason: "timeout", date: endedAt)
            }
        }
    }

    private func resumeStoppedWait(reason: String, date: Date? = nil) {
        guard let sessionStoppedContinuation else { return }
        self.sessionStoppedContinuation = nil
        sessionStopFallbackTask?.cancel()
        sessionStopFallbackTask = nil
        PulsarSyncDebugLogger.log("Personalized HealthKit stopped wait completed reason=\(reason) date=\(date?.description ?? "none")")
        sessionStoppedContinuation.resume()
    }

    private func resetRuntime() {
        tickTask?.cancel()
        sessionStopFallbackTask?.cancel()
        if let sessionStoppedContinuation {
            self.sessionStoppedContinuation = nil
            sessionStoppedContinuation.resume()
        }
        PulsarHealthKitWorkoutSessionTeardown.stopAndEnd(
            workoutSession,
            reason: "PersonalizedWorkoutResetRuntime"
        )
        workoutSession = nil
        workoutBuilder = nil
        metrics = PersonalizedWorkoutLiveMetrics()
        startedAt = nil
        pausedAt = nil
        accumulatedPausedTime = 0
        isFinishing = false
    }

    private func cleanup(keepsMetrics: Bool) {
        let retainedMetrics = metrics
        tickTask?.cancel()
        tickTask = nil
        sessionStopFallbackTask?.cancel()
        sessionStopFallbackTask = nil
        if let sessionStoppedContinuation {
            self.sessionStoppedContinuation = nil
            sessionStoppedContinuation.resume()
        }
        PulsarHealthKitWorkoutSessionTeardown.stopAndEnd(
            workoutSession,
            reason: "PersonalizedWorkoutCleanup"
        )
        workoutSession = nil
        workoutBuilder = nil
        startedAt = nil
        pausedAt = nil
        accumulatedPausedTime = 0
        isFinishing = false
        if keepsMetrics {
            metrics = retainedMetrics
        }
    }

    private static func workoutConfiguration(for workout: PersonalizedWorkoutKind) -> HKWorkoutConfiguration {
        if workout == .gym {
            return PulsarWorkoutCatalog.gymWorkoutConfiguration
        }
        if let workoutKind = workout.outdoorWorkoutKind,
           let entry = PulsarWorkoutCatalog.entry(for: workoutKind) {
            return entry.workoutConfiguration
        }
        return PulsarOutdoorWorkoutKind.other.workoutConfiguration
    }

    private static func metadata(for workout: PersonalizedWorkoutKind, sessionId: UUID) -> [String: Any] {
        var metadata = PulsarWorkoutMetadata.base(
            sessionId: sessionId,
            workoutType: workout.rawValue,
            startedFrom: .iPhone
        )
        metadata["PulsarWorkoutCategory"] = "Personalized"
        metadata["PulsarWorkoutKind"] = workout.rawValue
        metadata["PulsarWorkoutDisplayName"] = workout.title
        metadata[PulsarWorkoutMetadata.legacySessionIdKey] = sessionId.uuidString
        return metadata
    }

    private static var healthShareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
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
            .stepCount
        ].compactMap { HKObjectType.quantityType(forIdentifier: $0) }.forEach { types.insert($0) }
        return types
    }
}

extension PersonalizedWorkoutHealthKitManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            if toState == .stopped || toState == .ended {
                self.resumeStoppedWait(reason: Self.describe(toState), date: date)
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.healthAccessMessage = "Apple Health workout session failed: \(error.localizedDescription)"
            self.statusMessage = "Session Failed"
            self.phase = .finished
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor in
            self.watchConnectionMessage = "Apple Watch Disconnected"
        }
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
}

extension PersonalizedWorkoutHealthKitManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            self.updateBuilderStatistics(for: collectedTypes)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

@MainActor
final class PersonalizedWorkoutSessionViewModel: ObservableObject {
    @Published private(set) var dashboardState: PulsarLiveWorkoutDashboardState

    private let workout: PersonalizedWorkoutKind
    private let profile: UserProfile
    private let zoneProfile: PulsarHeartRateZoneProfile
    private let workoutManager = PersonalizedWorkoutHealthKitManager()
    private var cancellables: Set<AnyCancellable> = []

    init(workout: PersonalizedWorkoutKind, profile: UserProfile) {
        let zoneProfile = PulsarHeartRateZoneProfile(profile: profile)
        self.workout = workout
        self.profile = profile
        self.zoneProfile = zoneProfile
        self.dashboardState = Self.makeDashboardState(
            workout: workout,
            profile: profile,
            zoneProfile: zoneProfile,
            manager: workoutManager,
            nowPlaying: .unavailable()
        )

        workoutManager.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    await Task.yield()
                    self?.updateDashboard()
                }
            }
            .store(in: &cancellables)
    }

    func start() async {
        await workoutManager.start(workout: workout)
        updateDashboard()
    }

    func togglePause() {
        switch workoutManager.phase {
        case .paused:
            workoutManager.resume()
        case .running:
            workoutManager.pause()
        case .preparing, .finishing, .finished:
            break
        }
        updateDashboard()
    }

    func end() async {
        await workoutManager.finish()
        updateDashboard()
    }

    func completionSummary(endedAt: Date = Date()) -> PulsarRunSummary {
        let metrics = workoutManager.metrics
        let workoutKind = workout.outdoorWorkoutKind ?? .indoorRunning
        return PulsarRunSummary(
            id: UUID(),
            workoutUUID: metrics.savedWorkoutUUID,
            workoutKind: workoutKind,
            startedAt: endedAt.addingTimeInterval(-metrics.elapsedTime),
            endedAt: endedAt,
            source: .iPhone,
            distanceMeters: metrics.distanceMeters ?? 0,
            elapsedTime: metrics.elapsedTime,
            movingTime: metrics.elapsedTime,
            activeEnergyKilocalories: metrics.activeEnergyKilocalories,
            elevationGainMeters: 0,
            averageHeartRate: metrics.averageHeartRate,
            maxHeartRate: metrics.maxHeartRate,
            steps: metrics.stepCount.map { Int($0.rounded()) },
            averageCadenceStepsPerMinute: nil,
            route: [],
            splits: []
        )
    }

    func cancel() {
        if workoutManager.phase == .running || workoutManager.phase == .paused || workoutManager.phase == .finishing {
            workoutManager.stopWithoutSaving()
        }
        updateDashboard()
    }

    func updateNowPlaying(_ track: PulsarNowPlayingTrack) {
        dashboardState.nowPlaying = track
    }

    private func updateDashboard() {
        dashboardState = Self.makeDashboardState(
            workout: workout,
            profile: profile,
            zoneProfile: zoneProfile,
            manager: workoutManager,
            nowPlaying: dashboardState.nowPlaying
        )
    }

    private static func makeDashboardState(
        workout: PersonalizedWorkoutKind,
        profile: UserProfile,
        zoneProfile: PulsarHeartRateZoneProfile,
        manager: PersonalizedWorkoutHealthKitManager,
        nowPlaying: PulsarNowPlayingTrack
    ) -> PulsarLiveWorkoutDashboardState {
        let metrics = manager.metrics
        let tint = workout.accent.color
        let zone = zoneProfile.zone(for: metrics.currentHeartRate)
        let distanceValue = metrics.distanceMeters.map(PulsarRunFormatters.distance) ?? "--"
        let intensityTitle = manager.phase == .paused ? "Paused" : zone?.title ?? "Moderate"
        let intensitySubtitle = manager.phase == .paused ? "Workout paused" : zone?.detail ?? "Great pace. Keep it up."

        var banners: [PulsarLiveWorkoutBanner] = []
        if let healthAccessMessage = manager.healthAccessMessage {
            banners.append(
                PulsarLiveWorkoutBanner(
                    id: "health-access",
                    title: manager.statusMessage,
                    message: healthAccessMessage,
                    symbolName: "heart.text.square.fill",
                    tint: .red
                )
            )
        } else if manager.phase == .preparing {
            banners.append(
                PulsarLiveWorkoutBanner(
                    id: "health-loading",
                    title: "Waiting for Apple Health",
                    message: "Live metrics appear as HealthKit receives sensor data.",
                    symbolName: "waveform.path.ecg",
                    tint: tint
                )
            )
        }

        if let watchConnectionMessage = manager.watchConnectionMessage {
            banners.append(
                PulsarLiveWorkoutBanner(
                    id: "watch-disconnected",
                    title: watchConnectionMessage,
                    message: "Metrics will continue from HealthKit when new samples are available.",
                    symbolName: "applewatch.slash",
                    tint: .orange
                )
            )
        }

        return PulsarLiveWorkoutDashboardState(
            title: workout.title,
            subtitle: workout.liveSubtitle,
            symbolName: workout.symbolName,
            tint: tint,
            glowColor: workout.liveGlowColor,
            phase: manager.phase,
            statusText: manager.phase.statusText,
            recorderStatusText: manager.statusMessage,
            recorderStatusSymbolName: manager.isHealthKitEnabled ? "heart.text.square.fill" : "exclamationmark.triangle.fill",
            primaryMetricTitle: "DISTANCE",
            primaryMetricValue: distanceValue,
            primaryMetricSubtitle: metrics.distanceMeters == nil ? "HealthKit distance" : "walking/running",
            elapsedTime: metrics.elapsedTime,
            currentHeartRate: metrics.currentHeartRate,
            heartRateZone: zone,
            zoneProfile: zoneProfile,
            insightTitle: workout.liveInsightTitle,
            intensityTitle: intensityTitle,
            intensitySubtitle: intensitySubtitle,
            nowPlaying: nowPlaying,
            metrics: Self.dashboardMetrics(workout: workout, metrics: metrics, zone: zone, tint: tint),
            banners: banners,
            controlsDisabled: manager.phase == .preparing || manager.phase == .finishing || manager.phase == .finished || manager.healthAccessMessage != nil,
            musicControlsDisabled: !nowPlaying.isAvailable,
            presentationStyle: workout.usesPremiumNonGPSDashboard ? .premiumNonGPS : .classic
        )
    }

    private static func dashboardMetrics(
        workout: PersonalizedWorkoutKind,
        metrics: PersonalizedWorkoutLiveMetrics,
        zone: PulsarHeartRateZone?,
        tint: Color
    ) -> [PulsarLiveWorkoutMetric] {
        let caloriesValue = metrics.activeEnergyKilocalories.map(PulsarRunFormatters.calories) ?? "--"
        let distanceValue = metrics.distanceMeters.map(PulsarRunFormatters.distance) ?? "--"
        let paceValue = metrics.paceSecondsPerKilometer.map(PulsarRunFormatters.pace) ?? "--"
        let speedValue = metrics.speedMetersPerSecond.map(PulsarRunFormatters.speed) ?? "--"
        let stepsValue = metrics.stepCount.map { "\(Int($0.rounded()))" } ?? "--"
        let heartRateValue = metrics.currentHeartRate.map { "\(Int($0.rounded()))" } ?? "--"
        let averageHeartRateValue = metrics.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "--"

        var dashboardMetrics: [PulsarLiveWorkoutMetric] = [
            PulsarLiveWorkoutMetric(
                title: "Elapsed",
                value: PulsarRunFormatters.duration(metrics.elapsedTime),
                symbolName: "timer",
                tint: tint
            ),
            PulsarLiveWorkoutMetric(
                title: "Calories",
                value: caloriesValue,
                unit: metrics.activeEnergyKilocalories == nil ? nil : "cal",
                symbolName: "flame.fill",
                tint: .orange
            ),
            PulsarLiveWorkoutMetric(
                title: "Heart",
                value: heartRateValue,
                unit: metrics.currentHeartRate == nil ? nil : "bpm",
                symbolName: "heart.fill",
                tint: zone?.color ?? .gray
            ),
            PulsarLiveWorkoutMetric(
                title: "Average HR",
                value: averageHeartRateValue,
                unit: metrics.averageHeartRate == nil ? nil : "bpm",
                symbolName: "heart.text.square.fill",
                tint: metrics.averageHeartRate == nil ? .gray : .pink
            )
        ]

        if workout == .indoorRunning {
            dashboardMetrics.insert(
                PulsarLiveWorkoutMetric(
                    title: "Distance",
                    value: distanceValue,
                    symbolName: "point.topleft.down.curvedto.point.bottomright.up",
                    tint: tint
                ),
                at: 2
            )
            dashboardMetrics.insert(
                PulsarLiveWorkoutMetric(
                    title: "Pace",
                    value: paceValue,
                    symbolName: "speedometer",
                    tint: .cyan
                ),
                at: 3
            )
            dashboardMetrics.insert(
                PulsarLiveWorkoutMetric(
                    title: "Speed",
                    value: speedValue,
                    symbolName: "gauge.with.dots.needle.bottom.50percent",
                    tint: .mint
                ),
                at: 4
            )
            dashboardMetrics.insert(
                PulsarLiveWorkoutMetric(
                    title: "Steps",
                    value: stepsValue,
                    symbolName: "shoeprints.fill",
                    tint: .green
                ),
                at: 5
            )
        } else {
            dashboardMetrics.append(
                PulsarLiveWorkoutMetric(
                    title: "Zone",
                    value: zone.map { "Z\($0.number)" } ?? "--",
                    unit: zone?.title,
                    symbolName: "gauge.with.dots.needle.67percent",
                    tint: zone?.color ?? .gray
                )
            )
        }

        return dashboardMetrics
    }
}

private extension PersonalizedWorkoutKind {
    var usesPremiumNonGPSDashboard: Bool {
        switch self {
        case .indoorRunning, .gym:
            true
        case .running, .walking, .hiking:
            false
        }
    }

    var liveSubtitle: String {
        switch self {
        case .indoorRunning:
            "Treadmill"
        case .gym:
            "Strength Training"
        case .running, .walking, .hiking:
            "Personalized Training"
        }
    }

    var liveInsightTitle: String {
        switch self {
        case .gym:
            "Workout Load"
        case .indoorRunning, .running, .walking, .hiking:
            "Workout Intensity"
        }
    }

    var liveGlowColor: Color {
        switch self {
        case .indoorRunning, .running:
            Color(red: 1.00, green: 0.72, blue: 0.42)
        case .walking:
            Color(red: 0.78, green: 0.92, blue: 1.00)
        case .hiking:
            Color(red: 0.80, green: 1.00, blue: 0.70)
        case .gym:
            Color(red: 0.86, green: 0.82, blue: 1.00)
        }
    }
}
