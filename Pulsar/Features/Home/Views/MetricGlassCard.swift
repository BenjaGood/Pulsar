//
//  MetricGlassCard.swift
//  Pulsar
//

import SwiftUI

struct PremiumGlassMetricCard: View {
    var title: String
    var score: Int
    var status: String
    var description: String
    var icon: String
    var metric: PulsarMetricRingKind
    var showsZeroValue = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.homeAdaptiveAppearance) private var appearance
    @ScaledMetric(relativeTo: .largeTitle) private var scoreFontSize: CGFloat = 40
    @State private var displayedProgress = 0.0

    private var tint: Color { PulsarMetricRingTheme.tint(for: metric) }
    private var progress: Double { ScoreMath.clamp(Double(score) / 100) }
    private var hasValue: Bool { score > 0 || showsZeroValue }
    private var scoreText: String { hasValue ? "\(score)" : metric == .sleep ? "–" : "––" }
    private var resolvedStatus: String { hasValue ? status : metric == .sleep ? "No data" : "Unavailable" }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let ringSize = max(74, min(82, width * 0.70))

            PremiumGlassContainer(cornerRadius: HomePremiumDesign.Radius.metricCard, tint: tint, isInteractive: true) {
                VStack(spacing: 0) {
                    metricRing(size: ringSize)
                        .frame(width: ringSize, height: ringSize)
                        .padding(.top, 10)

                    Text(title.uppercased())
                        .font(.caption.weight(.medium))
                        .tracking(0.45)
                        .foregroundStyle(appearance.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .padding(.top, 8)

                    Text(scoreText)
                        .font(.system(size: scoreFontSize, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(appearance.primaryText.opacity(hasValue ? 1 : 0.52))
                        .lineLimit(1)
                        .minimumScaleFactor(0.60)
                        .padding(.top, 1)

                    Text(resolvedStatus)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(hasValue ? tint : appearance.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    Spacer(minLength: 4)

                    Rectangle()
                        .fill(appearance.tertiaryText.opacity(0.14))
                        .frame(width: 28, height: 1)

                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(appearance.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(hasValue ? 3 : 2)
                        .minimumScaleFactor(0.76)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(1)
                        .padding(.horizontal, max(8, width * 0.07))
                        .padding(.top, 6)
                        .padding(.bottom, 10)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .task { animateProgress() }
        .onChange(of: score) { _, _ in animateProgress() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(scoreText), \(resolvedStatus), \(description)")
    }

    private func metricRing(size: CGFloat) -> some View {
        let lineWidth = max(4.5, min(5.5, size * 0.056))

        return ZStack {
            Circle()
                .stroke(appearance.metricRecessColor, lineWidth: lineWidth * 2.0)

            Circle()
                .stroke(appearance.metricTrackColor, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: hasValue ? displayedProgress : 0.14)
                .stroke(
                    tint.opacity(hasValue ? 0.96 : 0.20),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(Color.white.opacity(0.78))
                .frame(width: size * 0.56, height: size * 0.56)
                .overlay {
                    Circle().stroke(tint.opacity(0.12), lineWidth: 0.75)
                }
                .shadow(color: tint.opacity(0.08), radius: 10, y: 4)

            Image(systemName: icon)
                .font(.system(size: size * 0.245, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(hasValue ? tint : tint.opacity(0.52))
        }
    }

    private func animateProgress() {
        let target = progress
        guard abs(displayedProgress - target) > 0.001 else { return }

        if reduceMotion {
            displayedProgress = target
        } else {
            withAnimation(.smooth(duration: 0.82)) {
                displayedProgress = target
            }
        }
    }
}

#Preview("Metric Glass Cards") {
    HStack(spacing: 10) {
        PremiumGlassMetricCard(title: "Sleep", score: 87, status: "Optimal", description: "You slept well last night.", icon: "moon.zzz.fill", metric: .sleep)
        PremiumGlassMetricCard(title: "Recovery", score: 82, status: "Good", description: "Your body is recovering well.", icon: "leaf.fill", metric: .recovery)
        PremiumGlassMetricCard(title: "Strain", score: 65, status: "Moderate", description: "Training load is in a good range.", icon: "figure.run", metric: .strain)
    }
    .frame(height: 260)
    .padding(16)
    .background(HomePremiumDesign.background)
    .environment(\.homeAdaptiveAppearance, .premium)
}
