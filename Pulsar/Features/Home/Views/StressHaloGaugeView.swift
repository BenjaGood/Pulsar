//
//  StressHaloGaugeView.swift
//  Pulsar
//

import SwiftUI

struct StressHaloGaugeView: View {
    enum Style {
        case home
        case detail
    }

    var summary: StressSummary
    var style: Style = .home

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var animatedProgress = 0.0

    private let startAngle = 128.0
    private let endAngle = 412.0

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let ringWidth = size * (style == .detail ? 0.072 : 0.078)
            let radius = (size - ringWidth) / 2
            let tint = level.stressTint(colorScheme: colorScheme)
            let gradient = level.stressGradientColors(colorScheme: colorScheme)

            ZStack {
                haloGlow(size: size, tint: tint)

                StressHaloArc(progress: 1, startAngle: startAngle, endAngle: endAngle, inset: ringWidth / 2)
                    .stroke(trackStyle, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round, lineJoin: .round))
                    .frame(width: size, height: size)

                StressHaloArc(progress: animatedProgress, startAngle: startAngle, endAngle: endAngle, inset: ringWidth / 2)
                    .stroke(
                        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: tint.opacity(0.28), radius: size * 0.045)
                    .frame(width: size, height: size)

                particleLayer(size: size, radius: radius, ringWidth: ringWidth, tint: tint)

                if summary.currentScore != nil {
                    marker(size: size, radius: radius, ringWidth: ringWidth, tint: tint)
                }

                centerGlass(size: size, tint: tint)
                centerContent(size: size, tint: tint)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear(perform: animateToTarget)
        .onChange(of: targetProgress) { _, _ in animateToTarget() }
    }

    private var level: StressLevel {
        summary.level ?? .balanced
    }

    private var targetProgress: Double {
        ScoreMath.clamp((summary.currentScore ?? 0) / 100)
    }

    private var trackStyle: Color {
        Color.white.opacity(0.11)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color(red: 0.08, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color(red: 0.35, green: 0.39, blue: 0.47)
    }

    private func animateToTarget() {
        if reduceMotion {
            animatedProgress = targetProgress
            return
        }

        animatedProgress = 0
        withAnimation(.smooth(duration: style == .detail ? 1.15 : 0.9)) {
            animatedProgress = targetProgress
        }
    }

    private func haloGlow(size: CGFloat, tint: Color) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        tint.opacity(0.20),
                        tint.opacity(0.06),
                        .clear
                    ],
                    center: .center,
                    startRadius: size * 0.12,
                    endRadius: size * 0.58
                )
            )
            .blur(radius: size * 0.04)
            .frame(width: size * 1.02, height: size * 1.02)
    }

    private func centerGlass(size: CGFloat, tint: Color) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color.white.opacity(0.13),
                            tint.opacity(0.10),
                            Color.black.opacity(0.14)
                        ]
                        : [
                            Color.white.opacity(0.94),
                            tint.opacity(0.08),
                            Color.white.opacity(0.62)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.22 : 0.86),
                                tint.opacity(colorScheme == .dark ? 0.18 : 0.28),
                                Color.black.opacity(colorScheme == .dark ? 0.16 : 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: size * 0.055, y: size * 0.028)
            .frame(width: size * 0.60, height: size * 0.60)
    }

    private func centerContent(size: CGFloat, tint: Color) -> some View {
        VStack(spacing: style == .detail ? 8 : 5) {
            Text(summary.displayScoreText)
                .font(scoreFont(size: size))
                .foregroundStyle(primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.58)

            Text(summary.displayLevelText)
                .font(.system(size: size * (style == .detail ? 0.062 : 0.067), weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            if style == .detail, let updated = summary.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(width: size * 0.50)
    }

    private func scoreFont(size: CGFloat) -> Font {
        if summary.currentScore == nil {
            return .system(size: size * (style == .detail ? 0.088 : 0.094), weight: .bold, design: .rounded)
        }
        return .system(size: size * (style == .detail ? 0.18 : 0.19), weight: .bold, design: .rounded)
    }

    @ViewBuilder
    private func particleLayer(size: CGFloat, radius: CGFloat, ringWidth: CGFloat, tint: Color) -> some View {
        if summary.currentScore != nil {
            if reduceMotion {
                particles(size: size, radius: radius, ringWidth: ringWidth, tint: tint, phase: 0)
            } else {
                TimelineView(.animation) { timeline in
                    particles(
                        size: size,
                        radius: radius,
                        ringWidth: ringWidth,
                        tint: tint,
                        phase: timeline.date.timeIntervalSinceReferenceDate
                    )
                }
            }
        }
    }

    private func particles(size: CGFloat, radius: CGFloat, ringWidth: CGFloat, tint: Color, phase: TimeInterval) -> some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                let offset = Double(index) * 0.045
                let particleProgress = ScoreMath.clamp(animatedProgress - offset, 0, 1)
                let point = point(progress: particleProgress, radius: radius + ringWidth * 0.16, size: size)
                let pulse = reduceMotion ? CGFloat(1) : CGFloat(0.82 + sin(phase * 1.45 + Double(index) * 0.78) * 0.16)
                let particleSize = ringWidth * CGFloat(0.24 + Double(index % 2) * 0.06)
                Circle()
                    .fill(tint.opacity(colorScheme == .dark ? 0.38 : 0.26))
                    .frame(width: particleSize, height: particleSize)
                    .blur(radius: ringWidth * 0.04)
                    .scaleEffect(pulse)
                    .position(point)
                    .opacity(animatedProgress > 0.04 ? 1 - Double(index) * 0.13 : 0)
            }
        }
        .frame(width: size, height: size)
    }

    private func marker(size: CGFloat, radius: CGFloat, ringWidth: CGFloat, tint: Color) -> some View {
        let point = point(progress: animatedProgress, radius: radius, size: size)
        return Circle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.94) : Color.white)
            .frame(width: ringWidth * 0.84, height: ringWidth * 0.84)
            .overlay {
                Circle()
                    .fill(tint.opacity(0.88))
                    .frame(width: ringWidth * 0.44, height: ringWidth * 0.44)
            }
            .shadow(color: tint.opacity(0.36), radius: ringWidth * 1.15)
            .position(point)
            .frame(width: size, height: size)
    }

    private func point(progress: Double, radius: CGFloat, size: CGFloat) -> CGPoint {
        let angle = (startAngle + (endAngle - startAngle) * progress) * .pi / 180
        let center = CGPoint(x: size / 2, y: size / 2)
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * radius,
            y: center.y + CGFloat(sin(angle)) * radius
        )
    }

    private var accessibilityText: String {
        let value = summary.currentScore.map { "\(Int($0.rounded()))" } ?? summary.displayScoreText
        return "Stress, \(value), \(summary.displayLevelText), \(summary.confidence.shortLabel)"
    }
}

private struct StressHaloArc: Shape {
    var progress: Double
    var startAngle: Double
    var endAngle: Double
    var inset: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard progress > 0.0001 else { return path }
        let radius = max(0, min(rect.width, rect.height) / 2 - inset)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let clampedProgress = ScoreMath.clamp(progress, 0, 1)
        let resolvedEnd = startAngle + (endAngle - startAngle) * clampedProgress
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(resolvedEnd),
            clockwise: false
        )
        return path
    }
}

#Preview("Stress Halo - Elevated") {
    StressHaloGaugeView(summary: MockHealthData.stressSummary, style: .home)
        .frame(width: 220, height: 220)
        .padding()
        .background(PulsarSectionBackground())
}

#Preview("Stress Halo - Centered 86") {
    StressHaloGaugeView(summary: MockHealthData.stressPreviewSummary(score: 86), style: .home)
        .frame(width: 220, height: 220)
        .padding()
        .background(PulsarSectionBackground())
}
