//
//  PulsarBottomChromeLayout.swift
//  Pulsar
//

import Combine
import SwiftUI
import UIKit

struct PulsarBottomChromeLayout: Equatable {
    static let floatingNavigationHeight: CGFloat = 76
    static let floatingNavigationExtraScrollSpacing: CGFloat = 28
    static let floatingNavigationEndOfContentBuffer: CGFloat = 0
    static let maximumSystemBottomInset: CGFloat = 44

    var safeAreaBottom: CGFloat = 0
    var accessoryHeight: CGFloat = 0

    var scrollContentBottomMargin: CGFloat {
        Self.scrollContentBottomMargin(
            for: safeAreaBottom,
            accessoryHeight: accessoryHeight
        )
    }

    var endOfContentSpacerHeight: CGFloat {
        Self.floatingNavigationEndOfContentBuffer
    }

    static func scrollContentBottomMargin(
        for safeAreaBottom: CGFloat,
        accessoryHeight: CGFloat = 0
    ) -> CGFloat {
        floatingNavigationHeight
            + min(max(safeAreaBottom, 0), maximumSystemBottomInset)
            + max(accessoryHeight, 0)
            + floatingNavigationExtraScrollSpacing
    }
}

enum PulsarNativeBottomAccessoryLayoutState: Equatable {
    case orion
    case workout
}

/// Native-tab accessory identity derived from workout presentation.
/// Launch-owned and hidden states keep Orion installed so `setBottomAccessory`
/// cannot run underneath a still-present Fitness cover.
struct PulsarRootLiveChromeIdentity: Equatable, Sendable {
    var showsMiniWorkout: Bool
    var miniSessionID: UUID?
    var showsOrion: Bool

    static func resolve(
        presentationState: PulsarActiveWorkoutPresentationState
    ) -> Self {
        let showsOrion: Bool
        switch presentationState {
        case .hidden, .launchOwned, .handoffPending:
            showsOrion = true
        case .minimized, .expanded, .dismissing, .minimizing:
            showsOrion = false
        }

        let miniSessionID: UUID?
        if case .minimized(let sessionID) = presentationState {
            miniSessionID = sessionID
        } else {
            miniSessionID = nil
        }

        return Self(
            showsMiniWorkout: miniSessionID != nil,
            miniSessionID: miniSessionID,
            showsOrion: showsOrion
        )
    }

    var accessoryIdentity: PulsarNativeBottomAccessoryIdentity {
        if let miniSessionID {
            return .workout(sessionID: miniSessionID)
        }
        if showsOrion {
            return .orion
        }
        return .none
    }
}

enum PulsarNativeBottomAccessorySizing {
    static func height(for state: PulsarNativeBottomAccessoryLayoutState) -> CGFloat {
        switch state {
        case .orion: 44
        case .workout: PulsarWorkoutMiniPlayerSizing.stableNativeAccessoryHeight
        }
    }
}

struct PulsarBottomChromeLayoutInputs: Equatable {
    var safeAreaBottom: CGFloat
    var accessoryHeight: CGFloat
    var displayScale: CGFloat

    init(
        safeAreaBottom: CGFloat,
        displayScale: CGFloat,
        showsMiniWorkout: Bool,
        showsOrion: Bool
    ) {
        self.safeAreaBottom = safeAreaBottom
        self.displayScale = displayScale
        if showsMiniWorkout {
            accessoryHeight = PulsarNativeBottomAccessorySizing.height(for: .workout)
        } else if showsOrion {
            accessoryHeight = PulsarNativeBottomAccessorySizing.height(for: .orion)
        } else {
            accessoryHeight = 0
        }
    }
}

final class PulsarBottomChromeLayoutStore: ObservableObject {
    @Published private(set) var layout = PulsarBottomChromeLayout()

    @MainActor
    func update(
        safeAreaBottom: CGFloat,
        accessoryHeight: CGFloat = 0,
        displayScale: CGFloat = 1
    ) {
        guard safeAreaBottom.isFinite, accessoryHeight.isFinite else { return }
        let normalizedScale = displayScale.isFinite ? max(displayScale, 1) : 1
        let normalizedBottomInset = (max(safeAreaBottom, 0) * normalizedScale).rounded() / normalizedScale
        let normalizedAccessoryHeight = (max(accessoryHeight, 0) * normalizedScale).rounded() / normalizedScale

        var nextLayout = layout
        nextLayout.safeAreaBottom = normalizedBottomInset
        nextLayout.accessoryHeight = normalizedAccessoryHeight
        guard nextLayout != layout else { return }
        layout = nextLayout
    }
}

struct PulsarBottomChromeSpacer: View {
    @ObservedObject var layoutStore: PulsarBottomChromeLayoutStore

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: layoutStore.layout.endOfContentSpacerHeight)
            .background(PulsarPrimaryScrollViewMarker())
            .accessibilityHidden(true)
    }
}

extension View {
    func pulsarBottomChromeScrollContainer(layoutStore: PulsarBottomChromeLayoutStore) -> some View {
        self
            .contentMargins(.bottom, layoutStore.layout.scrollContentBottomMargin, for: .scrollContent)
            .scrollBounceBehavior(.basedOnSize)
            .background(PulsarPrimaryScrollViewMarker())
    }
}

private struct PulsarPrimaryScrollViewMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = PulsarPrimaryScrollViewMarkerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? PulsarPrimaryScrollViewMarkerView)?.markPrimaryScrollView()
    }
}

private final class PulsarPrimaryScrollViewMarkerView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        markPrimaryScrollView()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        markPrimaryScrollView()
    }

    func markPrimaryScrollView() {
        guard let scrollView = pulsarEnclosingScrollView else { return }
        scrollView.accessibilityIdentifier = UIView.pulsarPrimaryBottomChromeScrollViewIdentifier
    }
}

extension UIView {
    static let pulsarPrimaryBottomChromeScrollViewIdentifier = "pulsar.primaryBottomChromeScrollView"

    var pulsarPrimaryBottomChromeScrollView: UIScrollView? {
        if let scrollView = self as? UIScrollView,
           scrollView.accessibilityIdentifier == Self.pulsarPrimaryBottomChromeScrollViewIdentifier {
            return scrollView
        }

        for subview in subviews {
            if let scrollView = subview.pulsarPrimaryBottomChromeScrollView {
                return scrollView
            }
        }

        return nil
    }

    var pulsarBestVerticalContentScrollView: UIScrollView? {
        var best: UIScrollView?
        var bestScore: CGFloat = -1

        func inspect(_ view: UIView) {
            if let scrollView = view as? UIScrollView,
               scrollView.isScrollEnabled,
               !scrollView.isHidden,
               scrollView.alpha > 0.05,
               scrollView.bounds.width > 1,
               scrollView.bounds.height > 1 {
                let verticalOverflow = max(0, scrollView.contentSize.height - scrollView.bounds.height)
                let aspectBias = scrollView.bounds.height >= scrollView.bounds.width ? scrollView.bounds.height : 0
                let score = scrollView.bounds.width * scrollView.bounds.height + verticalOverflow * 10 + aspectBias

                if score > bestScore {
                    best = scrollView
                    bestScore = score
                }
            }

            for subview in view.subviews {
                inspect(subview)
            }
        }

        inspect(self)
        return best
    }

    var pulsarEnclosingScrollView: UIScrollView? {
        var current: UIView? = superview
        while let view = current {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }
}
