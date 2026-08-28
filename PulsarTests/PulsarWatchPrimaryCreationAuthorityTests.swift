//
//  PulsarWatchPrimaryCreationAuthorityTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct PulsarWatchPrimaryCreationAuthorityTests {
    @Test func companionStartWatchAppCreatesWhenIdentitiesArePresent() {
        let decision = PulsarWatchPrimaryCreationAuthority.decision(
            source: .startWatchAppConfiguration,
            workoutID: UUID(),
            requestID: UUID()
        )
        #expect(decision == .allow)
    }

    @Test func explicitWatchLocalStartCreatesWithoutRequestID() {
        let decision = PulsarWatchPrimaryCreationAuthority.decision(
            source: .watchUIStart,
            workoutID: UUID(),
            requestID: nil
        )
        #expect(decision == .allow)
    }

    @Test func companionHealthKitLaunchCreatesBeforeMetadataArrives() {
        let decision = PulsarWatchPrimaryCreationAuthority.decision(
            source: .startWatchAppConfiguration,
            workoutID: UUID(),
            requestID: nil
        )
        #expect(decision == .allow)
        #expect(!PulsarWatchPrimaryCreationSource.startWatchAppConfiguration.requiresCompanionRequestID)
    }

    @Test func unauthorizedSourcesCannotCreateAPrimary() {
        let workoutID = UUID()
        let unauthorized: [PulsarWatchPrimaryCreationSource] = [
            .activeGymStateSink,
            .activeWorkoutStateSink,
            .watchGymViewAppear,
            .prelaunchHint,
            .routineSnapshotReceived,
            .heartbeat,
            .restore,
            .requestState,
            .recovery
        ]
        for source in unauthorized {
            let decision = PulsarWatchPrimaryCreationAuthority.decision(
                source: source,
                workoutID: workoutID,
                requestID: UUID()
            )
            guard case .reject = decision else {
                Issue.record("\(source.rawValue) must not create a Watch HKWorkoutSession")
                return
            }
            #expect(!source.canCreatePrimarySession)
        }
    }

    @Test func creationAuthorityTableMatchesTheArchitecturalRule() {
        #expect(PulsarWatchPrimaryCreationSource.startWatchAppConfiguration.canCreatePrimarySession)
        #expect(PulsarWatchPrimaryCreationSource.watchUIStart.canCreatePrimarySession)
        #expect(!PulsarWatchPrimaryCreationSource.activeGymStateSink.canCreatePrimarySession)
        #expect(!PulsarWatchPrimaryCreationSource.watchGymViewAppear.canCreatePrimarySession)
        #expect(!PulsarWatchPrimaryCreationSource.prelaunchHint.canCreatePrimarySession)
        #expect(!PulsarWatchPrimaryCreationSource.routineSnapshotReceived.canCreatePrimarySession)
        #expect(!PulsarWatchPrimaryCreationSource.heartbeat.canCreatePrimarySession)
        #expect(!PulsarWatchPrimaryCreationSource.restore.canCreatePrimarySession)
        #expect(!PulsarWatchPrimaryCreationSource.requestState.canCreatePrimarySession)
    }
}
