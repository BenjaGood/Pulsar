//
//  StressTimelineChartView.swift
//  Pulsar
//

import SwiftUI

struct StressTimelineChartView: View {
    let summary: StressSummary

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSample: StressSample?

    private let sortedSamples: [StressSample]

    init(samples: [StressSample], summary: StressSummary) {
        self.summary = summary
        sortedSamples = samples.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StressTimelineHeader(datePhrase: datePhrase, statusText: statusText, tint: tint)

            if sortedSamples.count >= 2, let range = timeRange {
                timelinePlot(range: range)
                    .frame(height: 210)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            } else {
                emptyState
                    .frame(maxWidth: .infinity)
                    .frame(height: 210)
            }
        }
        .padding(StressDetailsDesign.cardPadding)
        .stressCardSurface()
    }

    private func timelinePlot(range: DateInterval) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let plotRect = CGRect(
                x: 0,
                y: 4,
                width: max(1, size.width),
                height: max(1, size.height - 32)
            )
            let points = sortedSamples.map { point(for: $0, in: plotRect, range: range) }
            let segments = timelineSegments(points: points, range: range, plotRect: plotRect)

            ZStack(alignment: .topLeading) {
                zoneBackground(in: plotRect)

                ForEach(segments.filter { !$0.isGap }) { segment in
                    segment.areaPath
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(colorScheme == .dark ? 0.13 : 0.09), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                ForEach(segments) { segment in
                    segment.path
                        .stroke(
                            segment.isGap ? secondaryLineStyle : AnyShapeStyle(tint),
                            style: StrokeStyle(
                                lineWidth: segment.isGap ? 1.2 : 1.8,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: segment.isGap ? [5, 6] : []
                            )
                        )
                }

                if let contextSample {
                    contextMarker(for: contextSample, in: plotRect, range: range)
                }

                if let last = sortedSamples.last {
                    endMarker(for: last, in: plotRect, range: range)
                }

                if let selectedSample {
                    selectionMarker(for: selectedSample, in: plotRect, range: range)
                }

                timeLabels(range: range, plotRect: plotRect, size: size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateSelection(nearestSample(to: value.location.x, in: plotRect, range: range))
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Daily stress timeline")
            .accessibilityValue(accessibilityTimelineValue)
            .accessibilityAdjustableAction { direction in
                adjustSelection(direction)
            }
            .sensoryFeedback(.selection, trigger: selectedSample?.id)
        }
    }

    private func zoneBackground(in rect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(PulsarStressScale.bands, id: \.category.rawValue) { band in
                let top = yPosition(for: band.upperBound, in: rect)
                let bottom = yPosition(for: band.lowerBound, in: rect)
                let color = zoneColor(for: band.category)

                Rectangle()
                    .fill(color.opacity(colorScheme == .dark ? 0.055 : 0.075))
                    .frame(width: rect.width, height: max(1, bottom - top))
                    .position(x: rect.midX, y: (top + bottom) / 2)

                Text(zoneTitle(for: band.category))
                    .font(.caption)
                    .foregroundStyle(color)
                    .padding(.leading, 8)
                    .position(x: rect.minX + 31, y: (top + bottom) / 2)
            }
        }
        .clipShape(.rect(cornerRadius: 16))
    }

    private func contextMarker(for sample: StressSample, in rect: CGRect, range: DateInterval) -> some View {
        let anchor = point(for: sample, in: rect, range: range)
        let markerY = max(rect.minY + 18, anchor.y - 34)

        return ZStack {
            Path { path in
                path.move(to: anchor)
                path.addLine(to: CGPoint(x: anchor.x, y: markerY + 12))
            }
            .stroke(tint.opacity(0.24), lineWidth: 1)

            Image(systemName: "leaf.fill")
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(.white.opacity(colorScheme == .dark ? 0.08 : 0.46), in: Circle())
                .glassEffect(reduceTransparency ? .identity : .clear, in: .circle)
                .position(x: anchor.x, y: markerY)
        }
    }

    private func endMarker(for sample: StressSample, in rect: CGRect, range: DateInterval) -> some View {
        let markerPoint = point(for: sample, in: rect, range: range)

        return ZStack {
            Circle()
                .fill(tint.opacity(0.16))
                .frame(width: 24, height: 24)
            Circle()
                .fill(.background)
                .frame(width: 12, height: 12)
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
        }
        .shadow(color: tint.opacity(0.12), radius: 5)
        .position(markerPoint)
    }

    private func selectionMarker(for sample: StressSample, in rect: CGRect, range: DateInterval) -> some View {
        let markerPoint = point(for: sample, in: rect, range: range)
        let calloutX = min(rect.maxX - 52, max(rect.minX + 52, markerPoint.x))
        let calloutY = max(rect.minY + 18, markerPoint.y - 28)

        return ZStack {
            Circle()
                .fill(.background)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(tint, lineWidth: 2))
                .position(markerPoint)

            Text(selectionText(sample))
                .font(.caption)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .position(x: calloutX, y: calloutY)
        }
    }

    private func timeLabels(range: DateInterval, plotRect: CGRect, size: CGSize) -> some View {
        HStack(spacing: 6) {
            Text(range.start, format: .dateTime.hour().minute())
            Spacer(minLength: 2)
            Text("Morning")
            Spacer(minLength: 2)
            Text("Midday")
            Spacer(minLength: 2)
            Text(range.end, format: .dateTime.hour().minute())
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .frame(width: plotRect.width)
        .position(x: plotRect.midX, y: size.height - 8)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            emptyTitle,
            systemImage: "waveform.path.ecg",
            description: Text("Stress samples will appear as recent wearable signals become available.")
        )
    }

    private var timeRange: DateInterval? {
        if let start = summary.queryStart,
           let end = summary.queryEnd,
           end > start {
            return DateInterval(start: start, end: end)
        }

        guard let first = sortedSamples.first?.timestamp,
              let last = sortedSamples.last?.timestamp,
              last > first else {
            return nil
        }

        return DateInterval(start: first, end: last)
    }

    private var tint: Color {
        summary.score.map { stressGaugeTint(for: $0) } ?? .secondary
    }

    private var secondaryLineStyle: AnyShapeStyle {
        AnyShapeStyle(Color.secondary.opacity(0.38))
    }

    private var statusText: String {
        [summary.displayLevelText, summary.score.map(String.init)]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private var datePhrase: String {
        let date = summary.date ?? summary.queryStart ?? sortedSamples.first?.timestamp ?? .now
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        return "on \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var contextSample: StressSample? {
        sortedSamples.first { sample in
            sample.context == .recovery || sample.context == .rest
        }
    }

    private var emptyTitle: String {
        switch summary.state {
        case .buildingBaseline:
            return "Building your stress timeline"
        case .noData:
            return "No stress data for this date"
        case .ready, .lowConfidence:
            return "No stress samples for this date"
        case .workoutPaused:
            return "Stress is paused during your workout"
        case .cooldown:
            return "Stress is paused during cooldown"
        }
    }

    private var accessibilityTimelineValue: String {
        guard let sample = selectedSample ?? sortedSamples.last else {
            return "No samples"
        }
        return selectionText(sample)
    }

    private func point(for sample: StressSample, in rect: CGRect, range: DateInterval) -> CGPoint {
        let xProgress = sample.timestamp.timeIntervalSince(range.start) / max(1, range.duration)
        let yProgress = PulsarStressScale.clampedScore(sample.score) / 100
        return CGPoint(
            x: rect.minX + rect.width * CGFloat(ScoreMath.clamp(xProgress)),
            y: rect.maxY - rect.height * CGFloat(yProgress)
        )
    }

    private func timelineSegments(points: [CGPoint], range: DateInterval, plotRect: CGRect) -> [StressTimelineSegment] {
        guard points.count >= 2, points.count == sortedSamples.count else { return [] }
        let maxGap = PulsarStressScale.maxContinuousTimelineGap(rangeDuration: range.duration)

        return (1..<points.count).map { index in
            let previous = points[index - 1]
            let current = points[index]
            let controlOffset = (current.x - previous.x) * 0.42
            var path = Path()
            path.move(to: previous)
            path.addCurve(
                to: current,
                control1: CGPoint(x: previous.x + controlOffset, y: previous.y),
                control2: CGPoint(x: current.x - controlOffset, y: current.y)
            )

            var areaPath = path
            areaPath.addLine(to: CGPoint(x: current.x, y: plotRect.maxY))
            areaPath.addLine(to: CGPoint(x: previous.x, y: plotRect.maxY))
            areaPath.closeSubpath()

            return StressTimelineSegment(
                id: index,
                path: path,
                areaPath: areaPath,
                isGap: sortedSamples[index].timestamp.timeIntervalSince(sortedSamples[index - 1].timestamp) > maxGap
            )
        }
    }

    private func nearestSample(to x: CGFloat, in rect: CGRect, range: DateInterval) -> StressSample? {
        sortedSamples.min { lhs, rhs in
            abs(point(for: lhs, in: rect, range: range).x - x) < abs(point(for: rhs, in: rect, range: range).x - x)
        }
    }

    private func updateSelection(_ sample: StressSample?) {
        guard selectedSample?.id != sample?.id else { return }
        selectedSample = sample
    }

    private func adjustSelection(_ direction: AccessibilityAdjustmentDirection) {
        guard !sortedSamples.isEmpty else { return }
        let currentIndex = selectedSample.flatMap { selected in
            sortedSamples.firstIndex { $0.id == selected.id }
        } ?? (sortedSamples.count - 1)

        switch direction {
        case .increment:
            updateSelection(sortedSamples[min(currentIndex + 1, sortedSamples.count - 1)])
        case .decrement:
            updateSelection(sortedSamples[max(currentIndex - 1, 0)])
        @unknown default:
            break
        }
    }

    private func selectionText(_ sample: StressSample) -> String {
        let score = PulsarStressScale.roundedScore(sample.score)
        return "\(sample.timestamp.formatted(date: .omitted, time: .shortened)) · \(score) · \(zoneTitle(for: PulsarStressCategory.category(for: score)))"
    }

    private func yPosition(for score: Double, in rect: CGRect) -> CGFloat {
        rect.maxY - rect.height * CGFloat(PulsarStressScale.clampedScore(score) / 100)
    }

    private func zoneColor(for category: PulsarStressCategory) -> Color {
        switch category {
        case .low:
            return Color(red: 0.25, green: 0.61, blue: 0.39)
        case .balanced:
            return Color(red: 0.29, green: 0.55, blue: 0.72)
        case .elevated:
            return Color(red: 0.83, green: 0.59, blue: 0.24)
        case .high:
            return Color(red: 0.78, green: 0.35, blue: 0.33)
        }
    }

    private func zoneTitle(for category: PulsarStressCategory) -> String {
        switch category {
        case .low:
            return "Low"
        case .balanced:
            return "Balanced"
        case .elevated:
            return "Elevated"
        case .high:
            return "High"
        }
    }
}

#Preview("Stress Timeline") {
    StressTimelineChartView(
        samples: MockHealthData.stressDetailSummary.dailySamples,
        summary: MockHealthData.stressDetailSummary
    )
    .padding()
    .background(StressDetailsDesign.pageBackground)
}
