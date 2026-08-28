//
//  PulsarNativeBottomAccessoryReconcilerTests.swift
//  PulsarTests
//

import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Pulsar

struct PulsarNativeBottomAccessoryReconcilerTests {
    @Test func noneToNoneIsNoOp() {
        var reconciler = PulsarNativeBottomAccessoryReconciler()

        #expect(reconciler.register(.none) == .noOp)
        #expect(reconciler.applyCount == 0)
        #expect(reconciler.noOpCount == 1)
        #expect(!reconciler.isTransitionScheduled)
    }

    @Test func noneToOrionAppliesOnce() {
        var reconciler = PulsarNativeBottomAccessoryReconciler()

        #expect(reconciler.register(.orion) == .applyIdentity)
        #expect(reconciler.desired == .orion)
        #expect(reconciler.applied == .none)
        #expect(reconciler.isTransitionScheduled)

        #expect(reconciler.markApplied(.orion) == false)
        #expect(reconciler.applied == .orion)
        #expect(!reconciler.isTransitionScheduled)
        #expect(reconciler.register(.orion) == .noOp)
        #expect(reconciler.applyCount == 1)
    }

    @Test func orionToOrionIsNoOp() {
        var reconciler = PulsarNativeBottomAccessoryReconciler()
        #expect(reconciler.register(.orion) == .applyIdentity)
        #expect(reconciler.markApplied(.orion) == false)

        #expect(reconciler.register(.orion) == .noOp)
        #expect(reconciler.applyCount == 1)
    }

    @Test func orionToMiniWorkoutAppliesOnce() {
        var reconciler = PulsarNativeBottomAccessoryReconciler()
        let sessionID = UUID()
        let content = Self.watchGymState(sessionID: sessionID, elapsed: "1:00")

        #expect(reconciler.register(.orion) == .applyIdentity)
        #expect(reconciler.markApplied(.orion) == false)
        #expect(reconciler.register(.workout(sessionID: sessionID), workoutContent: content) == .applyIdentity)
        #expect(reconciler.markApplied(.workout(sessionID: sessionID), workoutContent: content) == false)
        #expect(reconciler.applied == .workout(sessionID: sessionID))
        #expect(reconciler.applyCount == 2)
    }

    @Test func miniWorkoutToSameContentIsNoOp() {
        var reconciler = PulsarNativeBottomAccessoryReconciler()
        let sessionID = UUID()
        let content = Self.watchGymState(sessionID: sessionID, elapsed: "1:00")

        #expect(reconciler.register(.workout(sessionID: sessionID), workoutContent: content) == .applyIdentity)
        #expect(reconciler.markApplied(.workout(sessionID: sessionID), workoutContent: content) == false)
        #expect(reconciler.register(.workout(sessionID: sessionID), workoutContent: content) == .noOp)
        #expect(reconciler.contentUpdateCount == 0)
        #expect(reconciler.applyCount == 1)
    }

    @Test func miniWorkoutContentChangeUpdatesWithoutIdentityApply() {
        var reconciler = PulsarNativeBottomAccessoryReconciler()
        let sessionID = UUID()
        let first = Self.watchGymState(sessionID: sessionID, elapsed: "1:00")
        let second = Self.watchGymState(sessionID: sessionID, elapsed: "1:01")

        #expect(reconciler.register(.workout(sessionID: sessionID), workoutContent: first) == .applyIdentity)
        #expect(reconciler.markApplied(.workout(sessionID: sessionID), workoutContent: first) == false)
        #expect(reconciler.register(.workout(sessionID: sessionID), workoutContent: second) == .updateContent)
        #expect(reconciler.applyCount == 1)
        #expect(reconciler.contentUpdateCount == 1)
        #expect(reconciler.register(.workout(sessionID: sessionID), workoutContent: second) == .noOp)
    }

    @Test func miniWorkoutToNoneAppliesOnce() {
        var reconciler = PulsarNativeBottomAccessoryReconciler()
        let sessionID = UUID()
        let content = Self.watchGymState(sessionID: sessionID)

        #expect(reconciler.register(.workout(sessionID: sessionID), workoutContent: content) == .applyIdentity)
        #expect(reconciler.markApplied(.workout(sessionID: sessionID), workoutContent: content) == false)
        #expect(reconciler.register(.none) == .applyIdentity)
        #expect(reconciler.markApplied(.none) == false)
        #expect(reconciler.applied == .none)
        #expect(reconciler.register(.none) == .noOp)
        #expect(reconciler.applyCount == 2)
    }

    @Test func pendingIdenticalRequestCoalesces() {
        var reconciler = PulsarNativeBottomAccessoryReconciler()

        #expect(reconciler.register(.orion) == .applyIdentity)
        #expect(reconciler.register(.orion) == .coalesced)
        #expect(reconciler.register(.orion) == .coalesced)
        #expect(reconciler.applyCount == 1)
        #expect(reconciler.coalescedCount == 2)
        #expect(reconciler.markApplied(.orion) == false)
        #expect(reconciler.register(.orion) == .noOp)
    }

    @Test func pendingRequestReplacedByLaterIdentityAppliesLatest() {
        var reconciler = PulsarNativeBottomAccessoryReconciler()
        let sessionID = UUID()
        let content = Self.watchGymState(sessionID: sessionID)

        #expect(reconciler.register(.orion) == .applyIdentity)
        #expect(reconciler.register(.workout(sessionID: sessionID), workoutContent: content) == .coalesced)
        #expect(reconciler.desired == .workout(sessionID: sessionID))
        #expect(reconciler.applyCount == 1)

        #expect(reconciler.markApplied(.workout(sessionID: sessionID), workoutContent: content) == false)
        #expect(reconciler.applied == .workout(sessionID: sessionID))
        #expect(reconciler.register(.workout(sessionID: sessionID), workoutContent: content) == .noOp)
    }

    @Test func appliedStaleIdentitySchedulesFollowUpToLatestDesired() {
        var reconciler = PulsarNativeBottomAccessoryReconciler()
        let sessionID = UUID()
        let content = Self.watchGymState(sessionID: sessionID)

        #expect(reconciler.register(.orion) == .applyIdentity)
        #expect(reconciler.register(.workout(sessionID: sessionID), workoutContent: content) == .coalesced)
        #expect(reconciler.markApplied(.orion) == true)
        #expect(reconciler.applied == .orion)
        #expect(reconciler.desired == .workout(sessionID: sessionID))
        #expect(reconciler.isTransitionScheduled)
        #expect(reconciler.applyCount == 2)
        #expect(reconciler.markApplied(.workout(sessionID: sessionID), workoutContent: content) == false)
        #expect(reconciler.applied == .workout(sessionID: sessionID))
    }

    @Test func rapidRepeatedIdenticalRequestsProduceOneMutation() {
        var reconciler = PulsarNativeBottomAccessoryReconciler()

        #expect(reconciler.register(.none) == .noOp)
        for _ in 0..<200 {
            #expect(reconciler.register(.none) == .noOp)
        }
        #expect(reconciler.applyCount == 0)
        #expect(reconciler.noOpCount == 201)

        #expect(reconciler.register(.orion) == .applyIdentity)
        for _ in 0..<200 {
            #expect(reconciler.register(.orion) == .coalesced)
        }
        #expect(reconciler.applyCount == 1)
        #expect(reconciler.markApplied(.orion) == false)
        #expect(reconciler.register(.orion) == .noOp)
    }

    @Test func layoutQuantizationCollapsesSubpixelJitter() {
        let first = PulsarLayoutQuantization.quantize(120.12)
        let second = PulsarLayoutQuantization.quantize(120.24)
        let third = PulsarLayoutQuantization.quantize(120.76)

        #expect(first == 120)
        #expect(first == second)
        #expect(first != third)
        #expect(PulsarLayoutQuantization.isEffectivelyEqual(44.01, 44.24))
        #expect(!PulsarLayoutQuantization.isEffectivelyEqual(44.01, 44.76))
        #expect(
            PulsarLayoutQuantization.quantize(CGRect(x: 0.12, y: 10.12, width: 390.12, height: 49.12))
                == PulsarLayoutQuantization.quantize(CGRect(x: 0.24, y: 10.24, width: 390.24, height: 49.24))
        )

        let previousInsets = PulsarLayoutQuantization.quantize(
            UIEdgeInsets(top: 0, left: 0, bottom: 34.12, right: 0)
        )
        let jitteredInsets = PulsarLayoutQuantization.quantize(
            UIEdgeInsets(top: 0, left: 0, bottom: 34.24, right: 0)
        )
        #expect(previousInsets == jitteredInsets)
    }

    private static func watchGymState(
        sessionID: UUID,
        elapsed: String = "0:00"
    ) -> PulsarWorkoutMiniPlayerState {
        PulsarWorkoutMiniPlayerState(
            id: "watchGym-\(sessionID.uuidString)",
            sessionID: sessionID,
            kind: .watchGym,
            title: "Gym",
            symbol: "dumbbell.fill",
            status: .live,
            elapsedText: elapsed,
            secondaryMetrics: []
        )
    }
}

struct PulsarRootLiveChromeIdentityTests {
    @Test func hiddenAndLaunchOwnedKeepTheSameOrionAccessory() {
        let sessionID = UUID()
        let hidden = PulsarRootLiveChromeIdentity.resolve(presentationState: .hidden)
        let launchOwned = PulsarRootLiveChromeIdentity.resolve(
            presentationState: .launchOwned(sessionID)
        )

        #expect(hidden.showsOrion)
        #expect(!hidden.showsMiniWorkout)
        #expect(launchOwned.showsOrion)
        #expect(!launchOwned.showsMiniWorkout)
        #expect(hidden == launchOwned)
        #expect(hidden.accessoryIdentity == .orion)
        #expect(launchOwned.accessoryIdentity == .orion)
    }

    @Test func minimizedReplacesOrionWithTheMiniWorkoutAccessory() {
        let sessionID = UUID()
        let minimized = PulsarRootLiveChromeIdentity.resolve(
            presentationState: .minimized(sessionID)
        )

        #expect(!minimized.showsOrion)
        #expect(minimized.showsMiniWorkout)
        #expect(minimized.miniSessionID == sessionID)
        #expect(minimized.accessoryIdentity == .workout(sessionID: sessionID))
    }

    @Test func expandedSummaryDoesNotKeepTheLaunchCoverOrionAccessory() {
        let sessionID = UUID()
        let expanded = PulsarRootLiveChromeIdentity.resolve(
            presentationState: .expanded(
                PulsarPresentedWorkoutItem(workout: .watchGym, sessionID: sessionID)
            )
        )
        let launchOwned = PulsarRootLiveChromeIdentity.resolve(
            presentationState: .launchOwned(sessionID)
        )

        #expect(!expanded.showsOrion)
        #expect(launchOwned.showsOrion)
        #expect(expanded != launchOwned)
    }
}
