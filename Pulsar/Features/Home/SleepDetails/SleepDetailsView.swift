//
//  SleepDetailsView.swift
//  Pulsar
//

import SwiftUI

struct SleepDetailsView: View {
    @StateObject private var viewModel: SleepDetailsViewModel
    @State private var contentVisible = false

    init(viewModel: SleepDetailsViewModel) {
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
        .background(SleepDetailsBackground())
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load() }
        .task {
            withAnimation(.smooth(duration: 0.45)) { contentVisible = true }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            SleepDetailsLoadingView()
        case .permissionRequired:
            SleepDetailsStateView(symbol: "heart.text.square", title: "Health Permission Required", message: "Grant HealthKit sleep permission to view your real sleep details. Pulsar never fills this screen with demo sleep data.")
        case .noData:
            SleepDetailsStateView(symbol: "moon.zzz", title: "No Sleep Data Available", message: "Wear Apple Watch to sleep or allow a compatible HealthKit source to write sleep-analysis samples.")
        case .error(let message):
            SleepDetailsStateView(symbol: "exclamationmark.triangle", title: "Could Not Load Sleep", message: message)
        case .loaded:
            loadedContent
        }
    }

    private var loadedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            SleepDetailsHeader(viewModel: viewModel)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 14)
            SleepFlowCard(summary: viewModel.summary)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 18)
            SleepMetricsGrid(metrics: viewModel.metricTiles)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 22)
            SleepStageBreakdownSection(rows: viewModel.stageBreakdownRows)
            SleepInsightsSection(insights: viewModel.insights)
            SleepDataQualitySection(viewModel: viewModel)
        }
        .animation(.smooth(duration: 0.45), value: contentVisible)
    }
}

private struct SleepDetailsHeader: View {
    @ObservedObject var viewModel: SleepDetailsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sleep")
                    .font(.largeTitle.weight(.bold))
                Text(viewModel.dateSubtitle)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .lastTextBaseline) {
                Text(viewModel.totalSleepText)
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 12)
                Text(viewModel.statusText)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.indigo.opacity(0.14), in: Capsule())
                    .foregroundStyle(.indigo)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulsarLiquidGlass(cornerRadius: 34)
    }
}

private struct SleepFlowCard: View {
    var summary: SleepSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sleep Flow")
                        .font(.title3.weight(.semibold))
                    Text("Normalized HealthKit stages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            SleepStageTimelineView(intervals: summary.intervals)
                .frame(height: 190)
            SleepStageLegend()
        }
        .padding(18)
        .pulsarLiquidGlass(cornerRadius: 30)
    }
}

struct SleepStageTimelineView: View {
    var intervals: [SleepStageInterval]
    @State private var animateSegments = false

    var body: some View {
        GeometryReader { proxy in
            let drawableHeight = max(1, proxy.size.height - 34)
            let range = timelineRange
            ZStack(alignment: .topLeading) {
                timelineRail(width: proxy.size.width, height: drawableHeight)
                ForEach(Array(visibleIntervals.enumerated()), id: \.element.id) { index, interval in
                    let frame = segmentFrame(interval, range: range, size: CGSize(width: proxy.size.width, height: drawableHeight))
                    Capsule(style: .continuous)
                        .fill(SleepStageVisualStyle.gradient(for: interval.stage))
                        .frame(width: frame.width, height: frame.height)
                        .shadow(color: SleepStageVisualStyle.color(for: interval.stage).opacity(0.22), radius: 10, y: 4)
                        .position(x: frame.midX, y: frame.midY)
                        .scaleEffect(x: animateSegments ? 1 : 0.04, y: 1, anchor: .leading)
                        .opacity(animateSegments ? 1 : 0.15)
                        .animation(.smooth(duration: 0.45).delay(Double(index) * 0.025), value: animateSegments)
                }
                markerLabels(range: range, width: proxy.size.width, top: drawableHeight + 8)
            }
        }
        .onAppear { animateSegments = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep stage timeline")
    }

    private var visibleIntervals: [SleepStageInterval] {
        intervals.filter { $0.stage != .inBed && $0.duration > 0 }.sorted { $0.startDate < $1.startDate }
    }

    private var timelineRange: DateInterval {
        let relevant = intervals.isEmpty ? visibleIntervals : intervals
        let start = relevant.map(\.startDate).min() ?? Date()
        let end = relevant.map(\.endDate).max() ?? start.addingTimeInterval(1)
        return DateInterval(start: start, end: max(end, start.addingTimeInterval(1)))
    }

    private func segmentFrame(_ interval: SleepStageInterval, range: DateInterval, size: CGSize) -> CGRect {
        let total = max(1, range.duration)
        let x = CGFloat(interval.startDate.timeIntervalSince(range.start) / total) * size.width
        let width = max(7, CGFloat(interval.duration / total) * size.width)
        let y = stageY(interval.stage, height: size.height)
        return CGRect(x: x, y: y - 9, width: width, height: 18)
    }

    private func stageY(_ stage: SleepStage, height: CGFloat) -> CGFloat {
        switch stage {
        case .awake: height * 0.12
        case .rem: height * 0.34
        case .core, .asleepUnspecified: height * 0.60
        case .deep: height * 0.84
        case .inBed: height * 0.50
        }
    }

    private func timelineRail(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach([SleepStage.awake, .rem, .core, .deep], id: \.self) { stage in
                Capsule(style: .continuous)
                    .fill(.primary.opacity(stage == .core ? 0.075 : 0.045))
                    .frame(width: width, height: 10)
                    .position(x: width / 2, y: stageY(stage, height: height))
            }
            ForEach(intervals.filter { $0.stage == .inBed }, id: \.id) { interval in
                let frame = segmentFrame(interval, range: timelineRange, size: CGSize(width: width, height: height))
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.10))
                    .frame(width: frame.width, height: 86)
                    .position(x: frame.midX, y: height * 0.50)
            }
        }
    }

    private func markerLabels(range: DateInterval, width: CGFloat, top: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(timeMarkers(range: range), id: \.self) { date in
                let total = max(1, range.duration)
                let x = CGFloat(date.timeIntervalSince(range.start) / total) * width
                Text(date.formatted(.dateTime.hour()))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .position(x: min(max(18, x), width - 18), y: top)
            }
        }
    }

    private func timeMarkers(range: DateInterval) -> [Date] {
        guard range.duration > 0 else { return [] }
        return (0...4).map { index in
            range.start.addingTimeInterval(range.duration * Double(index) / 4)
        }
    }
}

private enum SleepStageVisualStyle {
    static func color(for stage: SleepStage) -> Color {
        switch stage {
        case .awake: .orange.opacity(0.72)
        case .rem: .purple.opacity(0.78)
        case .core, .asleepUnspecified: .cyan.opacity(0.78)
        case .deep: .indigo.opacity(0.86)
        case .inBed: .white.opacity(0.12)
        }
    }

    static func gradient(for stage: SleepStage) -> LinearGradient {
        let base = color(for: stage)
        return LinearGradient(colors: [base.opacity(0.55), base, .white.opacity(0.22)], startPoint: .leading, endPoint: .trailing)
    }
}

private struct SleepStageLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            legend("Awake", .awake)
            legend("REM", .rem)
            legend("Core", .core)
            legend("Deep", .deep)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }

    private func legend(_ title: String, _ stage: SleepStage) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(SleepStageVisualStyle.color(for: stage))
                .frame(width: 8, height: 8)
            Text(title)
        }
    }
}

private struct SleepMetricsGrid: View {
    var metrics: [SleepMetricTileModel]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(metrics) { metric in
                SleepMetricTile(metric: metric)
            }
        }
    }
}

private struct SleepMetricTile: View {
    var metric: SleepMetricTileModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(metric.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(metric.value)
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let subtitle = metric.subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .padding(14)
        .pulsarLiquidGlass(cornerRadius: 22)
    }
}

private struct SleepStageBreakdownSection: View {
    var rows: [StageMetric]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stage Breakdown")
                .font(.title3.weight(.semibold))
            VStack(spacing: 10) {
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        Capsule()
                            .fill(SleepStageVisualStyle.color(for: row.stage))
                            .frame(width: 34, height: 8)
                        Text(row.stage == .core ? "Core / Light" : row.stage.rawValue)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(SleepDetailsViewModel.durationText(minutes: row.minutes))
                            .font(.subheadline.monospacedDigit())
                        if row.stage.isSleep {
                            Text(SleepDetailsViewModel.percentText(row.percentOfSleep))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(16)
            .pulsarLiquidGlass(cornerRadius: 26)
        }
    }
}

private struct SleepInsightsSection: View {
    var insights: [SleepInsight]

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Insights")
                    .font(.title3.weight(.semibold))
                ForEach(insights) { insight in
                    SleepInsightCard(text: insight.text)
                }
            }
        }
    }
}

private struct SleepInsightCard: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.indigo)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulsarLiquidGlass(cornerRadius: 24)
    }
}

private struct SleepDataQualitySection: View {
    @ObservedObject var viewModel: SleepDetailsViewModel
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                qualityRow("Data source", "HealthKit")
                qualityRow("Sample sources", viewModel.sourceText)
                qualityRow("Samples analyzed", viewModel.sampleCountText)
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

private struct SleepDetailsLoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Loading sleep details")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .pulsarLiquidGlass(cornerRadius: 32)
    }
}

private struct SleepDetailsStateView: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.indigo)
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

private struct SleepDetailsBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(.systemBackground), .indigo.opacity(0.15), .cyan.opacity(0.08), Color(.secondarySystemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

#Preview("Sleep Details") {
    NavigationStack {
        SleepDetailsView(
            viewModel: SleepDetailsViewModel(
                initialSummary: MockHealthData.sleepSummary,
                profile: MockHealthData.profile,
                wakeUpDate: MockHealthData.calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!,
                provider: PreviewSleepSummaryProvider(summary: MockHealthData.sleepSummary),
                calendar: MockHealthData.calendar
            )
        )
    }
}

private struct PreviewSleepSummaryProvider: SleepSummaryProviding {
    var summary: SleepSummary

    func sleepSummary(profile: UserProfile, wakeUpDate: Date, calendar: Calendar, refreshedAt: Date) async throws -> SleepSummary {
        var copy = summary
        copy.lastUpdated = refreshedAt
        return copy
    }
}
