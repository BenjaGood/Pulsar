//
//  PulsarRunDerivedMetricsTests.swift
//  PulsarTests
//

import Testing
import CoreLocation
import HealthKit
import WatchConnectivity
@testable import Pulsar

struct PulsarRunDerivedMetricsTests {
    @Test func durationFormatterDistinguishesHours() {
        #expect(PulsarRunFormatters.duration(65) == "01:05")
        #expect(PulsarRunFormatters.duration(3_725) == "1:02:05")
    }

    @Test func paceFormatterUsesKilometerPace() {
        #expect(PulsarRunFormatters.pace(301) == "5:01 /km")
        #expect(PulsarRunFormatters.pace(nil) == "--")
    }

    @Test func cyclingUsesSpeedFormattingInsteadOfPace() {
        #expect(PulsarRunFormatters.paceOrSpeedTitle(for: .cycling) == "Speed")
        #expect(PulsarRunFormatters.paceOrSpeedTitle(for: .cycling, average: true) == "Avg Speed")
        #expect(PulsarRunFormatters.paceOrSpeed(workoutKind: .cycling, paceSecondsPerKilometer: 180, speedMetersPerSecond: nil) == "20.0 km/h")
        #expect(PulsarRunFormatters.paceOrSpeed(workoutKind: .running, paceSecondsPerKilometer: 301, speedMetersPerSecond: 5) == "5:01 /km")
    }

    @Test func shareRouteProjectionKeepsStraightRoutesVisible() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let vertical = GPSWorkoutRoute(points: [
            GPSRoutePoint(latitude: 37.00, longitude: -122.00, timestamp: start),
            GPSRoutePoint(latitude: 37.01, longitude: -122.00, timestamp: start.addingTimeInterval(60))
        ])
        let horizontal = GPSWorkoutRoute(points: [
            GPSRoutePoint(latitude: 37.00, longitude: -122.00, timestamp: start),
            GPSRoutePoint(latitude: 37.00, longitude: -121.99, timestamp: start.addingTimeInterval(60))
        ])

        for route in [vertical, horizontal] {
            let points = PulsarShareRouteProjection.normalizedPoints(from: route, inset: 0.09)
            #expect(points.count == 2)
            #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
            #expect(points.allSatisfy { $0.x >= 0.09 && $0.x <= 0.91 && $0.y >= 0.09 && $0.y <= 0.91 })
        }
    }

    @Test func shareRouteProjectionSortsByTimestampBeforeDrawing() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let route = GPSWorkoutRoute(points: [
            GPSRoutePoint(latitude: 37.01, longitude: -122.00, timestamp: start.addingTimeInterval(60)),
            GPSRoutePoint(latitude: 37.00, longitude: -122.00, timestamp: start)
        ])

        let points = PulsarShareRouteProjection.normalizedPoints(from: route, inset: 0.09)

        #expect(points.count == 2)
        #expect(abs((points.first?.y ?? 0) - 0.91) < 0.001)
    }

    @Test func autoPauseIgnoresPoorAccuracy() {
        #expect(PulsarRunDerivedMetrics.shouldAutoPause(speedMetersPerSecond: 0.2, horizontalAccuracy: 12))
        #expect(!PulsarRunDerivedMetrics.shouldAutoPause(speedMetersPerSecond: 0.2, horizontalAccuracy: 80))
        #expect(!PulsarRunDerivedMetrics.shouldAutoPause(speedMetersPerSecond: 1.4, horizontalAccuracy: 12))
    }

    @Test func elevationGainRequiresMeaningfulPositiveChange() {
        #expect(PulsarRunDerivedMetrics.elevationGain(previousAltitude: 100, nextAltitude: 101.0, verticalAccuracy: 4) == 0)
        #expect(PulsarRunDerivedMetrics.elevationGain(previousAltitude: 100, nextAltitude: 102.1, verticalAccuracy: 4) > 2)
        #expect(PulsarRunDerivedMetrics.elevationGain(previousAltitude: 100, nextAltitude: 105, verticalAccuracy: 40) == 0)
    }

    @Test func elevationChangeTracksGainAndLoss() {
        let uphill = PulsarRunDerivedMetrics.elevationChange(previousAltitude: 100, nextAltitude: 103, verticalAccuracy: 5)
        let downhill = PulsarRunDerivedMetrics.elevationChange(previousAltitude: 103, nextAltitude: 99, verticalAccuracy: 5)
        let noisy = PulsarRunDerivedMetrics.elevationChange(previousAltitude: 100, nextAltitude: 101, verticalAccuracy: 5)

        #expect(uphill.gain == 3)
        #expect(uphill.loss == 0)
        #expect(downhill.gain == 0)
        #expect(downhill.loss == 4)
        #expect(noisy.gain == 0)
        #expect(noisy.loss == 0)
    }

    @Test func outdoorLocationSanityRejectsStaleAndImpossibleSamples() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(
            PulsarRunDerivedMetrics.isUsableLocationSample(
                timestamp: start.addingTimeInterval(5),
                startDate: start,
                receivedAt: start.addingTimeInterval(6),
                horizontalAccuracy: 8
            )
        )
        #expect(
            !PulsarRunDerivedMetrics.isUsableLocationSample(
                timestamp: start.addingTimeInterval(-1),
                startDate: start,
                receivedAt: start.addingTimeInterval(6),
                horizontalAccuracy: 8
            )
        )
        #expect(
            !PulsarRunDerivedMetrics.isUsableLocationSample(
                timestamp: start.addingTimeInterval(5),
                startDate: start,
                receivedAt: start.addingTimeInterval(6),
                horizontalAccuracy: 80
            )
        )
        #expect(PulsarRunDerivedMetrics.isPlausibleLocationDelta(distanceMeters: 120, elapsedSeconds: 30, workoutKind: .running))
        #expect(!PulsarRunDerivedMetrics.isPlausibleLocationDelta(distanceMeters: 10, elapsedSeconds: 0, workoutKind: .running))
        #expect(!PulsarRunDerivedMetrics.isPlausibleLocationDelta(distanceMeters: 260, elapsedSeconds: 30, workoutKind: .walking))
        #expect(!PulsarRunDerivedMetrics.isPlausibleLocationDelta(distanceMeters: 500, elapsedSeconds: 10, workoutKind: .hiking))
    }

    @Test func watchOutdoorLocationFilterUsesStrictFreshnessAndAccuracy() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(
            PulsarRunDerivedMetrics.watchLocationSampleRejectionReason(
                timestamp: start.addingTimeInterval(12),
                startDate: start,
                receivedAt: start.addingTimeInterval(13),
                horizontalAccuracy: 12,
                workoutKind: .running
            ) == nil
        )
        #expect(
            PulsarRunDerivedMetrics.watchLocationSampleRejectionReason(
                timestamp: start.addingTimeInterval(12),
                startDate: start,
                receivedAt: start.addingTimeInterval(16),
                horizontalAccuracy: 12,
                workoutKind: .running
            ) == .cachedSample
        )
        #expect(
            PulsarRunDerivedMetrics.watchLocationSampleRejectionReason(
                timestamp: start.addingTimeInterval(12),
                startDate: start,
                receivedAt: start.addingTimeInterval(13),
                horizontalAccuracy: 24,
                workoutKind: .walking
            ) == .poorHorizontalAccuracy
        )
        #expect(
            PulsarRunDerivedMetrics.watchLocationSampleRejectionReason(
                timestamp: start.addingTimeInterval(12),
                startDate: start,
                receivedAt: start.addingTimeInterval(13),
                horizontalAccuracy: 30,
                workoutKind: .hiking
            ) == nil
        )
        #expect(
            PulsarRunDerivedMetrics.shouldDeferHikingDistanceUntilAccuracyStabilizes(
                horizontalAccuracy: 30,
                workoutKind: .hiking
            )
        )
    }

    @Test func outdoorWorkoutSpeedLimitsMatchWatchDistanceFilter() {
        #expect(PulsarRunDerivedMetrics.maximumPlausibleSpeedMetersPerSecond(for: .running) == 8)
        #expect(PulsarRunDerivedMetrics.maximumPlausibleSpeedMetersPerSecond(for: .walking) == 3)
        #expect(PulsarRunDerivedMetrics.maximumPlausibleSpeedMetersPerSecond(for: .hiking) == 4)
        #expect(PulsarRunDerivedMetrics.minimumMovingSpeedMetersPerSecond(for: .walking) == 0.35)
        #expect(PulsarRunDerivedMetrics.autoPauseSpeedThresholdMetersPerSecond(for: .cycling) == 1.2)
        #expect(!PulsarRunDerivedMetrics.isPlausibleLocationDelta(distanceMeters: 9, elapsedSeconds: 1, workoutKind: .running))
        #expect(!PulsarRunDerivedMetrics.isPlausibleLocationDelta(distanceMeters: 4, elapsedSeconds: 1, workoutKind: .walking))
        #expect(!PulsarRunDerivedMetrics.isPlausibleLocationDelta(distanceMeters: 5, elapsedSeconds: 1, workoutKind: .hiking))
    }

    @Test func gpsJitterFilterKeepsStationaryRunAtZero() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var filter = PulsarRunGPSDistanceFilter()
        let samples = [
            makeLocation(xMeters: 0, yMeters: 0, accuracy: 5, speed: 0, timestamp: start.addingTimeInterval(11)),
            makeLocation(xMeters: 4, yMeters: 1, accuracy: 5, speed: 0.2, timestamp: start.addingTimeInterval(20)),
            makeLocation(xMeters: -3, yMeters: 2, accuracy: 6, speed: 0.1, timestamp: start.addingTimeInterval(35)),
            makeLocation(xMeters: 5, yMeters: -2, accuracy: 5, speed: 0.2, timestamp: start.addingTimeInterval(50)),
            makeLocation(xMeters: -4, yMeters: -1, accuracy: 6, speed: 0.1, timestamp: start.addingTimeInterval(80)),
            makeLocation(xMeters: 3, yMeters: 3, accuracy: 5, speed: 0.2, timestamp: start.addingTimeInterval(100))
        ]

        var appendedRoutePointCount = 0
        var lastDecision: PulsarRunGPSDistanceFilter.Decision?
        for sample in samples {
            let decision = filter.process(
                location: sample,
                startDate: start,
                receivedAt: sample.timestamp.addingTimeInterval(1),
                workoutKind: .running,
                isRunning: true
            )
            appendedRoutePointCount += decision.routeLocationsToAppend.count
            lastDecision = decision
        }

        #expect(filter.totalAcceptedDistanceMeters == 0)
        #expect(filter.totalMovingTime == 0)
        #expect(filter.stationaryLockActive)
        #expect(appendedRoutePointCount == 0)
        #expect(lastDecision?.rejectedReason == "tooSlow" || lastDecision?.rejectedReason == "gpsJitter")
    }

    @Test func gpsJitterFilterRequiresConfirmedMovementBeforeRouteAndDistance() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var filter = PulsarRunGPSDistanceFilter()
        let samples = [
            makeLocation(xMeters: 0, yMeters: 0, accuracy: 5, speed: 0, timestamp: start.addingTimeInterval(11)),
            makeLocation(xMeters: 15, yMeters: 0, accuracy: 5, speed: 1.2, timestamp: start.addingTimeInterval(20)),
            makeLocation(xMeters: 17, yMeters: 0, accuracy: 5, speed: 1.2, timestamp: start.addingTimeInterval(24)),
            makeLocation(xMeters: 19, yMeters: 0, accuracy: 5, speed: 1.2, timestamp: start.addingTimeInterval(28)),
            makeLocation(xMeters: 28, yMeters: 0, accuracy: 5, speed: 1.2, timestamp: start.addingTimeInterval(36))
        ]

        var appendedRoutePointCount = 0
        for sample in samples {
            let decision = filter.process(
                location: sample,
                startDate: start,
                receivedAt: sample.timestamp.addingTimeInterval(1),
                workoutKind: .walking,
                isRunning: true
            )
            appendedRoutePointCount += decision.routeLocationsToAppend.count
        }

        #expect(!filter.stationaryLockActive)
        #expect(filter.totalAcceptedDistanceMeters >= 8)
        #expect(filter.totalMovingTime > 0)
        #expect(appendedRoutePointCount >= 2)
    }

    @Test func gpsJitterFilterDoesNotUnlockOnDirectionReversal() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var filter = PulsarRunGPSDistanceFilter()
        let samples = [
            makeLocation(xMeters: 0, yMeters: 0, accuracy: 5, speed: 0, timestamp: start.addingTimeInterval(11)),
            makeLocation(xMeters: 16, yMeters: 0, accuracy: 5, speed: 1.2, timestamp: start.addingTimeInterval(20)),
            makeLocation(xMeters: -16, yMeters: 0, accuracy: 5, speed: 1.2, timestamp: start.addingTimeInterval(34)),
            makeLocation(xMeters: 16, yMeters: 0, accuracy: 5, speed: 1.2, timestamp: start.addingTimeInterval(48))
        ]

        var appendedRoutePointCount = 0
        var rejectedReasons: [String] = []
        for sample in samples {
            let decision = filter.process(
                location: sample,
                startDate: start,
                receivedAt: sample.timestamp.addingTimeInterval(1),
                workoutKind: .running,
                isRunning: true
            )
            appendedRoutePointCount += decision.routeLocationsToAppend.count
            if let rejectedReason = decision.rejectedReason {
                rejectedReasons.append(rejectedReason)
            }
        }

        #expect(filter.totalAcceptedDistanceMeters == 0)
        #expect(filter.totalMovingTime == 0)
        #expect(filter.stationaryLockActive)
        #expect(appendedRoutePointCount == 0)
        #expect(rejectedReasons.contains("directionReversal"))
    }

    @Test func unknownHealthKitWorkoutTypeDoesNotDefaultToRunning() {
        #expect(PulsarOutdoorWorkoutKind(activityType: .traditionalStrengthTraining) == .strength)
        #expect(PulsarOutdoorWorkoutKind(activityType: .mindAndBody) != .running)
        #expect(PulsarOutdoorWorkoutKind(activityType: .hiking) == .hiking)
        #expect(PulsarOutdoorWorkoutKind(activityType: .cycling) == .cycling)
        #expect(PulsarOutdoorWorkoutKind(activityType: .barre) != .running)
    }

    @Test func outdoorRunWalkAndHikeUseExactHealthKitTypes() {
        #expect(PulsarOutdoorWorkoutKind.running.healthKitActivityType == .running)
        #expect(PulsarOutdoorWorkoutKind.walking.healthKitActivityType == .walking)
        #expect(PulsarOutdoorWorkoutKind.hiking.healthKitActivityType == .hiking)
        #expect(PulsarOutdoorWorkoutKind(activityType: .running) == .running)
        #expect(PulsarOutdoorWorkoutKind(activityType: .walking) == .walking)
        #expect(PulsarOutdoorWorkoutKind(activityType: .hiking) == .hiking)
    }

    @Test func pulsarWorkoutMetadataOverridesFallbackWorkoutType() {
        let metadata: [String: Any] = [
            PulsarWorkoutMetadata.workoutTypeKey: PulsarOutdoorWorkoutKind.cycling.rawValue
        ]

        #expect(PulsarOutdoorWorkoutKind(metadata: metadata, fallbackActivityType: .running) == .cycling)
    }

    @Test func runWorkoutTypeAliasesCanonicalizeToRunning() {
        for alias in ["running", "Running", "Run", "run", "RUN"] {
            #expect(PulsarOutdoorWorkoutKind(workoutTypeRawValue: alias) == .running)
            #expect(PulsarWorkoutMetadata.canonicalWorkoutType(alias) == PulsarOutdoorWorkoutKind.running.rawValue)
        }

        let legacyMetadata: [String: Any] = [
            PulsarWorkoutMetadata.workoutTypeKey: "Run"
        ]
        let writtenMetadata = PulsarWorkoutMetadata.base(
            sessionId: UUID(),
            workoutType: "Running",
            startedFrom: .iPhone
        )

        #expect(PulsarWorkoutMetadata.workoutType(from: legacyMetadata) == PulsarOutdoorWorkoutKind.running.rawValue)
        #expect(PulsarOutdoorWorkoutKind(metadata: legacyMetadata, fallbackActivityType: .cycling) == .running)
        #expect(writtenMetadata[PulsarWorkoutMetadata.workoutTypeKey] as? String == PulsarOutdoorWorkoutKind.running.rawValue)
    }

    @Test func activeWorkoutSyncDecodesLegacyRunTypeAsRunning() throws {
        let state = PulsarActiveWorkoutSyncState(
            sessionId: UUID(),
            kind: .outdoor(.running),
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            startedFrom: .iPhone,
            lastUpdatedFrom: .iPhone,
            phase: .active,
            elapsedSeconds: 42
        )
        let data = try JSONEncoder().encode(state)
        let json = try #require(String(data: data, encoding: .utf8))
            .replacingOccurrences(of: "\"outdoor\":\"running\"", with: "\"outdoor\":\"Run\"")
        let decoded = try JSONDecoder().decode(PulsarActiveWorkoutSyncState.self, from: Data(json.utf8))
        let reencoded = try #require(String(data: JSONEncoder().encode(decoded), encoding: .utf8))

        #expect(decoded.kind == .outdoor(.running))
        #expect(reencoded.contains("\"outdoor\":\"running\""))
        #expect(!reencoded.contains("\"outdoor\":\"Run\""))
    }

    @Test func iPhoneRequestedWatchStartStillUsesAppleWatchRecorder() {
        #expect(PulsarWorkoutStartedFrom.iPhoneRequestedWatchStart.isAppleWatchRecorder)
        #expect(PulsarWorkoutStartedFrom.appleWatch.isAppleWatchRecorder)
        #expect(!PulsarWorkoutStartedFrom.iPhone.isAppleWatchRecorder)
    }

    @Test func activeWorkoutSyncStateCarriesOutdoorRunMetrics() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = PulsarRunMetricSnapshot.empty
        snapshot.pulsarWorkoutSessionId = UUID()
        snapshot.source = .appleWatch
        snapshot.workoutKind = .hiking
        snapshot.phase = .running
        snapshot.startedAt = start
        snapshot.elapsedTime = 92
        snapshot.movingTime = 88
        snapshot.distanceMeters = 183
        snapshot.currentPaceSecondsPerKilometer = 481
        snapshot.averagePaceSecondsPerKilometer = 509
        snapshot.splitPaceSecondsPerKilometer = 509
        snapshot.activeSplitIndex = 1
        snapshot.elevationGainMeters = 7
        snapshot.currentElevationMeters = 1_220
        snapshot.currentHeartRate = 142
        snapshot.averageHeartRate = 136
        snapshot.maxHeartRate = 148
        snapshot.activeEnergyKilocalories = 18
        snapshot.stepCount = 211
        snapshot.cadenceStepsPerMinute = 141
        snapshot.elevationLossMeters = 3
        snapshot.route = [
            PulsarRunCoordinate(latitude: 37.3349, longitude: -122.0090, altitude: 120, horizontalAccuracy: 5, verticalAccuracy: 4, timestamp: start),
            PulsarRunCoordinate(latitude: 37.3352, longitude: -122.0087, altitude: 127, horizontalAccuracy: 5, verticalAccuracy: 4, timestamp: start.addingTimeInterval(30))
        ]

        let state = PulsarActiveWorkoutSyncState(
            runSnapshot: snapshot,
            startedFrom: .iPhoneRequestedWatchStart,
            lastUpdatedFrom: .appleWatch
        )

        #expect(state.sessionId == snapshot.pulsarWorkoutSessionId)
        #expect(state.kind == .outdoor(.hiking))
        #expect(state.distanceMeters == 183)
        #expect(state.movingSeconds == 88)
        #expect(state.currentPaceSecondsPerKilometer == 481)
        #expect(state.activeEnergyKilocalories == 18)
        #expect(state.currentHeartRate == 142)
        #expect(state.cadenceStepsPerMinute == 141)
        #expect(state.runMetricsUpdatedAt != nil)
        #expect(state.elevationLossMeters == 3)
        #expect(state.routePointCount == 2)
        #expect(state.lastLatitude == 37.3352)
        #expect(state.lastLongitude == -122.0087)
        #expect(state.lastLocationUpdatedAt == start.addingTimeInterval(30))
        #expect(state.averageSpeedMetersPerSecond == 183.0 / 88.0)
    }

    @Test func resumedPhaseIsActiveForWorkoutPresentation() {
        #expect(PulsarActiveWorkoutSyncPhase.resumed.isActiveWorkoutPresentationPhase)
    }

    @Test func gpsRouteComputesElevationAndBounds() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let route = GPSWorkoutRoute(points: [
            GPSRoutePoint(latitude: 37.3349, longitude: -122.0090, altitude: 100, horizontalAccuracy: 5, verticalAccuracy: 4, timestamp: start),
            GPSRoutePoint(latitude: 37.3350, longitude: -122.0089, altitude: 103, horizontalAccuracy: 5, verticalAccuracy: 4, timestamp: start.addingTimeInterval(20)),
            GPSRoutePoint(latitude: 37.3351, longitude: -122.0088, altitude: 98, horizontalAccuracy: 5, verticalAccuracy: 4, timestamp: start.addingTimeInterval(40))
        ], source: .pulsarLive, capturedAt: start.addingTimeInterval(40))

        #expect(route.routePointCount == 3)
        #expect(route.bounds?.minimumLatitude == 37.3349)
        #expect(route.bounds?.maximumLongitude == -122.0088)
        #expect(route.elevationMetrics.gainMeters == 3)
        #expect(route.elevationMetrics.lossMeters == 5)
        #expect(route.elevationMetrics.minimumElevationMeters == 98)
        #expect(route.elevationMetrics.maximumElevationMeters == 103)
        #expect(route.elevationSamples.count == 3)
    }

    @Test func recentWatchHeartbeatOverridesRawInstalledFalse() {
        let snapshot = PulsarWatchRecorderAvailabilitySnapshot(
            isSupported: true,
            activationStateRawValue: WCSessionActivationState.activated.rawValue,
            activationStateDescription: "activated",
            activationErrorMessage: nil,
            isPaired: true,
            rawIsWatchAppInstalled: false,
            rawIsReachable: false,
            lastWatchSeenAt: Date(),
            hasEverReceivedWatchPayload: true
        )

        #expect(snapshot.hasRecentWatchHeartbeat)
        #expect(snapshot.isWatchAppInstalled)
        #expect(snapshot.isReachable)
        #expect(snapshot.canStartOnWatch)
        #expect(snapshot.fallbackReason == nil)
        #expect(snapshot.derivedReachabilityDescription == "recentHeartbeat")
    }

    @Test func staleWatchPayloadAvoidsFalseNotInstalledFallback() {
        let snapshot = PulsarWatchRecorderAvailabilitySnapshot(
            isSupported: true,
            activationStateRawValue: WCSessionActivationState.activated.rawValue,
            activationStateDescription: "activated",
            activationErrorMessage: nil,
            isPaired: true,
            rawIsWatchAppInstalled: false,
            rawIsReachable: false,
            lastWatchSeenAt: Date().addingTimeInterval(-3_600),
            hasEverReceivedWatchPayload: true
        )

        #expect(!snapshot.hasRecentWatchHeartbeat)
        #expect(snapshot.isWatchAppInstalled)
        #expect(!snapshot.isReachable)
        #expect(snapshot.fallbackReason == .notReachable)
    }

    @Test func staleActiveWorkoutStateIsNotRoutable() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let staleState = PulsarActiveWorkoutSyncState(
            sessionId: UUID(),
            kind: .outdoor(.walking),
            startedAt: now.addingTimeInterval(-7_200),
            startedFrom: .appleWatch,
            lastUpdatedFrom: .appleWatch,
            phase: .active,
            elapsedSeconds: 7_200,
            updatedAt: now.addingTimeInterval(-3_600)
        )
        let freshState = PulsarActiveWorkoutSyncState(
            sessionId: UUID(),
            kind: .outdoor(.walking),
            startedAt: now.addingTimeInterval(-7_200),
            startedFrom: .appleWatch,
            lastUpdatedFrom: .appleWatch,
            phase: .active,
            elapsedSeconds: 7_200,
            updatedAt: now.addingTimeInterval(-30)
        )

        #expect(!staleState.isValidLiveRouteCandidate(now: now))
        #expect(freshState.isValidLiveRouteCandidate(now: now))
    }

    @Test func activeWorkoutPresentationRequiresActiveOrPausedFreshState() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let activeState = makeActiveWorkoutState(sessionId: UUID(), phase: .active, now: now)
        let pausedState = makeActiveWorkoutState(sessionId: UUID(), phase: .paused, now: now)
        let startingState = makeActiveWorkoutState(sessionId: UUID(), phase: .starting, now: now)
        let staleState = PulsarActiveWorkoutSyncState(
            sessionId: UUID(),
            kind: .outdoor(.walking),
            startedAt: now.addingTimeInterval(-3_600),
            startedFrom: .appleWatch,
            lastUpdatedFrom: .appleWatch,
            phase: .active,
            elapsedSeconds: 3_600,
            updatedAt: now.addingTimeInterval(-1_200)
        )

        #expect(activeState.isValidActiveWorkoutPresentationCandidate(now: now))
        #expect(pausedState.isValidActiveWorkoutPresentationCandidate(now: now))
        #expect(!startingState.isValidActiveWorkoutPresentationCandidate(now: now))
        #expect(staleState.activeWorkoutPresentationRejectionReason(now: now)?.contains("stale updatedAt") == true)
    }

    @Test func activeGymPresentationRejectsFinishedStaleOrUntrustedState() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let freshState = makeActiveGymState(now: now)
        var staleState = freshState
        staleState.startedAt = now.addingTimeInterval(-1_800)
        staleState.updatedAt = now.addingTimeInterval(-1_200)
        var finishedState = freshState
        finishedState.isFinished = true
        var missingSourceState = freshState
        missingSourceState.startedFrom = nil

        #expect(freshState.isValidActiveWorkoutPresentationCandidate(now: now))
        #expect(staleState.activeWorkoutPresentationRejectionReason(now: now)?.contains("stale updatedAt") == true)
        #expect(finishedState.activeWorkoutPresentationRejectionReason(now: now) == "finished")
        #expect(missingSourceState.activeWorkoutPresentationRejectionReason(now: now) == "invalid source")
    }

    @Test func failedActiveWorkoutDecisionRequiresCurrentSessionMatch() {
        let sessionId = UUID()
        let failedState = makeActiveWorkoutState(sessionId: sessionId, phase: .failed)

        #expect(
            ActiveWorkoutUpdateDecision.userInterfaceDecision(
                for: failedState,
                currentSessionID: nil,
                ignoredFailedSessionIDs: []
            ) == .ignoredStaleFailed(sessionId)
        )

        #expect(
            ActiveWorkoutUpdateDecision.userInterfaceDecision(
                for: failedState,
                currentSessionID: UUID(),
                ignoredFailedSessionIDs: []
            ) == .ignoredStaleFailed(sessionId)
        )

        #expect(
            ActiveWorkoutUpdateDecision.userInterfaceDecision(
                for: failedState,
                currentSessionID: sessionId,
                currentSessionCanShowConnectionLostAlert: false,
                ignoredFailedSessionIDs: []
            ) == .ignoredStaleFailed(sessionId)
        )

        #expect(
            ActiveWorkoutUpdateDecision.userInterfaceDecision(
                for: failedState,
                currentSessionID: sessionId,
                ignoredFailedSessionIDs: []
            ) == .failedCurrentAndShouldAlert(sessionId)
        )
    }

    @Test func duplicateStaleFailedDecisionSuppressesAlert() {
        let sessionId = UUID()
        let failedState = makeActiveWorkoutState(sessionId: sessionId, phase: .failed)

        let decision = ActiveWorkoutUpdateDecision.userInterfaceDecision(
            for: failedState,
            currentSessionID: nil,
            ignoredFailedSessionIDs: [sessionId]
        )

        #expect(decision == .ignoredDuplicateStaleFailed(sessionId))
        #expect(decision.isIgnoredFailedUpdate)
        #expect(!decision.didApplySyncState)
    }

    @Test func remoteFailedSyncDecisionUsesPriorCurrentSessionBeforePriorSyncedState() {
        let sessionId = UUID()
        let failedState = makeActiveWorkoutState(sessionId: sessionId, phase: .failed)

        let decision = ActiveWorkoutUpdateDecision.syncStoreFailedDecision(
            for: failedState,
            priorCurrentSessionID: nil,
            priorSyncedSessionID: sessionId,
            ignoredFailedSessionIDs: [],
            isIncomingFromCounterpart: true
        )

        #expect(decision == .ignoredStaleFailed(sessionId))
        #expect(!decision.didApplySyncState)
    }

    @Test func remoteFailedSyncDecisionOnlyAlertsForMatchingPriorCurrentSession() {
        let sessionId = UUID()
        let failedState = makeActiveWorkoutState(sessionId: sessionId, phase: .failed)

        let staleDecision = ActiveWorkoutUpdateDecision.syncStoreFailedDecision(
            for: failedState,
            priorCurrentSessionID: UUID(),
            priorSyncedSessionID: sessionId,
            ignoredFailedSessionIDs: [],
            isIncomingFromCounterpart: true
        )
        let currentDecision = ActiveWorkoutUpdateDecision.syncStoreFailedDecision(
            for: failedState,
            priorCurrentSessionID: sessionId,
            priorSyncedSessionID: nil,
            ignoredFailedSessionIDs: [],
            isIncomingFromCounterpart: true
        )

        #expect(staleDecision == .ignoredStaleFailed(sessionId))
        #expect(currentDecision == .failedCurrentAndShouldAlert(sessionId))
    }

    @Test func failedSyncDecisionRequiresAlertEligiblePriorCurrentSession() {
        let sessionId = UUID()
        let failedState = makeActiveWorkoutState(sessionId: sessionId, phase: .failed)

        let decision = ActiveWorkoutUpdateDecision.syncStoreFailedDecision(
            for: failedState,
            priorCurrentSessionID: sessionId,
            priorCurrentWorkoutCanShowConnectionLostAlert: false,
            priorSyncedSessionID: sessionId,
            ignoredFailedSessionIDs: [],
            isIncomingFromCounterpart: true
        )

        #expect(decision == .ignoredStaleFailed(sessionId))
        #expect(!decision.didApplySyncState)
    }

    @Test func failedSyncDecisionDoesNotAlertFromSyncedStateAlone() {
        let sessionId = UUID()
        let failedState = makeActiveWorkoutState(sessionId: sessionId, phase: .failed)

        let decision = ActiveWorkoutUpdateDecision.syncStoreFailedDecision(
            for: failedState,
            priorCurrentSessionID: nil,
            priorSyncedSessionID: sessionId,
            ignoredFailedSessionIDs: [],
            isIncomingFromCounterpart: false
        )

        #expect(decision == .ignoredStaleFailed(sessionId))
        #expect(!decision.didApplySyncState)
    }

    @Test func endedHistoricalWorkoutDecisionDoesNotAlert() {
        let endedState = makeActiveWorkoutState(sessionId: UUID(), phase: .ended)

        let decision = ActiveWorkoutUpdateDecision.userInterfaceDecision(
            for: endedState,
            currentSessionID: nil,
            ignoredFailedSessionIDs: []
        )

        #expect(decision == .ignoredHistoricalOnly)
        #expect(!decision.isIgnoredFailedUpdate)
        #expect(!decision.didApplySyncState)
    }

    @Test func staleEndedWorkoutDecisionDoesNotClearNewerCurrentSession() {
        let sessionId = UUID()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let staleEndedState = makeActiveWorkoutState(
            sessionId: sessionId,
            phase: .ended,
            now: now.addingTimeInterval(-30)
        )

        let decision = ActiveWorkoutUpdateDecision.userInterfaceDecision(
            for: staleEndedState,
            currentSessionID: sessionId,
            currentSessionUpdatedAt: now,
            ignoredFailedSessionIDs: []
        )

        #expect(decision == .ignoredHistoricalOnly)
        #expect(!decision.didApplySyncState)
    }

    @Test func endingWorkoutWithoutCurrentSessionDoesNotRestoreUI() {
        let sessionId = UUID()
        let endingState = makeActiveWorkoutState(sessionId: sessionId, phase: .ending)

        let decision = ActiveWorkoutUpdateDecision.userInterfaceDecision(
            for: endingState,
            currentSessionID: nil,
            ignoredFailedSessionIDs: []
        )

        #expect(decision == .ignoredHistoricalOnly)
        #expect(!decision.didApplySyncState)
    }

    @Test func endingWorkoutForCurrentSessionCanShowFinishingState() {
        let sessionId = UUID()
        let endingState = makeActiveWorkoutState(sessionId: sessionId, phase: .ending)

        let decision = ActiveWorkoutUpdateDecision.userInterfaceDecision(
            for: endingState,
            currentSessionID: sessionId,
            ignoredFailedSessionIDs: []
        )

        #expect(decision == .appliedActive(sessionId))
    }

    @Test func freshWatchRestoreConfirmationRequiresRecentRestorablePhase() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let activeState = makeActiveWorkoutState(sessionId: UUID(), phase: .active, now: now)
        let staleState = makeActiveWorkoutState(sessionId: UUID(), phase: .active, now: now.addingTimeInterval(-120))
        let endingState = makeActiveWorkoutState(sessionId: UUID(), phase: .ending, now: now)

        #expect(activeState.isFreshRestoreConfirmation(now: now, interval: 90))
        #expect(!staleState.isFreshRestoreConfirmation(now: now, interval: 90))
        #expect(!endingState.isFreshRestoreConfirmation(now: now, interval: 90))
    }

    @Test func cancelledWorkoutDecisionOnlyClearsMatchingCurrentSession() {
        let sessionId = UUID()
        let cancelledState = makeActiveWorkoutState(sessionId: sessionId, phase: .cancelled)

        #expect(
            ActiveWorkoutUpdateDecision.userInterfaceDecision(
                for: cancelledState,
                currentSessionID: nil,
                ignoredFailedSessionIDs: []
            ) == .ignoredHistoricalOnly
        )

        #expect(
            ActiveWorkoutUpdateDecision.userInterfaceDecision(
                for: cancelledState,
                currentSessionID: sessionId,
                ignoredFailedSessionIDs: []
            ) == .endedCurrent(sessionId)
        )
    }

    @Test @MainActor func activeWorkoutManagerBlocksMinimizeWithoutSession() {
        let manager = PulsarActiveWorkoutManager()

        manager.minimizeRunWorkout(.running, sessionID: nil)

        #expect(manager.activeWorkout == nil)
        #expect(manager.presentation == .hidden)
        #expect(manager.presentedWorkout == nil)
    }

    @Test @MainActor func activeWorkoutManagerMinimizesCurrentRunImmediately() {
        let manager = PulsarActiveWorkoutManager()
        let sessionId = UUID()

        manager.reconcileActiveWorkoutPresentation(
            route: .run(.running),
            sessionID: sessionId,
            phase: "active",
            reason: "testStart"
        )
        manager.minimizeRunWorkout(.running, sessionID: sessionId)

        #expect(manager.activeWorkout?.sessionID == sessionId)
        #expect(manager.presentation == .minimized(sessionId))
        #expect(manager.presentedWorkout == nil)
    }

    @Test @MainActor func activeWorkoutManagerIgnoresClearForDifferentSession() {
        let manager = PulsarActiveWorkoutManager()
        let currentSessionId = UUID()

        manager.reconcileActiveWorkoutPresentation(
            route: .run(.running),
            sessionID: currentSessionId,
            phase: "active",
            reason: "testStart"
        )
        manager.minimizeRunWorkout(.running, sessionID: currentSessionId)
        manager.clearRunWorkout(sessionID: UUID())

        #expect(manager.activeWorkout?.sessionID == currentSessionId)
        #expect(manager.presentation == .minimized(currentSessionId))
    }

    @Test @MainActor func activeWorkoutManagerBlocksNonTerminalRunClear() {
        let manager = PulsarActiveWorkoutManager()
        let sessionId = UUID()

        manager.reconcileActiveWorkoutPresentation(
            route: .run(.running),
            sessionID: sessionId,
            phase: "active",
            reason: "testStart"
        )
        manager.minimizeRunWorkout(.running, sessionID: sessionId)
        manager.clearRunWorkout(
            sessionID: sessionId,
            phase: "idle",
            source: "test",
            reason: "transientLocalPhase"
        )

        #expect(manager.activeWorkout?.sessionID == sessionId)
        #expect(manager.presentation == .minimized(sessionId))
        #expect(manager.presentedWorkout == nil)
    }

    @Test @MainActor func activeWorkoutManagerPreservesMinimizedRunAcrossDuplicateSync() {
        let manager = PulsarActiveWorkoutManager()
        let sessionId = UUID()

        let didOpen = manager.reconcileActiveWorkoutPresentation(
            route: .run(.running),
            sessionID: sessionId,
            phase: "active",
            reason: "initialSync"
        )
        manager.minimizeRunWorkout(.running, sessionID: sessionId)
        let didReopen = manager.reconcileActiveWorkoutPresentation(
            route: .run(.running),
            sessionID: sessionId,
            phase: "active",
            reason: "duplicateWatchPayload"
        )

        #expect(didOpen)
        #expect(!didReopen)
        #expect(manager.activeWorkout?.sessionID == sessionId)
        #expect(manager.presentation == .minimized(sessionId))
        #expect(manager.presentedWorkout == nil)
    }

    @Test func runHistoryMergesSavesWithSamePulsarSessionId() async throws {
        let suiteName = "pulsar.run.history.test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PulsarRunHistoryStore(defaults: defaults)
        let sessionId = UUID()
        let workoutUUID = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        await store.save(makeRunSummary(id: UUID(), sessionId: sessionId, workoutUUID: nil, start: start, distance: 0))
        await store.save(makeRunSummary(id: UUID(), sessionId: sessionId, workoutUUID: workoutUUID, start: start, distance: 1_200))

        let cachedRuns = await store.loadCachedRuns()
        #expect(cachedRuns.count == 1)
        #expect(cachedRuns.first?.pulsarWorkoutSessionId == sessionId)
        #expect(cachedRuns.first?.workoutUUID == workoutUUID)
        #expect(cachedRuns.first?.distanceMeters == 1_200)
    }

    @Test func runTransportPreservesSessionScopedCommandsAndAcknowledgements() throws {
        let sessionId = UUID()
        let commandId = UUID()
        let sentAt = Date(timeIntervalSince1970: 1_800_000_100)
        let command = PulsarRunSessionCommand(
            sessionId: sessionId,
            command: .finish,
            commandId: commandId,
            sentAt: sentAt,
            retryAttempt: 1
        )

        let commandData = try #require(PulsarRunTransportCodec.encode(.sessionCommand(command)))
        #expect(PulsarRunTransportCodec.decode(commandData) == .sessionCommand(command))

        let acknowledgement = PulsarRunCommandAcknowledgement(
            commandId: commandId,
            sessionId: sessionId,
            command: .finish,
            accepted: true,
            phase: .finishing,
            message: nil,
            acknowledgedAt: sentAt.addingTimeInterval(0.2)
        )

        let acknowledgementData = try #require(PulsarRunTransportCodec.encode(.commandAcknowledgement(acknowledgement)))
        #expect(PulsarRunTransportCodec.decode(acknowledgementData) == .commandAcknowledgement(acknowledgement))
    }

    private func makeActiveWorkoutState(
        sessionId: UUID,
        phase: PulsarActiveWorkoutSyncPhase,
        now: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> PulsarActiveWorkoutSyncState {
        PulsarActiveWorkoutSyncState(
            sessionId: sessionId,
            kind: .outdoor(.walking),
            startedAt: now.addingTimeInterval(-600),
            endedAt: phase.isLive ? nil : now,
            startedFrom: .appleWatch,
            lastUpdatedFrom: .appleWatch,
            phase: phase,
            elapsedSeconds: 600,
            updatedAt: now
        )
    }

    private func makeActiveGymState(now: Date) -> ActiveGymWorkoutState {
        ActiveGymWorkoutState(
            sessionId: UUID(),
            routineId: UUID(),
            routineName: "Upper Pair",
            routineEmoji: nil,
            workoutKind: .routine,
            startedFrom: .appleWatch,
            startedAt: now.addingTimeInterval(-600),
            elapsedSeconds: 600,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: 1,
            totalSets: 3,
            completedSets: 1,
            currentHeartRate: 92,
            averageHeartRate: 88,
            maxHeartRate: 104,
            activeEnergyKilocalories: 72,
            healthKitWorkoutUUID: nil,
            restRemainingSeconds: nil,
            restTotalSeconds: nil,
            isHealthKitEnabled: true,
            healthKitStatusMessage: nil,
            isFinished: false,
            updatedAt: now,
            exercises: []
        )
    }

    private func makeLocation(
        xMeters: Double,
        yMeters: Double,
        accuracy: Double,
        speed: Double,
        timestamp: Date
    ) -> CLLocation {
        let originLatitude = 37.3349
        let originLongitude = -122.0090
        let latitude = originLatitude + yMeters / 111_111
        let longitude = originLongitude + xMeters / (111_111 * cos(originLatitude * .pi / 180))
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 12,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 5,
            course: -1,
            speed: speed,
            timestamp: timestamp
        )
    }

    private func makeRunSummary(
        id: UUID,
        sessionId: UUID,
        workoutUUID: UUID?,
        start: Date,
        distance: Double
    ) -> PulsarRunSummary {
        PulsarRunSummary(
            id: id,
            pulsarWorkoutSessionId: sessionId,
            workoutUUID: workoutUUID,
            workoutKind: .walking,
            startedAt: start,
            endedAt: start.addingTimeInterval(1_800),
            source: .iPhone,
            distanceMeters: distance,
            elapsedTime: 1_800,
            movingTime: 1_700,
            activeEnergyKilocalories: nil,
            elevationGainMeters: 0,
            averageHeartRate: nil,
            maxHeartRate: nil,
            steps: nil,
            averageCadenceStepsPerMinute: nil,
            route: [],
            splits: []
        )
    }
}
