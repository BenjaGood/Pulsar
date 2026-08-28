import SwiftUI

enum PulsarWorkoutMiniPlayerSizing {
    static let compactContentHeight: CGFloat = 44
    static let expandedContentHeight: CGFloat = 58

    /// Native tab accessories use one compact visual contract. Their intrinsic
    /// height never depends on placement traits or user layout.
    static let stableNativeAccessoryHeight: CGFloat = 48
}

enum PulsarWorkoutMiniPlayerInteractionPolicy {
    static func allowsLayoutAdjustment(usesNativeAccessoryChrome: Bool) -> Bool {
        !usesNativeAccessoryChrome
    }
}

struct PulsarWorkoutMiniPlayerView: View {
    let state: PulsarWorkoutMiniPlayerState
    let usesNativeAccessoryChrome: Bool
    @ObservedObject var layoutController: PulsarBottomChromeLayoutController
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLiveIndicatorPulsing = false

    var body: some View {
        layoutAdjustableContent
            // Bottom accessories have a system-constrained height; cap visual
            // scaling while preserving the complete VoiceOver summary.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    @ViewBuilder
    private var layoutAdjustableContent: some View {
        if PulsarWorkoutMiniPlayerInteractionPolicy.allowsLayoutAdjustment(
            usesNativeAccessoryChrome: usesNativeAccessoryChrome
        ) {
            workoutButton
                .highPriorityGesture(layoutGesture)
                .accessibilityAction(named: Text("Collapse workout bar")) {
                    layoutController.commit(.compact, reduceMotion: reduceMotion)
                }
                .accessibilityAction(named: Text("Expand workout bar")) {
                    layoutController.commit(.expanded, reduceMotion: reduceMotion)
                }
        } else {
            workoutButton
        }
    }

    private var workoutButton: some View {
        Button(action: onOpen) {
            content
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilitySummary)
        .accessibilityHint("Opens the live workout")
        .accessibilityAction(named: Text("Open live workout"), onOpen)
    }

    private var content: some View {
        HStack(spacing: interpolated(expanded: 11, compact: 8)) {
            statusIndicator

            Image(systemName: state.symbol)
                .font(.system(
                    layoutController.effectiveLayout == .compact ? .body : .title3,
                    design: .rounded,
                    weight: .semibold
                ))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(state.accentColor)
                .frame(width: interpolated(expanded: 30, compact: 22))
                .accessibilityHidden(true)

            if layoutController.effectiveLayout == .compact {
                compactContent
                    .transition(.opacity)
            } else {
                expandedContent
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, interpolated(expanded: 12, compact: 9))
        .frame(minWidth: 1, maxWidth: .infinity)
        .frame(height: interpolated(
            expanded: PulsarWorkoutMiniPlayerSizing.expandedContentHeight,
            compact: PulsarWorkoutMiniPlayerSizing.compactContentHeight
        ))
        .contentShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .modifier(PulsarBottomChromeGlassModifier(
            cornerRadius: cornerRadius,
            usesNativeAccessoryChrome: usesNativeAccessoryChrome
        ))
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.88), value: layoutController.effectiveLayout)
    }

    private var statusIndicator: some View {
        Circle()
            .fill(state.status.color)
            .frame(width: 8, height: 8)
            .shadow(color: state.status.color.opacity(state.status == .live ? 0.9 : 0.35), radius: 5)
            .scaleEffect(state.status == .live && isLiveIndicatorPulsing ? 1.18 : 0.86)
            .opacity(state.status == .paused ? 0.75 : 1)
            .onAppear {
                synchronizeLiveIndicatorPulse()
            }
            .onDisappear {
                isLiveIndicatorPulsing = false
            }
            .onChange(of: state.status) { _, _ in
                synchronizeLiveIndicatorPulse()
            }
            .onChange(of: scenePhase) { _, _ in
                synchronizeLiveIndicatorPulse()
            }
            .onChange(of: reduceMotion) { _, _ in
                synchronizeLiveIndicatorPulse()
            }
            .accessibilityHidden(true)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.title)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.82)

            HStack(spacing: 5) {
                Text(state.status.label)
                    .foregroundStyle(state.status == .live ? state.status.color : .primary)

                separator

                Text(state.elapsedText)
                    .monospacedDigit()

                ForEach(state.secondaryMetrics.prefix(2)) { metric in
                    separator
                    Text(metric.value)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private var compactContent: some View {
        HStack(spacing: 4) {
            Text(state.title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)

            separator

            Text(state.elapsedText)
                .monospacedDigit()

            if let compactMetric = state.compactMetric {
                separator
                Text(compactMetric.value)
            }
        }
        .font(.system(.footnote, design: .rounded))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private var separator: some View {
        Text("•")
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private var cornerRadius: CGFloat {
        interpolated(expanded: 29, compact: 22)
    }

    private func interpolated(expanded: CGFloat, compact: CGFloat) -> CGFloat {
        expanded + (compact - expanded) * layoutController.visualProgress
    }

    private func synchronizeLiveIndicatorPulse() {
        let shouldPulse = state.status == .live && scenePhase == .active && !reduceMotion
        guard shouldPulse != isLiveIndicatorPulsing else { return }

        if shouldPulse {
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                isLiveIndicatorPulsing = true
            }
        } else {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                isLiveIndicatorPulsing = false
            }
        }
    }

    private var layoutGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                layoutController.updateDrag(translation: value.translation.height)
            }
            .onEnded { value in
                layoutController.endDrag(
                    translation: value.translation.height,
                    predictedTranslation: value.predictedEndTranslation.height,
                    reduceMotion: reduceMotion
                )
            }
    }
}
