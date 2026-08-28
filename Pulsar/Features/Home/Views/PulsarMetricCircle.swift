//
//  PulsarMetricCircle.swift
//  Pulsar
//

import SwiftUI

enum MetricOrbColorState {
    case inactive
    case low
    case medium
    case high

    init(score: Double) {
        switch score {
        case 70...100:
            self = .high
        case 40..<70:
            self = .medium
        case 1..<40:
            self = .low
        default:
            self = .inactive
        }
    }

    var glowTint: Color {
        switch self {
        case .inactive:
            return Color(red: 0.62, green: 0.68, blue: 0.78)
        case .low:
            return Color(red: 0.98, green: 0.36, blue: 0.42)
        case .medium:
            return Color(red: 0.96, green: 0.72, blue: 0.28)
        case .high:
            return Color(red: 0.33, green: 0.84, blue: 0.58)
        }
    }
}

struct PulsarMetricCircle: View {
    var title: String
    var value: Double
    var description: String
    var icon: String?
    var metric: PulsarMetricRingKind
    var colorState: MetricOrbColorState
    var targetValue: Double?
    var targetRange: ClosedRange<Double>? = nil
    var targetLabel: String?
    var showsZeroValue = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var displayedProgress = 0.0

    private var clampedValue: Double { min(max(value, 0), 100) }
    private var scoreProgress: Double { clampedValue / 100 }
    private var markerProgress: Double? {
        guard let targetValue else { return nil }
        return min(max(targetValue, 0), 100) / 100
    }
    private var targetRangeProgress: ClosedRange<Double>? {
        guard let targetRange else { return nil }
        let lower = min(max(targetRange.lowerBound, 0), 100) / 100
        let upper = min(max(targetRange.upperBound, 0), 100) / 100
        guard upper > lower else { return nil }
        return lower...upper
    }
    private var palette: MetricOrbPalette {
        MetricOrbPalette(metric: metric, colorScheme: colorScheme)
    }
    private var scoreText: String { clampedValue > 0 || showsZeroValue ? "\(Int(clampedValue.rounded()))" : "--" }
    private var targetAccessibilityText: String {
        if let targetRange, let targetLabel {
            return ", \(targetLabel.lowercased()) \(Int(targetRange.lowerBound.rounded())) to \(Int(targetRange.upperBound.rounded()))"
        }
        guard let targetValue, let targetLabel else { return "" }
        return ", \(targetLabel.lowercased()) \(Int(targetValue.rounded()))"
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let horizontalPadding = max(7, min(11, width * 0.10))
            let verticalPadding = max(9, min(13, width * 0.11))
            let availableRingSize = max(58, min(width - horizontalPadding * 2, height - 58))
            let ringSize = min(112, availableRingSize)
            let ringWidth = max(6, min(10, ringSize * 0.10))

            VStack(spacing: max(6, min(9, width * 0.075))) {
                metricRing(size: ringSize, ringWidth: ringWidth)
                    .frame(width: ringSize, height: ringSize)

                Text(description)
                    .font(.system(size: max(9, min(11, width * 0.09)), weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(width: width, height: height, alignment: .top)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(cardBorder)
            .shadow(color: palette.cardShadow, radius: colorScheme == .dark ? 16 : 12, y: 8)
        }
        .task {
            animateProgress()
        }
        .onChange(of: value, initial: false) { _, _ in
            animateProgress()
        }
    }

    private func metricRing(size: CGFloat, ringWidth: CGFloat) -> some View {
        let centerSize = size * 0.60
        let particleRadius = (size - ringWidth) / 2

        return ZStack {
            Circle()
                .strokeBorder(
                    palette.track,
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round, lineJoin: .round)
                )

            progressStroke(size: size, ringWidth: ringWidth)
                .shadow(color: palette.ringShadow, radius: 5, y: 2)

            if let targetRangeProgress {
                targetRangeBand(progress: targetRangeProgress, size: size, ringWidth: ringWidth)
            }

            if let markerProgress {
                targetMarker(progress: markerProgress, size: size, ringWidth: ringWidth)
            }

            MetricOrbParticles(
                progress: displayedProgress,
                radius: particleRadius,
                palette: palette,
                reduceMotion: reduceMotion
            )

            Circle()
                .fill(.thinMaterial)
                .overlay {
                    Circle()
                        .stroke(palette.centerStroke, lineWidth: 0.6)
                }
                .frame(width: centerSize, height: centerSize)

            centerContent(size: size, centerSize: centerSize)
        }
        .frame(width: size, height: size, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) score \(scoreText)\(targetAccessibilityText)")
    }

    @ViewBuilder
    private func progressStroke(size: CGFloat, ringWidth: CGFloat) -> some View {
        let progressGradient = LinearGradient(
            colors: palette.ringColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        if displayedProgress >= 0.995 {
            Circle()
                .strokeBorder(progressGradient, lineWidth: ringWidth)
        } else {
            MetricOrbProgressArc(progress: displayedProgress, inset: ringWidth / 2)
                .stroke(progressGradient, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
        }
    }

    private func centerContent(size: CGFloat, centerSize: CGFloat) -> some View {
        ZStack {
            Text(scoreText)
                .font(.system(size: max(20, size * 0.245), weight: .bold, design: .rounded))
                .foregroundStyle(palette.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            VStack(spacing: 0) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: max(9, size * 0.108), weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.iconTint)
                        .symbolRenderingMode(.hierarchical)
                        .frame(height: centerSize * 0.24, alignment: .top)
                } else {
                    Color.clear.frame(height: centerSize * 0.24)
                }

                Spacer(minLength: 0)

                Text(title.uppercased())
                    .font(.system(size: max(7, size * 0.074), weight: .semibold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(palette.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(height: centerSize * 0.22, alignment: .bottom)
            }
            .padding(.vertical, centerSize * 0.09)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 6)
        .frame(width: centerSize * 0.94, height: centerSize * 0.94, alignment: .center)
    }

    private func targetMarker(progress: Double, size: CGFloat, ringWidth: CGFloat) -> some View {
        let angle = Angle.degrees(progress * 360 - 90)
        let radius = (size - ringWidth) / 2
        let markerWidth = max(8, ringWidth * 1.45)
        let markerHeight = max(2, ringWidth * 0.26)

        return Capsule(style: .continuous)
            .fill(palette.targetMarker)
            .frame(width: markerWidth, height: markerHeight)
            .overlay {
                Capsule(style: .continuous)
                    .stroke(palette.targetMarkerStroke, lineWidth: 0.65)
            }
            .shadow(color: palette.targetMarker.opacity(colorScheme == .dark ? 0.26 : 0.16), radius: 3, y: 1)
            .rotationEffect(.degrees(progress * 360))
            .position(
                x: size / 2 + CGFloat(cos(angle.radians)) * radius,
                y: size / 2 + CGFloat(sin(angle.radians)) * radius
            )
            .accessibilityHidden(true)
    }

    private func targetRangeBand(progress: ClosedRange<Double>, size: CGFloat, ringWidth: CGFloat) -> some View {
        MetricOrbRangeArc(startProgress: progress.lowerBound, endProgress: progress.upperBound, inset: ringWidth / 2)
            .stroke(
                LinearGradient(colors: [palette.targetMarker.opacity(0.24), palette.targetMarker.opacity(0.52)], startPoint: .topLeading, endPoint: .bottomTrailing),
                style: StrokeStyle(lineWidth: max(3, ringWidth * 0.42), lineCap: .round, lineJoin: .round)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(palette.cardFill)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(palette.cardSheen)
                    .blendMode(colorScheme == .dark ? .screen : .normal)
            }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(palette.cardStroke, lineWidth: 1)
    }

    private func animateProgress() {
        let target = scoreProgress
        guard abs(displayedProgress - target) > 0.001 else { return }

        if reduceMotion {
            displayedProgress = target
        } else {
            withAnimation(.spring(response: 0.84, dampingFraction: 0.86)) {
                displayedProgress = target
            }
        }
    }
}

struct PulsarMetricCircleButtonStyle: ButtonStyle {
    var glowColor: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.982 : 1)
            .brightness(configuration.isPressed ? (colorScheme == .dark ? 0.018 : -0.012) : 0)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(configuration.isPressed && colorScheme == .dark ? 0.18 : 0), lineWidth: 1)
                    .shadow(color: glowColor.opacity(configuration.isPressed ? 0.20 : 0.06), radius: configuration.isPressed ? 14 : 7)
            }
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.78),
                value: configuration.isPressed
            )
    }
}

private struct MetricOrbProgressArc: Shape {
    var progress: Double
    var inset: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard progress > 0.0001 else { return path }
        let clampedProgress = ScoreMath.clamp(progress, 0, 1)
        let radius = max(0, min(rect.width, rect.height) / 2 - inset)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * clampedProgress),
            clockwise: false
        )
        return path
    }
}

private struct MetricOrbRangeArc: Shape {
    var startProgress: Double
    var endProgress: Double
    var inset: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(startProgress, endProgress) }
        set {
            startProgress = newValue.first
            endProgress = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let lower = ScoreMath.clamp(startProgress, 0, 1)
        let upper = ScoreMath.clamp(endProgress, 0, 1)
        guard upper > lower else { return path }
        let radius = max(0, min(rect.width, rect.height) / 2 - inset)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90 + 360 * lower),
            endAngle: .degrees(-90 + 360 * upper),
            clockwise: false
        )
        return path
    }
}

private struct MetricOrbParticles: View {
    var progress: Double
    var radius: CGFloat
    var palette: MetricOrbPalette
    var reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                if progress > 0.02 {
                    if reduceMotion {
                        particle(index: 0, time: 0, size: size)
                    } else {
                        TimelineView(.animation) { timeline in
                            let time = timeline.date.timeIntervalSinceReferenceDate
                            ZStack {
                                ForEach(0..<2, id: \.self) { index in
                                    particle(index: index, time: time, size: size)
                                }
                            }
                        }
                    }
                }
            }
            .frame(width: size, height: size)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .allowsHitTesting(false)
    }

    private func particle(index: Int, time: TimeInterval, size: CGFloat) -> some View {
        let baseProgress = max(progress, 0.04)
        let trailingProgress = max(0.01, baseProgress - Double(index) * 0.045)
        let drift = reduceMotion ? 0 : sin(time * (0.75 + Double(index) * 0.14) + Double(index)) * 0.008
        let angle = Angle.degrees((trailingProgress + drift) * 360 - 90)
        let orbit = radius + CGFloat(reduceMotion ? 0 : cos(time * 1.2 + Double(index)) * 1.6)
        let diameter = max(1.4, min(2.6, size * (0.013 + CGFloat(index) * 0.002)))
        let opacity = reduceMotion ? 0.10 : 0.055 + 0.025 * CGFloat(sin(time * 1.9 + Double(index)))

        return Circle()
            .fill(palette.highlight)
            .frame(width: diameter, height: diameter)
            .opacity(opacity)
            .position(
                x: size / 2 + CGFloat(cos(angle.radians)) * orbit,
                y: size / 2 + CGFloat(sin(angle.radians)) * orbit
            )
    }
}

private struct MetricOrbPalette {
    var glow: Color
    var highlight: Color
    var ringColors: [Color]
    var ringShadow: Color
    var track: Color
    var cardFill: LinearGradient
    var cardSheen: LinearGradient
    var cardStroke: LinearGradient
    var cardShadow: Color
    var centerStroke: Color
    var primaryText: Color
    var secondaryText: Color
    var tertiaryText: Color
    var iconTint: Color
    var targetMarker: Color
    var targetMarkerStroke: Color

    init(metric: PulsarMetricRingKind, colorScheme: ColorScheme) {
        let tint = PulsarMetricRingTheme.tint(for: metric)

        self.glow = tint
        self.highlight = Color.white.opacity(0.82)
        self.ringColors = PulsarMetricRingTheme.progressColors(tint: tint)
        self.ringShadow = PulsarMetricRingTheme.ringShadow(tint: tint)
        self.track = PulsarMetricRingTheme.track
        self.cardFill = PulsarMetricRingTheme.cardFill(tint: tint)
        self.cardSheen = LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.10 : 0.30),
                Color.white.opacity(colorScheme == .dark ? 0.02 : 0.12),
                tint.opacity(colorScheme == .dark ? 0.05 : 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        self.cardStroke = PulsarMetricRingTheme.cardStroke(tint: tint)
        self.cardShadow = PulsarMetricRingTheme.cardShadow(tint: tint)
        self.centerStroke = PulsarMetricRingTheme.centerStroke
        self.primaryText = colorScheme == .dark ? .white.opacity(0.96) : Color(red: 0.10, green: 0.12, blue: 0.16)
        self.secondaryText = colorScheme == .dark ? .white.opacity(0.68) : Color(red: 0.32, green: 0.36, blue: 0.44)
        self.tertiaryText = colorScheme == .dark ? .white.opacity(0.56) : Color(red: 0.42, green: 0.46, blue: 0.54)
        self.iconTint = tint
        self.targetMarker = colorScheme == .dark ? Color.white.opacity(0.92) : Color(red: 0.12, green: 0.14, blue: 0.18).opacity(0.78)
        self.targetMarkerStroke = tint.opacity(colorScheme == .dark ? 0.44 : 0.34)
    }
}

#Preview("Metric Orb") {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        PulsarMetricCircle(
            title: "Recovery",
            value: 82,
            description: "Ready to perform",
            icon: "heart.text.square.fill",
            metric: .recovery,
            colorState: .high
        )
        .frame(width: 112, height: 168)
        .padding()
    }
}

#Preview("Metric Orb Row - Polish Values") {
    HStack(spacing: 10) {
        PulsarMetricCircle(
            title: "Sleep",
            value: 77,
            description: "7h 38m sleep",
            icon: "moon.zzz.fill",
            metric: .sleep,
            colorState: MetricOrbColorState(score: 77)
        )
        PulsarMetricCircle(
            title: "Recovery",
            value: 45,
            description: "Balanced",
            icon: "heart.text.square.fill",
            metric: .recovery,
            colorState: MetricOrbColorState(score: 45)
        )
        PulsarMetricCircle(
            title: "Strain",
            value: 98,
            description: "63m training",
            icon: "figure.run.circle.fill",
            metric: .strain,
            colorState: MetricOrbColorState(score: 98),
            targetValue: 85,
            targetRange: 65...85,
            targetLabel: "Target range"
        )
    }
    .frame(height: 168)
    .padding(18)
    .background(PulsarSectionBackground())
}
