//
//  PulsarCollapsingHeaderBar.swift
//  Pulsar
//

import SwiftUI

enum PulsarCollapsingHeaderMetrics {
    static let compactContentHeight: CGFloat = 44
    static let transitionDistance: CGFloat = 50
    static let hitTestThreshold: CGFloat = 0.6
    static let scrimFadeTailHeight: CGFloat = 28
    static let progressSteps: CGFloat = 120
}

struct PulsarHeaderItem: Identifiable {
    let id = UUID()
    var pinned: Bool = false
    var accessibilityLabel: String
    var action: () -> Void
    var systemImage: String?
    var customView: AnyView?

    static func systemImage(
        _ name: String,
        accessibilityLabel: String,
        pinned: Bool = false,
        action: @escaping () -> Void
    ) -> PulsarHeaderItem {
        PulsarHeaderItem(
            pinned: pinned,
            accessibilityLabel: accessibilityLabel,
            action: action,
            systemImage: name,
            customView: nil
        )
    }

    static func custom<V: View>(
        accessibilityLabel: String,
        pinned: Bool = false,
        action: @escaping () -> Void = {},
        @ViewBuilder content: () -> V
    ) -> PulsarHeaderItem {
        PulsarHeaderItem(
            pinned: pinned,
            accessibilityLabel: accessibilityLabel,
            action: action,
            systemImage: nil,
            customView: AnyView(content())
        )
    }
}

struct PulsarScreenHeaderConfiguration {
    var title: String
    var titleAccessibilityLabel: String?
    var titleAction: (() -> Void)?
    var leading: PulsarHeaderItem?
    var trailing: [PulsarHeaderItem]

    init(
        title: String,
        titleAccessibilityLabel: String? = nil,
        titleAction: (() -> Void)? = nil,
        leading: PulsarHeaderItem? = nil,
        trailing: [PulsarHeaderItem] = []
    ) {
        self.title = title
        self.titleAccessibilityLabel = titleAccessibilityLabel
        self.titleAction = titleAction
        self.leading = leading
        self.trailing = trailing
    }
}

enum PulsarCollapsingHeaderProgress {
    static func value(
        scrollOffset: CGFloat,
        expandedHeaderHeight: CGFloat
    ) -> CGFloat {
        let triggerStart = max(0, expandedHeaderHeight - PulsarCollapsingHeaderMetrics.compactContentHeight)
        let distance = PulsarCollapsingHeaderMetrics.transitionDistance
        guard distance > 0 else { return scrollOffset > triggerStart ? 1 : 0 }
        return min(max((scrollOffset - triggerStart) / distance, 0), 1)
    }
}

@MainActor
@Observable
final class PulsarCollapsingHeaderProgressModel {
    var progress: CGFloat = 0
}

struct PulsarCollapsingHeaderBar: View {
    var configuration: PulsarScreenHeaderConfiguration
    var progress: CGFloat
    var safeAreaTop: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            PulsarCollapsingHeaderScrim(
                safeAreaTop: safeAreaTop,
                progress: scrimProgress
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            ZStack {
                titleView

                HStack(spacing: 8) {
                    leadingSlot
                    Spacer(minLength: 0)
                    trailingSlot
                }
            }
            .padding(.horizontal, 16)
            .frame(height: PulsarCollapsingHeaderMetrics.compactContentHeight)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var leadingSlot: some View {
        if let leading = configuration.leading {
            headerItemButton(leading)
                .frame(width: 44, height: 44)
        } else {
            Color.clear
                .frame(width: 44, height: 44)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var trailingSlot: some View {
        HStack(spacing: 8) {
            ForEach(configuration.trailing) { item in
                headerItemButton(item)
            }
        }
        .frame(minWidth: 44, alignment: .trailing)
    }

    @ViewBuilder
    private var titleView: some View {
        let titleOpacity = Double(progress)
        let drift = reduceMotion ? 0.0 : (1 - progress) * 4

        Group {
            if let titleAction = configuration.titleAction {
                Button(action: titleAction) {
                    titleLabel
                }
                .buttonStyle(.plain)
            } else {
                titleLabel
            }
        }
        .opacity(titleOpacity)
        .offset(y: -drift)
        .padding(.horizontal, 56)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(progress <= 0.05)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(configuration.titleAccessibilityLabel ?? configuration.title)
        .allowsHitTesting(
            configuration.titleAction != nil
                && progress > PulsarCollapsingHeaderMetrics.hitTestThreshold
        )
    }

    private var titleLabel: some View {
        Text(configuration.title)
            .pulsarTextStyle(.sectionHeader)
            .foregroundStyle(primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    @ViewBuilder
    private func headerItemButton(_ item: PulsarHeaderItem) -> some View {
        let itemProgress = item.pinned ? 1 : progress
        let opacity = Double(itemProgress)
        let scale = reduceMotion ? 1.0 : (0.9 + 0.1 * itemProgress)
        let isInteractive = item.pinned || progress > PulsarCollapsingHeaderMetrics.hitTestThreshold

        Button(action: item.action) {
            itemLabel(item)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .opacity(opacity)
        .scaleEffect(scale)
        .allowsHitTesting(isInteractive)
        .accessibilityHidden(!isInteractive)
        .accessibilityLabel(item.accessibilityLabel)
    }

    @ViewBuilder
    private func itemLabel(_ item: PulsarHeaderItem) -> some View {
        if let customView = item.customView {
            customView
        } else if let systemImage = item.systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(primaryText)
                .frame(width: 44, height: 44)
                .background {
                    PulsarCircularGlassSurface(cornerRadius: 22)
                }
        }
    }

    private var scrimProgress: CGFloat {
        let shifted = (progress - 0.25) / 0.75
        return min(max(shifted, 0), 1)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color(red: 0.07, green: 0.10, blue: 0.14)
    }
}

struct PulsarCollapsingHeaderScrim: View {
    var safeAreaTop: CGFloat
    var progress: CGFloat

    var body: some View {
        PulsarTopBlurOverlay(
            height: PulsarCollapsingHeaderMetrics.compactContentHeight
                + PulsarCollapsingHeaderMetrics.scrimFadeTailHeight,
            safeAreaTop: safeAreaTop,
            solidContentHeight: PulsarCollapsingHeaderMetrics.compactContentHeight,
            style: .collapsingHeader
        )
        .opacity(Double(progress))
        .frame(
            height: safeAreaTop
                + PulsarCollapsingHeaderMetrics.compactContentHeight
                + PulsarCollapsingHeaderMetrics.scrimFadeTailHeight
        )
        .frame(maxWidth: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .top)
    }
}

struct PulsarCollapsingHeaderScrollModifier: ViewModifier {
    var expandedHeaderHeight: CGFloat
    var progressModel: PulsarCollapsingHeaderProgressModel

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                let offset = max(0, geometry.contentOffset.y + geometry.contentInsets.top)
                return PulsarCollapsingHeaderProgress.value(
                    scrollOffset: offset,
                    expandedHeaderHeight: expandedHeaderHeight
                )
            } action: { _, newProgress in
                let quantizedProgress = (
                    newProgress * PulsarCollapsingHeaderMetrics.progressSteps
                ).rounded() / PulsarCollapsingHeaderMetrics.progressSteps

                if progressModel.progress != quantizedProgress {
                    progressModel.progress = quantizedProgress
                }
            }
    }
}

struct PulsarCollapsingHeaderBarHost: View {
    var configuration: PulsarScreenHeaderConfiguration
    var safeAreaTop: CGFloat
    var progressModel: PulsarCollapsingHeaderProgressModel

    var body: some View {
        PulsarCollapsingHeaderBar(
            configuration: configuration,
            progress: progressModel.progress,
            safeAreaTop: safeAreaTop
        )
    }
}

struct PulsarScrollEdgeTopEffectModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

extension View {
    func pulsarCollapsingHeaderProgress(
        expandedHeaderHeight: CGFloat,
        progressModel: PulsarCollapsingHeaderProgressModel
    ) -> some View {
        modifier(
            PulsarCollapsingHeaderScrollModifier(
                expandedHeaderHeight: expandedHeaderHeight,
                progressModel: progressModel
            )
        )
    }
}
