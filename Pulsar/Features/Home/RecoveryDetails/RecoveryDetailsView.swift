//
//  RecoveryDetailsView.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct RecoveryDetailsView: View {
    @StateObject private var viewModel: RecoveryDetailsViewModel
    @State private var contentVisible = false

    init(viewModel: RecoveryDetailsViewModel) {
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
        .background(RecoveryDetailsBackground())
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load() }
        .task {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.smooth(duration: 0.45)) { contentVisible = true }
            await viewModel.loadIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            RecoveryDetailsLoadingView()
        case .permissionRequired:
            RecoveryDetailsStateView(symbol: "heart.text.square", title: "Health Permission Required", message: "Grant HealthKit HRV, resting heart rate, sleep, and activity permissions to view real recovery details.")
        case .noData:
            RecoveryDetailsStateView(symbol: "waveform.path.ecg", title: "No Recovery Data Available", message: "Recovery details appear after HealthKit records HRV, resting heart rate, sleep, or strain signals for this day.")
        case .error(let message):
            RecoveryDetailsStateView(symbol: "exclamationmark.triangle", title: "Could Not Load Recovery", message: message)
        case .loaded:
            loadedContent
        }
    }

    private var loadedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            RecoveryDetailsHeader(viewModel: viewModel)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 14)
            RecoveryBalanceCard(summary: viewModel.summary, subtitle: viewModel.recoveryBalanceSubtitle)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 18)
            RecoveryTrendCard(points: viewModel.summary.trend)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 20)
            RecoveryMetricsGrid(metrics: viewModel.metricTiles)
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 22)
            RecoveryComponentsSection(components: viewModel.summary.components)
            RecoveryInsightsSection(insights: viewModel.insights)
            RecoveryDataQualitySection(viewModel: viewModel)
        }
        .animation(.smooth(duration: 0.45), value: contentVisible)
    }
}

private struct RecoveryDetailsHeader: View {
    @ObservedObject var viewModel: RecoveryDetailsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recovery")
                    .pulsarTextStyle(.screenTitle)
                Text(viewModel.dateSubtitle)
                    .pulsarTextStyle(.screenSubtitle)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .lastTextBaseline) {
                Text(viewModel.scoreText)
                    .pulsarMonospacedMetric(.heroMetric)
                    .fontWidth(.expanded)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 12)
                Text(viewModel.statusText)
                    .pulsarTextStyle(.metricLabel)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(recoveryColor(viewModel.summary.status).opacity(0.14), in: Capsule())
                    .foregroundStyle(recoveryColor(viewModel.summary.status))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulsarLiquidGlass(cornerRadius: 34)
    }
}

private struct RecoveryBalanceCard: View {
    var summary: RecoverySummary
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Recovery Balance")
                    .pulsarTextStyle(.sectionTitle)
                Text(subtitle)
                    .pulsarTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }
            RecoveryBalanceGraphView(summary: summary)
                .frame(height: 230)
            Text("Wellness observations only. Pulsar does not diagnose medical conditions.")
                .pulsarTextStyle(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .pulsarLiquidGlass(cornerRadius: 30)
    }
}

struct RecoveryBalanceGraphView: View {
    var summary: RecoverySummary
    @State private var progress = 0.0

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 18)
                ForEach(Array(summary.components.prefix(4).enumerated()), id: \.element.id) { index, component in
                    Circle()
                        .trim(from: 0, to: CGFloat((component.contribution ?? 0) * progress) * 0.19)
                        .stroke(componentColor(component.status), style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90 + Double(index) * 90))
                        .shadow(color: componentColor(component.status).opacity(0.28), radius: 14)
                }
                VStack(spacing: 4) {
                    Text(summary.score > 0 ? "\(summary.score)" : "--")
                        .pulsarMonospacedMetric(.heroMetric)
                    Text(summary.status.label)
                        .pulsarTextStyle(.metricLabel)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(22)
            }
            .frame(width: 154, height: 154)

            VStack(spacing: 8) {
                ForEach(summary.components.prefix(4)) { component in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(componentColor(component.status))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(component.title)
                                .pulsarTextStyle(.metricLabel)
                            Text(component.valueText)
                                .pulsarTextStyle(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(9)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .onAppear { withAnimation(.smooth(duration: 0.9)) { progress = 1 } }
    }
}

private struct RecoveryTrendCard: View {
    var points: [RecoveryTrendPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("7-Day Trend")
                    .pulsarTextStyle(.sectionTitle)
                Text("Based on available HealthKit data")
                    .pulsarTextStyle(.caption)
                    .foregroundStyle(.secondary)
            }
            RecoveryTrendGraphView(points: points)
                .frame(height: 160)
        }
        .padding(18)
        .pulsarLiquidGlass(cornerRadius: 30)
    }
}

struct RecoveryTrendGraphView: View {
    var points: [RecoveryTrendPoint]
    @State private var drawProgress = 0.0

    var body: some View {
        GeometryReader { proxy in
            let plot = CGRect(x: 0, y: 10, width: proxy.size.width, height: max(1, proxy.size.height - 34))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.045))
                    .frame(width: plot.width, height: plot.height)
                    .position(x: plot.midX, y: plot.midY)
                ForEach([0, 25, 50, 75, 100], id: \.self) { value in
                    let y = plot.maxY - plot.height * CGFloat(value) / 100
                    Capsule()
                        .fill(.white.opacity(value == 0 ? 0.12 : 0.06))
                        .frame(width: plot.width, height: 1)
                        .position(x: plot.midX, y: y)
                }
                trendLine(plot: plot)
                    .mask(alignment: .leading) { Rectangle().frame(width: plot.width * drawProgress, height: proxy.size.height) }
                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    let x = xPosition(index: index, count: points.count, plot: plot)
                    if let score = point.recoveryScore {
                        Circle()
                            .fill(index == points.count - 1 ? .green : .white.opacity(0.75))
                            .frame(width: index == points.count - 1 ? 8 : 5, height: index == points.count - 1 ? 8 : 5)
                            .position(x: x, y: yPosition(score, plot: plot))
                            .opacity(drawProgress)
                    } else {
                        Circle()
                            .stroke(.white.opacity(0.22), lineWidth: 1)
                            .frame(width: 5, height: 5)
                            .position(x: x, y: plot.midY)
                    }
                    Text(dayLabel(point.date))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .position(x: x, y: plot.maxY + 18)
                }
            }
        }
        .onAppear { withAnimation(.smooth(duration: 0.9)) { drawProgress = 1 } }
    }

    private func trendLine(plot: CGRect) -> some View {
        let valid = Array(points.enumerated()).compactMap { index, point -> CGPoint? in
            guard let score = point.recoveryScore else { return nil }
            return CGPoint(x: xPosition(index: index, count: points.count, plot: plot), y: yPosition(score, plot: plot))
        }
        return RecoveryTrendLineShape(points: valid)
            .stroke(LinearGradient(colors: [.purple, .blue, .green], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .shadow(color: .blue.opacity(0.28), radius: 10)
    }

    private func xPosition(index: Int, count: Int, plot: CGRect) -> CGFloat {
        guard count > 1 else { return plot.midX }
        return plot.minX + plot.width * CGFloat(index) / CGFloat(count - 1)
    }

    private func yPosition(_ score: Double, plot: CGRect) -> CGFloat {
        plot.maxY - plot.height * min(max(0, CGFloat(score) / 100), 1)
    }

    private func dayLabel(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.narrow))
    }
}

private struct RecoveryTrendLineShape: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
            path.addQuadCurve(to: current, control: current)
        }
        return path
    }
}

private struct RecoveryMetricsGrid: View {
    var metrics: [RecoveryMetricTileModel]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(metrics) { metric in
                RecoveryMetricTile(metric: metric)
            }
        }
    }
}

private struct RecoveryMetricTile: View {
    var metric: RecoveryMetricTileModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: metric.symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.blue)
            Text(metric.title)
                .pulsarTextStyle(.metricLabel)
                .foregroundStyle(.secondary)
            Text(metric.value)
                .pulsarMonospacedMetric(.cardTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            if let subtitle = metric.subtitle {
                Text(subtitle)
                    .pulsarTextStyle(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(14)
        .pulsarLiquidGlass(cornerRadius: 22)
    }
}

private struct RecoveryComponentsSection: View {
    var components: [RecoveryComponent]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Components")
                .pulsarTextStyle(.sectionTitle)
            VStack(spacing: 10) {
                ForEach(components) { component in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(component.title)
                                .pulsarTextStyle(.cardTitle)
                            Spacer()
                            Text(component.status.label)
                                .pulsarTextStyle(.metricLabel)
                                .foregroundStyle(componentColor(component.status))
                        }
                        Text(component.valueText)
                            .pulsarMonospacedMetric(.appBodyEmphasis)
                            .foregroundStyle(.secondary)
                        if let detail = component.detail {
                            Text(detail)
                                .pulsarTextStyle(.caption)
                                .foregroundStyle(.tertiary)
                        }
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

private struct RecoveryInsightsSection: View {
    var insights: [RecoveryInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insights")
                .pulsarTextStyle(.sectionTitle)
            ForEach(insights) { insight in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "heart.text.square")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                    Text(insight.text)
                        .pulsarTextStyle(.appBody)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .pulsarLiquidGlass(cornerRadius: 24)
            }
        }
    }
}

private struct RecoveryDataQualitySection: View {
    @ObservedObject var viewModel: RecoveryDetailsViewModel
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                qualityRow("Data source", "HealthKit")
                qualityRow("Sample sources", viewModel.sourceText)
                qualityRow("Samples analyzed", viewModel.sampleCountText)
                qualityRow("Query range", viewModel.queryText)
                qualityRow("Baseline", viewModel.baselineText)
                qualityRow("Last updated", viewModel.lastUpdatedText)
            }
            .padding(.top, 8)
        } label: {
            Text("Data Quality")
                .pulsarTextStyle(.cardTitle)
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
        .pulsarTextStyle(.caption)
    }
}

private struct RecoveryDetailsLoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Loading recovery details")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .pulsarLiquidGlass(cornerRadius: 32)
    }
}

private struct RecoveryDetailsStateView: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.blue)
            Text(title)
                .pulsarTextStyle(.sectionTitle)
            Text(message)
                .pulsarTextStyle(.appBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 300)
        .pulsarLiquidGlass(cornerRadius: 32)
    }
}

private struct RecoveryDetailsBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(.systemBackground), .blue.opacity(0.12), .purple.opacity(0.10), Color(.secondarySystemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private func recoveryColor(_ status: RecoveryStatus) -> Color {
    switch status {
    case .excellent: .green
    case .balanced: .mint
    case .moderate: .yellow
    case .low: .orange
    case .needsAttention: .blue
    case .unknown: .secondary
    }
}

private func componentColor(_ status: RecoveryStatus) -> Color {
    recoveryColor(status)
}

#Preview("Recovery Details") {
    NavigationStack {
        RecoveryDetailsView(
            viewModel: RecoveryDetailsViewModel(
                initialSummary: MockHealthData.recoverySummary,
                profile: MockHealthData.profile,
                date: MockHealthData.calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!,
                provider: PreviewRecoverySummaryProvider(summary: MockHealthData.recoverySummary),
                calendar: MockHealthData.calendar
            )
        )
    }
}

private struct PreviewRecoverySummaryProvider: RecoverySummaryProviding {
    var summary: RecoverySummary

    func recoverySummary(profile: UserProfile, date: Date, calendar: Calendar, refreshedAt: Date) async throws -> RecoverySummary {
        var copy = summary
        copy.lastUpdated = refreshedAt
        return copy
    }
}
