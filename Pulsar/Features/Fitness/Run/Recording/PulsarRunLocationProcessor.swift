//
//  PulsarRunLocationProcessor.swift
//  Pulsar
//

import CoreLocation
import Foundation

nonisolated struct PulsarRunLocationSample: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var horizontalAccuracy: Double
    var verticalAccuracy: Double
    var course: Double
    var speed: Double
    var timestamp: Date

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude = location.altitude
        horizontalAccuracy = location.horizontalAccuracy
        verticalAccuracy = location.verticalAccuracy
        course = location.course
        speed = location.speed
        timestamp = location.timestamp
    }

    var location: CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy,
            course: course,
            speed: speed,
            timestamp: timestamp
        )
    }

    var runCoordinate: PulsarRunCoordinate {
        PulsarRunCoordinate(
            latitude: latitude,
            longitude: longitude,
            altitude: verticalAccuracy >= 0 ? altitude : nil,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: verticalAccuracy >= 0 ? verticalAccuracy : nil,
            timestamp: timestamp
        )
    }
}

nonisolated struct PulsarRunLocationBatch: Sendable {
    var sessionID: UUID
    var startDate: Date
    var receivedAt: Date
    var workoutKind: PulsarOutdoorWorkoutKind
    var phase: PulsarRunPhase
    var phaseRevision: Int = 0
    var autoPauseEnabled: Bool
    var initialElevationGainMeters: Double
    var initialElevationLossMeters: Double
    var samples: [PulsarRunLocationSample]
}

nonisolated enum PulsarRunLocationPhaseAction: Equatable, Sendable {
    case pause(Date)
    case resume(Date)
}

nonisolated struct PulsarRunLocationDecisionLog: Sendable {
    var timestamp: Date
    var horizontalAccuracy: Double?
    var rawDistanceDelta: Double
    var acceptedDistanceDelta: Double
    var totalAcceptedDistance: Double
    var speedMetersPerSecond: Double?
    var stationaryLock: Bool
    var movementConfidence: Int
    var rejectedReason: String?
}

nonisolated struct PulsarRunLocationUpdate: Sendable {
    var distanceMeters: Double
    var movingTime: TimeInterval
    var elevationGainMeters: Double
    var elevationLossMeters: Double
    var elevationGainDelta: Double
    var elevationLossDelta: Double
    var currentElevationMeters: Double?
    var currentPaceSecondsPerKilometer: Double?
    var acceptedRouteSamples: [PulsarRunLocationSample]
    var phaseActions: [PulsarRunLocationPhaseAction]
    var decisionLogs: [PulsarRunLocationDecisionLog]
}

/// Serializes GPS filtering and derived metric work away from `MainActor`.
/// The actor deliberately reuses Pulsar's existing distance filter so moving
/// distance and route acceptance remain identical to the pre-actor path.
actor PulsarRunLocationProcessor {
    private var sessionID: UUID?
    private var phase: PulsarRunPhase = .idle
    private var phaseRevision = 0
    private var distanceFilter = PulsarRunGPSDistanceFilter()
    private var lastAcceptedAltitude: Double?
    private var recentMovingSamples: [(date: Date, distanceMeters: Double)] = []
    private var autoPauseCandidateSince: Date?
    private var elevationGainMeters: Double = 0
    private var elevationLossMeters: Double = 0

    func process(_ batch: PulsarRunLocationBatch) -> PulsarRunLocationUpdate {
        guard prepareForBatch(batch) else {
            return PulsarRunLocationUpdate(
                distanceMeters: distanceFilter.totalAcceptedDistanceMeters,
                movingTime: distanceFilter.totalMovingTime,
                elevationGainMeters: elevationGainMeters,
                elevationLossMeters: elevationLossMeters,
                elevationGainDelta: 0,
                elevationLossDelta: 0,
                currentElevationMeters: lastAcceptedAltitude,
                currentPaceSecondsPerKilometer: currentPace,
                acceptedRouteSamples: [],
                phaseActions: [],
                decisionLogs: []
            )
        }

        var acceptedRouteSamples: [PulsarRunLocationSample] = []
        var phaseActions: [PulsarRunLocationPhaseAction] = []
        var decisionLogs: [PulsarRunLocationDecisionLog] = []
        var elevationGainDelta: Double = 0
        var elevationLossDelta: Double = 0
        var currentElevationMeters: Double?

        for sample in batch.samples.sorted(by: { $0.timestamp < $1.timestamp }) {
            let location = sample.location
            let decision = distanceFilter.process(
                location: location,
                startDate: batch.startDate,
                receivedAt: batch.receivedAt,
                workoutKind: batch.workoutKind,
                isRunning: phase == .running
            )

            if decision.acceptedDistanceDelta > 0 {
                recentMovingSamples.append((location.timestamp, decision.totalAcceptedDistance))
                recentMovingSamples.removeAll { location.timestamp.timeIntervalSince($0.date) > 24 }

                let elevationChange = PulsarRunDerivedMetrics.elevationChange(
                    previousAltitude: lastAcceptedAltitude,
                    nextAltitude: location.altitude,
                    verticalAccuracy: location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil
                )
                if phase == .running {
                    elevationGainMeters += elevationChange.gain
                    elevationLossMeters += elevationChange.loss
                    elevationGainDelta += elevationChange.gain
                    elevationLossDelta += elevationChange.loss
                }
            }

            currentElevationMeters = location.verticalAccuracy >= 0 ? location.altitude : nil
            if location.verticalAccuracy >= 0 && location.verticalAccuracy <= 18 {
                lastAcceptedAltitude = location.altitude
            }

            acceptedRouteSamples.append(contentsOf: decision.routeLocationsToAppend.map(PulsarRunLocationSample.init))
            updateAutoPause(
                with: location,
                enabled: batch.autoPauseEnabled,
                workoutKind: batch.workoutKind,
                actions: &phaseActions
            )
            decisionLogs.append(
                PulsarRunLocationDecisionLog(
                    timestamp: decision.timestamp,
                    horizontalAccuracy: decision.horizontalAccuracy,
                    rawDistanceDelta: decision.rawDistanceDelta,
                    acceptedDistanceDelta: decision.acceptedDistanceDelta,
                    totalAcceptedDistance: decision.totalAcceptedDistance,
                    speedMetersPerSecond: decision.speedMetersPerSecond,
                    stationaryLock: decision.stationaryLock,
                    movementConfidence: decision.movementConfidence,
                    rejectedReason: decision.rejectedReason
                )
            )
        }

        return PulsarRunLocationUpdate(
            distanceMeters: distanceFilter.totalAcceptedDistanceMeters,
            movingTime: distanceFilter.totalMovingTime,
            elevationGainMeters: elevationGainMeters,
            elevationLossMeters: elevationLossMeters,
            elevationGainDelta: elevationGainDelta,
            elevationLossDelta: elevationLossDelta,
            currentElevationMeters: currentElevationMeters,
            currentPaceSecondsPerKilometer: currentPace,
            acceptedRouteSamples: acceptedRouteSamples,
            phaseActions: phaseActions,
            decisionLogs: decisionLogs
        )
    }

    func transitionPhase(
        sessionID: UUID,
        phase: PulsarRunPhase,
        revision: Int
    ) {
        guard self.sessionID == sessionID, revision >= phaseRevision else { return }
        phaseRevision = revision
        self.phase = phase
        resetMovementBaseline()
    }

    private func prepareForBatch(_ batch: PulsarRunLocationBatch) -> Bool {
        if sessionID != batch.sessionID {
            sessionID = batch.sessionID
            phaseRevision = batch.phaseRevision
            distanceFilter.reset()
            lastAcceptedAltitude = nil
            recentMovingSamples = []
            autoPauseCandidateSince = nil
            elevationGainMeters = batch.initialElevationGainMeters
            elevationLossMeters = batch.initialElevationLossMeters
            phase = batch.phase
            return true
        }

        guard batch.phaseRevision >= phaseRevision else { return false }
        phaseRevision = batch.phaseRevision
        if phase != batch.phase {
            phase = batch.phase
            resetMovementBaseline()
        }
        return true
    }

    private func updateAutoPause(
        with location: CLLocation,
        enabled: Bool,
        workoutKind: PulsarOutdoorWorkoutKind,
        actions: inout [PulsarRunLocationPhaseAction]
    ) {
        guard enabled else { return }
        let shouldPause = PulsarRunDerivedMetrics.shouldAutoPause(
            speedMetersPerSecond: location.speed >= 0 ? location.speed : nil,
            horizontalAccuracy: location.horizontalAccuracy,
            workoutKind: workoutKind
        )

        if shouldPause {
            if autoPauseCandidateSince == nil {
                autoPauseCandidateSince = location.timestamp
            }
            if let candidate = autoPauseCandidateSince,
               location.timestamp.timeIntervalSince(candidate) >= 8,
               phase == .running {
                actions.append(.pause(location.timestamp))
                phase = .paused
                resetMovementBaseline()
            }
        } else {
            autoPauseCandidateSince = nil
            if phase == .paused {
                actions.append(.resume(location.timestamp))
                phase = .running
                resetMovementBaseline()
            }
        }
    }

    private func resetMovementBaseline() {
        distanceFilter.resetBaselineKeepingTotals()
        recentMovingSamples = []
        autoPauseCandidateSince = nil
    }

    private var currentPace: Double? {
        guard let first = recentMovingSamples.first,
              let last = recentMovingSamples.last,
              last.distanceMeters > first.distanceMeters,
              last.date > first.date else { return nil }
        return last.date.timeIntervalSince(first.date) / ((last.distanceMeters - first.distanceMeters) / 1_000)
    }
}
