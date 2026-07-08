//
//  FitnessProgressQuickView.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct DailyExerciseProgressSection: View {
    @ObservedObject var viewModel: ExerciseProgressViewModel
    var selectedWeek: WeekPeriod
    var displayUnit: PulsarWeightUnit
    var onStartWorkout: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedMetric: DailyExerciseChartMetric = .weight
    @State private var selectedHistoryTarget: ExerciseProgressLookup?
    @State private var railWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            dateStrip

            if !viewModel.dailySummaries.isEmpty {
                metricPicker
            }

            if viewModel.isLoading && viewModel.dailySummaries.isEmpty {
                DailyProgressLoadingCard()
                    .transition(.opacity)
            } else if viewModel.dailySummaries.isEmpty {
                DailyProgressEmptyState(date: viewModel.selectedDate, isToday: isSelectedDateToday) {
                    onStartWorkout()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                dailyExerciseRail
                    .transition(.opacity)
            }
        }
        .padding(16)
        .padding(.bottom, 14)
        .modifier(
            FitnessGlassSurfaceModifier(
                cornerRadius: 32,
                tint: Color(red: 0.72, green: 0.82, blue: 0.92),
                borderOpacity: 0.94
            )
        )
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: viewModel.selectedDate)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: viewModel.dailySummaries.count)
        .sheet(item: $selectedHistoryTarget) { target in
            ExerciseProgressHistorySheet(target: target, displayUnit: displayUnit)
        }
    }

    private var header: some View {
        FitnessSectionHeader(
            title: isSelectedDateToday ? "Today's Progress" : "Daily Progress",
            subtitle: selectedDateSubtitle
        ) {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(PulsarTheme.fitnessSecondaryText(for: colorScheme))
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "dumbbell.fill")
                        .pulsarTextStyle(.caption)
                    Text("\(viewModel.dailySummaries.count)")
                        .pulsarMonospacedMetric(.metricLabel)
                }
                .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(PulsarTheme.matrixPillBackground(for: colorScheme), in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(colorScheme == .dark ? 0.10 : 0.72), lineWidth: 1)
                }
                .accessibilityLabel("\(viewModel.dailySummaries.count) exercises logged")
            }
        }
    }

    private var dateStrip: some View {
        DailyProgressDateStrip(
            days: viewModel.days(in: selectedWeek),
            selectedDate: viewModel.selectedDate,
            exerciseCountsByDay: viewModel.exerciseCountsByDay
        ) { date in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task {
                await viewModel.selectDate(date, displayUnit: displayUnit, selectedWeek: selectedWeek)
            }
        }
    }

    private var metricPicker: some View {
        HStack(spacing: 6) {
            ForEach(DailyExerciseChartMetric.allCases) { metric in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selectedMetric = metric
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: metric.symbolName)
                            .pulsarTextStyle(.caption)
                        Text(metric.title)
                            .pulsarTextStyle(.metricLabel)
                    }
                    .foregroundStyle(metric == selectedMetric ? selectedMetricText : unselectedMetricText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(metricBackground(for: metric), in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(metricBorder(for: metric), lineWidth: 1)
                    }
                }
                .buttonStyle(FitnessWeekPressStyle())
                .accessibilityLabel(metric.accessibilityTitle)
            }
        }
        .padding(4)
        .modifier(FitnessGlassSurfaceModifier(cornerRadius: 22, tint: .green))
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.10 : 0.72), lineWidth: 1)
        }
    }

    private var dailyExerciseRail: some View {
        let cardWidth = max(240, railWidth - 28)

        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(viewModel.dailySummaries) { summary in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedHistoryTarget = ExerciseProgressLookup(summary: summary)
                    } label: {
                        DailyExerciseProgressCard(
                            summary: summary,
                            selectedMetric: selectedMetric,
                            cardWidth: cardWidth
                        )
                    }
                    .buttonStyle(FitnessWeekPressStyle())
                    .accessibilityLabel("\(summary.exerciseName) progress details")
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 2)
        }
        .frame(minHeight: 330)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        railWidth = proxy.size.width
                    }
                    .onChange(of: proxy.size.width) { _, width in
                        railWidth = width
                    }
            }
        }
    }

    private var isSelectedDateToday: Bool {
        Calendar.autoupdatingCurrent.isDateInToday(viewModel.selectedDate)
    }

    private var selectedDateSubtitle: String {
        if isSelectedDateToday {
            return "Exercises completed today"
        }
        return viewModel.selectedDate.formatted(date: .abbreviated, time: .omitted)
    }

    private var selectedMetricText: Color {
        colorScheme == .dark ? .white : Color(red: 0.06, green: 0.08, blue: 0.13)
    }

    private var unselectedMetricText: Color {
        PulsarTheme.fitnessSecondaryText(for: colorScheme)
    }

    private func metricBackground(for metric: DailyExerciseChartMetric) -> LinearGradient {
        let isSelected = metric == selectedMetric
        return LinearGradient(
            colors: isSelected
                ? [
                    metric.accent.opacity(colorScheme == .dark ? 0.22 : 0.16),
                    Color.white.opacity(colorScheme == .dark ? 0.10 : 0.78),
                    Color.green.opacity(colorScheme == .dark ? 0.12 : 0.08)
                ]
                : [
                    Color.white.opacity(0),
                    Color.white.opacity(0)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func metricBorder(for metric: DailyExerciseChartMetric) -> Color {
        metric == selectedMetric
            ? metric.accent.opacity(colorScheme == .dark ? 0.34 : 0.42)
            : Color.white.opacity(0)
    }
}

private enum DailyExerciseChartMetric: String, CaseIterable, Identifiable {
    case weight
    case reps
    case volume

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: "Weight"
        case .reps: "Reps"
        case .volume: "Volume"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .weight: "Weight used across sets"
        case .reps: "Reps across sets"
        case .volume: "Volume per set"
        }
    }

    var symbolName: String {
        switch self {
        case .weight: "scalemass.fill"
        case .reps: "number"
        case .volume: "chart.bar.fill"
        }
    }

    var accent: Color {
        switch self {
        case .weight: Color(red: 0.58, green: 0.68, blue: 1.0)
        case .reps: Color(red: 0.42, green: 0.82, blue: 1.0)
        case .volume: Color(red: 0.34, green: 0.90, blue: 0.66)
        }
    }
}

private struct DailyProgressDateStrip: View {
    var days: [Date]
    var selectedDate: Date
    var exerciseCountsByDay: [Date: Int]
    var onSelect: (Date) -> Void

    @Environment(\.colorScheme) private var colorScheme
    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        HStack(spacing: 8) {
            ForEach(days, id: \.self) { day in
                Button {
                    onSelect(day)
                } label: {
                    VStack(spacing: 7) {
                        Text(daySymbol(for: day))
                            .pulsarTextStyle(.caption)
                            .foregroundStyle(isSelected(day) ? primaryText : secondaryText)

                        Text(dayNumber(for: day))
                            .pulsarMonospacedMetric(.appBodyEmphasis)
                            .foregroundStyle(isSelected(day) ? primaryText : secondaryText)

                        HStack(spacing: 3) {
                            ForEach(0..<min(3, count(for: day)), id: \.self) { _ in
                                Circle()
                                    .fill(accent(for: day))
                                    .frame(width: 4, height: 4)
                            }
                            if count(for: day) == 0 {
                                Circle()
                                    .fill(PulsarTheme.matrixInactiveDot(for: colorScheme))
                                    .frame(width: 4, height: 4)
                            }
                        }
                        .frame(height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(background(for: day), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(border(for: day), lineWidth: 1)
                    }
                }
                .buttonStyle(FitnessWeekPressStyle())
                .accessibilityLabel(day.formatted(date: .abbreviated, time: .omitted))
            }
        }
    }

    private func isSelected(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: selectedDate)
    }

    private func count(for day: Date) -> Int {
        exerciseCountsByDay[calendar.startOfDay(for: day)] ?? 0
    }

    private func daySymbol(for day: Date) -> String {
        String(Self.weekdayFormatter.string(from: day).prefix(1))
    }

    private func dayNumber(for day: Date) -> String {
        Self.dayFormatter.string(from: day)
    }

    private func accent(for day: Date) -> Color {
        isSelected(day) ? Color.green : Color(red: 0.42, green: 0.78, blue: 1.0)
    }

    private func background(for day: Date) -> LinearGradient {
        LinearGradient(
            colors: isSelected(day)
                ? [
                    Color.green.opacity(colorScheme == .dark ? 0.18 : 0.14),
                    Color.white.opacity(colorScheme == .dark ? 0.08 : 0.72)
                ]
                : [
                    Color.white.opacity(colorScheme == .dark ? 0.07 : 0.62),
                    Color.white.opacity(colorScheme == .dark ? 0.025 : 0.35)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func border(for day: Date) -> Color {
        isSelected(day)
            ? Color.green.opacity(colorScheme == .dark ? 0.32 : 0.42)
            : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.56)
    }

    private var primaryText: Color {
        PulsarTheme.fitnessPrimaryText(for: colorScheme)
    }

    private var secondaryText: Color {
        PulsarTheme.fitnessSecondaryText(for: colorScheme)
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()
}

private struct DailyExerciseProgressCard: View {
    var summary: DailyExerciseSummary
    var selectedMetric: DailyExerciseChartMetric
    var cardWidth: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        FitnessPanel(cornerRadius: 26, padding: 15, tint: accent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(summary.exerciseName)
                            .pulsarTextStyle(.cardTitle)
                            .foregroundStyle(primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(accent)
                                .frame(width: 6, height: 6)
                            Text(summary.muscleGroupName)
                                .pulsarTextStyle(.metricLabel)
                                .foregroundStyle(accent)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 6)

                    Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                        .pulsarTextStyle(.sectionHeader)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(accent)
                        .accessibilityHidden(true)
                }

                DailyExerciseMetricGrid(summary: summary, accent: accent)

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(chartTitle)
                            .pulsarTextStyle(.overline)
                            .foregroundStyle(PulsarTheme.fitnessTertiaryText(for: colorScheme))
                            .textCase(.uppercase)

                        Spacer()

                        Text(bestSetText)
                            .pulsarMonospacedMetric(.metricLabel)
                            .foregroundStyle(primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    DailyExerciseMiniChart(values: chartValues, accent: selectedMetric.accent)
                        .frame(height: 54)
                }
                .padding(12)
                .modifier(FitnessGlassSurfaceModifier(cornerRadius: 18, tint: selectedMetric.accent, borderOpacity: 0.54))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(colorScheme == .dark ? 0.08 : 0.56), lineWidth: 1)
                }
            }
        }
        .frame(width: cardWidth, alignment: .leading)
    }

    private var chartTitle: String {
        switch selectedMetric {
        case .weight:
            summary.isBodyweight ? "Reps by set" : "Weight by set"
        case .reps:
            "Reps by set"
        case .volume:
            "Volume by set"
        }
    }

    private var chartValues: [Double] {
        switch selectedMetric {
        case .weight:
            let weights = summary.setPoints.map(\.weight)
            return weights.contains(where: { $0 > 0.05 }) ? weights : summary.setPoints.map { Double($0.reps) }
        case .reps:
            return summary.setPoints.map { Double($0.reps) }
        case .volume:
            return summary.setPoints.map(\.volume)
        }
    }

    private var bestSetText: String {
        summary.bestSet?.displayText(unit: summary.displayUnit, isBodyweight: summary.isBodyweight) ?? "--"
    }

    private var accent: Color {
        summary.matrixGroup?.accent ?? Color(red: 0.42, green: 0.76, blue: 1.0)
    }

    private var primaryText: Color {
        PulsarTheme.fitnessPrimaryText(for: colorScheme)
    }
}

private struct DailyExerciseMetricGrid: View {
    var summary: DailyExerciseSummary
    var accent: Color

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            DailyExerciseMetricTile(title: "Sets", value: "\(summary.completedSets)", accent: accent)
            DailyExerciseMetricTile(title: "Reps", value: "\(summary.totalReps)", accent: accent)
            DailyExerciseMetricTile(title: "Best", value: maxWeightText, accent: accent)
            DailyExerciseMetricTile(title: "Volume", value: volumeText, accent: accent)
        }
    }

    private var maxWeightText: String {
        if summary.isBodyweight || summary.maxWeight <= 0.05 {
            return "BW"
        }
        return "\(summary.maxWeight.formattedGymDecimal) \(summary.displayUnit.displayName)"
    }

    private var volumeText: String {
        guard summary.totalVolume > 0.05 else { return "--" }
        return "\(summary.totalVolume.formattedGymDecimal) \(summary.displayUnit.displayName)"
    }
}

private struct DailyExerciseMetricTile: View {
    var title: String
    var value: String
    var accent: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .pulsarMonospacedMetric(.appBodyEmphasis)
                .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(title)
                .pulsarTextStyle(.caption)
                .foregroundStyle(PulsarTheme.fitnessTertiaryText(for: colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .modifier(FitnessGlassSurfaceModifier(cornerRadius: 15, tint: accent, borderOpacity: 0.50))
    }
}

private struct DailyExerciseMiniChart: View {
    var values: [Double]
    var accent: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            let cleaned = values.filter { $0.isFinite && $0 >= 0 }

            ZStack(alignment: .bottomLeading) {
                if cleaned.contains(where: { $0 > 0 }) {
                    DailyProgressBars(values: cleaned)
                        .fill(accent.opacity(colorScheme == .dark ? 0.17 : 0.13))

                    DailyProgressSparkline(values: cleaned)
                        .stroke(accent, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                        .shadow(color: accent.opacity(0.20), radius: 4, y: 2)

                    if cleaned.count == 1 {
                        Circle()
                            .fill(accent)
                            .frame(width: 7, height: 7)
                            .position(x: rect.midX, y: rect.midY)
                    }
                } else {
                    HStack(spacing: 6) {
                        ForEach(0..<max(1, values.count), id: \.self) { _ in
                            Capsule(style: .continuous)
                                .fill(accent.opacity(colorScheme == .dark ? 0.20 : 0.16))
                                .frame(width: 9, height: 26)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

private struct DailyProgressSparkline: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        let cleaned = values.filter { $0.isFinite }
        guard cleaned.count > 1 else {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }

        let minValue = cleaned.min() ?? 0
        let maxValue = cleaned.max() ?? 1
        let range = max(maxValue - minValue, 0.001)
        let step = rect.width / CGFloat(cleaned.count - 1)

        var path = Path()
        for index in cleaned.indices {
            let x = rect.minX + CGFloat(index) * step
            let normalized = (cleaned[index] - minValue) / range
            let y = rect.maxY - CGFloat(normalized) * rect.height
            let point = CGPoint(x: x, y: y)
            if index == cleaned.startIndex {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

private struct DailyProgressBars: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        let cleaned = values.filter { $0.isFinite && $0 >= 0 }
        guard !cleaned.isEmpty else { return Path() }

        let maxValue = max(cleaned.max() ?? 1, 0.001)
        let gap: CGFloat = 5
        let count = CGFloat(cleaned.count)
        let barWidth = max(4, (rect.width - gap * max(0, count - 1)) / count)

        var path = Path()
        for index in cleaned.indices {
            let normalized = CGFloat(cleaned[index] / maxValue)
            let height = max(8, rect.height * normalized)
            let x = rect.minX + CGFloat(index) * (barWidth + gap)
            let barRect = CGRect(x: x, y: rect.maxY - height, width: barWidth, height: height)
            path.addRoundedRect(in: barRect, cornerSize: CGSize(width: min(8, barWidth / 2), height: min(8, barWidth / 2)))
        }
        return path
    }
}

private struct DailyProgressEmptyState: View {
    var date: Date
    var isToday: Bool
    var onStartWorkout: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 15) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(colorScheme == .dark ? 0.16 : 0.12))
                    .frame(width: 72, height: 72)

                Image(systemName: "figure.strengthtraining.traditional.circle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.green)
            }

            VStack(spacing: 6) {
                Text(isToday ? "No exercises logged today yet" : "No exercises logged this day")
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))

                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .pulsarTextStyle(.label)
                    .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
            }

            if isToday {
                Button(action: onStartWorkout) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .pulsarTextStyle(.captionEmphasis)
                        Text("Start Workout")
                            .pulsarTextStyle(.label)
                    }
                    .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(PulsarTheme.matrixPillBackground(for: colorScheme), in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.70), lineWidth: 1)
                    }
                }
                .buttonStyle(FitnessWeekPressStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 18)
        .modifier(FitnessGlassSurfaceModifier(cornerRadius: 26, tint: .green))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.72), lineWidth: 1)
        }
    }
}

private struct DailyProgressLoadingCard: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(PulsarTheme.fitnessSecondaryText(for: colorScheme))
            Text("Loading daily progress")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
        }
        .frame(maxWidth: .infinity, minHeight: 176)
        .modifier(FitnessGlassSurfaceModifier(cornerRadius: 26, tint: .green))
    }
}

struct ExerciseProgressHistorySheet: View {
    @StateObject private var viewModel: ExerciseProgressHistoryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @MainActor
    init(target: ExerciseProgressLookup, displayUnit: PulsarWeightUnit) {
        _viewModel = StateObject(
            wrappedValue: ExerciseProgressHistoryViewModel(
                target: target,
                displayUnit: displayUnit
            )
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ExerciseHistoryHeader(history: viewModel.history)

                    if viewModel.isLoading && viewModel.history.points.isEmpty {
                        DailyProgressLoadingCard()
                    } else if viewModel.history.points.isEmpty {
                        ExerciseHistoryEmptyState(history: viewModel.history)
                    } else {
                        ExerciseHistorySummaryCard(history: viewModel.history)

                        if !viewModel.history.hasTrendData {
                            ExerciseLimitedHistoryNotice()
                        }

                        ExerciseHistoryChartPanel(
                            title: viewModel.history.isBodyweight ? "Rep Progression" : "Weight Progression",
                            subtitle: viewModel.history.isBodyweight ? "Total reps by workout date" : "Max load by workout date",
                            values: viewModel.history.isBodyweight
                                ? viewModel.history.points.map { Double($0.totalReps) }
                                : viewModel.history.points.map(\.maxWeight),
                            valueSuffix: viewModel.history.isBodyweight ? " reps" : " \(viewModel.history.displayUnit.displayName)",
                            accent: accent
                        )

                        ExerciseHistoryChartPanel(
                            title: "Reps Progression",
                            subtitle: "Total reps per workout date",
                            values: viewModel.history.points.map { Double($0.totalReps) },
                            valueSuffix: " reps",
                            accent: Color(red: 0.42, green: 0.82, blue: 1.0)
                        )

                        ExerciseHistoryChartPanel(
                            title: "Volume Progression",
                            subtitle: "Completed load volume per workout date",
                            values: viewModel.history.points.map(\.totalVolume),
                            valueSuffix: " \(viewModel.history.displayUnit.displayName)",
                            accent: Color(red: 0.34, green: 0.90, blue: 0.66)
                        )

                        ExerciseBestSetHistoryList(history: viewModel.history)
                    }
                }
                .padding(20)
            }
            .background(FitnessWeeklyBackground())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .pulsarTextStyle(.cardTitle)
                }
            }
        }
        .task {
            await viewModel.load()
        }
    }

    private var accent: Color {
        viewModel.history.matrixGroup?.accent ?? Color(red: 0.58, green: 0.68, blue: 1.0)
    }
}

private struct ExerciseHistoryHeader: View {
    var history: ExerciseProgressHistory

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(history.muscleGroupName)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(accent)
                .textCase(.uppercase)

            Text("\(history.target.exerciseName) Progress")
                .pulsarTextStyle(.displayMedium)
                .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            Text(history.equipment)
                .pulsarTextStyle(.label)
                .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
        }
    }

    private var accent: Color {
        history.matrixGroup?.accent ?? Color(red: 0.58, green: 0.68, blue: 1.0)
    }
}

private struct ExerciseHistorySummaryCard: View {
    var history: ExerciseProgressHistory

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        FitnessPanel(cornerRadius: 26, padding: 15) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(history.target.exerciseName)
                            .pulsarTextStyle(.sectionHeader)
                            .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))
                            .lineLimit(2)

                        Text(summaryLine)
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(PulsarTheme.fitnessTertiaryText(for: colorScheme))
                    }

                    Spacer()

                    if let improvementText {
                        Text(improvementText)
                            .pulsarTextStyle(.captionEmphasis)
                            .monospacedDigit()
                            .foregroundStyle(improvementColor)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(improvementColor.opacity(colorScheme == .dark ? 0.14 : 0.10), in: Capsule(style: .continuous))
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    ExerciseHistoryMetricTile(title: "Trained", value: "\(history.totalTimesTrained)x")
                    ExerciseHistoryMetricTile(title: "Current Best", value: currentBestText)
                    ExerciseHistoryMetricTile(title: "Lifetime Set", value: lifetimeSetText)
                    ExerciseHistoryMetricTile(title: "Last Trained", value: lastTrainedText)
                    ExerciseHistoryMetricTile(title: "Lifetime Volume", value: lifetimeVolumeText)
                    ExerciseHistoryMetricTile(title: "Best Weight", value: bestWeightText)
                }
            }
        }
    }

    private var summaryLine: String {
        "\(history.points.count) logged \(history.points.count == 1 ? "day" : "days")"
    }

    private var currentBestText: String {
        if history.isBodyweight || history.currentBestWeight <= 0.05 {
            return "BW"
        }
        return "\(history.currentBestWeight.formattedGymDecimal) \(history.displayUnit.displayName)"
    }

    private var bestWeightText: String {
        if history.isBodyweight || history.bestWeightEver <= 0.05 {
            return "BW"
        }
        return "\(history.bestWeightEver.formattedGymDecimal) \(history.displayUnit.displayName)"
    }

    private var lifetimeSetText: String {
        history.lifetimeBestSet?.displayText(unit: history.displayUnit, isBodyweight: history.isBodyweight) ?? "--"
    }

    private var lastTrainedText: String {
        history.lastPerformedAt?.formatted(date: .abbreviated, time: .omitted) ?? "--"
    }

    private var lifetimeVolumeText: String {
        guard history.totalLifetimeVolume > 0.05 else { return "--" }
        return "\(history.totalLifetimeVolume.formattedGymDecimal) \(history.displayUnit.displayName)"
    }

    private var improvementText: String? {
        guard let percent = history.improvementPercent, percent.isFinite else { return nil }
        let prefix = percent >= 0 ? "+" : ""
        return "\(prefix)\(percent.formattedGymDecimal)%"
    }

    private var improvementColor: Color {
        guard let percent = history.improvementPercent else { return Color(red: 0.42, green: 0.82, blue: 1.0) }
        if percent >= 0 {
            return Color(red: 0.30, green: 0.90, blue: 0.62)
        }
        return Color(red: 1.0, green: 0.64, blue: 0.34)
    }
}

private struct ExerciseHistoryMetricTile: View {
    var title: String
    var value: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .pulsarTextStyle(.cardTitle)
                .monospacedDigit()
                .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(title)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(PulsarTheme.fitnessTertiaryText(for: colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(PulsarTheme.matrixPillBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

private struct ExerciseHistoryChartPanel: View {
    var title: String
    var subtitle: String
    var values: [Double]
    var valueSuffix: String
    var accent: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))

                    Text(subtitle)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(PulsarTheme.fitnessTertiaryText(for: colorScheme))
                }

                Spacer()

                Text(latestValueText)
                    .pulsarTextStyle(.captionEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(accent.opacity(colorScheme == .dark ? 0.14 : 0.10), in: Capsule(style: .continuous))
            }

            if values.contains(where: { $0 > 0 }) {
                ZStack(alignment: .bottom) {
                    DailyProgressBars(values: values)
                        .fill(accent.opacity(colorScheme == .dark ? 0.15 : 0.11))

                    DailyProgressSparkline(values: values)
                        .stroke(accent, style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                        .shadow(color: accent.opacity(0.22), radius: 12, y: 6)
                }
                .frame(height: 150)
            } else {
                ExerciseNoChartDataCard()
            }
        }
        .padding(16)
        .background(PulsarTheme.glassCardBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(PulsarTheme.glassCardBorder(for: colorScheme), lineWidth: 1)
        }
    }

    private var latestValueText: String {
        guard let latest = values.last, latest > 0 else { return "--" }
        return "\(latest.formattedGymDecimal)\(valueSuffix)"
    }
}

private struct ExerciseNoChartDataCard: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(PulsarTheme.fitnessTertiaryText(for: colorScheme))

            Text("No load data for this chart yet")
                .pulsarTextStyle(.label)
                .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
        }
        .frame(maxWidth: .infinity, minHeight: 118)
        .background(PulsarTheme.matrixPillBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ExerciseBestSetHistoryList: View {
    var history: ExerciseProgressHistory

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Best Set History")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))

            ForEach(history.points.reversed()) { point in
                HStack(spacing: 12) {
                    Text(point.date.formatted(date: .abbreviated, time: .omitted))
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(PulsarTheme.fitnessTertiaryText(for: colorScheme))
                        .frame(width: 78, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(point.bestSet?.displayText(unit: history.displayUnit, isBodyweight: history.isBodyweight) ?? "--")
                            .pulsarTextStyle(.label)
                            .monospacedDigit()
                            .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))

                        Text("\(point.completedSets) sets / \(point.totalReps) reps")
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
                    }

                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(PulsarTheme.matrixPillBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

private struct ExerciseLimitedHistoryNotice: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(Color.green)

            Text("Complete this exercise again to unlock trend charts.")
                .pulsarTextStyle(.label)
                .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color.green.opacity(colorScheme == .dark ? 0.10 : 0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.green.opacity(colorScheme == .dark ? 0.18 : 0.22), lineWidth: 1)
        }
    }
}

private struct ExerciseHistoryEmptyState: View {
    var history: ExerciseProgressHistory

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.50, green: 0.70, blue: 1.0).opacity(colorScheme == .dark ? 0.16 : 0.12))
                    .frame(width: 74, height: 74)

                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.system(size: 35, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(red: 0.50, green: 0.70, blue: 1.0))
            }

            VStack(spacing: 6) {
                Text("No saved history yet")
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))

                Text("Finish a workout with \(history.target.exerciseName) to start the trend.")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .modifier(FitnessGlassSurfaceModifier(cornerRadius: 26, tint: .green))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.72), lineWidth: 1)
        }
    }
}
