//
//  PulsarGlassStyle.swift
//  Pulsar
//

import SwiftUI

extension View {
    @ViewBuilder
    func pulsarLiquidGlass(cornerRadius: CGFloat = 28) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
    var body: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
    }
}

struct PulsarTopBlurOverlay: View {
    var height: CGFloat = 56
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(tintGradient)
                .frame(height: proxy.safeAreaInsets.top + height)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black.opacity(0.96), location: 0.56),
                            .init(color: .black.opacity(0.0), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
        }
    }

    private var tintGradient: LinearGradient {
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
                    .font(.headline)
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
