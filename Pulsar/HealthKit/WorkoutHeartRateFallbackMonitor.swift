//
//  WorkoutHeartRateFallbackMonitor.swift
//  Pulsar
//

import Foundation
import HealthKit

@MainActor
final class WorkoutHeartRateFallbackMonitor {
    var onStateChanged: ((WorkoutHeartRateFallbackState) -> Void)?
    var onFallbackHeartRateSample: ((WorkoutHeartRateFallbackSample) -> Void)?
    var onStatusBanner: ((String) -> Void)?

    private let healthStore: HKHealthStore
    private let policy: WorkoutHeartRateFallbackPolicy

    private var query: HKAnchoredObjectQuery?
    private var queryAnchor: HKQueryAnchor?
    private var statusTimerTask: Task<Void, Never>?
    private var isWorkoutActive: (() -> Bool)?

    private var workoutStartedAt: Date?
    private var configuredPrimarySource: WorkoutHeartRateSourceKind = .unknown
    private var primarySource: WorkoutHeartRateSourceKind = .unknown
    private var primaryLastSeenAt: Date?
    private var airPodsLastSeenAt: Date?
    private var primaryMarkedUnavailable = false
    private var latestMetadata: WorkoutHeartRateSourceMetadata?
    private var latestAirPodsSample: WorkoutHeartRateFallbackSample?
    private var deliveredAirPodsSampleAt: Date?
    private var lastStatus: WorkoutHeartRateFallbackStatus?
    private var sourceHistory: [WorkoutHeartRateSourceSegment] = []

    init(
        healthStore: HKHealthStore,
        policy: WorkoutHeartRateFallbackPolicy = WorkoutHeartRateFallbackPolicy()
    ) {
        self.healthStore = healthStore
        self.policy = policy
    }

    func start(
        primarySource: WorkoutHeartRateSourceKind,
        workoutStartedAt: Date,
        isWorkoutActive: @escaping () -> Bool
    ) {
        stop()
        resetState()
        self.workoutStartedAt = workoutStartedAt
        configuredPrimarySource = primarySource
        self.primarySource = primarySource
        self.isWorkoutActive = isWorkoutActive

        guard HKHealthStore.isHealthDataAvailable(),
              let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            emitState()
            return
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: workoutStartedAt.addingTimeInterval(-5),
            end: nil,
            options: [.strictStartDate]
        )

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: queryAnchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            Task { @MainActor in
                self?.handleAddedSamples(samples, newAnchor: newAnchor)
            }
        }

        query.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
            Task { @MainActor in
                self?.handleAddedSamples(samples, newAnchor: newAnchor)
            }
        }

        self.query = query
        healthStore.execute(query)
        startStatusTimer()
        evaluateStatus(now: workoutStartedAt)
    }

    func stop() {
        if let query {
            healthStore.stop(query)
        }
        query = nil
        statusTimerTask?.cancel()
        statusTimerTask = nil
        isWorkoutActive = nil
    }

    func markPrimaryUnavailable(at date: Date = Date()) {
        guard isWorkoutActive?() == true else { return }
        primaryMarkedUnavailable = true
        evaluateStatus(now: date)
    }

    func recordExternalPrimaryHeartRate(
        sourceKind: WorkoutHeartRateSourceKind,
        sampledAt: Date = Date()
    ) {
        guard sourceKind.canBePrimaryWorkoutSource,
              isWorkoutActive?() == true else { return }
        if primarySource == .unknown || primarySource == sourceKind {
            primarySource = sourceKind
            primaryLastSeenAt = sampledAt
            primaryMarkedUnavailable = false
            let metadata = WorkoutHeartRateSourceMetadata(sourceKind: sourceKind)
            latestMetadata = metadata
            recordSource(metadata, at: sampledAt, isFallback: false)
            evaluateStatus(now: sampledAt)
        }
    }

    private func resetState() {
        queryAnchor = nil
        workoutStartedAt = nil
        configuredPrimarySource = .unknown
        primarySource = .unknown
        primaryLastSeenAt = nil
        airPodsLastSeenAt = nil
        primaryMarkedUnavailable = false
        latestMetadata = nil
        latestAirPodsSample = nil
        deliveredAirPodsSampleAt = nil
        lastStatus = nil
        sourceHistory = []
    }

    private func startStatusTimer() {
        statusTimerTask?.cancel()
        statusTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self?.evaluateStatus(now: Date())
            }
        }
    }

    private func handleAddedSamples(_ samples: [HKSample]?, newAnchor: HKQueryAnchor?) {
        queryAnchor = newAnchor
        guard isWorkoutActive?() == true else {
            evaluateStatus(now: Date())
            return
        }

        let heartRateSamples = (samples as? [HKQuantitySample] ?? [])
            .sorted { $0.startDate < $1.startDate }
        guard !heartRateSamples.isEmpty else {
            evaluateStatus(now: Date())
            return
        }

        for sample in heartRateSamples {
            handleHeartRateSample(sample)
        }

        evaluateStatus(now: heartRateSamples.last?.startDate ?? Date())
    }

    private func handleHeartRateSample(_ sample: HKQuantitySample) {
        let metadata = Self.metadata(from: sample)
        latestMetadata = metadata

        switch metadata.sourceKind {
        case .airPodsPro3:
            airPodsLastSeenAt = sample.startDate
            latestAirPodsSample = WorkoutHeartRateFallbackSample(
                beatsPerMinute: sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
                sampledAt: sample.startDate,
                metadata: metadata
            )
        case .appleWatch, .garmin:
            if primarySource == .unknown || primarySource == metadata.sourceKind {
                primarySource = metadata.sourceKind
                primaryLastSeenAt = sample.startDate
                primaryMarkedUnavailable = false
                recordSource(metadata, at: sample.startDate, isFallback: false)
            }
        case .healthKit, .unknown:
            if configuredPrimarySource == .unknown,
               primarySource == .unknown {
                recordSource(metadata, at: sample.startDate, isFallback: false)
            }
        }
    }

    private func evaluateStatus(now: Date) {
        let active = isWorkoutActive?() ?? false
        let nextStatus = policy.status(
            primarySource: primarySource,
            primaryLastSeenAt: primaryLastSeenAt,
            airPodsLastSeenAt: airPodsLastSeenAt,
            workoutStartedAt: workoutStartedAt ?? now,
            now: now,
            isWorkoutActive: active,
            primaryMarkedUnavailable: primaryMarkedUnavailable
        )

        let previousStatus = lastStatus
        lastStatus = nextStatus
        emitState()

        if let nextStatus,
           previousStatus != nil,
           previousStatus != nextStatus {
            onStatusBanner?(nextStatus.message)
        }

        if nextStatus?.usesAirPodsFallback == true {
            deliverLatestAirPodsFallbackIfNeeded()
        }
    }

    private func deliverLatestAirPodsFallbackIfNeeded() {
        guard let latestAirPodsSample else { return }
        guard deliveredAirPodsSampleAt != latestAirPodsSample.sampledAt else { return }
        deliveredAirPodsSampleAt = latestAirPodsSample.sampledAt
        recordSource(
            latestAirPodsSample.metadata,
            at: latestAirPodsSample.sampledAt,
            isFallback: true
        )
        onFallbackHeartRateSample?(latestAirPodsSample)
        emitState()
    }

    private func recordSource(
        _ metadata: WorkoutHeartRateSourceMetadata,
        at date: Date,
        isFallback: Bool
    ) {
        guard metadata.sourceKind != .airPodsPro3 || isFallback else { return }

        if let lastIndex = sourceHistory.indices.last,
           sourceHistory[lastIndex].sourceKind == metadata.sourceKind,
           sourceHistory[lastIndex].isFallback == isFallback {
            sourceHistory[lastIndex].endedAt = date
            sourceHistory[lastIndex].metadata = metadata
            return
        }

        if let lastIndex = sourceHistory.indices.last,
           sourceHistory[lastIndex].endedAt == nil {
            sourceHistory[lastIndex].endedAt = date
        }

        sourceHistory.append(
            WorkoutHeartRateSourceSegment(
                sourceKind: metadata.sourceKind == .unknown ? .healthKit : metadata.sourceKind,
                startedAt: date,
                endedAt: nil,
                metadata: metadata,
                isFallback: isFallback
            )
        )
    }

    private func emitState() {
        onStateChanged?(
            WorkoutHeartRateFallbackState(
                status: lastStatus,
                sourceHistory: sourceHistory,
                latestMetadata: latestMetadata
            )
        )
    }

    nonisolated static func metadata(from sample: HKQuantitySample) -> WorkoutHeartRateSourceMetadata {
        let revision = sample.sourceRevision
        let device = sample.device
        let sourceKind = WorkoutHeartRateSourceClassifier.classify(
            sourceName: revision.source.name,
            sourceBundleIdentifier: revision.source.bundleIdentifier,
            productType: revision.productType,
            deviceName: device?.name,
            deviceManufacturer: device?.manufacturer,
            deviceModel: device?.model
        )

        return WorkoutHeartRateSourceMetadata(
            sourceName: revision.source.name,
            sourceBundleIdentifier: revision.source.bundleIdentifier,
            sourceVersion: revision.version,
            operatingSystemVersion: osVersionString(revision.operatingSystemVersion),
            productType: revision.productType,
            deviceName: device?.name,
            deviceManufacturer: device?.manufacturer,
            deviceModel: device?.model,
            sourceKind: sourceKind
        )
    }

    private nonisolated static func osVersionString(_ version: OperatingSystemVersion) -> String {
        "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
