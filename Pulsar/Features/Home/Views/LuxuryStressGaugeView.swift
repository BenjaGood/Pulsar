import SwiftUI

struct LuxuryStressGaugeView: View {
    var summary: StressSummary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var animatedProgress = 0.0
    @State private var lightSweep = -1.0

    /// The scale sweeps ~232 degrees like the reference speedometer: both
    /// ends dip below the horizontal so 0 and 100 tuck inside the dial.
    private let startAngle = -206.0
    private let endAngle = 26.0

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let radius = min(size.width * 0.5 - 10, size.height * 0.56)
            let center = CGPoint(x: size.width * 0.52, y: radius + max(4, size.height * 0.03))
            let lineWidth = min(6, max(4.5, radius * 0.058))

            ZStack {
                ambientGlow(center: center, radius: radius)

                gaugeArc(center: center, radius: radius)
                    .stroke(
                        .white.opacity(colorScheme == .dark ? 0.08 : 0.26),
                        style: StrokeStyle(lineWidth: lineWidth * 1.8, lineCap: .round)
                    )
                    .blur(radius: 2.2)

                gaugeArc(center: center, radius: radius)
                    .stroke(
                        AngularGradient(
                            stops: StressLuxuryGaugePalette.gradientStops,
                            center: UnitPoint(
                                x: center.x / size.width,
                                y: center.y / size.height
                            ),
                            startAngle: .degrees(startAngle),
                            endAngle: .degrees(endAngle)
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .opacity(summary.score == nil ? 0.18 : 0.94)

                gaugeArc(center: center, radius: radius)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.50), .white.opacity(0.06), .white.opacity(0.24)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: 0.7, lineCap: .round)
                    )
                    .blur(radius: 0.25)

                tickMarks(size: size, center: center, radius: radius, lineWidth: lineWidth)
                scaleLabels(size: size, center: center, radius: radius)
                crownTick(center: center, radius: radius, lineWidth: lineWidth)

                if summary.score != nil {
                    valueMarker(center: center, radius: radius, lineWidth: lineWidth)
                    pointer(size: size, center: center, radius: radius, lineWidth: lineWidth)
                }

                centerCopy(size: size, center: center, radius: radius)
            }
            .frame(width: size.width, height: size.height)
        }
        .task { animateToCurrentValue() }
        .onChange(of: summary.score) { _, _ in
            animateToCurrentValue()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stress gauge")
        .accessibilityValue("\(summary.displayScoreText), \(summary.displayLevelText)")
    }

    // MARK: - Arc

    private func gaugeArc(center: CGPoint, radius: CGFloat) -> Path {
        Path { path in
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(startAngle),
                endAngle: .degrees(endAngle),
                clockwise: false
            )
        }
    }

    private func ambientGlow(center: CGPoint, radius: CGFloat) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [.white.opacity(0.07), statusColor.opacity(0.02), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
            .frame(width: radius * 1.9, height: radius * 1.05)
            .position(x: center.x, y: center.y - radius * 0.30)
            .blur(radius: 10)
    }

    // MARK: - Ticks

    private func tickMarks(size: CGSize, center: CGPoint, radius: CGFloat, lineWidth: CGFloat) -> some View {
        ZStack {
            ForEach(0..<41, id: \.self) { index in
                let fraction = Double(index) / 40
                let angle = startAngle + (endAngle - startAngle) * fraction
                let isMajor = index.isMultiple(of: 10)
                let tickRadius = radius * 0.915
                let tickLength: CGFloat = isMajor ? 5.5 : 3.2

                Capsule()
                    .fill(tickColor.opacity(isMajor ? 0.26 : 0.11))
                    .frame(width: isMajor ? 1.0 : 0.6, height: tickLength)
                    .rotationEffect(.degrees(angle + 90))
                    .position(point(angle: angle, radius: tickRadius, center: center))
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private var tickColor: Color {
        colorScheme == .dark
            ? .white
            : Color(red: 0.42, green: 0.47, blue: 0.55)
    }

    // MARK: - Scale labels

    private func scaleLabels(size: CGSize, center: CGPoint, radius: CGFloat) -> some View {
        ZStack {
            gaugeLabel("0", angle: startAngle + 3, fraction: 0.83, center: center, radius: radius)
            gaugeLabel("50", angle: -90, fraction: 0.79, center: center, radius: radius)
            gaugeLabel("100", angle: endAngle - 3, fraction: 0.83, center: center, radius: radius)
        }
        .frame(width: size.width, height: size.height)
    }

    private func gaugeLabel(
        _ text: String,
        angle: Double,
        fraction: CGFloat,
        center: CGPoint,
        radius: CGFloat
    ) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(labelColor)
            .monospacedDigit()
            .position(point(angle: angle, radius: radius * fraction, center: center))
    }

    /// Small amber accent poking just past the crown of the arc at the 50 mark.
    private func crownTick(center: CGPoint, radius: CGFloat, lineWidth: CGFloat) -> some View {
        Capsule()
            .fill(Color(red: 0.94, green: 0.76, blue: 0.28))
            .frame(width: 2.8, height: lineWidth + 7)
            .position(point(angle: -90, radius: radius + 2, center: center))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var labelColor: Color {
        colorScheme == .dark
            ? .white.opacity(0.48)
            : Color(red: 0.55, green: 0.58, blue: 0.63)
    }

    // MARK: - Value marker

    /// Small glass pill riding the outer arc at the current value.
    private func valueMarker(center: CGPoint, radius: CGFloat, lineWidth: CGFloat) -> some View {
        let angle = pointerAngle

        return Capsule()
            .fill(.white.opacity(colorScheme == .dark ? 0.88 : 0.97))
            .overlay {
                Capsule().stroke(.black.opacity(0.05), lineWidth: 0.5)
            }
            .frame(width: max(13, lineWidth * 2.4), height: max(5, lineWidth * 0.95))
            .shadow(color: .black.opacity(0.12), radius: 2.2, y: 0.6)
            .rotationEffect(.degrees(angle))
            .position(point(angle: angle, radius: radius, center: center))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Pointer

    /// The pivot orb floats below the dial center like the reference, so the
    /// blade angle and length are derived from orb-to-value geometry rather
    /// than the raw scale angle.
    private func pointer(size: CGSize, center: CGPoint, radius: CGFloat, lineWidth: CGFloat) -> some View {
        let orbCenter = CGPoint(x: center.x, y: center.y + radius * 0.34)
        let tip = point(angle: pointerAngle, radius: radius - lineWidth * 1.8, center: center)
        let dx = tip.x - orbCenter.x
        let dy = tip.y - orbCenter.y

        return StressGlassPointerView(
            size: size,
            center: orbCenter,
            radius: radius,
            bladeLength: sqrt(dx * dx + dy * dy),
            angle: atan2(dy, dx) * 180 / .pi,
            lightSweep: lightSweep,
            tint: statusColor
        )
    }

    // MARK: - Center copy

    private func centerCopy(size: CGSize, center: CGPoint, radius: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(summary.displayScoreText)
                .font(centerScoreFont(radius: radius))
                .foregroundStyle(centerScoreColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.opacity)

            Text(summary.displayLevelText)
                .font(.system(size: min(21, max(16, radius * 0.20)), weight: .medium))
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .minimumScaleFactor(0.66)
                .contentTransition(.opacity)
        }
        .frame(width: radius * 1.04)
        .position(x: center.x, y: center.y - radius * 0.10)
        .frame(width: size.width, height: size.height)
        .animation(.easeInOut(duration: 0.22), value: summary.score)
    }

    private func centerScoreFont(radius: CGFloat) -> Font {
        if summary.score == nil {
            return .system(size: min(24, max(17, radius * 0.22)), weight: .light)
        }

        return .system(size: min(54, max(38, radius * 0.48)), weight: .thin)
    }

    private var centerScoreColor: Color {
        colorScheme == .dark
            ? .white.opacity(0.96)
            : Color(red: 0.07, green: 0.09, blue: 0.12)
    }

    // MARK: - Value mapping

    private var progress: Double {
        ScoreMath.clamp((summary.currentScore ?? 0) / 100)
    }

    private var pointerAngle: Double {
        startAngle + (endAngle - startAngle) * animatedProgress
    }

    private var statusColor: Color {
        StressHeroPalette.statusColor(for: summary.score)
    }

    private func point(angle: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * radius,
            y: center.y + CGFloat(sin(radians)) * radius
        )
    }

    private func animateToCurrentValue() {
        let target = progress

        if reduceMotion {
            animatedProgress = target
            lightSweep = 0
            return
        }

        lightSweep = -1
        withAnimation(.spring(duration: 0.82, bounce: 0.08)) {
            animatedProgress = target
        }
        withAnimation(.easeInOut(duration: 0.66)) {
            lightSweep = 1
        } completion: {
            lightSweep = -1
        }
    }
}

#Preview("Luxury Stress Gauge") {
    LuxuryStressGaugeView(summary: MockHealthData.stressPreviewSummary(score: 10))
        .frame(width: 220, height: 190)
        .padding()
        .background(StressDetailsDesign.pageBackground)
}
