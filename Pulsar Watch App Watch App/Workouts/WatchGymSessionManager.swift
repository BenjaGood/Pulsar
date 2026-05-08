//
//  WatchGymSessionManager.swift
//  Pulsar Watch App Watch App
//

import Combine
import Foundation
import HealthKit
import WatchKit

@MainActor
final class WatchGymSessionManager: NSObject, ObservableObject {
    static let shared = WatchGymSessionManager()

    @Published private(set) var currentHeartRate: Double?
    @Published private(set) var averageHeartRate: Double?
    @Published private(set) var maxHeartRate: Double?
    @Published private(set) var activeEnergyKilocalories: Double?
    @Published private(set) var message: String?

    private let healthStore = HKHealthStore()
    private let syncStore = PulsarWatchConnectivitySyncStore.shared
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var activeSessionId: UUID?
    private var startedAt: Date?
    private var tickTask: Task<Void, Never>?
    private var isFinishing = false
    private var lastMetricsSentAt = Date.distantPast

    private override init() {
        super.init()
        syncStore.registerGymActionHandler { [weak self] action in
            Task { @MainActor in
                await self?.handle(action)
            }
        }
    }

    func startFromCompanion(configuration: HKWorkoutConfiguration) async {
        await startWorkoutIfNeeded(configuration: configuration)
        syncStore.sendGymAction(.requestState())
    }

    func startIfNeeded(for state: ActiveGymWorkoutState) async {
        activeSessionId = state.sessionId
        if state.isFinished {
            await finishCurrentWorkoutIfNeeded()
            return
        }
        await startWorkoutIfNeeded(configuration: Self.strengthConfiguration)
    }

    func finishCurrentWorkoutIfNeeded() async {
        guard workoutSession != nil || workoutBuilder != nil else { return }
        workoutSession?.end()
        await finishWorkout()
    }

    private func startWorkoutIfNeeded(configuration: HKWorkoutConfiguration) async {
        if workoutSession != nil {
            activeSessionId = activeSessionId ?? syncStore.activeGymState?.sessionId
            return
        }

        guard await requestAuthorization() else {
            syncStore.sendGymAction(.requestState())
            return
        }

        do {
            activeSessionId = syncStore.activeGymState?.sessionId ?? activeSessionId
            currentHeartRate = nil
            averageHeartRate = nil
            maxHeartRate = nil
            activeEnergyKilocalories = nil
            message = nil

            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self

            workoutSession = session
            workoutBuilder = builder

            let start = syncStore.activeGymState?.startedAt ?? Date()
            startedAt = start
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            try? await session.startMirroringToCompanionDevice()
            startTicking()
            sendMetricsIfNeeded(force: true)
            WKInterfaceDevice.current().play(.start)
        } catch {
            message = "Apple Watch could not start Health recording for this gym workout."
            PulsarSyncDebugLogger.log("Watch Gym workout start failed: \(error.localizedDescription)")
            cleanup()
        }
    }

    private func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            message = "Health is unavailable on this Apple Watch."
            return false
        }

        do {
            try await healthStore.requestAuthorization(toShare: Self.healthShareTypes, read: Self.healthReadTypes)
            let workoutStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
            guard workoutStatus != .sharingDenied else {
                message = "Allow Health workout access on Apple Watch to read heart rate."
                return false
            }
            message = nil
            return true
        } catch {
            message = "Allow Health access on Apple Watch to read heart rate and calories."
            return false
        }
    }

    private func updateBuilderStatistics(for collectedTypes: Set<HKSampleType>) {
        guard let builder = workoutBuilder else { return }

        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let statistics = builder.statistics(for: quantityType)
            switch quantityType.identifier {
            case HKQuantityTypeIdentifier.heartRate.rawValue:
                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                currentHeartRate = statistics?.mostRecentQuantity()?.doubleValue(for: bpmUnit)
                averageHeartRate = statistics?.averageQuantity()?.doubleValue(for: bpmUnit)
                maxHeartRate = statistics?.maximumQuantity()?.doubleValue(for: bpmUnit)
            case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                activeEnergyKilocalories = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie())
            default:
                break
            }
        }

        sendMetricsIfNeeded()
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run {
                    self?.sendMetricsIfNeeded(force: true)
                }
            }
        }
    }

    private func sendMetricsIfNeeded(force: Bool = false, workoutUUID: UUID? = nil) {
        let now = Date()
        guard force || now.timeIntervalSince(lastMetricsSentAt) >= 1.5 else { return }
        lastMetricsSentAt = now

        let sessionId = activeSessionId ?? syncStore.activeGymState?.sessionId
        guard currentHeartRate != nil ||
            averageHeartRate != nil ||
            maxHeartRate != nil ||
            activeEnergyKilocalories != nil ||
            workoutUUID != nil else { return }

        syncStore.sendGymAction(
            .metricsUpdated(
                sessionId: sessionId,
                currentHeartRate: currentHeartRate,
                averageHeartRate: averageHeartRate,
                maxHeartRate: maxHeartRate,
                activeEnergyKilocalories: activeEnergyKilocalories,
                healthKitWorkoutUUID: workoutUUID
            )
        )
    }

    private func handle(_ action: ActiveGymWorkoutAction) async {
        if let sessionId = action.sessionId {
            activeSessionId = activeSessionId ?? sessionId
        }

        switch action.kind {
        case .finishWorkout:
            await finishCurrentWorkoutIfNeeded()
        case .requestState:
            syncStore.sendGymAction(.requestState(sessionId: activeSessionId))
        default:
            break
        }
    }

    private func finishWorkout() async {
        guard !isFinishing, workoutSession != nil || workoutBuilder != nil else { return }
        isFinishing = true
        tickTask?.cancel()
        tickTask = nil

        let end = Date()
        do {
            try await workoutBuilder?.endCollection(at: end)
            workoutBuilder?.discardWorkout()
            sendMetricsIfNeeded(force: true)
            WKInterfaceDevice.current().play(.success)
        } catch {
            message = "Apple Watch saved the local gym state, but Health finish failed."
            PulsarSyncDebugLogger.log("Watch Gym workout finish failed: \(error.localizedDescription)")
            sendMetricsIfNeeded(force: true)
        }
        cleanup()
    }

    private func cleanup() {
        tickTask?.cancel()
        tickTask = nil
        workoutSession = nil
        workoutBuilder = nil
        startedAt = nil
        isFinishing = false
    }

    private static let strengthConfiguration: HKWorkoutConfiguration = {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        return configuration
    }()

    private static var healthShareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        [
            HKQuantityTypeIdentifier.activeEnergyBurned
        ].compactMap { HKObjectType.quantityType(forIdentifier: $0) }.forEach { types.insert($0) }
        return types
    }

    private static var healthReadTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = healthShareTypes
        [
            HKQuantityTypeIdentifier.heartRate,
            .activeEnergyBurned
        ].compactMap { HKObjectType.quantityType(forIdentifier: $0) }.forEach { types.insert($0) }
        return types
    }
}

extension WatchGymSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            if toState == .ended {
                await self.finishWorkout()
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.message = error.localizedDescription
            PulsarSyncDebugLogger.log("Watch Gym workout session failed: \(error.localizedDescription)")
        }
    }
}

extension WatchGymSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            self.updateBuilderStatistics(for: collectedTypes)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
