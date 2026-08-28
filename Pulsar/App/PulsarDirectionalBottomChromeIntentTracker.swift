//
//  PulsarDirectionalBottomChromeIntentTracker.swift
//  Pulsar
//

import CoreGraphics
import Foundation
import UIKit

/// Finger-driven upward intent for restoring native tab/accessory chrome.
///
/// Translation comes from the selected scroll view's existing pan recognizer,
/// so geometry changes, programmatic scrolling, and content-size updates cannot
/// look like a reversal. UIKit pan `translation.y` decreases as the finger
/// travels up (content scrolls down) and increases as the finger travels down
/// (content scrolls up). The lowest translation in the gesture is the reversal
/// pivot; upward intent is travel back from that pivot.
struct PulsarDirectionalBottomChromeIntentTracker: Equatable, Sendable {
    static let reversalDeadZone: CGFloat = 2
    static let expansionTravel: CGFloat = 22

    private var isTracking = false
    private var lowestTranslationY: CGFloat = 0
    private var hasRequestedExpansion = false

    var hasLatchedExpansion: Bool {
        hasRequestedExpansion
    }

    mutating func update(
        translationY: CGFloat,
        phase: PulsarDirectionalPanPhase,
        context: PulsarDirectionalBottomChromeIntentContext
    ) -> PulsarDirectionalBottomChromeIntent {
        switch phase {
        case .began:
            beginGesture(translationY: translationY)
            return evaluate(translationY: translationY, context: context)
        case .changed:
            if !isTracking {
                beginGesture(translationY: translationY)
            }
            return evaluate(translationY: translationY, context: context)
        case .ended, .cancelled:
            reset()
            return .none
        }
    }

    mutating func reset() {
        isTracking = false
        lowestTranslationY = 0
        hasRequestedExpansion = false
    }

    private mutating func beginGesture(translationY: CGFloat) {
        isTracking = true
        lowestTranslationY = translationY
        hasRequestedExpansion = false
    }

    private mutating func evaluate(
        translationY: CGFloat,
        context: PulsarDirectionalBottomChromeIntentContext
    ) -> PulsarDirectionalBottomChromeIntent {
        guard isTracking else { return .none }

        let upwardTravel = translationY - lowestTranslationY
        if upwardTravel < Self.reversalDeadZone {
            lowestTranslationY = min(lowestTranslationY, translationY)
            return .none
        }

        guard context.isEligible, !hasRequestedExpansion else { return .none }
        guard upwardTravel >= Self.expansionTravel else { return .none }

        hasRequestedExpansion = true
        return .expand
    }
}

enum PulsarDirectionalPanPhase: Equatable, Sendable {
    case began
    case changed
    case ended
    case cancelled

    init?(gestureState: UIGestureRecognizer.State) {
        switch gestureState {
        case .began:
            self = .began
        case .changed:
            self = .changed
        case .ended:
            self = .ended
        case .cancelled, .failed:
            self = .cancelled
        default:
            return nil
        }
    }

    var isTerminal: Bool {
        self == .ended || self == .cancelled
    }
}

struct PulsarDirectionalBottomChromeIntentContext: Equatable, Sendable {
    var isHomeSelected: Bool
    var isOrionAccessory: Bool
    var isCompact: Bool

    var isEligible: Bool {
        isHomeSelected && isOrionAccessory && isCompact
    }

    static let eligibleCompactHomeOrion = PulsarDirectionalBottomChromeIntentContext(
        isHomeSelected: true,
        isOrionAccessory: true,
        isCompact: true
    )
}

enum PulsarDirectionalBottomChromeIntent: Equatable, Sendable {
    case none
    case expand
}
