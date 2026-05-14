//
//  GymHealthKitWorkoutManager.swift
//  Pulsar
//

import Combine
import Foundation
import HealthKit

struct GymHealthKitWorkoutMetrics: Equatable {
    var currentHeartRate: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var activeEnergyKilocalories: Double?
}

struct GymHealthKitWorkoutResult: Equatable {
    var workoutUUID: UUID?
    var activeEnergyKilocalories: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var statusMessage: String?

    static func localOnly(_ message: String?) -> GymHealthKitWorkoutResult {
        GymHealthKitWorkoutResult(
            workoutUUID: nil,
            activeEnergyKilocalories: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            statusMessage: message
        )
    }
}

@MainActor
final class GymHealthKitWorkoutManager: NSObject, ObservableObject {
    @Published private(set) var metrics = GymHealthKitWorkoutMetrics()
    @Published private(set) var statusMessage: String?
    @Published private(set) var isHealthKitEnabled = false

    var onMetricsUpdated: ((GymHealthKitWorkoutMetrics) -> Void)?

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var workoutStartedAt: Date?
    private var isFinishing = false

    func startWorkout(
        routineName: String,
        workoutKind: PulsarGymWorkoutKind,
        routineId: UUID,
        sessionId: UUID,
        startedAt: Date
    ) async -> Bool {
        statusMessage = nil
        isFinishing = false
        metrics = GymHealthKitWorkoutMetrics()

        guard await requestAuthorization() else {
            return false
        }

        do {
            let configuration = Self.strengthConfiguration
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self

            workoutSession = session
            workoutBuilder = builder
            workoutStartedAt = startedAt

            session.startActivity(with: startedAt)
            try await builder.beginCollection(at: startedAt)
            addMetadata(
                Self.metadata(
                    routineName: routineName,
                    workoutKind: workoutKind,
                    routineId: routineId,
                    sessionId: sessionId,
                    startedFrom: .iPhone
                ),
                to: builder
            )

            isHealthKitEnabled = true
            statusMessage = nil
            PulsarSyncDebugLogger.log("Gym HealthKit start selectedType=\(workoutKind.rawValue) hkType=\(configuration.activityType.rawValue) session=\(sessionId.uuidString) startedFrom=iPhone")
            return true
        } catch {
            isHealthKitEnabled = false
            statusMessage = "Apple Health could not start this strength workout. Pulsar is still tracking it locally."
            return false
        }
    }

    func finishWorkout(endedAt: Date) async -> GymHealthKitWorkoutResult {
        guard !isFinishing else {
            return currentResult(statusMessage: statusMessage)
        }
        isFinishing = true

        guard let builder = workoutBuilder else {
            return GymHealthKitWorkoutResult.localOnly(statusMessage)
        }

        workoutSession?.end()

        do {
            try await addExternalActiveEnergySampleIfNeeded(to: builder, endedAt: endedAt)
            try await builder.endCollection(at: endedAt)
            let workout = try await builder.finishWorkout()
            let result = GymHealthKitWorkoutResult(
                workoutUUID: workout?.uuid,
                activeEnergyKilocalories: metrics.activeEnergyKilocalories,
                averageHeartRate: metrics.averageHeartRate,
                maxHeartRate: metrics.maxHeartRate,
                statusMessage: statusMessage
            )
            cleanup()
            return result
        } catch {
            let message = "Workout saved in Pulsar, but Apple Health sync failed: \(error.localizedDescription)"
            statusMessage = message
            let result = currentResult(statusMessage: message)
            cleanup()
            return result
        }
    }

    func stopWithoutSaving() {
        workoutSession?.end()
        cleanup()
    }

    func mergeExternalMetrics(_ externalMetrics: GymHealthKitWorkoutMetrics) {
        var nextMetrics = metrics
        nextMetrics.currentHeartRate = externalMetrics.currentHeartRate ?? nextMetrics.currentHeartRate
        nextMetrics.averageHeartRate = externalMetrics.averageHeartRate ?? nextMetrics.averageHeartRate
        nextMetrics.maxHeartRate = externalMetrics.maxHeartRate ?? nextMetrics.maxHeartRate
        nextMetrics.activeEnergyKilocalories = externalMetrics.activeEnergyKilocalories ?? nextMetrics.activeEnergyKilocalories
        guard nextMetrics != metrics else { return }
        metrics = nextMetrics
        onMetricsUpdated?(nextMetrics)
    }

    private func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            statusMessage = "Apple Health is not available on this device. Pulsar is tracking locally."
            isHealthKitEnabled = false
            return false
        }

        do {
            try await healthStore.requestAuthorization(toShare: Self.healthShareTypes, read: Self.healthReadTypes)
            let workoutStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
            guard workoutStatus != .sharingDenied else {
                statusMessage = "Apple Health workout access is off. Pulsar is tracking locally."
                isHealthKitEnabled = false
                return false
            }
            isHealthKitEnabled = true
            return true
        } catch {
            statusMessage = "Apple Health permission is needed for heart rate and workout saving. Pulsar is tracking locally."
            isHealthKitEnabled = false
            return false
        }
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
            default:
                break
            }
        }

        guard nextMetrics != metrics else { return }
        metrics = nextMetrics
        onMetricsUpdated?(nextMetrics)
    }

    private func addMetadata(_ metadata: [String: Any], to builder: HKLiveWorkoutBuilder) {
        builder.addMetadata(metadata) { success, error in
            if success {
                PulsarSyncDebugLogger.log("Gym HealthKit metadata added session=\(metadata[PulsarWorkoutMetadata.sessionIdKey] as? String ?? "none") type=\(metadata[PulsarWorkoutMetadata.workoutTypeKey] as? String ?? "unknown") startedFrom=\(metadata[PulsarWorkoutMetadata.startedFromKey] as? String ?? "unknown")")
            } else if let error {
                PulsarSyncDebugLogger.log("Gym HealthKit metadata failed: \(error.localizedDescription)")
            }
        }
    }

    private func addExternalActiveEnergySampleIfNeeded(to builder: HKLiveWorkoutBuilder, endedAt: Date) async throws {
        guard let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
              let activeEnergyKilocalories = metrics.activeEnergyKilocalories,
              activeEnergyKilocalories > 0 else { return }

        let collectedEnergy = builder
            .statistics(for: energyType)?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie()) ?? 0
        guard collectedEnergy <= 0 else { return }

        let start = workoutStartedAt ?? endedAt.addingTimeInterval(-1)
        let sample = HKQuantitySample(
            type: energyType,
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: activeEnergyKilocalories),
            start: min(start, endedAt),
            end: endedAt,
            metadata: [
                "PulsarMetricSource": "Apple Watch live workout builder"
            ]
        )
        try await builder.addSamples([sample])
    }

    private func currentResult(statusMessage: String?) -> GymHealthKitWorkoutResult {
        GymHealthKitWorkoutResult(
            workoutUUID: nil,
            activeEnergyKilocalories: metrics.activeEnergyKilocalories,
            averageHeartRate: metrics.averageHeartRate,
            maxHeartRate: metrics.maxHeartRate,
            statusMessage: statusMessage
        )
    }

    private func cleanup() {
        workoutSession = nil
        workoutBuilder = nil
        workoutStartedAt = nil
        isFinishing = false
    }

    private static let strengthConfiguration: HKWorkoutConfiguration = {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        return configuration
    }()

    static func metadata(
        routineName: String,
        workoutKind: PulsarGymWorkoutKind,
        routineId: UUID,
        sessionId: UUID,
        startedFrom: PulsarWorkoutStartedFrom
    ) -> [String: Any] {
        let displayName = workoutKind == .freeWorkout ? workoutKind.displayName : routineName
        var metadata = PulsarWorkoutMetadata.base(
            sessionId: sessionId,
            workoutType: workoutKind.rawValue,
            startedFrom: startedFrom
        )
        metadata["PulsarWorkoutCategory"] = workoutKind.categoryName
        metadata["PulsarWorkoutKind"] = workoutKind.rawValue
        metadata["PulsarWorkoutDisplayName"] = displayName
        metadata["PulsarRoutineName"] = routineName
        metadata["PulsarRoutineID"] = routineId.uuidString
        metadata[PulsarWorkoutMetadata.legacySessionIdKey] = sessionId.uuidString
        return metadata
    }

    private static var healthShareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        [
            HKQuantityTypeIdentifier.activeEnergyBurned,
            .basalEnergyBurned
        ].compactMap { HKObjectType.quantityType(forIdentifier: $0) }.forEach { types.insert($0) }
        return types
    }

    private static var healthReadTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = healthShareTypes
        [
            HKQuantityTypeIdentifier.heartRate,
            .activeEnergyBurned,
            .basalEnergyBurned
        ].compactMap { HKObjectType.quantityType(forIdentifier: $0) }.forEach { types.insert($0) }
        return types
    }
}

extension GymHealthKitWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.statusMessage = "Apple Health workout session failed: \(error.localizedDescription)"
            self.isHealthKitEnabled = false
        }
    }
}

extension GymHealthKitWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            self.updateBuilderStatistics(for: collectedTypes)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
