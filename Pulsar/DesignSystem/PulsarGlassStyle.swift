//
//  PulsarGlassStyle.swift
//  Pulsar
//

import SwiftUI

extension View {
    @ViewBuilder
    func pulsarLiquidGlass(
        cornerRadius: CGFloat = 28,
        tint: Color? = nil,
        interactive: Bool = false,
        isClear: Bool = false
    ) -> some View {
        if #available(iOS 26.0, *) {
            let glass = isClear ? Glass.clear : .regular
            self.glassEffect(
                glass
                    .tint(tint)
                    .interactive(interactive),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
        }
    }

  @available(*, deprecated, message: "Use PulsarScreenScaffold header: configuration with expandedHeader: instead.")
    func premiumScrollHeaderBlur(
        height: CGFloat = 56,
        fadeStart: CGFloat = 8,
        fadeEnd: CGFloat = 40
    ) -> some View {
        modifier(
            PulsarScrollAwareTopBlurModifier(
                height: height,
                fadeStart: fadeStart,
                fadeEnd: fadeEnd
            )
        )
    }
}

struct PulsarGlassEffectGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: () -> Content

    init(spacing: CGFloat = 20, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

private struct PulsarScrollAwareTopBlurModifier: ViewModifier {
    var height: CGFloat
    var fadeStart: CGFloat
    var fadeEnd: CGFloat

    @State private var scrollOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                let normalizedOffset = max(0, geometry.contentOffset.y + geometry.contentInsets.top)
                return min(normalizedOffset, fadeEnd)
            } action: { _, newValue in
                scrollOffset = newValue
            }
            .overlay(alignment: .top) {
                PulsarTopBlurOverlay(height: min(height, 64))
                    .opacity(blurOpacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }

    private var blurOpacity: Double {
        guard fadeEnd > fadeStart else {
            return scrollOffset > fadeStart ? 1 : 0
        }

        let progress = (scrollOffset - fadeStart) / (fadeEnd - fadeStart)
        return Double(min(max(progress, 0), 1))
    }
}

struct PulsarSectionBackground: View {
    @Environment(\.pulsarFitnessUsesMonochromeAppearance) private var usesFitnessMonochromeAppearance

    var body: some View {
        if usesFitnessMonochromeAppearance {
            PulsarFitnessMonochromeBackground()
        } else {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        }
    }
}

enum PulsarTopBlurOverlayStyle {
    case legacy
    case collapsingHeader
}

struct PulsarTopBlurOverlay: View {
    var height: CGFloat = 56
    var safeAreaTop: CGFloat = 0
    var solidContentHeight: CGFloat = 0
    var style: PulsarTopBlurOverlayStyle = .legacy
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    var body: some View {
        switch style {
        case .legacy:
            legacyOverlay
        case .collapsingHeader:
            collapsingHeaderOverlay
        }
    }

    private var legacyOverlay: some View {
        GeometryReader { proxy in
            Group {
                if reduceTransparency {
                    Rectangle()
                        .fill(Color(.systemBackground).opacity(0.98))
                } else {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(tintGradient)
                }
            }
            .frame(height: proxy.safeAreaInsets.top + height)
            .mask(maskGradient)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
        }
    }

    private var collapsingHeaderOverlay: some View {
        Group {
            if reduceTransparency {
                Rectangle()
                    .fill(Color(.systemBackground).opacity(0.94))
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(tintGradient)
            }
        }
        .frame(height: collapsingHeaderTotalHeight)
        .mask(collapsingHeaderMaskGradient)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var maskGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0.0),
                .init(color: .black.opacity(0.96), location: 0.56),
                .init(color: .black.opacity(0.0), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var collapsingHeaderMaskGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: collapsingHeaderSolidStop),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var collapsingHeaderTotalHeight: CGFloat {
        safeAreaTop + height
    }

    private var collapsingHeaderSolidStop: CGFloat {
        guard collapsingHeaderTotalHeight > 0 else { return 1 }
        return min(
            max((safeAreaTop + solidContentHeight) / collapsingHeaderTotalHeight, 0),
            1
        )
    }

    private var tintGradient: LinearGradient {
        switch style {
        case .legacy:
            let colors: [Color] = colorScheme == .dark
                ? [
                    Color.black.opacity(0.34),
                    Color(red: 0.12, green: 0.08, blue: 0.20).opacity(0.18),
                    Color.black.opacity(0.0)
                ]
                : [
                    Color.white.opacity(0.54),
                    Color(red: 0.94, green: 0.95, blue: 0.99).opacity(0.22),
                    Color.white.opacity(0.0)
                ]
            return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        case .collapsingHeader:
            let colors: [Color] = colorScheme == .dark
                ? [
                    Color.black.opacity(0.22),
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.0)
                ]
                : [
                    Color.white.opacity(0.36),
                    Color.white.opacity(0.12),
                    Color.white.opacity(0.0)
                ]
            return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        }
    }
}

struct PlaceholderMetricCard: View {
    var title: String
    var value: String
    var subtitle: String
    var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: symbol)
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(.tint)
                    .frame(width: 34, height: 34)
                    .background(.tint.opacity(0.12), in: Circle())
                Spacer()
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .pulsarTextStyle(.cardTitle)
                Text(value)
                    .pulsarMonospacedMetric(.metricValue)
                Text(subtitle)
                    .pulsarTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulsarLiquidGlass()
    }
}

#Preview("Metric Card") {
    PlaceholderMetricCard(title: "Sleep", value: "86", subtitle: "Strong night", symbol: "moon.zzz.fill")
        .padding()
        .background(PulsarSectionBackground())
}
