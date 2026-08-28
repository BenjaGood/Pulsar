import SwiftUI

struct RecoveryTrendGraphView: View {
    var points: [RecoveryTrendPoint]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 8) {
            if points.isEmpty {
                Text("Recovery trend will appear as HealthKit data becomes available.")
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 104)
            } else {
                Canvas { context, size in
                    drawGuides(context: &context, size: size)
                    drawTrend(context: &context, size: size)
                }
                .frame(height: 86)
                .opacity(isVisible ? 1 : 0)

                HStack(spacing: 0) {
                    ForEach(points.enumerated(), id: \.element.id) { index, _ in
                        Text(xAxisLabel(index: index))
                            .pulsarTextStyle(.metadata)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.leading, 38)
                .padding(.trailing, 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seven day recovery trend")
        .accessibilityValue(accessibilitySummary)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .task {
            if reduceMotion {
                isVisible = true
            } else {
                withAnimation(.easeOut(duration: 0.45)) {
                    isVisible = true
                }
            }
        }
    }

    private func drawGuides(context: inout GraphicsContext, size: CGSize) {
        let plot = plotRect(in: size)
        for value in [0, 25, 50, 75, 100] {
            let y = yPosition(score: Double(value), plot: plot)
            var guide = Path()
            guide.move(to: CGPoint(x: plot.minX, y: y))
            guide.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(
                guide,
                with: .color(.secondary.opacity(0.16)),
                style: StrokeStyle(lineWidth: 0.7, dash: [4, 4])
            )
            context.draw(
                Text("\(value)")
                    .font(.caption)
                    .foregroundStyle(.secondary),
                at: CGPoint(x: plot.minX - 8, y: y),
                anchor: .trailing
            )
        }
    }

    private func drawTrend(context: inout GraphicsContext, size: CGSize) {
        let plot = plotRect(in: size)
        let plotted = plottedPoints(in: plot)
        guard let first = plotted.first, let last = plotted.last else { return }

        let line = smoothPath(for: plotted.map(\.point))
        var area = line
        area.addLine(to: CGPoint(x: last.point.x, y: plot.maxY))
        area.addLine(to: CGPoint(x: first.point.x, y: plot.maxY))
        area.closeSubpath()

        context.fill(
            area,
            with: .linearGradient(
                Gradient(colors: [
                    RecoveryDetailsDesign.trendGreen.opacity(0.11),
                    RecoveryDetailsDesign.trendGreen.opacity(0.01)
                ]),
                startPoint: CGPoint(x: plot.midX, y: plot.minY),
                endPoint: CGPoint(x: plot.midX, y: plot.maxY)
            )
        )

        context.stroke(
            line,
            with: .color(RecoveryDetailsDesign.trendGreen),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )

        for plottedPoint in plotted {
            let isCurrent = plottedPoint.index == points.indices.last
            let diameter = isCurrent ? 10.0 : 7.0
            let pointRect = CGRect(
                x: plottedPoint.point.x - diameter / 2,
                y: plottedPoint.point.y - diameter / 2,
                width: diameter,
                height: diameter
            )

            context.fill(
                Path(ellipseIn: pointRect),
                with: .color(RecoveryDetailsDesign.trendGreen)
            )

            if isCurrent {
                let highlightRect = pointRect.insetBy(dx: -5, dy: -5)
                context.fill(
                    Path(ellipseIn: highlightRect),
                    with: .color(RecoveryDetailsDesign.trendGreen.opacity(0.12))
                )
                context.stroke(
                    Path(ellipseIn: highlightRect),
                    with: .color(RecoveryDetailsDesign.trendGreen.opacity(0.32)),
                    lineWidth: 1.5
                )
                context.fill(
                    Path(ellipseIn: pointRect),
                    with: .color(RecoveryDetailsDesign.trendGreen)
                )
            }
        }
    }

    private func plottedPoints(in plot: CGRect) -> [(index: Int, point: CGPoint)] {
        points.enumerated().compactMap { index, trendPoint in
            guard let score = trendPoint.recoveryScore else { return nil }

            let x = xPosition(index: index, count: points.count, plot: plot)
            let y = yPosition(score: score, plot: plot)
            return (index, CGPoint(x: x, y: y))
        }
    }

    private func smoothPath(for points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }

        path.move(to: first)
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpointX = (previous.x + current.x) / 2
            path.addCurve(
                to: current,
                control1: CGPoint(x: midpointX, y: previous.y),
                control2: CGPoint(x: midpointX, y: current.y)
            )
        }
        return path
    }

    private func plotRect(in size: CGSize) -> CGRect {
        CGRect(x: 38, y: 8, width: max(1, size.width - 46), height: max(1, size.height - 16))
    }

    private func xPosition(index: Int, count: Int, plot: CGRect) -> Double {
        guard count > 1 else { return plot.midX }
        return plot.minX + (plot.width * Double(index) / Double(count - 1))
    }

    private func yPosition(score: Double, plot: CGRect) -> Double {
        let normalizedScore = min(max(score / 100, 0), 1)
        return plot.maxY - (plot.height * normalizedScore)
    }

    private func xAxisLabel(index: Int) -> String {
        let daysFromToday = points.count - 1 - index
        return daysFromToday == 0 ? "Today" : "-\(daysFromToday)d"
    }

    private var accessibilitySummary: String {
        let available = points.compactMap(\.recoveryScore)
        guard let latest = available.last else { return "No trend data available" }
        return "\(available.count) days available. Latest score \(Int(latest.rounded()))"
    }
}
