//
//  StressGaugeView.swift
//  Pulsar
//

import SwiftUI

struct PremiumStressGaugeView: View {
    var summary: StressSummary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.homeAdaptiveAppearance) private var appearance
    @State private var animatedProgress = 0.0

    private let startAngle = 164.0
    private let endAngle = 376.0

    private var progress: Double {
        ScoreMath.clamp((summary.currentScore ?? 0) / 100)
    }

    private var tint: Color {
        stressGaugeTint(for: summary.score)
    }

    private var markerTint: Color {
        StressGaugePalette.color(at: progress)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let gaugeSize = min(width * 0.86, height / 0.72)
            let lineWidth = max(2.5, gaugeSize * 0.016)
            let arcRadius = gaugeSize / 2 - lineWidth / 2

            ZStack {
                gaugeGlow(size: gaugeSize)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(appearance.usesLightText ? 0.045 : 0.120),
                                Color.black.opacity(appearance.usesLightText ? 0.025 : 0.000),
                                .clear
                            ],
                            center: .center,
                            startRadius: gaugeSize * 0.10,
                            endRadius: gaugeSize * 0.50
                        )
                    )
                    .frame(width: gaugeSize * 0.82, height: gaugeSize * 0.82)
                    .blur(radius: 1)

                StressGaugeArc(startAngle: startAngle, endAngle: endAngle, inset: lineWidth / 2, progress: 1)
                    .stroke(appearance.metricRecessColor.opacity(0.62), style: StrokeStyle(lineWidth: lineWidth * 1.45, lineCap: .round, lineJoin: .round))
                    .frame(width: gaugeSize, height: gaugeSize)

                StressGaugeArc(startAngle: startAngle, endAngle: endAngle, inset: lineWidth / 2, progress: 1)
                    .stroke(appearance.metricTrackColor.opacity(0.72), style: StrokeStyle(lineWidth: lineWidth * 0.85, lineCap: .round, lineJoin: .round))
                    .frame(width: gaugeSize, height: gaugeSize)

                StressGaugeArc(startAngle: startAngle, endAngle: endAngle, inset: lineWidth / 2, progress: 1)
                    .stroke(
                        AngularGradient(
                            stops: StressGaugePalette.gradientStops,
                            center: .center,
                            startAngle: .degrees(startAngle),
                            endAngle: .degrees(endAngle)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )
                    .opacity(summary.score == nil ? 0.16 : 0.76)
                    .frame(width: gaugeSize, height: gaugeSize)
                    .shadow(color: markerTint.opacity(summary.score == nil ? 0 : 0.07), radius: 4)

                tickMarks(size: gaugeSize, lineWidth: lineWidth)

                if summary.score != nil {
                    marker(size: gaugeSize, radius: arcRadius, lineWidth: lineWidth)
                }

                centerContent(size: gaugeSize)
            }
            .frame(width: gaugeSize, height: gaugeSize)
            .position(x: width / 2, y: gaugeSize / 2 + 2)
            .animation(reduceMotion ? nil : .spring(duration: 0.72, bounce: 0.10), value: summary.score)
        }
        .aspectRatio(1.42, contentMode: .fit)
        .task { animate() }
        .onChange(of: summary.score) { _, _ in animate() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stress, \(summary.displayScoreText), \(displayLevelText), \(summary.confidence.shortLabel)")
    }

    private func gaugeGlow(size: CGFloat) -> some View {
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            markerTint.opacity(summary.score == nil ? 0.015 : 0.032),
                            markerTint.opacity(summary.score == nil ? 0.005 : 0.010),
                            .clear
                        ],
                        center: .center,
                        startRadius: size * 0.10,
                        endRadius: size * 0.54
                    )
                )
                .frame(width: size * 1.02, height: size * 1.02)

        }
        .blur(radius: 8)
        .frame(width: size, height: size)
    }

    private func tickMarks(size: CGFloat, lineWidth: CGFloat) -> some View {
        let tickCount = 49
        let arcRadius = size / 2 - lineWidth / 2
        let tickLength = lineWidth * 0.72
        let tickWidth = max(0.55, lineWidth * 0.15)
        let tickGap = lineWidth * 0.48
        let tickRadius = arcRadius + lineWidth / 2 + tickGap + tickLength / 2

        return ZStack {
            ForEach(0..<tickCount, id: \.self) { index in
                let fraction = Double(index) / Double(tickCount - 1)
                let angle = startAngle + (endAngle - startAngle) * fraction
                let tickColor = StressGaugePalette.color(at: fraction)
                Capsule(style: .continuous)
                    .fill(tickColor.opacity(summary.score == nil ? 0.07 : 0.20))
                    .frame(width: tickWidth, height: tickLength)
                    .position(point(angle: angle, radius: tickRadius, size: size))
                    .rotationEffect(.degrees(angle + 90))
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    private func marker(size: CGFloat, radius: CGFloat, lineWidth: CGFloat) -> some View {
        let angle = startAngle + (endAngle - startAngle) * animatedProgress
        let markerSize = max(7, lineWidth * 1.65)

        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.96), .white.opacity(0.76)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .strokeBorder(.white.opacity(0.72), lineWidth: max(0.55, markerSize * 0.07))

            Circle()
                .fill(markerTint)
                .frame(width: markerSize * 0.38, height: markerSize * 0.38)
        }
            .frame(width: markerSize, height: markerSize)
            .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
            .shadow(color: markerTint.opacity(0.14), radius: 4)
            .position(point(angle: angle, radius: radius, size: size))
            .frame(width: size, height: size)
    }

    private func centerContent(size: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(summary.displayScoreText)
                .font(scoreFont(size: size))
                .foregroundStyle(appearance.primaryText.opacity(summary.score == nil ? 0.74 : 1))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.48)
                .contentTransition(.numericText(value: summary.currentScore ?? 0))

            Text(displayLevelText)
                .font(.subheadline)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
                .contentTransition(.opacity)
        }
        .frame(width: size * 0.54)
        .padding(.top, size * 0.015)
    }

    private func scoreFont(size: CGFloat) -> Font {
        if summary.score == nil {
            return .system(size: max(21, size * 0.11), weight: .medium, design: .rounded)
        }

        return .system(size: max(48, size * 0.27), weight: .light, design: .rounded)
    }

    private var displayLevelText: String {
        summary.displayLevelText
    }

    private func animate() {
        let target = progress
        guard abs(animatedProgress - target) > 0.001 else { return }

        if reduceMotion {
            animatedProgress = target
        } else {
            withAnimation(.spring(duration: 0.72, bounce: 0.10)) {
                animatedProgress = target
            }
        }
    }

    private func point(angle: Double, radius: CGFloat, size: CGFloat) -> CGPoint {
        let radians = angle * .pi / 180
        let center = CGPoint(x: size / 2, y: size / 2)
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * radius,
            y: center.y + CGFloat(sin(radians)) * radius
        )
    }

}

fileprivate enum StressGaugePalette {
    static let green = Color(red: 0.38, green: 0.76, blue: 0.61)
    static let lime = Color(red: 0.57, green: 0.80, blue: 0.51)
    static let yellow = Color(red: 0.88, green: 0.76, blue: 0.40)
    static let orange = Color(red: 0.92, green: 0.58, blue: 0.31)
    static let red = Color(red: 0.86, green: 0.39, blue: 0.36)

    static let gradientStops: [Gradient.Stop] = [
        .init(color: green, location: 0.00),
        .init(color: lime, location: 0.30),
        .init(color: yellow, location: 0.55),
        .init(color: orange, location: 0.76),
        .init(color: red, location: 1.00)
    ]

    private static let rgbStops: [(location: Double, red: Double, green: Double, blue: Double)] = [
        (0.00, 0.38, 0.76, 0.61),
        (0.30, 0.57, 0.80, 0.51),
        (0.55, 0.88, 0.76, 0.40),
        (0.76, 0.92, 0.58, 0.31),
        (1.00, 0.86, 0.39, 0.36)
    ]

    static func color(at fraction: Double) -> Color {
        let value = ScoreMath.clamp(fraction)
        guard let upperIndex = rgbStops.firstIndex(where: { value <= $0.location }) else {
            return red
        }

        if upperIndex == 0 {
            return color(from: rgbStops[0])
        }

        let lower = rgbStops[upperIndex - 1]
        let upper = rgbStops[upperIndex]
        let span = max(upper.location - lower.location, 0.0001)
        let amount = (value - lower.location) / span
        return Color(
            red: lower.red + (upper.red - lower.red) * amount,
            green: lower.green + (upper.green - lower.green) * amount,
            blue: lower.blue + (upper.blue - lower.blue) * amount
        )
    }

    private static func color(from stop: (location: Double, red: Double, green: Double, blue: Double)) -> Color {
        Color(red: stop.red, green: stop.green, blue: stop.blue)
    }
}

private struct StressGaugeArc: Shape {
    var startAngle: Double
    var endAngle: Double
    var inset: CGFloat
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard progress > 0 else { return path }

        let radius = min(rect.width, rect.height) / 2 - inset
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let end = startAngle + (endAngle - startAngle) * ScoreMath.clamp(progress)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(end),
            clockwise: false
        )
        return path
    }
}

func stressGaugeTint(for score: Int?) -> Color {
    guard let score else {
        return Color(red: 0.56, green: 0.64, blue: 0.76)
    }
    switch PulsarStressCategory.category(for: score) {
    case .low:
        return Color(red: 0.16, green: 0.53, blue: 0.43)
    case .balanced:
        return Color(red: 0.34, green: 0.52, blue: 0.30)
    case .elevated:
        return Color(red: 0.76, green: 0.40, blue: 0.12)
    case .high:
        return Color(red: 0.73, green: 0.25, blue: 0.23)
    }
}

#Preview("Stress Gauge") {
    ZStack {
        HomePremiumDesign.background
        PremiumStressGaugeView(summary: MockHealthData.stressPreviewSummary(score: 25))
            .frame(width: 320, height: 320)
            .padding()
    }
    .environment(\.homeAdaptiveAppearance, .premium)
}
