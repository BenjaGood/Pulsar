//
//  WatchComponents.swift
//  Pulsar Watch App Watch App
//

import SwiftUI

struct WatchGlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.13),
                        Color.white.opacity(0.045),
                        Color.black.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }
}

struct WatchMetricCardView: View {
    var title: String
    var score: Int?
    var subtitle: String
    var symbol: String
    var tint: Color
    var ringSize: CGFloat = 54
    var showsSubtitle = true
    var targetScore: Int? = nil
    var targetRange: PulsarSharedStrainTargetRange? = nil

    var body: some View {
        VStack(spacing: showsSubtitle ? 7 : 4) {
            WatchProgressRingView(
                score: score,
                title: title,
                symbol: symbol,
                tint: tint,
                size: ringSize,
                showsTitle: showsSubtitle,
                targetScore: targetScore,
                targetRange: targetRange
            )

            if showsSubtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .pulsarTextStyle(.watchSubtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity)
            } else {
                Text(title)
                    .pulsarTextStyle(.watchLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, showsSubtitle ? 8 : 4)
        .padding(.vertical, showsSubtitle ? 10 : 7)
        .frame(maxWidth: .infinity)
        .frame(minHeight: showsSubtitle ? max(92, ringSize + 48) : max(70, ringSize + 23))
        .background(
            LinearGradient(
                colors: [
                    tint.opacity(0.20),
                    Color.white.opacity(0.075),
                    Color.black.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.18), tint.opacity(0.18), .black.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .shadow(color: tint.opacity(0.14), radius: 8, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let targetText = targetRange.map { ", target range \($0.displayText)" } ?? targetScore.map { ", recommended today \($0)" } ?? ""
        if subtitle.isEmpty { return "\(title), \(WatchFormatters.score(score))\(targetText)" }
        return "\(title), \(WatchFormatters.score(score))\(targetText), \(subtitle)"
    }
}

struct WatchMetricCard: View {
    var title: String
    var value: String
    var subtitle: String
    var symbol: String
    var tint: Color
    var targetScore: Int? = nil
    var targetRange: PulsarSharedStrainTargetRange? = nil

    var body: some View {
        WatchGlassCard {
            HStack(alignment: .center, spacing: 10) {
                WatchProgressRingView(score: Int(value), title: title, symbol: symbol, tint: tint, size: 52, targetScore: targetScore, targetRange: targetRange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .pulsarTextStyle(.watchLabel)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .pulsarMonospacedMetric(.watchValue)
                    Text(subtitle)
                        .pulsarTextStyle(.watchSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var ringValue: Double {
        guard let number = Double(value), number > 0 else { return 0 }
        return min(1, number / 100)
    }
}

struct WatchAlarmPill: View {
    var alarm: WatchSleepAlarmSummary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "alarm.fill")
                .pulsarTextStyle(.overline)
                .foregroundStyle(.orange)
            Text(WatchFormatters.clockTime(alarm.timeMinutesFromMidnight))
                .pulsarMonospacedMetric(.watchMetric)
                .foregroundStyle(.primary)
            if alarm.usesWakeTime {
                Text("Wake")
                    .pulsarTextStyle(.watchLabel)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.10), in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(0.16), lineWidth: 0.8)
        }
        .shadow(color: .orange.opacity(0.14), radius: 8, y: 4)
    }
}

struct WatchProgressRingView: View {
    var score: Int?
    var title: String
    var symbol: String
    var tint: Color
    var size: CGFloat
    var showsTitle = true
    var targetScore: Int? = nil
    var targetRange: PulsarSharedStrainTargetRange? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedProgress = 0.0

    private var progress: Double {
        guard let score else { return 0 }
        return Double(min(100, max(0, score))) / 100
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(PulsarMetricRingTheme.track, lineWidth: ringWidth)

            WatchRingArc(progress: animatedProgress, inset: ringWidth / 2)
                .stroke(
                    PulsarMetricRingTheme.progressGradient(tint: tint),
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: PulsarMetricRingTheme.ringShadow(tint: tint), radius: 5, y: 2)

            if let targetRangeProgress {
                targetRangeBand(progress: targetRangeProgress)
            }

            if let targetProgress {
                targetMarker(progress: targetProgress)
            }

            Circle()
                .fill(.thinMaterial)
                .overlay(Circle().stroke(PulsarMetricRingTheme.centerStroke, lineWidth: 0.6))
                .frame(width: size * 0.60, height: size * 0.60)

            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(height: showsTitle ? size * 0.18 : size * 0.16)
                Text(WatchFormatters.score(score))
                    .font(.system(size: size * (showsTitle ? 0.30 : 0.36), weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                if showsTitle {
                    Text(title.uppercased())
                        .font(.system(size: size * 0.105, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(height: size * 0.15)
                }
            }
            .frame(width: size * 0.56, height: size * 0.56)
        }
        .frame(width: size, height: size)
        .onAppear {
            displayedProgress = reduceMotion ? progress : 0
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.72)) {
                displayedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            if reduceMotion {
                displayedProgress = newValue
            } else {
                withAnimation(.easeOut(duration: 0.44)) {
                    displayedProgress = newValue
                }
            }
        }
    }

    private var animatedProgress: Double { reduceMotion ? progress : displayedProgress }
    private var ringWidth: CGFloat { max(5, size * 0.105) }
    private var targetProgress: Double? {
        if let targetRange {
            return Double(min(100, max(0, targetRange.upperBound))) / 100
        }
        guard let targetScore else { return nil }
        return Double(min(100, max(0, targetScore))) / 100
    }
    private var targetRangeProgress: ClosedRange<Double>? {
        guard let targetRange else { return nil }
        let lower = Double(min(100, max(0, targetRange.lowerBound))) / 100
        let upper = Double(min(100, max(0, targetRange.upperBound))) / 100
        guard upper > lower else { return nil }
        return lower...upper
    }

    private func targetMarker(progress: Double) -> some View {
        let angle = Angle.degrees(progress * 360 - 90)
        let radius = (size - ringWidth) / 2
        return Capsule(style: .continuous)
            .fill(.white.opacity(0.94))
            .frame(width: max(7, ringWidth * 1.32), height: max(2, ringWidth * 0.28))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.42), lineWidth: 0.6)
            }
            .rotationEffect(.degrees(progress * 360))
            .position(
                x: size / 2 + CGFloat(cos(angle.radians)) * radius,
                y: size / 2 + CGFloat(sin(angle.radians)) * radius
            )
            .accessibilityHidden(true)
    }

    private func targetRangeBand(progress: ClosedRange<Double>) -> some View {
        WatchRingRangeArc(startProgress: progress.lowerBound, endProgress: progress.upperBound, inset: ringWidth / 2)
            .stroke(
                tint.opacity(0.34),
                style: StrokeStyle(lineWidth: max(2.5, ringWidth * 0.45), lineCap: .round, lineJoin: .round)
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct WatchRing<Content: View>: View {
    var value: Double
    var tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, value)))
                .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            content
        }
        .frame(width: 42, height: 42)
    }
}

private struct WatchRingArc: Shape {
    var progress: Double
    var inset: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard progress > 0.0001 else { return path }
        let radius = max(0, min(rect.width, rect.height) / 2 - inset)
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * min(1, max(0, progress))),
            clockwise: false
        )
        return path
    }
}

private struct WatchRingRangeArc: Shape {
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
        let lower = min(1, max(0, startProgress))
        let upper = min(1, max(0, endProgress))
        guard upper > lower else { return path }
        let radius = max(0, min(rect.width, rect.height) / 2 - inset)
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
            startAngle: .degrees(-90 + lower * 360),
            endAngle: .degrees(-90 + upper * 360),
            clockwise: false
        )
        return path
    }
}

struct WatchStressCardView: View {
    var stress: WatchStressSummary

    private var tint: Color {
        WatchStressPalette.tint(for: stress.score)
    }

    var body: some View {
        WatchGlassCard {
            WatchStressHaloGaugeView(stress: stress, size: 92)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stress, \(WatchFormatters.score(stress.score)), \(stress.level), \(WatchFormatters.confidence(stress.confidence))")
    }
}

struct WatchStressHaloGaugeView: View {
    var stress: WatchStressSummary
    var size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedProgress = 0.0

    private var progress: Double {
        guard let score = stress.score else { return 0 }
        return Double(min(100, max(0, score))) / 100
    }

    private var tint: Color {
        WatchStressPalette.tint(for: stress.score)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.20), tint.opacity(0.06), .clear],
                        center: .center,
                        startRadius: size * 0.12,
                        endRadius: size * 0.55
                    )
                )

            WatchStressHaloArc(progress: 1, inset: ringWidth / 2)
                .stroke(.white.opacity(0.11), style: StrokeStyle(lineWidth: ringWidth, lineCap: .round, lineJoin: .round))

            WatchStressHaloArc(progress: animatedProgress, inset: ringWidth / 2)
                .stroke(
                    LinearGradient(
                        colors: WatchStressPalette.gradient(for: stress.score),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: tint.opacity(0.28), radius: 6, y: 2)

            Circle()
                .fill(.thinMaterial)
                .overlay(Circle().stroke(.white.opacity(0.14), lineWidth: 0.7))
                .frame(width: size * 0.58, height: size * 0.58)

            VStack(spacing: 1) {
                Text(WatchFormatters.score(stress.score))
                    .font(.system(size: size * 0.24, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                Text("Stress")
                    .font(.system(size: size * 0.095, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            displayedProgress = reduceMotion ? progress : 0
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.86)) {
                displayedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            if reduceMotion {
                displayedProgress = newValue
            } else {
                withAnimation(.easeOut(duration: 0.48)) {
                    displayedProgress = newValue
                }
            }
        }
    }

    private var animatedProgress: Double { reduceMotion ? progress : displayedProgress }
    private var ringWidth: CGFloat { max(6, size * 0.09) }
}

private struct WatchStressHaloArc: Shape {
    var progress: Double
    var inset: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard progress > 0.0001 else { return path }
        let start = 128.0
        let end = 412.0
        let radius = max(0, min(rect.width, rect.height) / 2 - inset)
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
            startAngle: .degrees(start),
            endAngle: .degrees(start + (end - start) * min(1, max(0, progress))),
            clockwise: false
        )
        return path
    }
}

struct WatchMiniStressTimelineView: View {
    var samples: [WatchStressSample]
    var tint: Color

    var body: some View {
        GeometryReader { proxy in
            let points = chartPoints(in: proxy.size)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.05))
                if points.count >= 2 {
                    smoothPath(points: points)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .shadow(color: tint.opacity(0.24), radius: 4)
                } else {
                    Text("No timeline yet")
                        .pulsarTextStyle(.metadata)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first?.timestamp,
              let last = sorted.last?.timestamp,
              last > first else { return [] }
        return sorted.map { sample in
            let x = sample.timestamp.timeIntervalSince(first) / max(1, last.timeIntervalSince(first))
            let y = min(1, max(0, sample.score / 100))
            return CGPoint(x: CGFloat(x) * size.width, y: size.height - CGFloat(y) * size.height)
        }
    }

    private func smoothPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let offset = (current.x - previous.x) * 0.42
            path.addCurve(
                to: current,
                control1: CGPoint(x: previous.x + offset, y: previous.y),
                control2: CGPoint(x: current.x - offset, y: current.y)
            )
        }
        return path
    }
}

enum WatchStressPalette {
    static func tint(for score: Int?) -> Color {
        PulsarStressRingTheme.tint(for: score)
    }

    static func gradient(for score: Int?) -> [Color] {
        PulsarStressRingTheme.gradient(for: score)
    }
}

struct WatchStatPill: View {
    var title: String
    var value: String
    var unit: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .pulsarTextStyle(.watchLabel)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .pulsarMonospacedMetric(.watchMetric)
                if let unit {
                    Text(unit)
                        .pulsarTextStyle(.watchLabel)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

struct WatchSectionTitle: View {
    var title: String

    var body: some View {
        Text(title.uppercased())
            .pulsarTextStyle(.watchLabel)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }
}

struct WatchEmptyState: View {
    var title: String
    var message: String
    var symbol: String

    var body: some View {
        WatchGlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .pulsarTextStyle(.sectionHeader)
                    .foregroundStyle(.secondary)
                Text(title)
                    .pulsarTextStyle(.watchTitle)
                Text(message)
                    .pulsarTextStyle(.watchSubtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#if DEBUG
struct WatchMetricCardView_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 7) {
            WatchMetricCardView(
                title: "Sleep",
                score: 77,
                subtitle: "7h 47m",
                symbol: "moon.zzz.fill",
                tint: PulsarMetricRingTheme.tint(for: .sleep)
            )
            WatchMetricCardView(
                title: "Recovery",
                score: 45,
                subtitle: "Build baseline",
                symbol: "heart.text.square.fill",
                tint: PulsarMetricRingTheme.tint(for: .recovery)
            )
            WatchMetricCardView(
                title: "Strain",
                score: 98,
                subtitle: "1h 16m training",
                symbol: "figure.run",
                tint: PulsarMetricRingTheme.tint(for: .strain)
            )
        }
        .padding(8)
        .previewDisplayName("Watch Metric Cards")
    }
}

struct WatchStressCardView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            WatchStressCardView(stress: WatchPreviewData.snapshot.stress)
                .padding(8)
                .previewDisplayName("Stress Full")
            WatchStressCardView(stress: .empty)
                .padding(8)
                .previewDisplayName("Stress Missing")
            WatchMiniStressTimelineView(samples: WatchPreviewData.stressSamples, tint: .red)
                .frame(height: 58)
                .padding(8)
                .previewDisplayName("Stress Timeline")
        }
    }
}
#endif
