//
//  PulsarBottomChromeState.swift
//  Pulsar
//

import Combine
import SwiftUI

@MainActor
final class PulsarBottomChromeState: ObservableObject {
    enum Phase {
        case expanded
        case compact
    }

    @Published private(set) var compactProgress: CGFloat = 0
    @Published private(set) var phase: Phase = .expanded
    @Published private(set) var visibleChromeHeight: CGFloat = 88

    private var lastScrollOffset: CGFloat = 0
    private var accumulatedDownwardScroll: CGFloat = 0
    private var accumulatedUpwardScroll: CGFloat = 0
    private var scrollUpdatesSuspendedUntil: Date?
    private var settleTask: Task<Void, Never>?

    var floatingControlBottomPadding: CGFloat {
        max(visibleChromeHeight, 72) + 18
    }

    var scrollContentBottomPadding: CGFloat {
        max(visibleChromeHeight, 72) + 18
    }

    func updateScrollOffset(_ offset: CGFloat) {
        updateScrollMetrics(PulsarBottomChromeScrollMetrics(offset: offset, isNearBottom: false))
    }

    func updateScrollMetrics(_ metrics: PulsarBottomChromeScrollMetrics) {
        let normalizedOffset = max(0, metrics.offset)

        guard !shouldIgnoreScrollUpdate(normalizedOffset) else {
            return
        }

        guard normalizedOffset > Self.nearTopOffset else {
            lastScrollOffset = normalizedOffset
            resetScrollAccumulation()
            setPhase(.expanded, source: "nearTop")
            return
        }

        let delta = normalizedOffset - lastScrollOffset
        guard abs(delta) > Self.minimumScrollDelta else {
            lastScrollOffset = normalizedOffset
            schedulePhaseSettle()
            return
        }

        if delta > 0 {
            accumulatedDownwardScroll += delta
            accumulatedUpwardScroll = 0

            if accumulatedDownwardScroll >= Self.compactThreshold {
                setPhase(.compact, source: "scrollDown")
            }
        } else {
            guard !isLikelyBottomBounce(metrics) else {
                lastScrollOffset = normalizedOffset
                resetScrollAccumulation()
                schedulePhaseSettle()
                return
            }

            accumulatedUpwardScroll += abs(delta)
            accumulatedDownwardScroll = 0

            if accumulatedUpwardScroll >= Self.expandThreshold {
                setPhase(.expanded, source: "scrollUp")
            }
        }

        lastScrollOffset = normalizedOffset
        schedulePhaseSettle()
    }

    func expandForInteraction() {
        resetScrollAccumulation()
        setPhase(.expanded, source: "interaction")
    }

    func prepareForRootTransition() {
        scrollUpdatesSuspendedUntil = Date().addingTimeInterval(Self.rootTransitionScrollSuspension)
        resetScrollAccumulation()
        setPhase(.expanded, source: "rootTransition")
    }

    func restoreCompactIfScrolledDown() {
        resetScrollAccumulation()
        if lastScrollOffset >= Self.restoreCompactOffset {
            setPhase(.compact, source: "restore")
        } else {
            setPhase(.expanded, source: "restore")
        }
    }

    func reset() {
        settleTask?.cancel()
        lastScrollOffset = 0
        expandForInteraction()
    }

    func updateVisibleChromeHeight(_ height: CGFloat) {
        guard height > 0, abs(height - visibleChromeHeight) > 1 else { return }
        visibleChromeHeight = height
    }

    private func setPhase(_ nextPhase: Phase, source: String) {
        guard phase != nextPhase else { return }
        phase = nextPhase

        #if DEBUG
        print("[BottomChrome] phase=\(nextPhase) source=\(source) offset=\(Int(lastScrollOffset))")
        #endif

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86, blendDuration: 0.08)) {
            compactProgress = nextPhase == .compact ? 1 : 0
        }
    }

    private func isLikelyBottomBounce(_ metrics: PulsarBottomChromeScrollMetrics) -> Bool {
        phase == .compact && metrics.isNearBottom
    }

    private func resetScrollAccumulation() {
        accumulatedDownwardScroll = 0
        accumulatedUpwardScroll = 0
    }

    private func schedulePhaseSettle() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.phaseSettleDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.settleToCurrentPhase()
        }
    }

    private func settleToCurrentPhase() {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.94, blendDuration: 0.04)) {
            compactProgress = phase == .compact ? 1 : 0
        }
    }

    private func shouldIgnoreScrollUpdate(_ normalizedOffset: CGFloat) -> Bool {
        guard let suspendedUntil = scrollUpdatesSuspendedUntil else {
            return false
        }

        if Date() < suspendedUntil {
            lastScrollOffset = normalizedOffset
            resetScrollAccumulation()
            return true
        }

        scrollUpdatesSuspendedUntil = nil
        lastScrollOffset = normalizedOffset
        resetScrollAccumulation()
        return true
    }

    private static let nearTopOffset: CGFloat = 16
    private static let minimumScrollDelta: CGFloat = 1.5
    private static let compactThreshold: CGFloat = 42
    private static let expandThreshold: CGFloat = 26
    private static let restoreCompactOffset: CGFloat = 56
    private static let rootTransitionScrollSuspension: TimeInterval = 0.42
    private static let phaseSettleDelayNanoseconds: UInt64 = 220_000_000
}

struct PulsarBottomChromeScrollMetrics: Equatable {
    var offset: CGFloat
    var isNearBottom: Bool
}

private struct PulsarBottomChromeStateKey: EnvironmentKey {
    static let defaultValue: PulsarBottomChromeState? = nil
}

extension EnvironmentValues {
    var pulsarBottomChromeState: PulsarBottomChromeState? {
        get { self[PulsarBottomChromeStateKey.self] }
        set { self[PulsarBottomChromeStateKey.self] = newValue }
    }
}

extension View {
    func pulsarBottomChromeScrollTracking() -> some View {
        modifier(PulsarBottomChromeScrollTrackingModifier())
    }
}

private struct PulsarBottomChromeScrollTrackingModifier: ViewModifier {
    @Environment(\.pulsarBottomChromeState) private var chromeState

    func body(content: Content) -> some View {
        if let chromeState {
            content.modifier(PulsarObservedBottomChromeScrollTrackingModifier(chromeState: chromeState))
        } else {
            content
        }
    }
}

private struct PulsarObservedBottomChromeScrollTrackingModifier: ViewModifier {
    @ObservedObject var chromeState: PulsarBottomChromeState

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.bottom, chromeState.scrollContentBottomPadding)
            .onScrollGeometryChange(for: PulsarBottomChromeScrollMetrics.self) { geometry in
                let offset = max(0, geometry.contentOffset.y + geometry.contentInsets.top)
                let scrollableHeight = max(
                    0,
                    geometry.contentSize.height
                    + geometry.contentInsets.top
                    + geometry.contentInsets.bottom
                    - geometry.containerSize.height
                )
                return PulsarBottomChromeScrollMetrics(
                    offset: offset,
                    isNearBottom: offset >= max(0, scrollableHeight - 160)
                )
            } action: { _, newOffset in
                chromeState.updateScrollMetrics(newOffset)
            }
            .onAppear {
                chromeState.reset()
            }
    }
}
