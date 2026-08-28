import SwiftUI

struct SleepStageTimelineView: View {
    var intervals: [SleepStageInterval]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var timelineVisible = false

    private let stages: [SleepStage] = [.awake, .rem, .core, .deep]

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(stages, id: \.self) { stage in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(SleepStageVisualStyle.color(for: stage))
                                .frame(width: 7, height: 7)

                            Text(SleepStageVisualStyle.displayName(for: stage))
                                .pulsarTextStyle(.metadata)
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: plotHeight / CGFloat(stages.count))
                    }
                }
                .frame(width: stageLabelWidth, alignment: .leading)

                Canvas { context, size in
                    drawTimeline(in: context, size: size)
                }
                .mask(alignment: .leading) {
                    Rectangle()
                        .scaleEffect(
                            x: timelineVisible || reduceMotion ? 1 : 0.001,
                            anchor: .leading
                        )
                }
                .animation(
                    reduceMotion ? nil : .smooth(duration: 0.84),
                    value: timelineVisible
                )
                .frame(height: plotHeight)
            }

            HStack(spacing: 0) {
                Color.clear
                    .frame(width: stageLabelWidth + 12, height: 1)

                ForEach(timeMarkers, id: \.self) { date in
                    Text(date.formatted(.dateTime.hour()))
                        .pulsarTextStyle(.metadata)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .task { timelineVisible = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var visibleIntervals: [SleepStageInterval] {
        intervals
            .filter { $0.stage != .inBed && $0.duration > 0 }
            .sorted { $0.startDate < $1.startDate }
    }

    private var timelineRange: DateInterval {
        let relevant = intervals.isEmpty ? visibleIntervals : intervals
        let start = relevant.map(\.startDate).min() ?? .now
        let end = relevant.map(\.endDate).max() ?? start.addingTimeInterval(1)
        return DateInterval(
            start: start,
            end: max(end, start.addingTimeInterval(1))
        )
    }

    private var timeMarkers: [Date] {
        let markerCount = dynamicTypeSize.isAccessibilitySize ? 3 : 5
        return (0..<markerCount).map { index in
            timelineRange.start.addingTimeInterval(
                timelineRange.duration * Double(index) / Double(markerCount - 1)
            )
        }
    }

    private var plotHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 220 : 164
    }

    private var stageLabelWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 92 : 54
    }

    private var accessibilitySummary: String {
        let start = timelineRange.start.formatted(.dateTime.hour().minute())
        let end = timelineRange.end.formatted(.dateTime.hour().minute())
        return "Sleep stage timeline from \(start) to \(end), with \(visibleIntervals.count) recorded stage intervals."
    }

    private func drawTimeline(in context: GraphicsContext, size: CGSize) {
        let rowHeight = size.height / CGFloat(stages.count)
        let range = timelineRange
        let totalDuration = max(1, range.duration)

        for marker in 0...4 {
            let x = size.width * CGFloat(marker) / 4
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(
                path,
                with: .color(.secondary.opacity(0.09)),
                style: StrokeStyle(lineWidth: 0.6, dash: [3, 5])
            )
        }

        for index in stages.indices {
            let y = rowHeight * CGFloat(index) + (rowHeight / 2)
            let rail = CGRect(
                x: 0,
                y: y - 3,
                width: size.width,
                height: 6
            )
            context.fill(
                Path(roundedRect: rail, cornerRadius: 3),
                with: .color(.secondary.opacity(0.065))
            )
        }

        for interval in visibleIntervals {
            guard let row = rowIndex(for: interval.stage) else { continue }
            let startFraction = interval.startDate.timeIntervalSince(range.start) / totalDuration
            let durationFraction = interval.duration / totalDuration
            let x = max(0, CGFloat(startFraction) * size.width)
            let width = max(5, CGFloat(durationFraction) * size.width)
            let y = rowHeight * CGFloat(row) + (rowHeight / 2)
            let segment = CGRect(
                x: x,
                y: y - 6,
                width: min(width, max(0, size.width - x)),
                height: 12
            )

            context.fill(
                Path(roundedRect: segment, cornerRadius: 6),
                with: .color(
                    SleepStageVisualStyle.color(for: interval.stage).opacity(0.88)
                )
            )
        }
    }

    private func rowIndex(for stage: SleepStage) -> Int? {
        switch stage {
        case .awake:
            0
        case .rem:
            1
        case .core, .asleepUnspecified:
            2
        case .deep:
            3
        case .inBed:
            nil
        }
    }
}
