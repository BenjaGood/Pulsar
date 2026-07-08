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

    var scrollContentBottomMargin: CGFloat {
        Self.scrollContentBottomMargin(for: safeAreaBottom)
    }

    var endOfContentSpacerHeight: CGFloat {
        Self.floatingNavigationEndOfContentBuffer
    }

    static func scrollContentBottomMargin(for safeAreaBottom: CGFloat) -> CGFloat {
        floatingNavigationHeight
            + min(max(safeAreaBottom, 0), maximumSystemBottomInset)
            + floatingNavigationExtraScrollSpacing
    }
}

final class PulsarBottomChromeLayoutStore: ObservableObject {
    @Published private(set) var layout = PulsarBottomChromeLayout()

    @MainActor
    func update(safeAreaBottom: CGFloat) {
        var nextLayout = layout
        nextLayout.safeAreaBottom = safeAreaBottom
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
