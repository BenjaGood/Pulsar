//
//  PulsarNativeBottomAccessoryReconciler.swift
//  Pulsar
//

import CoreGraphics
import Foundation
import UIKit

enum PulsarNativeBottomAccessoryIdentity: Equatable, Sendable {
    case none
    case orion
    case workout(sessionID: UUID)

    init(workoutState: PulsarWorkoutMiniPlayerState?, showsOrion: Bool) {
        if let workoutState {
            self = .workout(sessionID: workoutState.sessionID)
        } else if showsOrion {
            self = .orion
        } else {
            self = .none
        }
    }

    var diagnosticName: String {
        switch self {
        case .none: "none"
        case .orion: "orion"
        case .workout(let sessionID): "workout(\(sessionID.uuidString))"
        }
    }

    var layoutState: PulsarNativeBottomAccessoryLayoutState? {
        switch self {
        case .none: nil
        case .orion: .orion
        case .workout: .workout
        }
    }
}

enum PulsarNativeBottomAccessoryReconcileResult: Equatable, Sendable {
    case noOp
    case coalesced
    case applyIdentity
    case updateContent

    var rateBucket: String {
        switch self {
        case .noOp: "[BottomAccessory] noOp"
        case .coalesced: "[BottomAccessory] coalesced"
        case .applyIdentity: "[BottomAccessory] apply"
        case .updateContent: "[BottomAccessory] contentUpdate"
        }
    }
}

/// Owns desired / pending / applied accessory identity so SwiftUI representable
/// updates cannot schedule UIKit `setBottomAccessory` when nothing changed.
struct PulsarNativeBottomAccessoryReconciler: Equatable, Sendable {
    private(set) var desired: PulsarNativeBottomAccessoryIdentity = .none
    private(set) var applied: PulsarNativeBottomAccessoryIdentity = .none
    private(set) var isTransitionScheduled = false
    private(set) var appliedWorkoutContent: PulsarWorkoutMiniPlayerState?

    private(set) var requestCount = 0
    private(set) var noOpCount = 0
    private(set) var coalescedCount = 0
    private(set) var applyCount = 0
    private(set) var contentUpdateCount = 0

    var pending: PulsarNativeBottomAccessoryIdentity? {
        isTransitionScheduled ? desired : nil
    }

    mutating func register(
        _ next: PulsarNativeBottomAccessoryIdentity,
        workoutContent: PulsarWorkoutMiniPlayerState? = nil
    ) -> PulsarNativeBottomAccessoryReconcileResult {
        requestCount += 1
        desired = next

        if isTransitionScheduled {
            coalescedCount += 1
            return .coalesced
        }

        if next == applied {
            if case .workout = next, workoutContent != appliedWorkoutContent {
                appliedWorkoutContent = workoutContent
                contentUpdateCount += 1
                return .updateContent
            }
            noOpCount += 1
            return .noOp
        }

        isTransitionScheduled = true
        applyCount += 1
        return .applyIdentity
    }

    /// Call after the UIKit accessory matches `appliedIdentity`.
    /// Returns true when `desired` moved during the transition and another
    /// apply is required.
    @discardableResult
    mutating func markApplied(
        _ appliedIdentity: PulsarNativeBottomAccessoryIdentity,
        workoutContent: PulsarWorkoutMiniPlayerState? = nil
    ) -> Bool {
        applied = appliedIdentity
        appliedWorkoutContent = {
            switch appliedIdentity {
            case .workout:
                workoutContent
            case .none, .orion:
                nil
            }
        }()
        isTransitionScheduled = false
        guard desired != applied else { return false }
        isTransitionScheduled = true
        applyCount += 1
        return true
    }

    mutating func resetForTesting() {
        self = PulsarNativeBottomAccessoryReconciler()
    }
}

enum PulsarLayoutQuantization {
    static let pointTolerance: CGFloat = 0.5

    static func quantize(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return (value / pointTolerance).rounded() * pointTolerance
    }

    static func quantize(_ rect: CGRect) -> CGRect {
        CGRect(
            x: quantize(rect.origin.x),
            y: quantize(rect.origin.y),
            width: quantize(rect.size.width),
            height: quantize(rect.size.height)
        )
    }

    static func quantize(_ insets: UIEdgeInsets) -> UIEdgeInsets {
        UIEdgeInsets(
            top: quantize(insets.top),
            left: quantize(insets.left),
            bottom: quantize(insets.bottom),
            right: quantize(insets.right)
        )
    }

    static func isEffectivelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(quantize(lhs) - quantize(rhs)) < 0.001
    }
}
