//
//  PulsarRunLocationProcessorTests.swift
//  PulsarTests
//

import CoreLocation
import Testing
@testable import Pulsar

struct PulsarRunLocationProcessorTests {
    @Test func actorProcessorPreservesDistanceMovingTimeAndRouteAcceptance() async {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let locations = [
            makeLocation(xMeters: 0, speed: 0, timestamp: start.addingTimeInterval(11)),
            makeLocation(xMeters: 15, speed: 1.2, timestamp: start.addingTimeInterval(20)),
            makeLocation(xMeters: 17, speed: 1.2, timestamp: start.addingTimeInterval(24)),
            makeLocation(xMeters: 19, speed: 1.2, timestamp: start.addingTimeInterval(28)),
            makeLocation(xMeters: 28, speed: 1.2, timestamp: start.addingTimeInterval(36)),
            makeLocation(xMeters: 40, speed: 1.2, timestamp: start.addingTimeInterval(46))
        ]

        var referenceFilter = PulsarRunGPSDistanceFilter()
        var referenceRouteCount = 0
        for location in locations {
            let decision = referenceFilter.process(
                location: location,
                startDate: start,
                receivedAt: start.addingTimeInterval(47),
                workoutKind: .walking,
                isRunning: true
            )
            referenceRouteCount += decision.routeLocationsToAppend.count
        }

        let processor = PulsarRunLocationProcessor()
        let update = await processor.process(
            PulsarRunLocationBatch(
                sessionID: UUID(),
                startDate: start,
                receivedAt: start.addingTimeInterval(47),
                workoutKind: .walking,
                phase: .running,
                autoPauseEnabled: false,
                initialElevationGainMeters: 0,
                initialElevationLossMeters: 0,
                samples: locations.map(PulsarRunLocationSample.init)
            )
        )

        #expect(update.distanceMeters == referenceFilter.totalAcceptedDistanceMeters)
        #expect(update.movingTime == referenceFilter.totalMovingTime)
        #expect(update.acceptedRouteSamples.count == referenceRouteCount)
        #expect(update.decisionLogs.count == locations.count)
    }

    @Test func actorProcessorKeepsAutoPauseAndResumeOrdering() async {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let pauseDate = start.addingTimeInterval(20)
        let resumeDate = start.addingTimeInterval(22)
        let processor = PulsarRunLocationProcessor()
        let update = await processor.process(
            PulsarRunLocationBatch(
                sessionID: UUID(),
                startDate: start,
                receivedAt: resumeDate.addingTimeInterval(1),
                workoutKind: .running,
                phase: .running,
                autoPauseEnabled: true,
                initialElevationGainMeters: 0,
                initialElevationLossMeters: 0,
                samples: [
                    makeLocation(xMeters: 0, speed: 0, timestamp: start.addingTimeInterval(11)),
                    makeLocation(xMeters: 0, speed: 0, timestamp: pauseDate),
                    makeLocation(xMeters: 4, speed: 1.4, timestamp: resumeDate)
                ].map(PulsarRunLocationSample.init)
            )
        )

        #expect(update.phaseActions == [.pause(pauseDate), .resume(resumeDate)])
    }

    @Test func rapidManualPauseResumeRejectsPreTransitionLocationBatch() async {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let sessionID = UUID()
        let processor = PulsarRunLocationProcessor()
        _ = await processor.process(
            PulsarRunLocationBatch(
                sessionID: sessionID,
                startDate: start,
                receivedAt: start.addingTimeInterval(12),
                workoutKind: .running,
                phase: .running,
                phaseRevision: 0,
                autoPauseEnabled: false,
                initialElevationGainMeters: 0,
                initialElevationLossMeters: 0,
                samples: [makeLocation(xMeters: 0, speed: 1.2, timestamp: start.addingTimeInterval(11))]
                    .map(PulsarRunLocationSample.init)
            )
        )

        await processor.transitionPhase(sessionID: sessionID, phase: .paused, revision: 1)
        await processor.transitionPhase(sessionID: sessionID, phase: .running, revision: 2)

        let staleUpdate = await processor.process(
            PulsarRunLocationBatch(
                sessionID: sessionID,
                startDate: start,
                receivedAt: start.addingTimeInterval(22),
                workoutKind: .running,
                phase: .running,
                phaseRevision: 0,
                autoPauseEnabled: false,
                initialElevationGainMeters: 0,
                initialElevationLossMeters: 0,
                samples: [makeLocation(xMeters: 120, speed: 1.2, timestamp: start.addingTimeInterval(21))]
                    .map(PulsarRunLocationSample.init)
            )
        )

        #expect(staleUpdate.decisionLogs.isEmpty)
        #expect(staleUpdate.acceptedRouteSamples.isEmpty)
        #expect(staleUpdate.distanceMeters == 0)
    }

    private func makeLocation(
        xMeters: Double,
        speed: Double,
        timestamp: Date
    ) -> CLLocation {
        let latitude = 37.0
        let longitude = -122.0 + xMeters / (111_320 * cos(latitude * .pi / 180))
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 12,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 90,
            speed: speed,
            timestamp: timestamp
        )
    }
}
