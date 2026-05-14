//
//  StressTimelineChartView.swift
//  Pulsar
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct StressTimelineChartView: View {
    var samples: [StressSample]
    var summary: StressSummary

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSample: StressSample?

    private var sortedSamples: [StressSample] {
        samples.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if sortedSamples.count >= 2, let range = timeRange {
                chart(range: range)
                    .frame(height: 228)
                selectionReadout
                durationDistribution
            } else {
                emptyState
                    .frame(maxWidth: .infinity)
                    .frame(height: 228)
            }
        }
        .padding(18)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(cardBorder)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Stress Timeline")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(primaryText)
                Text("How your physiological load moved \(datePhrase)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(secondaryText)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text("\(summary.displayLevelText) \(summary.score.map { "\($0)" } ?? "")")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tint.opacity(colorScheme == .dark ? 0.15 : 0.10), in: Capsule())
        }
    }

    private func chart(range: DateInterval) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            let plotRect = CGRect(x: 10, y: 14, width: max(1, size.width - 20), height: max(1, size.height - 46))
            let points = sortedSamples.map { point(for: $0, in: plotRect, range: range) }
            let segments = timelineSegments(points: points, samples: sortedSamples, range: range, plotRect: plotRect)
            let nowX = nowXPosition(in: plotRect, range: range)
            let markerPlacements = contextMarkerPlacements(in: plotRect, range: range, nowX: nowX)

            ZStack(alignment: .topLeading) {
                zoneBackground(in: plotRect)

                grid(in: plotRect)

                ForEach(segments.filter { !$0.isGap }) { segment in
                    segment.areaPath
                        .fill(
                            LinearGradient(
                                colors: [
                                    stressColor(for: segment.endScore).opacity(colorScheme == .dark ? 0.24 : 0.16),
                                    stressColor(for: segment.startScore).opacity(colorScheme == .dark ? 0.08 : 0.06),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                ForEach(segments) { segment in
                    segment.path
                        .stroke(
                            segment.isGap ? AnyShapeStyle(secondaryText.opacity(0.30)) : AnyShapeStyle(
                                LinearGradient(
                                    colors: [
                                        stressColor(for: segment.startScore),
                                        stressColor(for: segment.endScore)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            ),
                            style: StrokeStyle(
                                lineWidth: segment.isGap ? 1.5 : 3.4,
                                lineCap: segment.isGap ? .round : .butt,
                                lineJoin: .round,
                                dash: segment.isGap ? [4, 5] : []
                            )
                        )
                        .shadow(color: stressColor(for: segment.endScore).opacity(segment.isGap ? 0 : (colorScheme == .dark ? 0.20 : 0.10)), radius: 7, y: 3)
                }

                peakAndEndMarkers(in: plotRect, range: range)

                contextMarkers(markerPlacements)

                nowMarker(in: plotRect, range: range)

                if let selected = selectedSample ?? sortedSamples.last {
                    selectedMarker(for: selected, in: plotRect, range: range)
                }

                timeLabels(range: range, size: size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateSelection(nearestSample(to: value.location.x, in: plotRect, range: range))
                    }
            )
        }
    }

    private var selectionReadout: some View {
        let selected = selectedSample ?? sortedSamples.last
        let selectedColor = stressColor(for: selected?.score ?? Double(summary.score ?? 50))
        return HStack(spacing: 8) {
            Image(systemName: icon(for: selected?.context))
                .font(.caption.weight(.semibold))
                .foregroundStyle(selectedColor)
            Text(selectedText(for: selected))
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.64), in: Capsule())
    }

    private var durationDistribution: some View {
        let buckets = durationBuckets
        let total = buckets.reduce(0) { $0 + $1.duration }
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("Duration by zone")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(primaryText)
                Spacer(minLength: 4)
                Text(total > 0 ? "Usable \(durationText(total))" : "No usable intervals")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(secondaryText)
            }

            HStack(spacing: 7) {
                ForEach(buckets) { bucket in
                    let color = stressColor(for: (bucket.category.lowerBound + bucket.category.upperBound) / 2)
                    VStack(alignment: .leading, spacing: 5) {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(color.opacity(colorScheme == .dark ? 0.16 : 0.11))
                                Capsule()
                                    .fill(color)
                                    .frame(width: proxy.size.width * CGFloat(ScoreMath.clamp(bucket.percentage)))
                            }
                        }
                        .frame(height: 4)

                        Text(bucket.category.displayText)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)

                        Text(bucket.duration > 0 ? durationText(bucket.duration) : "--")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(secondaryText)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.70)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(colorScheme == .dark ? Color.white.opacity(0.050) : Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(tint.opacity(0.82))
            Text(emptyTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primaryText)
            Text("Stress confidence will improve as Pulsar learns your daily signal pattern.")
                .font(.caption.weight(.medium))
                .foregroundStyle(secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
    }

    private var timeRange: DateInterval? {
        guard let first = sortedSamples.first?.timestamp,
              let last = sortedSamples.last?.timestamp,
              last > first else { return nil }
        return DateInterval(start: first, end: last)
    }

    private var tint: Color {
        summary.level?.stressTint(colorScheme: colorScheme) ?? Color(red: 0.45, green: 0.62, blue: 0.92)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color(red: 0.08, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color(red: 0.35, green: 0.39, blue: 0.47)
    }

    private var emptyTitle: String {
        switch summary.state {
        case .buildingBaseline:
            return "Build more baseline data"
        case .noData:
            return "No stress data for this date"
        case .ready, .lowConfidence:
            return "No stress samples for this date"
        case .workoutPaused:
            return "Stress paused during workout"
        case .cooldown:
            return "Cooldown pause active"
        }
    }

    private var datePhrase: String {
        let date = summary.date ?? summary.queryStart ?? sortedSamples.first?.timestamp ?? Date()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        return "on \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func point(for sample: StressSample, in rect: CGRect, range: DateInterval) -> CGPoint {
        let xProgress = range.duration > 0 ? sample.timestamp.timeIntervalSince(range.start) / range.duration : 0
        let yProgress = PulsarStressScale.clampedScore(sample.score) / 100
        return CGPoint(
            x: rect.minX + rect.width * CGFloat(ScoreMath.clamp(xProgress)),
            y: rect.maxY - rect.height * CGFloat(yProgress)
        )
    }

    private func smoothPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let controlOffset = (current.x - previous.x) * 0.42
            path.addCurve(
                to: current,
                control1: CGPoint(x: previous.x + controlOffset, y: previous.y),
                control2: CGPoint(x: current.x - controlOffset, y: current.y)
            )
        }
        return path
    }

    private func timelineSegments(points: [CGPoint], samples: [StressSample], range: DateInterval, plotRect: CGRect) -> [StressTimelineSegment] {
        guard points.count >= 2, points.count == samples.count else { return [] }
        let maxContinuousGap = PulsarStressScale.maxContinuousTimelineGap(rangeDuration: range.duration)
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
                startScore: samples[index - 1].score,
                endScore: samples[index].score,
                isGap: samples[index].timestamp.timeIntervalSince(samples[index - 1].timestamp) > maxContinuousGap
            )
        }
    }

    private func zoneBackground(in rect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(stressZoneBands) { band in
                let top = yPosition(forScore: band.upper, in: rect)
                let bottom = yPosition(forScore: band.lower, in: rect)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(band.color.opacity(colorScheme == .dark ? 0.105 : 0.070))
                    .frame(width: rect.width, height: max(1, bottom - top))
                    .position(x: rect.midX, y: (top + bottom) / 2)

                Text(band.title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(band.color.opacity(colorScheme == .dark ? 0.58 : 0.68))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(colorScheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.42), in: Capsule())
                    .position(x: rect.minX + 34, y: (top + bottom) / 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func grid(in rect: CGRect) -> some View {
        ZStack {
            ForEach([25.0, 50.0, 75.0], id: \.self) { score in
                let y = yPosition(forScore: score, in: rect)
                Path { path in
                    path.move(to: CGPoint(x: rect.minX, y: y))
                    path.addLine(to: CGPoint(x: rect.maxX, y: y))
                }
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
            }
        }
    }

    private func contextMarkers(_ markers: [ContextMarkerPlacement]) -> some View {
        ZStack {
            ForEach(markers) { marker in
                Path { path in
                    path.move(to: marker.anchor)
                    path.addLine(to: marker.position)
                }
                .stroke(stressColor(for: marker.sample.score).opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

                Circle()
                    .fill(stressColor(for: marker.sample.score))
                    .frame(width: 5, height: 5)
                    .shadow(color: stressColor(for: marker.sample.score).opacity(0.35), radius: 5)
                    .position(marker.anchor)

                Image(systemName: icon(for: marker.sample.context))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(stressColor(for: marker.sample.score))
                    .frame(width: 20, height: 20)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(stressColor(for: marker.sample.score).opacity(0.24), lineWidth: 1))
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.08), radius: 6, y: 3)
                    .position(marker.position)
            }
        }
    }

    private var contextMarkerSamples: [StressSample] {
        var markers: [StressSample] = []
        var lastContext: StressContext?
        for sample in sortedSamples {
            guard let context = sample.context, context != .unknown else { continue }
            if context != lastContext {
                markers.append(sample)
                lastContext = context
            }
        }
        return Array(markers.prefix(6))
    }

    private func contextMarkerPlacements(in rect: CGRect, range: DateInterval, nowX: CGFloat?) -> [ContextMarkerPlacement] {
        var placements: [ContextMarkerPlacement] = []
        let markerSize: CGFloat = 20
        let horizontalPadding = markerSize / 2 + 2

        for sample in contextMarkerSamples {
            let anchor = point(for: sample, in: rect, range: range)
            var x = anchor.x
            if let nowX, abs(x - nowX) < 18 {
                x += x < rect.midX ? -18 : 18
            }
            x = min(rect.maxX - horizontalPadding, max(rect.minX + horizontalPadding, x))

            let prefersBelow = anchor.y < rect.minY + 38
            let baseY = prefersBelow ? anchor.y + 30 : anchor.y - 30
            let candidates: [CGFloat] = [
                baseY,
                baseY - 24,
                baseY + 24,
                baseY - 46,
                baseY + 46
            ].map {
                min(rect.maxY - markerSize / 2, max(rect.minY + markerSize / 2, $0))
            }

            let y = candidates.first { candidate in
                placements.allSatisfy { existing in
                    abs(existing.position.x - x) > 26 || abs(existing.position.y - candidate) > 24
                }
            } ?? candidates[0]

            placements.append(
                ContextMarkerPlacement(
                    id: "\(sample.id.timeIntervalSinceReferenceDate)-\(sample.context?.rawValue ?? "unknown")",
                    sample: sample,
                    anchor: anchor,
                    position: CGPoint(x: x, y: y)
                )
            )
        }

        return placements
    }

    private func nowMarker(in rect: CGRect, range: DateInterval) -> some View {
        let now = Date()
        let isVisible = range.contains(now)
        let x = nowXPosition(in: rect, range: range) ?? rect.maxX

        return ZStack(alignment: .topLeading) {
            Path { path in
                guard isVisible else { return }
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            .stroke(tint.opacity(0.36), style: StrokeStyle(lineWidth: 1.4, dash: [5, 6], dashPhase: 0))

            if isVisible {
                Text("Now")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .position(x: min(rect.maxX - 18, max(rect.minX + 18, x)), y: rect.minY + 8)
            }
        }
    }

    private func selectedMarker(for sample: StressSample, in rect: CGRect, range: DateInterval) -> some View {
        let point = point(for: sample, in: rect, range: range)
        let color = stressColor(for: sample.score)
        return ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 26, height: 26)
            Circle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.96) : Color.white)
                .frame(width: 12, height: 12)
                .overlay(Circle().fill(color).frame(width: 6, height: 6))
        }
        .shadow(color: color.opacity(0.22), radius: 8)
        .position(point)
    }

    private func peakAndEndMarkers(in rect: CGRect, range: DateInterval) -> some View {
        ZStack {
            if let peak = sortedSamples.max(by: { $0.score < $1.score }), peak.score >= PulsarStressScale.highLowerBound {
                scoreCallout(sample: peak, label: "Peak", rect: rect, range: range)
            }

            if let last = sortedSamples.last {
                endScoreDot(sample: last, rect: rect, range: range)
            }
        }
    }

    private func scoreCallout(sample: StressSample, label: String, rect: CGRect, range: DateInterval) -> some View {
        let point = point(for: sample, in: rect, range: range)
        let color = stressColor(for: sample.score)
        let y = max(rect.minY + 16, point.y - 22)
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text("\(label) \(PulsarStressScale.roundedScore(sample.score))")
                .font(.system(size: 9, weight: .bold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.20), lineWidth: 0.8))
        .position(x: min(rect.maxX - 34, max(rect.minX + 34, point.x)), y: y)
    }

    private func endScoreDot(sample: StressSample, rect: CGRect, range: DateInterval) -> some View {
        let point = point(for: sample, in: rect, range: range)
        let color = stressColor(for: sample.score)
        return ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 20, height: 20)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.white.opacity(colorScheme == .dark ? 0.88 : 0.76), lineWidth: 1.2))
        }
        .shadow(color: color.opacity(0.32), radius: 8)
        .position(point)
    }

    private func timeLabels(range: DateInterval, size: CGSize) -> some View {
        let plotRect = CGRect(x: 10, y: 14, width: max(1, size.width - 20), height: max(1, size.height - 46))
        return ZStack(alignment: .topLeading) {
            ForEach(timeLabelItems(range: range, rect: plotRect, size: size)) { label in
                Text(label.title)
                    .font(.caption2.weight(label.isPrimary ? .bold : .semibold))
                    .foregroundStyle(label.isPrimary ? tint.opacity(0.86) : secondaryText.opacity(0.84))
                    .position(x: label.x, y: size.height - 9)
            }
        }
        .frame(width: size.width)
    }

    private func nearestSample(to x: CGFloat, in rect: CGRect, range: DateInterval) -> StressSample? {
        sortedSamples.min { lhs, rhs in
            let lhsX = point(for: lhs, in: rect, range: range).x
            let rhsX = point(for: rhs, in: rect, range: range).x
            return abs(lhsX - x) < abs(rhsX - x)
        }
    }

    private func updateSelection(_ sample: StressSample?) {
        guard selectedSample?.id != sample?.id else { return }
        selectedSample = sample
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    private func selectedText(for sample: StressSample?) -> String {
        guard let sample else { return "Select a point to inspect the day" }
        let score = PulsarStressScale.roundedScore(sample.score)
        let level = stressLevelText(for: score)
        let reason = reason(for: sample)
        return "\(sample.timestamp.formatted(date: .omitted, time: .shortened)) · \(score) · \(level) · \(reason)"
    }

    private func icon(for context: StressContext?) -> String {
        switch context {
        case .sleep:
            return "moon.zzz.fill"
        case .workout:
            return "figure.run"
        case .rest, .recovery:
            return "leaf.fill"
        case .active:
            return "bolt.heart.fill"
        case .unknown, nil:
            return "waveform.path.ecg"
        }
    }

    private func reason(for sample: StressSample) -> String {
        switch sample.context {
        case .sleep:
            return "Sleep"
        case .workout:
            return "Workout pause"
        case .rest:
            return "Resting physiology"
        case .recovery:
            return "Cooldown pause"
        case .active:
            return "Activity context"
        case .unknown, nil:
            return summary.driverInsights.first ?? "Wearable signal"
        }
    }

    private func stressLevelText(for score: Int) -> String {
        switch StressLevel.level(for: score) {
        case .low:
            return "Low"
        case .balanced:
            return "Medium"
        case .elevated:
            return "Elevated"
        case .high:
            return "High"
        }
    }

    private func nowXPosition(in rect: CGRect, range: DateInterval) -> CGFloat? {
        let now = Date()
        guard range.contains(now) else { return nil }
        return rect.minX + rect.width * CGFloat(ScoreMath.clamp(now.timeIntervalSince(range.start) / max(1, range.duration)))
    }

    private func timeLabelItems(range: DateInterval, rect: CGRect, size: CGSize) -> [TimelineLabelItem] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: range.start)
        let candidates: [(String, Date, Bool)] = [
            (range.start.formatted(date: .omitted, time: .shortened), range.start, false),
            ("Morning", calendar.date(bySettingHour: 9, minute: 0, second: 0, of: startOfDay) ?? range.start, false),
            ("Midday", calendar.date(bySettingHour: 12, minute: 0, second: 0, of: startOfDay) ?? range.start, false),
            ("Afternoon", calendar.date(bySettingHour: 16, minute: 0, second: 0, of: startOfDay) ?? range.start, false),
            ("Now", Date(), true),
            (range.end.formatted(date: .omitted, time: .shortened), range.end, false)
        ]

        var labels: [TimelineLabelItem] = []
        for candidate in candidates where range.contains(candidate.1) || candidate.1 == range.start || candidate.1 == range.end {
            let x = rect.minX + rect.width * CGFloat(ScoreMath.clamp(candidate.1.timeIntervalSince(range.start) / max(1, range.duration)))
            guard labels.allSatisfy({ abs($0.x - x) > 42 || candidate.2 }) else { continue }
            labels.append(TimelineLabelItem(id: "\(candidate.0)-\(candidate.1.timeIntervalSinceReferenceDate)", title: candidate.0, x: x, isPrimary: candidate.2))
        }
        return labels
    }

    private var stressZoneBands: [StressZoneBand] {
        PulsarStressScale.bands.map { band in
            StressZoneBand(
                title: band.category.rawValue,
                lower: band.lowerBound,
                upper: band.upperBound,
                color: stressColor(for: (band.lowerBound + band.upperBound) / 2)
            )
        }
    }

    private func stressColor(for score: Double) -> Color {
        StressLevel.level(for: PulsarStressScale.roundedScore(score)).stressTint(colorScheme: colorScheme)
    }

    private func yPosition(forScore score: Double, in rect: CGRect) -> CGFloat {
        rect.maxY - rect.height * CGFloat(PulsarStressScale.clampedScore(score) / 100)
    }

    private var durationBuckets: [PulsarStressDurationBucket] {
        PulsarStressTimelineDistribution.buckets(
            samples: sortedSamples.map { PulsarStressTimelineSample(timestamp: $0.timestamp, score: $0.score) },
            range: timeRange
        )
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int((duration / 60).rounded()))
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }
        return "\(totalMinutes)m"
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color.white.opacity(0.08),
                            Color(red: 0.06, green: 0.08, blue: 0.14).opacity(0.86),
                            tint.opacity(0.08)
                        ]
                        : [
                            Color.white.opacity(0.86),
                            Color(red: 0.96, green: 0.98, blue: 1.00).opacity(0.76),
                            tint.opacity(0.06)
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.18 : 0.82),
                        tint.opacity(colorScheme == .dark ? 0.13 : 0.20),
                        Color.black.opacity(colorScheme == .dark ? 0.14 : 0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}

private struct StressTimelineSegment: Identifiable {
    var id: Int
    var path: Path
    var areaPath: Path
    var startScore: Double
    var endScore: Double
    var isGap: Bool
}

private struct StressZoneBand: Identifiable {
    var id: String { title }
    var title: String
    var lower: Double
    var upper: Double
    var color: Color
}

private struct ContextMarkerPlacement: Identifiable {
    var id: String
    var sample: StressSample
    var anchor: CGPoint
    var position: CGPoint
}

private struct TimelineLabelItem: Identifiable {
    var id: String
    var title: String
    var x: CGFloat
    var isPrimary: Bool
}

#Preview("Stress Timeline") {
    StressTimelineChartView(samples: MockHealthData.stressDetailSummary.dailySamples, summary: MockHealthData.stressDetailSummary)
        .padding()
        .background(PulsarSectionBackground())
}
