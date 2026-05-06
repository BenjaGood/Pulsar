//
//  StrainDetailsView.swift
//  Pulsar
//

import SwiftUI

struct StrainDetailsView: View {
    @StateObject private var viewModel: StrainDetailsViewModel
    @State private var contentVisible = false

    init(viewModel: StrainDetailsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(StrainDetailsBackground())
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load() }
        .task {
            withAnimation(.smooth(duration: 0.45)) { contentVisible = true }
        }
        .safeAreaInset(edge: .top) {
            PulsarSyncStatusPill()
                .padding(.horizontal, 18)
                .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            StrainDetailsLoadingView()
        case .permissionRequired:
            StrainDetailsStateView(symbol: "heart.text.square", title: "Health Permission Required", message: "Grant HealthKit activity, workout, and heart-rate permissions to view real strain details.")
        case .noData:
            StrainDetailsStateView(symbol: "figure.walk", title: "No Strain Data Available", message: "Strain details appear after HealthKit records workouts, movement, calories, or heart-rate samples for this day.")
        case .error(let message):
            StrainDetailsStateView(symbol: "exclamationmark.triangle", title: "Could Not Load Strain", message: message)
        case .loaded:
            loadedContent
        }
    }

    private var loadedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            StrainDetailsHeader(viewModel: viewModel)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 14)
            StrainHeartLoadCard(chart: viewModel.heartLoadChart)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 18)
            StrainMetricsGrid(metrics: viewModel.metricTiles)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 22)
            StrainWorkoutSection(workouts: viewModel.summary.workouts)
            StrainHeartSection(summary: viewModel.summary)
            StrainStepsSection(steps: viewModel.summary.steps, goal: viewModel.summary.stepGoal, progress: viewModel.stepProgress)
            StrainInsightsSection(insights: viewModel.insights)
            StrainDataQualitySection(viewModel: viewModel)
        }
        .animation(.smooth(duration: 0.45), value: contentVisible)
    }
}

private struct StrainDetailsHeader: View {
    @ObservedObject var viewModel: StrainDetailsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Strain")
                    .font(.largeTitle.weight(.bold))
                Text(viewModel.dateSubtitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .lastTextBaseline) {
                Text(viewModel.scoreText)
                    .font(.system(size: 58, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 12)
                Text(viewModel.statusText)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.orange.opacity(0.14), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulsarLiquidGlass(cornerRadius: 34)
    }
}

private struct StrainHeartLoadCard: View {
    var chart: StrainHeartLoadChartModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !chart.callouts.isEmpty {
                HeartLoadCalloutRow(callouts: chart.callouts)
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Heart Load")
                        .font(.title3.weight(.semibold))
                    Text("Heart rate and workout intensity across the day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HeartLoadTimelineView(chart: chart)
                .frame(height: 276)
            HeartLoadLegend(hasHeartRate: chart.hasHeartRate, hasWorkouts: chart.hasWorkouts, hasMovement: chart.hasMovement)
        }
        .padding(18)
        .pulsarLiquidGlass(cornerRadius: 30)
    }
}

private struct HeartLoadCalloutRow: View {
    var callouts: [StrainHeartLoadCallout]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(callouts) { callout in
                VStack(alignment: .leading, spacing: 5) {
                    Image(systemName: callout.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(callout.title)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(callout.value)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

struct HeartLoadTimelineView: View {
    var chart: StrainHeartLoadChartModel
    @State private var drawProgress = 0.0
    @State private var bandsVisible = false

    var body: some View {
        GeometryReader { proxy in
            let layout = HeartLoadChartLayout(size: proxy.size)
            ZStack(alignment: .topLeading) {
                HeartLoadPlotBackground(chart: chart, layout: layout)
                workoutBands(layout: layout)
                    .opacity(bandsVisible ? 1 : 0)
                    .animation(.smooth(duration: 0.5), value: bandsVisible)
                if chart.hasHeartRate {
                    heartRateLine(layout: layout)
                    peakHeartLabel(layout: layout)
                } else if chart.hasWorkouts {
                    HeartLoadPartialState(symbol: "heart.slash", title: "Heart rate data is unavailable for this day.", message: "Workout blocks still show when strain was created.")
                        .frame(width: layout.plotRect.width, height: layout.plotRect.height)
                        .position(x: layout.plotRect.midX, y: layout.plotRect.midY)
                } else if chart.hasMovement {
                    HeartLoadMovementState(chart: chart)
                        .frame(width: layout.plotRect.width, height: layout.plotRect.height)
                        .position(x: layout.plotRect.midX, y: layout.plotRect.midY)
                } else {
                    HeartLoadPartialState(symbol: "waveform.path.ecg", title: "No heart load data yet", message: "Strain appears after HealthKit records heart rate, workouts, or movement for this day.")
                        .frame(width: layout.plotRect.width, height: layout.plotRect.height)
                        .position(x: layout.plotRect.midX, y: layout.plotRect.midY)
                }
                markerLabels(layout: layout)
                note(layout: layout)
            }
        }
        .onAppear {
            bandsVisible = true
            withAnimation(.smooth(duration: 0.9)) { drawProgress = 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart load timeline")
    }

    private func workoutBands(layout: HeartLoadChartLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(chart.workoutBands) { band in
                let frame = bandFrame(band, layout: layout)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [.orange.opacity(0.16), .pink.opacity(0.10)], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.orange.opacity(0.24), lineWidth: 1)
                    )
                    .shadow(color: .orange.opacity(0.20), radius: 18, y: 6)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                if frame.width > 54 {
                    Text(workoutLabel(for: band))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: frame.width - 10, alignment: .leading)
                        .position(x: frame.midX, y: layout.plotRect.minY + 15)
                }
            }
        }
        .mask {
            Rectangle()
                .frame(width: layout.plotRect.width, height: layout.plotRect.height)
                .position(x: layout.plotRect.midX, y: layout.plotRect.midY)
        }
    }

    private func heartRateLine(layout: HeartLoadChartLayout) -> some View {
        let points = chart.heartRatePoints.map { point(for: $0, layout: layout) }
        return ZStack(alignment: .leading) {
            HeartLoadLineShape(points: points)
                .stroke(.pink.opacity(0.22), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                .blur(radius: 5)
            HeartLoadLineShape(points: points)
                .stroke(LinearGradient(colors: [.cyan, .orange, .pink], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            ForEach(chart.heartRatePoints.suffix(24)) { point in
                Circle()
                    .fill(.white.opacity(0.72))
                    .frame(width: 3, height: 3)
                    .position(self.point(for: point, layout: layout))
            }
        }
        .mask {
            Rectangle()
                .frame(width: layout.plotRect.width * drawProgress, height: layout.plotRect.height)
                .position(x: layout.plotRect.minX + layout.plotRect.width * drawProgress / 2, y: layout.plotRect.midY)
        }
    }

    @ViewBuilder
    private func peakHeartLabel(layout: HeartLoadChartLayout) -> some View {
        if let peak = chart.heartRatePoints.max(by: { $0.bpm < $1.bpm }) {
            let location = point(for: peak, layout: layout)
            let labelSize = CGSize(width: 66, height: 26)
            let labelX = min(max(layout.plotRect.minX + labelSize.width / 2 + 4, location.x), layout.plotRect.maxX - labelSize.width / 2 - 4)
            let preferredY = location.y - 24 < layout.plotRect.minY + 4 ? location.y + 24 : location.y - 24
            let labelY = min(max(layout.plotRect.minY + labelSize.height / 2 + 4, preferredY), layout.plotRect.maxY - labelSize.height / 2 - 4)
            Text("\(Int(peak.bpm.rounded())) bpm")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.black.opacity(0.30), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
                .position(x: labelX, y: labelY)
                .opacity(drawProgress)
        }
    }

    private func markerLabels(layout: HeartLoadChartLayout) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(visibleMarkers(for: layout)) { marker in
                let x = xPosition(for: marker.date, layout: layout)
                Text(marker.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .position(x: min(max(layout.plotRect.minX + 8, x), layout.plotRect.maxX - 8), y: layout.axisY)
            }
        }
    }

    private func note(layout: HeartLoadChartLayout) -> some View {
        Text(chart.intensityDescription)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .frame(width: layout.plotRect.width + layout.leftGutter, alignment: .center)
            .position(x: layout.plotRect.midX - layout.leftGutter / 2, y: layout.noteY)
    }

    private func point(for point: HeartRatePoint, layout: HeartLoadChartLayout) -> CGPoint {
        CGPoint(x: xPosition(for: point.date, layout: layout), y: yPosition(for: point.bpm, layout: layout))
    }

    private func bandFrame(_ band: WorkoutTimelineBand, layout: HeartLoadChartLayout) -> CGRect {
        let startX = xPosition(for: band.startDate, layout: layout)
        let endX = xPosition(for: band.endDate, layout: layout)
        let bandWidth = max(12, endX - startX)
        return CGRect(x: startX, y: layout.plotRect.minY, width: bandWidth, height: layout.plotRect.height)
    }

    private func xPosition(for date: Date, layout: HeartLoadChartLayout) -> CGFloat {
        let total = max(1, chart.range.duration)
        let value = date.timeIntervalSince(chart.range.start) / total
        return min(max(layout.plotRect.minX, layout.plotRect.minX + CGFloat(value) * layout.plotRect.width), layout.plotRect.maxX)
    }

    private func yPosition(for bpm: Double, layout: HeartLoadChartLayout) -> CGFloat {
        let span = max(1, chart.yAxisMax - chart.yAxisMin)
        let normalized = (bpm - chart.yAxisMin) / span
        return layout.plotRect.maxY - min(max(0, CGFloat(normalized)), 1) * layout.plotRect.height
    }

    private func visibleMarkers(for layout: HeartLoadChartLayout) -> [StrainTimelineMarker] {
        let minimumSpacing: CGFloat = layout.size.width < 360 ? 44 : 52
        var markers = chart.markers.sorted { $0.date < $1.date }
        if let now = markers.last, now.label == "Now" {
            markers.removeAll { marker in
                marker.id != now.id && abs(xPosition(for: marker.date, layout: layout) - xPosition(for: now.date, layout: layout)) < minimumSpacing
            }
        }
        var visible: [StrainTimelineMarker] = []
        for marker in markers {
            let x = xPosition(for: marker.date, layout: layout)
            if marker.label == "Now" || visible.allSatisfy({ abs(xPosition(for: $0.date, layout: layout) - x) >= minimumSpacing }) {
                visible.append(marker)
            }
        }
        return visible
    }

    private func workoutLabel(for band: WorkoutTimelineBand) -> String {
        "\(band.workoutType) · \(StrainDetailsViewModel.durationText(minutes: band.duration / 60))"
    }
}

private struct HeartLoadChartLayout {
    var size: CGSize

    var leftGutter: CGFloat { size.width < 360 ? 44 : 52 }
    var rightGutter: CGFloat { size.width < 360 ? 18 : 24 }
    var topInset: CGFloat { 28 }
    var axisHeight: CGFloat { 24 }
    var noteHeight: CGFloat { 28 }
    var bottomInset: CGFloat { 4 }

    var plotRect: CGRect {
        let height = max(118, size.height - topInset - axisHeight - noteHeight - bottomInset)
        return CGRect(
            x: leftGutter,
            y: topInset,
            width: max(1, size.width - leftGutter - rightGutter),
            height: min(height, max(1, size.height - topInset - axisHeight - noteHeight - bottomInset))
        )
    }

    var axisY: CGFloat { plotRect.maxY + 16 }
    var noteY: CGFloat { axisY + 24 }
}

private struct HeartLoadPlotBackground: View {
    var chart: StrainHeartLoadChartModel
    var layout: HeartLoadChartLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.055), .white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: layout.plotRect.width, height: layout.plotRect.height)
                .position(x: layout.plotRect.midX, y: layout.plotRect.midY)
            ForEach(chart.references) { reference in
                let y = yPosition(for: reference.bpm)
                Capsule()
                    .fill(.white.opacity(reference.title == "Low" ? 0.12 : 0.065))
                    .frame(width: layout.plotRect.width, height: 1)
                    .position(x: layout.plotRect.midX, y: y)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(reference.title)
                    Text("\(Int(reference.bpm.rounded()))")
                        .monospacedDigit()
                }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: layout.leftGutter - 8, alignment: .trailing)
                    .position(x: layout.leftGutter / 2 - 4, y: min(max(layout.plotRect.minY + 14, y), layout.plotRect.maxY - 14))
            }
        }
    }

    private func yPosition(for bpm: Double) -> CGFloat {
        let span = max(1, chart.yAxisMax - chart.yAxisMin)
        let normalized = (bpm - chart.yAxisMin) / span
        return layout.plotRect.maxY - min(max(0, CGFloat(normalized)), 1) * layout.plotRect.height
    }
}

private struct HeartLoadLineShape: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: midpoint, control: previous)
            path.addQuadCurve(to: current, control: current)
        }
        return path
    }
}

private struct HeartLoadPartialState: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
            Text(title)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
        }
    }
}

private struct HeartLoadMovementState: View {
    var chart: StrainHeartLoadChartModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.walk.motion")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Movement recorded without workout heart rate")
                .font(.footnote.weight(.semibold))
            HStack(spacing: 10) {
                movementMetric("Steps", chart.steps > 0 ? chart.steps.formatted() : "--")
                movementMetric("Exercise", StrainDetailsViewModel.durationText(minutes: chart.exerciseMinutes))
                movementMetric("Active", chart.activeEnergyKilocalories.map { "\(Int($0.rounded())) kcal" } ?? "--")
            }
        }
        .padding(.horizontal, 8)
    }

    private func movementMetric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct HeartLoadLegend: View {
    var hasHeartRate: Bool
    var hasWorkouts: Bool
    var hasMovement: Bool

    var body: some View {
        HStack(spacing: 12) {
            if hasHeartRate { legendItem(color: .pink, title: "Heart rate") }
            if hasWorkouts { legendItem(color: .orange, title: "Workout") }
            if hasMovement { legendItem(color: .cyan, title: "Active effort") }
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color.opacity(0.82))
                .frame(width: 8, height: 8)
            Text(title)
        }
    }
}

private struct StrainMetricsGrid: View {
    var metrics: [StrainMetricTileModel]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(metrics) { metric in
                StrainMetricTile(metric: metric)
            }
        }
    }
}

private struct StrainMetricTile: View {
    var metric: StrainMetricTileModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: metric.symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.orange)
            Text(metric.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(metric.value)
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if let subtitle = metric.subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(14)
        .pulsarLiquidGlass(cornerRadius: 22)
    }
}

private struct StrainWorkoutSection: View {
    var workouts: [StrainWorkoutSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workouts")
                .font(.title3.weight(.semibold))
            if workouts.isEmpty {
                StrainEmptySection(symbol: "figure.run", title: "No workouts logged today", message: "Movement and heart-rate signals can still contribute to strain.")
            } else {
                VStack(spacing: 10) {
                    ForEach(workouts) { workout in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(workout.workoutType)
                                    .font(.headline.weight(.semibold))
                                Spacer()
                                Text(workout.startDate, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(workout.startDate.formatted(.dateTime.hour().minute())) · \(StrainDetailsViewModel.durationText(minutes: workout.durationMinutes))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(workoutDetailText(workout))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(15)
                        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
                .padding(12)
                .pulsarLiquidGlass(cornerRadius: 28)
            }
        }
    }

    private func workoutDetailText(_ workout: StrainWorkoutSummary) -> String {
        var parts: [String] = []
        if let energy = workout.activeEnergyKilocalories { parts.append("\(Int(energy.rounded())) kcal") }
        if let average = workout.averageHeartRate { parts.append("Avg HR \(Int(average.rounded())) bpm") }
        if let peak = workout.peakHeartRate { parts.append("Peak \(Int(peak.rounded())) bpm") }
        return parts.isEmpty ? "Not enough heart or energy data" : parts.joined(separator: " · ")
    }
}

private struct StrainHeartSection: View {
    var summary: StrainSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Heart Signal")
                .font(.title3.weight(.semibold))
            HStack(spacing: 10) {
                heartTile("Avg Active", summary.averageActiveHeartRate)
                heartTile("Peak", summary.peakHeartRate)
                heartTile("Resting", summary.restingHeartRate)
            }
            if !summary.timeInZones.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Training Zones")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 5) {
                        let total = max(1, summary.timeInZones.reduce(0) { $0 + $1.minutes })
                        ForEach(summary.timeInZones) { zone in
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(zoneColor(zone.zone).opacity(zone.minutes > 0 ? 0.85 : 0.12))
                                .frame(maxWidth: .infinity)
                                .frame(height: max(8, 46 * zone.minutes / total))
                        }
                    }
                }
                .padding(16)
                .pulsarLiquidGlass(cornerRadius: 24)
            }
        }
    }

    private func heartTile(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.map { "\(Int($0.rounded()))" } ?? "--")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text("bpm")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .pulsarLiquidGlass(cornerRadius: 22)
    }

    private func zoneColor(_ zone: Int) -> Color {
        switch zone {
        case 1: .mint
        case 2: .green
        case 3: .yellow
        case 4: .orange
        default: .pink
        }
    }
}

private struct StrainStepsSection: View {
    var steps: Int
    var goal: Int
    var progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Movement")
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(steps > 0 ? steps.formatted() : "--")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    Spacer()
                    Text("Goal \(goal.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.08))
                        Capsule()
                            .fill(LinearGradient(colors: [.cyan.opacity(0.75), .orange.opacity(0.80)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 12)
                Text(steps > 0 ? "\(StrainDetailsViewModel.percentText(progress)) of your step goal" : "Not enough step data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .pulsarLiquidGlass(cornerRadius: 26)
        }
    }
}

private struct StrainInsightsSection: View {
    var insights: [StrainInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insights")
                .font(.title3.weight(.semibold))
            ForEach(insights) { insight in
                StrainInsightCard(text: insight.text)
            }
        }
    }
}

private struct StrainInsightCard: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bolt.badge.checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(text)
                .font(.callout)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulsarLiquidGlass(cornerRadius: 24)
    }
}

private struct StrainDataQualitySection: View {
    @ObservedObject var viewModel: StrainDetailsViewModel
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                qualityRow("Data source", "HealthKit")
                qualityRow("Sample sources", viewModel.sourceText)
                qualityRow("Samples analyzed", viewModel.sampleCountText)
                qualityRow("Query range", viewModel.queryText)
                qualityRow("Last updated", viewModel.lastUpdatedText)
            }
            .padding(.top, 8)
        } label: {
            Text("Data Quality")
                .font(.headline)
        }
        .padding(16)
        .pulsarLiquidGlass(cornerRadius: 24)
    }

    private func qualityRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.footnote)
    }
}

private struct StrainEmptySection: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .pulsarLiquidGlass(cornerRadius: 26)
    }
}

private struct StrainDetailsLoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Loading strain details")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .pulsarLiquidGlass(cornerRadius: 32)
    }
}

private struct StrainDetailsStateView: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.orange)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 300)
        .pulsarLiquidGlass(cornerRadius: 32)
    }
}

private struct StrainDetailsBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(.systemBackground), .orange.opacity(0.12), .purple.opacity(0.08), Color(.secondarySystemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

#Preview("Strain Details") {
    NavigationStack {
        StrainDetailsView(
            viewModel: StrainDetailsViewModel(
                initialSummary: MockHealthData.strainSummary,
                profile: MockHealthData.profile,
                date: MockHealthData.calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!,
                provider: PreviewStrainSummaryProvider(summary: MockHealthData.strainSummary),
                calendar: MockHealthData.calendar
            )
        )
    }
}

private struct PreviewStrainSummaryProvider: StrainSummaryProviding {
    var summary: StrainSummary

    func strainSummary(profile: UserProfile, date: Date, calendar: Calendar, refreshedAt: Date) async throws -> StrainSummary {
        var copy = summary
        copy.lastUpdated = refreshedAt
        return copy
    }
}
