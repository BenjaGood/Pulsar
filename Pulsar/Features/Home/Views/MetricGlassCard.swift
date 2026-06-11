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
    @State private var displayedProgress = 0.0

    private var tint: Color { PulsarMetricRingTheme.tint(for: metric) }
    private var progress: Double { ScoreMath.clamp(Double(score) / 100) }
    private var hasValue: Bool { score > 0 || showsZeroValue }
    private var scoreText: String { hasValue ? "\(score)" : metric == .sleep ? "-" : "--" }
    private var resolvedStatus: String { hasValue ? status : metric == .sleep ? "No data" : "Unavailable" }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let ringSize = max(82, min(94, width * 0.70))

            PremiumGlassContainer(cornerRadius: 28, tint: tint, isInteractive: true) {
                VStack(spacing: 0) {
                    ring(size: ringSize)
                        .frame(width: ringSize, height: ringSize)
                        .padding(.top, 15)
                        .padding(.bottom, 15)

                    Text(title.uppercased())
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(appearance.secondaryText.opacity(hasValue ? 1 : 0.76))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)

                    Text(scoreText)
                        .font(.system(size: max(36, min(46, width * 0.33)), weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(appearance.primaryText.opacity(hasValue ? 1 : 0.52))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .padding(.top, 8)

                    Text(resolvedStatus)
                        .font(statusFont(width: width))
                        .foregroundStyle(hasValue ? tint : tint.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .padding(.top, 0)

                    Text(description)
                        .font(.system(size: max(11, min(15, width * 0.108)), weight: .regular, design: .rounded))
                        .foregroundStyle(appearance.secondaryText.opacity(hasValue ? 0.92 : 0.68))
                        .multilineTextAlignment(.center)
                        .lineLimit(hasValue ? 2 : 3)
                        .minimumScaleFactor(0.72)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, max(8, width * 0.08))
                        .padding(.top, 12)
                        .padding(.bottom, 15)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .task { animateProgress() }
        .onChange(of: score) { _, _ in animateProgress() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(scoreText), \(resolvedStatus), \(description)")
    }

    private func ring(size: CGFloat) -> some View {
        let lineWidth = max(4.8, min(5.5, size * 0.058))

        return ZStack {
            Circle()
                .stroke(appearance.metricRecessColor, lineWidth: lineWidth * 2.15)
                .blur(radius: 0.6)

            Circle()
                .stroke(tint.opacity(hasValue ? 0.055 : 0.030), lineWidth: lineWidth * 1.42)
                .blur(radius: 3)

            Circle()
                .stroke(appearance.metricTrackColor, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: hasValue ? displayedProgress : 0.16)
                .stroke(
                    AngularGradient(
                        colors: PulsarMetricRingTheme.progressColors(tint: tint),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
                .opacity(hasValue ? 1 : 0.18)
                .shadow(color: tint.opacity(hasValue ? 0.26 : 0.06), radius: hasValue ? 8 : 4, y: 3)

            Circle()
                .trim(from: 0.015, to: hasValue ? min(displayedProgress, 0.16) : 0)
                .stroke(.white.opacity(hasValue ? 0.08 : 0), style: StrokeStyle(lineWidth: lineWidth * 0.18, lineCap: .round))
                .rotationEffect(.degrees(-86))
                .blur(radius: 0.5)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(appearance.usesLightText ? 0.080 : 0.175),
                            tint.opacity(hasValue ? 0.130 : 0.040),
                            Color.black.opacity(appearance.metricCenterBlackOpacity)
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: size * 0.42
                    )
                )
                .frame(width: size * 0.53, height: size * 0.53)
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(appearance.usesLightText ? 0.20 : 0.34), tint.opacity(0.16), .white.opacity(appearance.usesLightText ? 0.04 : 0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                }
                .shadow(color: tint.opacity(hasValue ? 0.18 : 0.045), radius: 13)

            Image(systemName: icon)
                .font(.system(size: size * 0.235, weight: .semibold, design: .rounded))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(hasValue ? tint : tint.opacity(0.58))
                .shadow(color: tint.opacity(hasValue ? 0.18 : 0.04), radius: 4)
        }
    }

    private func statusFont(width: CGFloat) -> Font {
        if hasValue {
            return .system(size: max(15, min(17, width * 0.13)), weight: .medium, design: .rounded)
        }
        return .system(size: max(13, min(15, width * 0.13)), weight: .medium, design: .rounded)
    }

    private func animateProgress() {
        displayedProgress = 0
        if reduceMotion {
            displayedProgress = progress
        } else {
            withAnimation(.spring(response: 0.86, dampingFraction: 0.86)) {
                displayedProgress = progress
            }
        }
    }
}

#Preview("Metric Glass Cards") {
    ZStack {
        StaticTimeBackgroundView(mode: .sunset)
        HStack(spacing: 12) {
            PremiumGlassMetricCard(title: "Sleep", score: 87, status: "Optimal", description: "You slept well last night.", icon: "moon.zzz.fill", metric: .sleep)
            PremiumGlassMetricCard(title: "Recovery", score: 82, status: "Good", description: "Your body is recovering well.", icon: "leaf.fill", metric: .recovery)
            PremiumGlassMetricCard(title: "Strain", score: 65, status: "Moderate", description: "Training load is in a good range.", icon: "figure.run", metric: .strain)
        }
        .frame(height: 250)
        .padding(20)
    }
}
