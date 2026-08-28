//
//  LabBiologicalAgeOverview.swift
//  Pulsar
//

import SwiftUI

struct LabBiologicalAgePresentation: Equatable {
    static let visualDeltaRange = -10.0...10.0
    static let alignmentTolerance = 0.05

    let result: BiologicalAgeResult

    var gaugeProgress: Double {
        let clampedDelta = min(max(result.ageDelta, Self.visualDeltaRange.lowerBound), Self.visualDeltaRange.upperBound)
        return (clampedDelta - Self.visualDeltaRange.lowerBound) /
            (Self.visualDeltaRange.upperBound - Self.visualDeltaRange.lowerBound)
    }

    var statusText: String {
        Self.statusText(for: result.ageDelta)
    }

    static func statusText(for delta: Double) -> String {
        let roundedMagnitude = (abs(delta) * 10).rounded() / 10
        let formattedMagnitude = roundedMagnitude.formatted(.number.precision(.fractionLength(1)))
        let yearNoun = abs(roundedMagnitude - 1) < 0.001 ? "year" : "years"

        if delta < -Self.alignmentTolerance {
            return "↓ \(formattedMagnitude) \(yearNoun) younger"
        }
        if delta > Self.alignmentTolerance {
            return "↑ \(formattedMagnitude) \(yearNoun) older"
        }
        return "Aligned"
    }

    var deltaText: String {
        let value = result.ageDelta.formatted(
            .number
                .sign(strategy: .always(includingZero: false))
                .precision(.fractionLength(1))
        )
        return "\(value) yr"
    }

    var chronologicalAgeText: String {
        let roundedAge = result.chronologicalAge.rounded()
        if abs(result.chronologicalAge - roundedAge) < 0.05 {
            return "\(Int(roundedAge)) years"
        }
        return "\(result.chronologicalAge.formatted(.number.precision(.fractionLength(1)))) years"
    }

    var confidencePercent: Int {
        switch result.confidence {
        case .high: 92
        case .medium: 68
        case .low: 38
        }
    }

    var confidenceProgress: Double {
        min(max(Double(confidencePercent) / 100, 0), 1)
    }

}

struct LabReferenceHeaderView: View {
    let onAboutEstimate: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                LabReferenceHeaderIdentity()
                LabAboutEstimateButton(action: onAboutEstimate)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                LabReferenceHeaderIdentity()
                    .layoutPriority(1)
                Spacer(minLength: 2)
                LabAboutEstimateButton(action: onAboutEstimate)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

private struct LabReferenceHeaderIdentity: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "testtube.2")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(PulsarTabPalette.primaryText)
                .frame(width: 50, height: 50)
                .labReferenceGlassSurface(cornerRadius: 20, shadowOpacity: 0.035)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Lab")
                    .font(.system(.largeTitle, design: .serif, weight: .regular))
                    .foregroundStyle(PulsarTabPalette.primaryText)

                Text("Biological age & blood test insights")
                    .font(.caption)
                    .foregroundStyle(PulsarTabPalette.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct LabAboutEstimateButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("About estimate", systemImage: "info.circle.fill")
                .font(.caption.scaled(by: 0.82).weight(.medium))
                .foregroundStyle(PulsarTabPalette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .labReferenceGlassSurface(cornerRadius: 22, isInteractive: true, shadowOpacity: 0.025)
    }
}

struct LabReferenceBiologicalAgeCard: View {
    let result: BiologicalAgeResult
    var startsSettled = false

    @State private var cardVisible = false
    @State private var ticksVisible = false
    @State private var markerProgress = 0.5
    @State private var numberVisible = false
    @State private var statusVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: LabBiologicalAgePresentation {
        LabBiologicalAgePresentation(result: result)
    }

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 1) {
                Text("Your biological age")
                    .font(.caption.scaled(by: 0.88).weight(.medium))
                    .textCase(.uppercase)
                    .tracking(0.55)
                    .foregroundStyle(PulsarTabPalette.secondaryText)

                VStack(spacing: -10) {
                    Text(result.biologicalAge, format: .number.precision(.fractionLength(1)))
                        .font(.system(.largeTitle, design: .serif, weight: .ultraLight).scaled(by: 1.88).monospacedDigit())
                        .foregroundStyle(PulsarTabPalette.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)

                    Text("years")
                        .font(.subheadline)
                        .foregroundStyle(PulsarTabPalette.secondaryText)
                }
            }
            .opacity(numberVisible ? 1 : 0)
            .scaleEffect(numberVisible || reduceMotion ? 1 : 0.975)

            Text(presentation.statusText)
                .font(.caption.scaled(by: 0.74).weight(.medium).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(minHeight: 22)
                .background(PulsarTabPalette.primaryText, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                .opacity(statusVisible ? 1 : 0)
                .scaleEffect(statusVisible || reduceMotion ? 1 : 0.97)
                .accessibilityLabel(presentation.statusText)

            LabBiologicalAgeGauge(
                delta: result.ageDelta,
                markerProgress: markerProgress,
                ticksVisible: ticksVisible
            )
            .frame(height: 66)

            LabAgeMetricsStrip(presentation: presentation)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity)
        .labReferenceGlassSurface(
            cornerRadius: 26,
            shadowOpacity: 0.028,
            shadowRadius: 14,
            shadowY: 6,
            fillOpacity: 0.62
        )
        .opacity(cardVisible ? 1 : 0)
        .offset(y: cardVisible || reduceMotion ? 0 : 10)
        .task {
            await runEntranceAnimation()
        }
        .onChange(of: result.ageDelta) { _, _ in
            updateMarker()
        }
        .accessibilityElement(children: .contain)
    }

    @MainActor
    private func runEntranceAnimation() async {
        let finalProgress = presentation.gaugeProgress

        guard !startsSettled, !reduceMotion else {
            cardVisible = true
            ticksVisible = true
            markerProgress = finalProgress
            numberVisible = true
            statusVisible = true
            return
        }

        markerProgress = 0.5
        withAnimation(.easeOut(duration: 0.32)) {
            cardVisible = true
        }
        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.easeOut(duration: 0.28)) {
            ticksVisible = true
        }
        withAnimation(.easeOut(duration: 0.38)) {
            numberVisible = true
        }
        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.smooth(duration: 0.88)) {
            markerProgress = finalProgress
        }
        try? await Task.sleep(for: .milliseconds(760))
        withAnimation(.easeOut(duration: 0.24)) {
            statusVisible = true
        }
    }

    private func updateMarker() {
        let finalProgress = presentation.gaugeProgress
        if reduceMotion {
            markerProgress = finalProgress
        } else {
            withAnimation(.smooth(duration: 0.88)) {
                markerProgress = finalProgress
            }
        }
    }
}

private struct LabBiologicalAgeGauge: View {
    let delta: Double
    let markerProgress: Double
    let ticksVisible: Bool

    private let tickCount = 31

    var body: some View {
        GeometryReader { proxy in
            let geometry = LabAgeGaugeGeometry(size: proxy.size)

            ZStack {
                LabAgeGaugeArcShape()
                    .stroke(Color.black.opacity(0.018), style: StrokeStyle(lineWidth: 1, lineCap: .round))

                ForEach(0..<tickCount, id: \.self) { index in
                    let progress = Double(index) / Double(tickCount - 1)
                    let isCenter = index == (tickCount - 1) / 2
                    let isMajor = isCenter || index % 5 == 0
                    let point = geometry.point(for: progress)

                    Capsule()
                        .fill(tickColor(progress: progress, markerProgress: markerProgress, isCenter: isCenter))
                        .frame(width: isCenter ? 4.5 : (isMajor ? 2.4 : 1.8), height: isCenter ? 17 : (isMajor ? 16 : 14))
                        .rotationEffect(.degrees(geometry.angleDegrees(for: progress) - 90))
                        .position(point)
                        .opacity(ticksVisible ? 1 : 0)
                }

                LabAgeGaugeAnimatedMarker(progress: markerProgress)
                    .opacity(ticksVisible ? 1 : 0)

                Text("Younger")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, geometry.horizontalInset * 0.78)
                    .position(x: proxy.size.width / 2, y: proxy.size.height - 23)

                Text("Aligned")
                    .position(x: proxy.size.width / 2, y: proxy.size.height - 8)

                Text("Older")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, geometry.horizontalInset * 0.78)
                    .position(x: proxy.size.width / 2, y: proxy.size.height - 23)
            }
            .font(.system(size: 11, weight: .medium))
            .textCase(.uppercase)
            .foregroundStyle(PulsarTabPalette.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func tickColor(progress: Double, markerProgress: Double, isCenter: Bool) -> Color {
        if isCenter {
            return PulsarTabPalette.primaryText.opacity(0.94)
        }

        let distanceFromMarker = abs(progress - markerProgress)
        let markerEmphasis = max(0, 1 - distanceFromMarker / 0.13)
        let rightSideFade = max(0, (progress - 0.50) / 0.50)
        let baseOpacity = 0.82 - 0.48 * rightSideFade
        return Color.black.opacity(max(baseOpacity, 0.28 + 0.60 * markerEmphasis))
    }

    private var accessibilityLabel: String {
        let status = LabBiologicalAgePresentation.statusText(for: delta)
        return "Biological age difference gauge. \(status). Younger is left, aligned is center, and older is right."
    }
}

private struct LabAgeGaugeArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        let geometry = LabAgeGaugeGeometry(size: rect.size)
        var path = Path()
        path.move(to: geometry.point(for: 0))
        for step in 1...80 {
            path.addLine(to: geometry.point(for: Double(step) / 80))
        }
        return path
    }
}

@Animatable
private struct LabAgeGaugeAnimatedMarker: View {
    var progress: Double

    var body: some View {
        GeometryReader { proxy in
            let geometry = LabAgeGaugeGeometry(size: proxy.size)
            Capsule()
                .fill(PulsarTabPalette.primaryText)
                .frame(width: 6, height: 20)
                .rotationEffect(.degrees(geometry.angleDegrees(for: progress) - 90))
                .position(geometry.point(for: progress))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        }
    }
}

private struct LabAgeGaugeGeometry {
    let size: CGSize

    var horizontalInset: CGFloat {
        (size.width - chordWidth) / 2
    }

    private var chordWidth: CGFloat {
        max(size.width * 0.88, 1)
    }

    private var halfChord: CGFloat {
        chordWidth / 2
    }

    private var sagitta: CGFloat {
        min(max(size.width * 0.10, 32), 36)
    }

    private var endpointY: CGFloat {
        0
    }

    private var radius: CGFloat {
        (halfChord * halfChord + sagitta * sagitta) / (2 * sagitta)
    }

    private var center: CGPoint {
        CGPoint(x: size.width / 2, y: endpointY - (radius - sagitta))
    }

    private var startAngle: Double {
        atan2(Double(endpointY - center.y), Double(-halfChord)) * 180 / .pi
    }

    private var endAngle: Double {
        atan2(Double(endpointY - center.y), Double(halfChord)) * 180 / .pi
    }

    func angleDegrees(for progress: Double) -> Double {
        let normalized = min(max(progress, 0), 1)
        return startAngle + (endAngle - startAngle) * normalized
    }

    func point(for progress: Double) -> CGPoint {
        let radians = angleDegrees(for: progress) * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * radius,
            y: center.y + CGFloat(sin(radians)) * radius
        )
    }
}

private struct LabAgeMetricsStrip: View {
    let presentation: LabBiologicalAgePresentation
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 0) {
                LabAgeMetric(title: "Chronological Age", value: presentation.chronologicalAgeText, symbol: "calendar")
                Divider()
                LabAgeMetric(title: "Delta", value: presentation.deltaText, symbol: deltaSymbol)
                Divider()
                LabAgeMetric(title: "Confidence", value: presentation.result.confidence.rawValue, symbol: "shield.lefthalf.filled")
            }
            .labMetricsStripSurface()
        } else {
            HStack(spacing: 0) {
                LabAgeMetric(title: "Chronological Age", value: presentation.chronologicalAgeText, symbol: "calendar")
                Divider().padding(.vertical, 8)
                LabAgeMetric(title: "Delta", value: presentation.deltaText, symbol: deltaSymbol)
                Divider().padding(.vertical, 8)
                LabAgeMetric(title: "Confidence", value: presentation.result.confidence.rawValue, symbol: "shield.lefthalf.filled")
            }
            .labMetricsStripSurface()
        }
    }

    private var deltaSymbol: String {
        if presentation.result.ageDelta < -LabBiologicalAgePresentation.alignmentTolerance {
            return "arrow.down.right"
        }
        if presentation.result.ageDelta > LabBiologicalAgePresentation.alignmentTolerance {
            return "arrow.up.right"
        }
        return "equal"
    }
}

private struct LabAgeMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 28, height: 28)
                .background(PulsarTabPalette.separator.opacity(0.5), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.scaled(by: 0.64))
                    .foregroundStyle(PulsarTabPalette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                Text(value)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(PulsarTabPalette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct LabReferencePillarSection: View {
    let pillars: [LabPillarResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Pillar signals")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(PulsarTabPalette.primaryText)
                Text("A conservative estimate weighted by fitness, lifestyle, and recent blood markers.")
                    .font(.subheadline)
                    .foregroundStyle(PulsarTabPalette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(pillars.enumerated(), id: \.element.id) { index, pillar in
                    LabReferencePillarRow(pillar: pillar)
                    if index < pillars.count - 1 {
                        Divider().padding(.leading, 64)
                    }
                }
            }
            .padding(.vertical, 2)
            .labReferenceGlassSurface(cornerRadius: 26, shadowOpacity: 0.035)
        }
    }
}

private struct LabReferencePillarRow: View {
    let pillar: LabPillarResult

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: pillar.kind.labReferenceSymbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(iconForeground)
                .frame(width: 44, height: 44)
                .background(iconBackground, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(pillar.kind.title)
                    .font(.headline)
                    .fontDesign(.serif)
                    .foregroundStyle(PulsarTabPalette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(pillar.statusLabel)
                    .font(.caption)
                    .foregroundStyle(PulsarTabPalette.secondaryText)
            }

            Spacer(minLength: 8)

            Text(scoreText)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(PulsarTabPalette.primaryText)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PulsarTabPalette.tertiaryText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pillar.kind.title), \(scoreText), \(pillar.statusLabel)")
    }

    private var scoreText: String {
        guard let score = pillar.score else { return "--" }
        return "\(Int(score.rounded()))"
    }

    private var iconForeground: Color {
        pillar.score == nil ? PulsarTabPalette.secondaryText : .white
    }

    private var iconBackground: Color {
        pillar.score == nil ? PulsarTabPalette.separator.opacity(0.5) : PulsarTabPalette.primaryText
    }
}

struct LabReferenceDataConfidenceCard: View {
    let result: BiologicalAgeResult
    var startsSettled = false

    @State private var displayedProgress = 0.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentation: LabBiologicalAgePresentation {
        LabBiologicalAgePresentation(result: result)
    }

    var body: some View {
        responsiveContent
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .labReferenceGlassSurface(
            cornerRadius: 28,
            shadowOpacity: 0.025,
            shadowRadius: 14,
            shadowY: 6,
            fillOpacity: 0.50
        )
        .task(id: presentation.confidenceProgress) {
            await updateProgress()
        }
        .onChange(of: reduceMotion) { _, isEnabled in
            if isEnabled {
                displayedProgress = presentation.confidenceProgress
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Data confidence")
        .accessibilityValue("\(presentation.confidencePercent) percent. \(LabDataConfidenceCopy.explanation)")
    }

    @ViewBuilder
    private var responsiveContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 16) {
                LabDataConfidenceCopy(
                    percent: presentation.confidencePercent,
                    maxWidth: .infinity
                )

                LabConfidenceRing(progress: displayedProgress)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    LabDataConfidenceCopy(percent: presentation.confidencePercent)
                        .layoutPriority(1)

                    Spacer(minLength: 0)

                    LabConfidenceRing(progress: displayedProgress)
                }

                VStack(alignment: .leading, spacing: 16) {
                    LabDataConfidenceCopy(
                        percent: presentation.confidencePercent,
                        maxWidth: .infinity
                    )

                    LabConfidenceRing(progress: displayedProgress)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    @MainActor
    private func updateProgress() async {
        let target = presentation.confidenceProgress

        guard !startsSettled, !reduceMotion else {
            displayedProgress = target
            return
        }

        await Task.yield()
        withAnimation(.easeInOut(duration: 0.78)) {
            displayedProgress = target
        }
    }
}

private struct LabDataConfidenceCopy: View {
    static let explanation = "Confidence improves with 20+ days of data and recent lab results. Blood markers should be less than 6 months old."

    let percent: Int
    var maxWidth: CGFloat = 190

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Data confidence")
                .font(.subheadline)
                .foregroundStyle(PulsarTabPalette.secondaryText)

            Text("\(percent)%")
                .font(.system(.largeTitle, design: .serif, weight: .ultraLight).scaled(by: 1.42).monospacedDigit())
                .foregroundStyle(PulsarTabPalette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(Self.explanation)
                .font(.caption.scaled(by: 0.92))
                .foregroundStyle(PulsarTabPalette.secondaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
    }
}

private struct LabConfidenceRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: 92, height: 92)
                .labReferenceGlassSurface(
                    cornerRadius: 46,
                    shadowOpacity: 0.014,
                    shadowRadius: 8,
                    shadowY: 3,
                    fillOpacity: 0.22
                )

            Circle()
                .stroke(PulsarTabPalette.separator.opacity(0.55), lineWidth: 6)

            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    PulsarTabPalette.primaryText.opacity(0.92),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Image(systemName: "testtube.2")
                .font(.system(size: 31, weight: .ultraLight))
                .foregroundStyle(PulsarTabPalette.tertiaryText.opacity(0.30))
        }
        .frame(width: 112, height: 112)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct LabReferenceGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isInteractive: Bool
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat
    let fillOpacity: Double

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        content
            .background {
                LabReferenceGlassBackground(
                    cornerRadius: cornerRadius,
                    isInteractive: isInteractive,
                    isOpaque: reduceTransparency,
                    fillOpacity: fillOpacity
                )
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.98),
                            Color.black.opacity(0.028),
                            Color.black.opacity(0.045)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
                .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
    }
}

private struct LabReferenceGlassBackground: View {
    let cornerRadius: CGFloat
    let isInteractive: Bool
    let isOpaque: Bool
    let fillOpacity: Double

    @ViewBuilder
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        if #available(iOS 26.0, *) {
            shape
                .fill(Color.white.opacity(isOpaque ? 0.98 : fillOpacity))
                .glassEffect(.clear.interactive(isInteractive), in: shape)
        } else {
            shape
                .fill(Color.white.opacity(isOpaque ? 0.98 : fillOpacity))
                .background(.ultraThinMaterial, in: shape)
        }
    }
}

extension View {
    func labReferenceGlassSurface(
        cornerRadius: CGFloat,
        isInteractive: Bool = false,
        shadowOpacity: Double = 0.04,
        shadowRadius: CGFloat = 20,
        shadowY: CGFloat = 10,
        fillOpacity: Double = 0.72
    ) -> some View {
        modifier(
            LabReferenceGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                isInteractive: isInteractive,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY,
                fillOpacity: fillOpacity
            )
        )
    }

    fileprivate func labMetricsStripSurface() -> some View {
        padding(.vertical, 3)
            .labReferenceGlassSurface(
                cornerRadius: 20,
                shadowOpacity: 0.008,
                shadowRadius: 5,
                shadowY: 2,
                fillOpacity: 0.30
            )
    }
}

#Preview("Lab Biological Age - Younger") {
    ScrollView {
        VStack(spacing: 20) {
            LabReferenceHeaderView(onAboutEstimate: {})
            LabReferenceBiologicalAgeCard(result: .labPreview(ageDelta: -0.1), startsSettled: true)
            LabReferencePillarSection(pillars: BiologicalAgeResult.labPreview(ageDelta: -0.1).pillarResults)
            LabReferenceDataConfidenceCard(result: .labPreview(ageDelta: -0.1))
        }
        .padding(20)
    }
    .background(PulsarFitnessMonochromeBackground())
    .pulsarFitnessMonochromeAppearance()
}

#Preview("Lab Biological Age - Older High Confidence") {
    ScrollView {
        LabReferenceBiologicalAgeCard(
            result: .labPreview(
                ageDelta: 7,
                confidence: .high,
                lifestyleScore: 91,
                biomarkerScore: 88
            ),
            startsSettled: true
        )
        .padding(20)
    }
    .background(PulsarFitnessMonochromeBackground())
    .pulsarFitnessMonochromeAppearance()
}

#Preview("Lab Gauge Delta Matrix") {
    let deltas: [Double] = [-10, -5, -1, -0.1, 0, 0.1, 1, 5, 10]

    ScrollView {
        LazyVStack(spacing: 12) {
            ForEach(deltas, id: \.self) { delta in
                let result = BiologicalAgeResult.labPreview(ageDelta: delta)
                let presentation = LabBiologicalAgePresentation(result: result)

                VStack(spacing: 4) {
                    HStack {
                        Text(presentation.deltaText)
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text(presentation.statusText)
                            .font(.caption.weight(.medium).monospacedDigit())
                    }

                    LabBiologicalAgeGauge(
                        delta: delta,
                        markerProgress: presentation.gaugeProgress,
                        ticksVisible: true
                    )
                    .frame(height: 66)
                }
                .padding(12)
                .labReferenceGlassSurface(
                    cornerRadius: 20,
                    shadowOpacity: 0.01,
                    shadowRadius: 5,
                    shadowY: 2,
                    fillOpacity: 0.48
                )
            }
        }
        .padding(20)
    }
    .background(PulsarFitnessMonochromeBackground())
    .pulsarFitnessMonochromeAppearance()
}

#Preview("Lab Pillars and Confidence") {
    let result = BiologicalAgeResult.labPreview(ageDelta: -0.1)

    ScrollView {
        VStack(spacing: 18) {
            LabReferencePillarSection(pillars: result.pillarResults)
            LabReferenceDataConfidenceCard(result: result)
        }
        .padding(20)
    }
    .background(PulsarFitnessMonochromeBackground())
    .pulsarFitnessMonochromeAppearance()
}

private extension BiologicalAgeResult {
    static func labPreview(
        ageDelta: Double,
        confidence: LabConfidenceLevel = .low,
        lifestyleScore: Double? = nil,
        biomarkerScore: Double? = nil
    ) -> BiologicalAgeResult {
        let chronologicalAge = 24.0
        return BiologicalAgeResult(
            biologicalAge: chronologicalAge + ageDelta,
            chronologicalAge: chronologicalAge,
            ageDelta: ageDelta,
            paceOfAging: 0.99,
            confidence: confidence,
            updatedAt: .now,
            nextUpdateAt: .now.addingTimeInterval(7 * 24 * 60 * 60),
            physiologicalScore: 90,
            lifestyleScore: lifestyleScore,
            biomarkerScore: biomarkerScore,
            physiologicalContributionYears: ageDelta,
            lifestyleContributionYears: 0,
            biomarkerContributionYears: 0,
            missingDataMessages: [],
            wearableDataDays: 12,
            recentBiomarkerCount: 0,
            lifestyleSurveyCompleted: lifestyleScore != nil
        )
    }
}

private extension LabPillarKind {
    var labReferenceSymbol: String {
        switch self {
        case .physiological: "heart"
        case .lifestyle: "leaf"
        case .biomarkers: "testtube.2"
        }
    }
}
