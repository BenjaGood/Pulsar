//
//  PulsarWatchConnectivityTransportPolicyTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct PulsarWatchConnectivityTransportPolicyTests {
    @Test func periodicGymStateDoesNotCreateInteractiveSends() {
        #expect(
            !PulsarWatchConnectivityTransportPolicy.usesInteractiveSend(
                messageType: "activeGymState",
                reason: "watchGymWorkoutTick",
                isReachable: true,
                hasLiveWorkout: true
            )
        )
        #expect(
            PulsarWatchConnectivityTransportPolicy.usesLatestStateOverwrite(
                messageType: "activeGymState",
                reason: "watchGymWorkoutTick"
            )
        )
        #expect(
            !PulsarWatchConnectivityTransportPolicy.allowsRetry(
                messageType: "activeGymState",
                reason: "watchGymWorkoutTick"
            )
        )
        #expect(
            !PulsarWatchConnectivityTransportPolicy.usesDurableTransfer(
                messageType: "activeGymState",
                reason: "watchGymWorkoutTick"
            )
        )
    }

    @Test func heartbeatDoesNotCompeteWithLiveWorkoutControls() {
        #expect(
            !PulsarWatchConnectivityTransportPolicy.usesInteractiveSend(
                messageType: "watchHeartbeat",
                reason: "watchHomeAppeared",
                isReachable: true,
                hasLiveWorkout: true
            )
        )
        #expect(
            PulsarWatchConnectivityTransportPolicy.messageClass(messageType: "watchHeartbeat") == .latestState
        )
        #expect(
            !PulsarWatchConnectivityTransportPolicy.allowsRetry(messageType: "watchHeartbeat")
        )
    }

    @Test func finishPauseResumeOutrankTelemetry() {
        #expect(
            PulsarWatchConnectivityTransportPolicy.usesInteractiveSend(
                messageType: "activeGymAction",
                actionKind: "finishWorkout",
                isReachable: true,
                hasLiveWorkout: true
            )
        )
        #expect(
            PulsarWatchConnectivityTransportPolicy.allowsRetry(
                messageType: "activeGymAction",
                actionKind: "finishWorkout"
            )
        )
        #expect(
            PulsarWatchConnectivityTransportPolicy.usesDurableTransfer(
                messageType: "activeGymAction",
                actionKind: "finishWorkout"
            )
        )
        #expect(
            PulsarWatchConnectivityTransportPolicy.controlOutranksTelemetry(
                controlType: "finishWorkout",
                telemetryType: "activeGymState"
            )
        )
        #expect(
            PulsarWatchConnectivityTransportPolicy.controlOutranksTelemetry(
                controlType: "pause",
                telemetryType: "watchHeartbeat"
            )
        )
        #expect(
            PulsarWatchConnectivityTransportPolicy.controlOutranksTelemetry(
                controlType: "resume",
                telemetryType: "activeGymState"
            )
        )
        #expect(
            !PulsarWatchConnectivityTransportPolicy.allowsRetry(
                messageType: "activeGymAction",
                actionKind: "requestState"
            )
        )
    }

    @Test func requestStateIsInteractiveOnly() {
        #expect(
            PulsarWatchConnectivityTransportPolicy.messageClass(
                messageType: "activeGymAction",
                actionKind: "requestState"
            ) == .interactive
        )
        #expect(!ActiveGymWorkoutAction.requestState().shouldQueueOverWatchConnectivity)
        #expect(!ActiveGymWorkoutAction.requestSavedRoutines().shouldQueueOverWatchConnectivity)
        #expect(
            !ActiveGymWorkoutAction.metricsUpdated(
                sessionId: UUID(),
                currentHeartRate: 120,
                averageHeartRate: 110,
                maxHeartRate: 130,
                activeEnergyKilocalories: 20
            ).shouldQueueOverWatchConnectivity
        )
        #expect(ActiveGymWorkoutAction.finishWorkout(sessionId: UUID()).shouldQueueOverWatchConnectivity)
    }

    @Test func terminalGymStateUsesDurableDelivery() {
        #expect(
            PulsarWatchConnectivityTransportPolicy.messageClass(
                messageType: "activeGymTerminal"
            ) == .durable
        )
        #expect(
            PulsarWatchConnectivityTransportPolicy.usesDurableTransfer(
                messageType: "activeGymTerminal"
            )
        )
        #expect(
            !PulsarWatchConnectivityTransportPolicy.usesLatestStateOverwrite(
                messageType: "activeGymTerminal"
            )
        )
    }
}
