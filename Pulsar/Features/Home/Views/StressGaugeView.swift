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

    private let startAngle = 160.0
    private let endAngle = 380.0

    private var progress: Double {
        ScoreMath.clamp((summary.currentScore ?? 0) / 100)
    }

    private var tint: Color {
        stressGaugeTint(for: summary.score)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let containerSize = min(width, height)
            let gaugeSize = containerSize * 0.86
            let lineWidth = max(4.5, gaugeSize * 0.028)
            let arcRadius = gaugeSize / 2 - lineWidth / 2
            let yOffset = -containerSize * 0.012

            ZStack {
                gaugeGlow(size: gaugeSize, arcRadius: arcRadius)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(appearance.usesLightText ? 0.045 : 0.120),
                                Color.black.opacity(appearance.usesLightText ? 0.050 : 0.000),
                                .clear
                            ],
                            center: .center,
                            startRadius: gaugeSize * 0.10,
                            endRadius: gaugeSize * 0.50
                        )
                    )
                    .frame(width: gaugeSize * 0.82, height: gaugeSize * 0.82)
                    .blur(radius: 2)

                StressGaugeArc(startAngle: startAngle, endAngle: endAngle, inset: lineWidth / 2, progress: 1)
                    .stroke(Color.white.opacity(0.035), style: StrokeStyle(lineWidth: lineWidth * 1.80, lineCap: .round, lineJoin: .round))
                    .frame(width: gaugeSize, height: gaugeSize)

                StressGaugeArc(startAngle: startAngle, endAngle: endAngle, inset: lineWidth / 2, progress: 1)
                    .stroke(Color.white.opacity(0.070), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    .frame(width: gaugeSize, height: gaugeSize)

                StressGaugeArc(startAngle: startAngle, endAngle: endAngle, inset: lineWidth / 2, progress: 1)
                    .stroke(
                        AngularGradient(
                            stops: StressGaugePalette.gradientStops,
                            center: .center,
                            startAngle: .degrees(startAngle),
                            endAngle: .degrees(endAngle)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth * 0.78, lineCap: .round, lineJoin: .round)
                    )
                    .opacity(summary.score == nil ? 0.22 : 0.92)
                    .frame(width: gaugeSize, height: gaugeSize)
                    .mask {
                        StressGaugeArc(startAngle: startAngle, endAngle: endAngle, inset: lineWidth / 2, progress: summary.score == nil ? 1 : animatedProgress)
                            .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                            .frame(width: gaugeSize, height: gaugeSize)
                    }
                    .shadow(color: tint.opacity(summary.score == nil ? 0 : 0.24), radius: 9)

                tickMarks(size: gaugeSize, lineWidth: lineWidth)

                if summary.score != nil {
                    marker(size: gaugeSize, radius: arcRadius, lineWidth: lineWidth)
                }

                centerContent(size: gaugeSize)
            }
            .frame(width: gaugeSize, height: gaugeSize)
            .position(x: width / 2, y: height / 2 + yOffset)
        }
        .aspectRatio(1.0, contentMode: .fit)
        .task { animate() }
        .onChange(of: summary.score) { _, _ in animate() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stress, \(summary.displayScoreText), \(displayLevelText), \(summary.confidence.shortLabel)")
    }

    private func gaugeGlow(size: CGFloat, arcRadius: CGFloat) -> some View {
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            tint.opacity(summary.score == nil ? 0.06 : 0.16),
                            tint.opacity(summary.score == nil ? 0.02 : 0.048),
                            .clear
                        ],
                        center: .center,
                        startRadius: size * 0.10,
                        endRadius: size * 0.54
                    )
                )
                .frame(width: size * 1.02, height: size * 1.02)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [StressGaugePalette.green.opacity(0.26), StressGaugePalette.green.opacity(0.060), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: size * 0.18
                    )
                )
                .frame(width: size * 0.34, height: size * 0.34)
                .position(point(angle: startAngle + 10, radius: arcRadius, size: size))

            Circle()
                .fill(
                    RadialGradient(
                        colors: [StressGaugePalette.orange.opacity(0.20), StressGaugePalette.red.opacity(0.040), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: size * 0.18
                    )
                )
                .frame(width: size * 0.34, height: size * 0.34)
                .position(point(angle: endAngle - 10, radius: arcRadius, size: size))
        }
        .blur(radius: 17)
        .frame(width: size, height: size)
    }

    private func tickMarks(size: CGFloat, lineWidth: CGFloat) -> some View {
        let tickCount = 61
        let arcRadius = size / 2 - lineWidth / 2
        let tickLength = lineWidth * 0.52
        let tickWidth = max(0.8, lineWidth * 0.12)
        let tickGap = lineWidth * 0.34
        let tickRadius = arcRadius + lineWidth / 2 + tickGap + tickLength / 2

        return ZStack {
            ForEach(0..<tickCount, id: \.self) { index in
                let fraction = Double(index) / Double(tickCount - 1)
                let angle = startAngle + (endAngle - startAngle) * fraction
                let color = StressGaugePalette.color(at: fraction)

                Capsule(style: .continuous)
                    .fill(color.opacity(summary.score == nil ? 0.13 : 0.50))
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
        let markerSize = max(11, lineWidth * 1.24)

        return ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.98), .white.opacity(0.62)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .strokeBorder(.white.opacity(0.70), lineWidth: max(0.8, markerSize * 0.08))

            Circle()
                .fill(tint)
                .frame(width: markerSize * 0.48, height: markerSize * 0.48)

            Capsule(style: .continuous)
                .fill(.white.opacity(0.72))
                .frame(width: markerSize * 0.30, height: max(1, markerSize * 0.07))
                .offset(y: -markerSize * 0.20)
        }
            .frame(width: markerSize, height: markerSize)
            .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
            .shadow(color: tint.opacity(0.34), radius: 8)
            .position(point(angle: angle, radius: radius, size: size))
            .frame(width: size, height: size)
    }

    private func centerContent(size: CGFloat) -> some View {
        VStack(spacing: 7) {
            Text(summary.displayScoreText)
                .font(scoreFont(size: size))
                .foregroundStyle(appearance.primaryText.opacity(summary.score == nil ? 0.74 : 1))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.48)

            Text(displayLevelText)
                .font(.system(size: max(16, size * 0.075), weight: .medium, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
        .frame(width: size * 0.54)
        .padding(.top, size * 0.035)
    }

    private func scoreFont(size: CGFloat) -> Font {
        if summary.score == nil {
            return .system(size: max(22, size * 0.115), weight: .semibold, design: .rounded)
        }

        return .system(size: max(52, size * 0.255), weight: .light, design: .rounded)
    }

    private var displayLevelText: String {
        guard let score = summary.score else {
            return summary.displayLevelText
        }

        let boundedScore = max(0, min(100, score))

        switch boundedScore {
        case 0...33:
            return "Low"
        case 34...66:
            return "Medium"
        default:
            return "High"
        }
    }

    private func animate() {
        animatedProgress = 0
        if reduceMotion {
            animatedProgress = progress
        } else {
            withAnimation(.smooth(duration: 1.0)) {
                animatedProgress = progress
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
    static let green = Color(red: 0.42, green: 0.92, blue: 0.55)
    static let lime = Color(red: 0.70, green: 0.94, blue: 0.34)
    static let yellow = Color(red: 1.00, green: 0.80, blue: 0.28)
    static let orange = Color(red: 1.00, green: 0.56, blue: 0.18)
    static let red = Color(red: 1.00, green: 0.30, blue: 0.23)

    static let gradientStops: [Gradient.Stop] = [
        .init(color: green, location: 0.00),
        .init(color: lime, location: 0.30),
        .init(color: yellow, location: 0.55),
        .init(color: orange, location: 0.76),
        .init(color: red, location: 1.00)
    ]

    private static let rgbStops: [(location: Double, red: Double, green: Double, blue: Double)] = [
        (0.00, 0.42, 0.92, 0.55),
        (0.30, 0.70, 0.94, 0.34),
        (0.55, 1.00, 0.80, 0.28),
        (0.76, 1.00, 0.56, 0.18),
        (1.00, 1.00, 0.30, 0.23)
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

    switch score {
    case 0...33:
        return StressGaugePalette.green
    case 34...66:
        return StressGaugePalette.yellow
    default:
        return StressGaugePalette.red
    }
}

#Preview("Stress Gauge") {
    ZStack {
        StaticTimeBackgroundView(mode: .sunset)
        PremiumStressGaugeView(summary: MockHealthData.stressPreviewSummary(score: 25))
            .frame(width: 320, height: 320)
            .padding()
    }
}
