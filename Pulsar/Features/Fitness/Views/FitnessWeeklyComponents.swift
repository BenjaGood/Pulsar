//
//  FitnessWeeklyComponents.swift
//  Pulsar
//

import MapKit
import SwiftUI
import UIKit

struct FitnessWeekHeaderView: View {
    var week: WeekPeriod
    var canMoveToNextWeek: Bool
    var isRefreshing: Bool
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onCurrent: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 360
            let chartWidth = isCompact ? min(max(proxy.size.width * 0.34, 108), 126) : min(max(proxy.size.width * 0.38, 132), 220)
            let contentSpacing: CGFloat = isCompact ? 12 : 18

            HStack(alignment: .bottom, spacing: contentSpacing) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Text("WEEKLY TRAINING RHYTHM")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(secondaryText.opacity(0.86))
                            .tracking(1.0)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        if isRefreshing {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(secondaryText)
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Week \(week.weekNumber)")
                            .font(.system(size: 36, weight: .bold, design: .default))
                            .monospacedDigit()
                            .foregroundStyle(primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text(FitnessWeekFormatters.heroDateRange(for: week))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    statusControl
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                VStack(alignment: .trailing, spacing: 12) {
                    HStack(spacing: 9) {
                        weekArrow(systemName: "chevron.left", action: onPrevious, isEnabled: true)
                        weekArrow(systemName: "chevron.right", action: onNext, isEnabled: canMoveToNextWeek)
                    }

                    FitnessWeeklyRhythmChart(hasWorkout: week.hasWorkout)
                        .frame(width: chartWidth, height: 68)
                        .accessibilityHidden(true)
                }
                .frame(width: chartWidth, alignment: .trailing)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 164)
        .modifier(FitnessGlassSurfaceModifier(cornerRadius: 30, tint: Color(red: 0.70, green: 0.88, blue: 0.72)))
    }

    private func weekArrow(systemName: String, action: @escaping () -> Void, isEnabled: Bool) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isEnabled ? primaryText : secondaryText.opacity(0.42))
                .frame(width: 34, height: 34)
                .background(FitnessCircularGlassSurface(cornerRadius: 17, opacity: isEnabled ? 1 : 0.54))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(systemName == "chevron.left" ? "Previous week" : "Next week")
    }

    @ViewBuilder
    private var statusControl: some View {
        if week.isCurrentWeek {
            statusPill(text: week.hasWorkout ? "Workout logged this week" : "No workout logged yet")
        } else {
            Button(action: onCurrent) {
                statusPill(text: "Current Week")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Return to current week")
        }
    }

    private func statusPill(text: String) -> some View {
        HStack(spacing: 9) {
            Circle()
                .fill(week.hasWorkout ? Color.green : secondaryText.opacity(0.54))
                .frame(width: 8, height: 8)

            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(week.hasWorkout ? Color.green.opacity(0.92) : secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.white.opacity(colorScheme == .dark ? 0.070 : 0.66), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.10 : 0.52), lineWidth: 0.7)
        }
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.98) : Color(red: 0.07, green: 0.10, blue: 0.14)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color(red: 0.36, green: 0.40, blue: 0.48)
    }
}

private struct FitnessWeeklyRhythmChart: View {
    var hasWorkout: Bool

    private let labels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let size = proxy.size
                let points = rhythmPoints(in: size)

                ZStack {
                    verticalGuides()
                    chartFill(points: points)
                    chartLine(points: points)
                    endpoint(points: points)
                }
            }
            .frame(height: 46)

            HStack {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.50))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func verticalGuides() -> some View {
        Canvas { context, canvasSize in
            let step = canvasSize.width / 6
            var path = Path()
            for index in 0...6 {
                let x = CGFloat(index) * step
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: canvasSize.height))
            }
            context.stroke(path, with: .color(.white.opacity(0.08)), lineWidth: 0.7)
        }
    }

    private func chartFill(points: [CGPoint]) -> some View {
        Canvas { context, canvasSize in
            var area = Path()
            guard let first = points.first, let last = points.last else { return }
            area.move(to: CGPoint(x: first.x, y: canvasSize.height))
            area.addLine(to: first)
            for point in points.dropFirst() {
                area.addLine(to: point)
            }
            area.addLine(to: CGPoint(x: last.x, y: canvasSize.height))
            area.closeSubpath()
            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [
                        Color.green.opacity(hasWorkout ? 0.30 : 0.16),
                        Color.green.opacity(0.040)
                    ]),
                    startPoint: CGPoint(x: canvasSize.width, y: 0),
                    endPoint: CGPoint(x: canvasSize.width, y: canvasSize.height)
                )
            )
        }
    }

    private func chartLine(points: [CGPoint]) -> some View {
        Canvas { context, _ in
            guard let first = points.first else { return }
            var path = Path()
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(Color.green.opacity(hasWorkout ? 0.42 : 0.20)), style: StrokeStyle(lineWidth: 7.0, lineCap: .round, lineJoin: .round))
            context.stroke(path, with: .color(.white.opacity(0.78)), style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
        }
    }

    private func endpoint(points: [CGPoint]) -> some View {
        Canvas { context, _ in
            guard let last = points.last else { return }
            let color = hasWorkout ? Color.green : Color.white.opacity(0.54)
            context.fill(Path(ellipseIn: CGRect(x: last.x - 7, y: last.y - 7, width: 14, height: 14)), with: .color(color.opacity(0.22)))
            context.fill(Path(ellipseIn: CGRect(x: last.x - 4.5, y: last.y - 4.5, width: 9, height: 9)), with: .color(color))
        }
    }

    private func rhythmPoints(in size: CGSize) -> [CGPoint] {
        let values: [CGFloat] = hasWorkout
            ? [0.68, 0.48, 0.36, 0.54, 0.22, 0.40, 0.16]
            : [0.64, 0.56, 0.52, 0.58, 0.50, 0.57, 0.48]
        return values.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) / CGFloat(max(values.count - 1, 1)) * size.width,
                y: value * size.height
            )
        }
    }
}

struct FitnessWeekSelectorView: View {
    var weeks: [WeekPeriod]
    var selectedWeek: WeekPeriod
    var onShowHistory: () -> Void
    var onSelect: (WeekPeriod) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Week Focus")
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(primaryText)

                    Text("Tap a week or browse history")
                        .pulsarTextStyle(.caption)
                        .foregroundStyle(secondaryText)
                }

                Spacer()

                Button(action: onShowHistory) {
                    HStack(spacing: 7) {
                        Image(systemName: "calendar")
                            .pulsarTextStyle(.caption)
                        Text("View all")
                            .pulsarTextStyle(.metricLabel)
                    }
                    .foregroundStyle(primaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(historyButtonBackground, in: Capsule(style: .continuous))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(.white.opacity(colorScheme == .dark ? 0.15 : 0.70), lineWidth: 1)
                    }
                }
                .buttonStyle(FitnessWeekPressStyle())
                .accessibilityLabel("View all weeks")
            }

            HStack(spacing: 10) {
                ForEach(weeks) { week in
                    FitnessWeekCard(week: week, isSelected: week.id == selectedWeek.id) {
                        onSelect(week)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .animation(.spring(response: 0.40, dampingFraction: 0.84), value: weeks)
    }

    private var historyButtonBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.12), Color.white.opacity(0.045)]
                : [Color.white.opacity(0.86), Color(red: 0.94, green: 0.98, blue: 1.00).opacity(0.66)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color(red: 0.08, green: 0.11, blue: 0.16)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.58) : Color(red: 0.38, green: 0.42, blue: 0.50)
    }
}

private struct FitnessWeekCard: View {
    var week: WeekPeriod
    var isSelected: Bool
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    statusIndicator
                    Spacer()
                    if week.isCurrentWeek {
                        Text("Current")
                            .pulsarTextStyle(.caption)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.green.opacity(colorScheme == .dark ? 0.15 : 0.11), in: Capsule(style: .continuous))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Week \(week.weekNumber)")
                        .pulsarMonospacedMetric(.cardTitle)
                        .foregroundStyle(primaryText)

                    Text(FitnessWeekFormatters.compactDateRange(for: week))
                        .pulsarTextStyle(.caption)
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96, alignment: .leading)
            .background(cardGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .modifier(FitnessGlassSurfaceModifier(cornerRadius: 24, tint: isSelected ? .green : Color(red: 0.68, green: 0.80, blue: 0.92), isInteractive: true))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isSelected ? Color.green.opacity(0.70) : .white.opacity(colorScheme == .dark ? 0.14 : 0.72), lineWidth: isSelected ? 1.4 : 1)
            }
            .shadow(color: (isSelected ? Color.green : .black).opacity(isSelected ? 0.20 : (colorScheme == .dark ? 0.22 : 0.08)), radius: isSelected ? 18 : 12, y: isSelected ? 9 : 7)
            .scaleEffect(isSelected ? 1.015 : 1)
        }
        .buttonStyle(FitnessWeekPressStyle())
        .accessibilityLabel("Week \(week.weekNumber), \(FitnessWeekFormatters.dateRange(for: week))")
        .accessibilityValue(week.hasWorkout ? "Has workout" : "No workouts")
    }

    private var statusIndicator: some View {
        ZStack {
            Circle()
                .fill(week.hasWorkout ? .green.opacity(0.16) : secondaryText.opacity(0.12))
                .frame(width: 22, height: 22)

            Circle()
                .fill(week.hasWorkout ? .green : secondaryText.opacity(0.45))
                .frame(width: 8, height: 8)
                .shadow(color: (week.hasWorkout ? Color.green : .clear).opacity(0.72), radius: 7)
        }
    }

    private var cardGradient: LinearGradient {
        LinearGradient(
            colors: isSelected
                ? [
                    Color.green.opacity(colorScheme == .dark ? 0.22 : 0.16),
                    Color.white.opacity(colorScheme == .dark ? 0.10 : 0.86),
                    Color.green.opacity(colorScheme == .dark ? 0.08 : 0.06)
                ]
                : [
                    Color.white.opacity(colorScheme == .dark ? 0.10 : 0.76),
                    Color.white.opacity(colorScheme == .dark ? 0.04 : 0.44)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.96) : Color(red: 0.08, green: 0.11, blue: 0.16)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.58) : Color(red: 0.38, green: 0.42, blue: 0.50)
    }
}

struct FitnessActivityLogSection: View {
    var week: WeekPeriod
    var activities: [WeeklyActivity]
    var isLoading: Bool
    var isExpanded: Bool
    var onToggleExpanded: () -> Void
    var onSelectActivity: (WeeklyActivity) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Activity Log")
                        .pulsarTextStyle(.sectionTitle)
                        .foregroundStyle(primaryText)

                    Text(summaryText)
                        .pulsarTextStyle(.screenSubtitle)
                        .foregroundStyle(secondaryText)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(secondaryText)
                }
            }

            if isLoading && activities.isEmpty {
                FitnessActivityLoadingCard()
            } else if activities.isEmpty {
                FitnessWeeklyEmptyState()
            } else {
                VStack(spacing: 12) {
                    ForEach(visibleActivities) { activity in
                        Button {
                            onSelectActivity(activity)
                        } label: {
                            FitnessActivityRow(activity: activity)
                        }
                        .buttonStyle(FitnessWeekPressStyle())
                        .accessibilityHint("Opens workout details")
                    }

                    if activities.count > 4 {
                        Button(action: onToggleExpanded) {
                            HStack(spacing: 8) {
                                Text(isExpanded ? "Show less" : "Show all \(activities.count) activities")
                                    .pulsarTextStyle(.label)
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .pulsarTextStyle(.captionEmphasis)
                            }
                            .foregroundStyle(primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(expandButtonBackground, in: Capsule(style: .continuous))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(.white.opacity(colorScheme == .dark ? 0.14 : 0.72), lineWidth: 1)
                            }
                        }
                        .buttonStyle(FitnessWeekPressStyle())
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: isExpanded)
    }

    private var summaryText: String {
        guard !activities.isEmpty else { return FitnessWeekFormatters.dateRange(for: week) }
        let count = activities.count
        let totalDuration = activities.reduce(0) { $0 + $1.duration }
        return "\(count) \(count == 1 ? "activity" : "activities") - \(FitnessWeekFormatters.duration(totalDuration)) total"
    }

    private var visibleActivities: [WeeklyActivity] {
        isExpanded ? activities : Array(activities.prefix(4))
    }

    private var expandButtonBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.10), Color.white.opacity(0.04), Color.green.opacity(0.045)]
                : [Color.white.opacity(0.86), Color(red: 0.95, green: 0.98, blue: 1.00).opacity(0.68), Color.green.opacity(0.045)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.97) : Color(red: 0.07, green: 0.10, blue: 0.14)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.58) : Color(red: 0.36, green: 0.40, blue: 0.48)
    }
}

private struct FitnessActivityRow: View {
    var activity: WeeklyActivity

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(activity.category.accent.opacity(colorScheme == .dark ? 0.18 : 0.14))
                    .frame(width: 48, height: 48)

                Image(systemName: activity.category.symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(activity.category.accent)
            }

            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activity.displayName)
                            .pulsarTextStyle(.cardTitle)
                            .foregroundStyle(primaryText)

                        Text(FitnessWeekFormatters.activityDateTime(activity.startDate))
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(secondaryText)
                    }

                    Spacer(minLength: 8)

                    Text(activity.sourceName)
                        .pulsarTextStyle(.overline)
                        .foregroundStyle(secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.white.opacity(colorScheme == .dark ? 0.07 : 0.58), in: Capsule(style: .continuous))
                }

                FlowLayout(spacing: 7, rowSpacing: 7) {
                    FitnessActivityMetricChip(symbolName: "timer", value: FitnessWeekFormatters.duration(activity.duration))

                    if let calories = activity.calories, calories > 0 {
                        FitnessActivityMetricChip(symbolName: "flame.fill", value: FitnessWeekFormatters.calories(calories))
                    }

                    if let distance = activity.distanceMeters, distance > 0 {
                        FitnessActivityMetricChip(symbolName: "location.fill", value: FitnessWeekFormatters.distance(distance))
                    }

                    if let heartRate = activity.averageHeartRate, heartRate > 0 {
                        FitnessActivityMetricChip(symbolName: "heart.fill", value: "Avg \(Int(heartRate.rounded())) bpm")
                    }

                    if let completedSets = activity.completedSets, completedSets > 0 {
                        FitnessActivityMetricChip(symbolName: "checkmark.circle.fill", value: "\(completedSets) sets")
                    }

                    if !activity.mainMuscleGroups.isEmpty {
                        FitnessActivityMetricChip(symbolName: "figure.strengthtraining.traditional", value: activity.mainMuscleGroups.prefix(3).joined(separator: ", "))
                    }
                }
            }

            Image(systemName: "chevron.right")
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(secondaryText.opacity(0.72))
                .padding(.top, 17)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .modifier(FitnessGlassSurfaceModifier(cornerRadius: 28, tint: activity.category.accent, isInteractive: true))
        .overlay(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(activity.category.accent)
                .frame(width: 4)
                .padding(.vertical, 18)
                .shadow(color: activity.category.accent.opacity(0.42), radius: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.14 : 0.78), lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.20 : 0.08), radius: 14, y: 8)
    }

    private var rowGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.095), Color.white.opacity(0.035), activity.category.accent.opacity(0.055)]
                : [Color.white.opacity(0.90), Color(red: 0.95, green: 0.98, blue: 1.00).opacity(0.72), activity.category.accent.opacity(0.045)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.97) : Color(red: 0.07, green: 0.10, blue: 0.14)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.58) : Color(red: 0.36, green: 0.40, blue: 0.48)
    }
}

private struct FitnessActivityMetricChip: View {
    var symbolName: String
    var value: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbolName)
                .pulsarTextStyle(.overline)
            Text(value)
                .pulsarTextStyle(.captionEmphasis)
                .monospacedDigit()
        }
        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.74) : Color(red: 0.20, green: 0.24, blue: 0.30))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.white.opacity(colorScheme == .dark ? 0.075 : 0.64), in: Capsule(style: .continuous))
    }
}

struct FitnessWorkoutDetailView: View {
    var activity: WeeklyActivity

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var bottomChromeLayoutStore: PulsarBottomChromeLayoutStore
    @StateObject private var detailViewModel: CompletedWorkoutDetailViewModel
    @State private var renderedShareImage: FitnessWorkoutRenderedImage?
    @State private var selectedExerciseProgressTarget: ExerciseProgressLookup?
    @State private var selectedSetEditor: CompletedWorkoutSetEditContext?
    @State private var selectedInstructionsExercise: CompletedWorkoutExercisePresentation?

    @MainActor
    init(
        activity: WeeklyActivity,
        bottomChromeLayoutStore: PulsarBottomChromeLayoutStore? = nil
    ) {
        self.activity = activity
        self._bottomChromeLayoutStore = ObservedObject(wrappedValue: bottomChromeLayoutStore ?? PulsarBottomChromeLayoutStore())
        self._detailViewModel = StateObject(wrappedValue: CompletedWorkoutDetailViewModel(activity: activity))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                routeSection
                gymSetsSection
                splitsSection
                trainingSection
                metadataSection
                shareButton
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .pulsarBottomChromeScrollContainer(layoutStore: bottomChromeLayoutStore)
        .background(FitnessWeeklyBackground())
        .navigationTitle(activity.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    renderShareImage()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(activity.shareActionTitle)
            }
        }
        .sheet(item: $renderedShareImage) { renderedImage in
            FitnessWorkoutActivityView(activityItems: [renderedImage.image])
        }
        .sheet(item: $selectedExerciseProgressTarget) { target in
            ExerciseProgressHistorySheet(target: target, displayUnit: target.displayUnit)
        }
        .sheet(item: $selectedInstructionsExercise) { exercise in
            CompletedWorkoutExerciseInstructionsSheet(exercise: exercise)
        }
        .sheet(item: $selectedSetEditor) { context in
            GymSetEditorSheet(
                setNumber: context.setNumber,
                reps: context.reps,
                weight: context.weight,
                weightUnit: context.weightUnit
            ) { reps, weight in
                let didSave = detailViewModel.updateSet(
                    exerciseId: context.exerciseId,
                    setId: context.setId,
                    reps: reps,
                    weight: weight
                )
                UINotificationFeedbackGenerator().notificationOccurred(didSave ? .success : .error)
            }
            .presentationDetents([.height(340)])
            .presentationDragIndicator(.visible)
        }
        .alert(
            "Unable to Save Set",
            isPresented: Binding(
                get: { detailViewModel.editErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        detailViewModel.clearEditError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                detailViewModel.clearEditError()
            }
        } message: {
            Text(detailViewModel.editErrorMessage ?? "Try again.")
        }
        .task {
            await detailViewModel.loadCatalogIfNeeded()
        }
    }

    private var header: some View {
        CompletedWorkoutSummaryHeaderCard(
            activity: activity,
            metrics: compactHeaderMetrics,
            routineEmoji: detailViewModel.routineEmoji,
            sourceSymbolName: sourceSymbolName,
            exerciseCount: detailViewModel.presentations.count
        )
    }

    @ViewBuilder
    private var routeSection: some View {
        if routeCoordinates.count > 1 {
            FitnessGlassCard(cornerRadius: 30, padding: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Route", systemImage: "map.fill")
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(primaryText)
                        .padding(.horizontal, 4)

                    Map(initialPosition: routeMapPosition) {
                        MapPolyline(coordinates: routeCoordinates)
                            .stroke(activity.category.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))

                        if let start = routeCoordinates.first {
                            Marker("Start", systemImage: "record.circle", coordinate: start)
                                .tint(.green)
                        }

                        if let finish = routeCoordinates.last {
                            Marker("Finish", systemImage: "flag.checkered", coordinate: finish)
                                .tint(activity.category.accent)
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                    .frame(height: 270)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
        } else if activity.category.isRouteTraining {
            FitnessGlassCard(cornerRadius: 30) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Route", systemImage: "map")
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(primaryText)

                    Text("No route data is attached to this workout.")
                        .pulsarTextStyle(.label)
                        .foregroundStyle(secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private var gymSetsSection: some View {
        if !detailViewModel.presentations.isEmpty {
            CompletedWorkoutExercisesSection(
                exercises: detailViewModel.presentations,
                expandedExerciseIds: detailViewModel.expandedExerciseIds,
                isEditable: detailViewModel.isEditable,
                onToggleExercise: { detailViewModel.toggleExpanded($0) },
                onExpandAll: { detailViewModel.expandAll() },
                onCollapseAll: { detailViewModel.collapseAll() },
                onShowHistory: { presentation in
                    selectedExerciseProgressTarget = ExerciseProgressLookup(
                        exerciseId: presentation.exerciseId,
                        exerciseName: presentation.exerciseName,
                        primaryMuscleGroup: presentation.primaryMuscleGroup,
                        equipment: presentation.equipment,
                        displayUnit: presentation.weightUnit
                    )
                },
                onShowInstructions: { selectedInstructionsExercise = $0 },
                onEditSet: { selectedSetEditor = $0 }
            )
        }
    }

    @ViewBuilder
    private var splitsSection: some View {
        if !activity.splits.isEmpty {
            FitnessGlassCard(cornerRadius: 30) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Splits", systemImage: "chart.bar.fill")
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(primaryText)

                    ForEach(activity.splits) { split in
                        HStack(spacing: 12) {
                            Text("\(split.index)")
                                .pulsarTextStyle(.cardTitle)
                                .monospacedDigit()
                                .frame(width: 30, alignment: .leading)

                            Text(FitnessWeekFormatters.distance(split.distanceMeters))
                                .pulsarTextStyle(.label)

                            Spacer()

                            Text(PulsarRunFormatters.pace(split.paceSecondsPerKilometer))
                                .pulsarTextStyle(.label)
                                .monospacedDigit()
                        }
                        .foregroundStyle(primaryText)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var trainingSection: some View {
        if !activity.mainMuscleGroups.isEmpty || !activity.notes.isEmpty {
            FitnessGlassCard(cornerRadius: 30) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Training", systemImage: activity.category.symbolName)
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(primaryText)

                    if !activity.mainMuscleGroups.isEmpty {
                        FlowLayout(spacing: 8, rowSpacing: 8) {
                            ForEach(activity.mainMuscleGroups, id: \.self) { muscleGroup in
                                Text(muscleGroup)
                                    .pulsarTextStyle(.captionEmphasis)
                                    .foregroundStyle(primaryText)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(activity.category.accent.opacity(colorScheme == .dark ? 0.18 : 0.12), in: Capsule(style: .continuous))
                            }
                        }
                    }

                    if !activity.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(activity.notes, id: \.self) { note in
                                Label(note, systemImage: "note.text")
                                    .pulsarTextStyle(.label)
                                    .foregroundStyle(secondaryText)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var metadataSection: some View {
        if !activity.metadata.isEmpty {
            FitnessGlassCard(cornerRadius: 30) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Details", systemImage: "info.circle.fill")
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(primaryText)

                    ForEach(activity.metadata) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(item.title)
                                .pulsarTextStyle(.captionEmphasis)
                                .foregroundStyle(secondaryText)
                                .frame(width: 118, alignment: .leading)

                            Text(item.value)
                                .font(.caption.weight(.semibold).monospaced())
                                .foregroundStyle(primaryText)
                                .lineLimit(3)
                                .minimumScaleFactor(0.72)

                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private var shareButton: some View {
        Button {
            renderShareImage()
        } label: {
            Label(activity.shareActionTitle, systemImage: "square.and.arrow.up")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(activity.category.accent.gradient, in: Capsule(style: .continuous))
        }
        .buttonStyle(FitnessWeekPressStyle())
    }

    private var compactHeaderMetrics: [FitnessWorkoutDetailMetric] {
        activity.category == .gym ? compactGymMetrics : compactTrainingMetrics
    }

    private var compactGymMetrics: [FitnessWorkoutDetailMetric] {
        var metrics = [
            FitnessWorkoutDetailMetric(title: "Duration", value: FitnessWeekFormatters.duration(activity.duration), symbolName: "timer", tint: .green)
        ]

        if let calories = activity.calories, calories > 0 {
            metrics.append(FitnessWorkoutDetailMetric(title: "Calories", value: FitnessWeekFormatters.calories(calories), symbolName: "flame.fill", tint: .orange))
        }

        if let averageHeartRate = activity.averageHeartRate, averageHeartRate > 0 {
            metrics.append(FitnessWorkoutDetailMetric(title: "Avg HR", value: "\(Int(averageHeartRate.rounded())) bpm", symbolName: "heart.fill", tint: .red))
        }

        if let setMetric {
            metrics.append(setMetric)
        }

        if metrics.count < 4,
           let maxHeartRateMetric {
            metrics.append(maxHeartRateMetric)
        }

        return Array(metrics.prefix(4))
    }

    private var compactTrainingMetrics: [FitnessWorkoutDetailMetric] {
        var metrics = [
            FitnessWorkoutDetailMetric(title: "Duration", value: FitnessWeekFormatters.duration(activity.duration), symbolName: "timer", tint: .green)
        ]

        if let distance = activity.distanceMeters, distance > 0 {
            metrics.append(FitnessWorkoutDetailMetric(title: "Distance", value: FitnessWeekFormatters.distance(distance), symbolName: "point.topleft.down.curvedto.point.bottomright.up", tint: activity.category.accent))
        }

        if let calories = activity.calories, calories > 0 {
            metrics.append(FitnessWorkoutDetailMetric(title: "Calories", value: FitnessWeekFormatters.calories(calories), symbolName: "flame.fill", tint: .orange))
        }

        if let averageHeartRate = activity.averageHeartRate, averageHeartRate > 0 {
            metrics.append(FitnessWorkoutDetailMetric(title: "Avg HR", value: "\(Int(averageHeartRate.rounded())) bpm", symbolName: "heart.fill", tint: .red))
        }

        if let paceMetric {
            metrics.append(paceMetric)
        }

        if let maxHeartRateMetric {
            metrics.append(maxHeartRateMetric)
        }

        if let setMetric,
           metrics.count < 6 {
            metrics.append(setMetric)
        }

        return Array(metrics.prefix(6))
    }

    private var setMetric: FitnessWorkoutDetailMetric? {
        guard let completedSets = activity.completedSets,
              completedSets > 0 || (activity.totalSets ?? 0) > 0 else { return nil }
        let value = activity.totalSets.map { "\(completedSets)/\($0)" } ?? "\(completedSets)"
        return FitnessWorkoutDetailMetric(title: "Sets", value: value, symbolName: "checkmark.circle.fill", tint: activity.category.accent)
    }

    private var maxHeartRateMetric: FitnessWorkoutDetailMetric? {
        guard let maxHeartRate = activity.maxHeartRate,
              maxHeartRate > 0 else { return nil }
        return FitnessWorkoutDetailMetric(title: "Max HR", value: "\(Int(maxHeartRate.rounded())) bpm", symbolName: "bolt.heart.fill", tint: .red)
    }

    private var paceMetric: FitnessWorkoutDetailMetric? {
        guard let distance = activity.distanceMeters,
              distance > 10,
              activity.duration > 0 else { return nil }
        let kind = outdoorKind
        let pace = activity.duration / (distance / 1_000)
        let speed = distance / activity.duration
        return FitnessWorkoutDetailMetric(
            title: PulsarRunFormatters.paceOrSpeedTitle(for: kind, average: true),
            value: PulsarRunFormatters.paceOrSpeed(workoutKind: kind, paceSecondsPerKilometer: pace, speedMetersPerSecond: speed),
            symbolName: "speedometer",
            tint: activity.category.accent
        )
    }

    private var outdoorKind: PulsarOutdoorWorkoutKind {
        if let kind = PulsarOutdoorWorkoutKind(workoutTypeRawValue: activity.workoutType) {
            return kind
        }
        if let kind = PulsarOutdoorWorkoutKind(workoutTypeRawValue: activity.displayName) {
            return kind
        }
        switch activity.category {
        case .running: return .running
        case .walking: return .walking
        case .hiking: return .hiking
        case .cycling: return .cycling
        case .hiit: return .hiit
        case .strength, .gym: return .strength
        case .yoga: return .yoga
        case .swimming: return .swimming
        case .rowing: return .rowing
        case .dance: return .dance
        case .recovery: return .cooldown
        case .other: return .other
        }
    }

    private var sourceSymbolName: String {
        let source = activity.effectiveSourceDeviceName.lowercased()
        if source.contains("watch") { return "applewatch" }
        if source.contains("iphone") { return "iphone" }
        return "heart.text.square.fill"
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        activity.route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var routeMapPosition: MapCameraPosition {
        let route = GPSWorkoutRoute(runCoordinates: activity.route)
        guard let bounds = route.bounds else { return .automatic }
        return .region(
            MKCoordinateRegion(
                center: bounds.center,
                span: MKCoordinateSpan(latitudeDelta: bounds.latitudeDelta, longitudeDelta: bounds.longitudeDelta)
            )
        )
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.97) : Color(red: 0.07, green: 0.10, blue: 0.14)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.60) : Color(red: 0.36, green: 0.40, blue: 0.48)
    }

    @MainActor
    private func renderShareImage() {
        let card = FitnessWorkoutHistoryShareCard(activity: activity)
            .frame(width: 1080, height: 1350)
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1350)
        renderer.scale = 1
        let image = renderer.uiImage ?? FitnessWorkoutFallbackShareRenderer.image(for: activity, size: CGSize(width: 1080, height: 1350))
        renderedShareImage = FitnessWorkoutRenderedImage(image: image)
    }
}

private struct FitnessWorkoutDetailMetric: Identifiable {
    var id: String { title }
    var title: String
    var value: String
    var symbolName: String
    var tint: Color
}

private struct CompletedWorkoutSummaryHeaderCard: View {
    var activity: WeeklyActivity
    var metrics: [FitnessWorkoutDetailMetric]
    var routineEmoji: String?
    var sourceSymbolName: String
    var exerciseCount: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 14) {
                CompletedWorkoutSummaryIcon(
                    category: activity.category,
                    routineEmoji: routineEmoji
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text(activity.displayName)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Text(activity.startDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))
                        .pulsarTextStyle(.label)
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                VStack(alignment: .trailing, spacing: 8) {
                    sourcePill
                    if exerciseCount > 0 {
                        exerciseCountChip
                    }
                }
                .frame(minWidth: 94, alignment: .trailing)
            }

            if !metrics.isEmpty {
                separator

                VStack(spacing: 12) {
                    ForEach(Array(metricRows.enumerated()), id: \.offset) { _, row in
                        CompletedWorkoutSummaryMetricRow(metrics: row)
                    }
                }
            }
        }
        .padding(16)
        .modifier(
            FitnessGlassSurfaceModifier(
                cornerRadius: 32,
                tint: Color(red: 0.72, green: 0.82, blue: 0.92),
                borderOpacity: 0.94
            )
        )
    }

    private var metricRows: [[FitnessWorkoutDetailMetric]] {
        let firstRow = Array(metrics.prefix(4))
        let secondRow = Array(metrics.dropFirst(4).prefix(2))
        return [firstRow, secondRow].filter { !$0.isEmpty }
    }

    private var sourcePill: some View {
        Label(activity.effectiveSourceDeviceName, systemImage: sourceSymbolName)
            .pulsarTextStyle(.captionEmphasis)
            .foregroundStyle(primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .modifier(FitnessGlassSurfaceModifier(cornerRadius: 17, tint: activity.category.accent, borderOpacity: 0.74))
    }

    private var exerciseCountChip: some View {
        Label("\(exerciseCount) \(exerciseCount == 1 ? "exercise" : "exercises")", systemImage: "list.bullet")
            .pulsarTextStyle(.captionEmphasis)
            .foregroundStyle(secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .modifier(FitnessGlassSurfaceModifier(cornerRadius: 17, tint: Color(red: 0.72, green: 0.82, blue: 0.92), borderOpacity: 0.58))
    }

    private var separator: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(colorScheme == .dark ? 0.14 : 0.44),
                        .white.opacity(colorScheme == .dark ? 0.06 : 0.22),
                        .white.opacity(colorScheme == .dark ? 0.04 : 0.14)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.7)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.97) : Color(red: 0.07, green: 0.10, blue: 0.14)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.60) : Color(red: 0.36, green: 0.40, blue: 0.48)
    }
}

private struct CompletedWorkoutSummaryMetricRow: View {
    var metrics: [FitnessWorkoutDetailMetric]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            metricHStack(metrics)

            VStack(spacing: 12) {
                metricHStack(Array(metrics.prefix(2)))
                metricHStack(Array(metrics.dropFirst(2)))
            }
        }
    }

    private func metricHStack(_ metrics: [FitnessWorkoutDetailMetric]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(metrics) { metric in
                CompletedWorkoutSummaryStatItem(metric: metric)
            }
        }
    }
}

private struct CompletedWorkoutSummaryIcon: View {
    var category: WeeklyActivityCategory
    var routineEmoji: String?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if let routineEmoji {
                Text(routineEmoji)
                    .font(.system(size: 32))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            } else {
                Image(systemName: category.symbolName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(category.accent)
            }
        }
        .frame(width: 64, height: 64)
        .modifier(FitnessGlassSurfaceModifier(cornerRadius: 22, tint: category.accent, borderOpacity: 0.86))
        .accessibilityHidden(true)
    }
}

private struct CompletedWorkoutSummaryStatItem: View {
    var metric: FitnessWorkoutDetailMetric

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: metric.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(metric.tint)
                    .frame(width: 18, height: 18)

                Text(metric.value)
                    .font(.system(size: 18, weight: .semibold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.70)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Text(metric.title)
                .pulsarTextStyle(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title), \(metric.value)")
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.97) : Color(red: 0.07, green: 0.10, blue: 0.14)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.60) : Color(red: 0.36, green: 0.40, blue: 0.48)
    }
}

private struct FitnessWorkoutRenderedImage: Identifiable {
    let id = UUID()
    var image: UIImage
}

private struct FitnessWorkoutHistoryShareCard: View {
    var activity: WeeklyActivity

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    activity.category.accent.opacity(0.86),
                    Color(red: 0.04, green: 0.06, blue: 0.08),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if routePoints.count > 1 {
                PulsarShareRouteLine(points: routePoints, accent: activity.category.accent, lineWidth: 11)
                    .padding(94)
            } else {
                Image(systemName: activity.category.symbolName)
                    .font(.system(size: 270, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.12))
            }

            VStack(alignment: .leading) {
                HStack {
                    Image("PulsarLogo")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 46, height: 46)
                    Text("Pulsar")
                        .font(.system(size: 28, weight: .bold, design: .default))
                    Spacer()
                    Text(activity.startDate.formatted(.dateTime.day().month(.abbreviated).year()))
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                }
                .foregroundStyle(.white)

                Spacer()

                VStack(alignment: .leading, spacing: 18) {
                    Label(activity.workoutType.uppercased(), systemImage: activity.category.symbolName)
                        .font(.system(size: 17, weight: .bold, design: .default))
                        .foregroundStyle(.white.opacity(0.76))
                        .tracking(4)

                    Text(activity.displayName)
                        .font(.system(size: 44, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.62)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(shareMetrics) { metric in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(metric.value)
                                    .font(.system(size: 32, weight: .bold, design: .default))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.70)
                                Text(metric.title)
                                    .font(.system(size: 15, weight: .semibold, design: .default))
                                    .foregroundStyle(.white.opacity(0.68))
                            }
                        }
                    }

                    Label("\(activity.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())) - \(activity.effectiveSourceDeviceName)", systemImage: "sparkles")
                        .font(.system(size: 18, weight: .semibold, design: .default))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }
                .padding(26)
                .modifier(FitnessGlassSurfaceModifier(cornerRadius: 30, tint: activity.category.accent))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 1)
                }
            }
            .padding(34)
        }
        .background(Color.black)
    }

    private var shareMetrics: [FitnessWorkoutShareMetric] {
        var metrics = [
            FitnessWorkoutShareMetric(title: "Duration", value: FitnessWeekFormatters.duration(activity.duration))
        ]
        if let distance = activity.distanceMeters, distance > 0 {
            metrics.append(FitnessWorkoutShareMetric(title: "Distance", value: FitnessWeekFormatters.distance(distance)))
            if let paceMetric = activity.sharePaceMetric {
                metrics.append(paceMetric)
            }
        }
        if let calories = activity.calories, calories > 0 {
            metrics.append(FitnessWorkoutShareMetric(title: "Calories", value: FitnessWeekFormatters.calories(calories)))
        }
        if let averageHeartRate = activity.averageHeartRate, averageHeartRate > 0 {
            metrics.append(FitnessWorkoutShareMetric(title: "Avg HR", value: "\(Int(averageHeartRate.rounded())) bpm"))
        }
        if let completedSets = activity.completedSets, completedSets > 0 {
            metrics.append(FitnessWorkoutShareMetric(title: "Sets", value: "\(completedSets)"))
        }
        if metrics.count < 3 {
            metrics.append(FitnessWorkoutShareMetric(title: "Source", value: activity.effectiveSourceDeviceName))
        }
        return Array(metrics.prefix(6))
    }

    private var routePoints: [CGPoint] {
        let route = GPSWorkoutRoute(runCoordinates: activity.route)
        return PulsarShareRouteProjection.normalizedPoints(from: route, inset: 0.09)
    }
}

private struct FitnessWorkoutShareMetric: Identifiable {
    let id = UUID()
    var title: String
    var value: String
}

private extension WeeklyActivity {
    var shareActionTitle: String {
        category.isRouteTraining ? "Share Route" : "Share Summary"
    }

    var sharePaceMetric: FitnessWorkoutShareMetric? {
        guard let distance = distanceMeters,
              distance > 10,
              duration > 0 else { return nil }
        let kind = shareOutdoorKind
        let pace = duration / (distance / 1_000)
        let speed = distance / duration
        return FitnessWorkoutShareMetric(
            title: PulsarRunFormatters.paceOrSpeedTitle(for: kind, average: true),
            value: PulsarRunFormatters.paceOrSpeed(
                workoutKind: kind,
                paceSecondsPerKilometer: pace,
                speedMetersPerSecond: speed
            )
        )
    }

    var shareOutdoorKind: PulsarOutdoorWorkoutKind {
        if let kind = PulsarOutdoorWorkoutKind(workoutTypeRawValue: workoutType) {
            return kind
        }
        if let kind = PulsarOutdoorWorkoutKind(workoutTypeRawValue: displayName) {
            return kind
        }
        switch category {
        case .running: return .running
        case .walking: return .walking
        case .hiking: return .hiking
        case .cycling: return .cycling
        case .hiit: return .hiit
        case .strength, .gym: return .strength
        case .yoga: return .yoga
        case .swimming: return .swimming
        case .rowing: return .rowing
        case .dance: return .dance
        case .recovery: return .cooldown
        case .other: return .other
        }
    }
}

private struct FitnessRouteMiniLine: View {
    var points: [CGPoint]
    var tint: Color

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }
            var path = Path()
            let scaled = points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            path.move(to: scaled[0])
            for point in scaled.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(tint), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            if let first = scaled.first {
                context.fill(Path(ellipseIn: CGRect(x: first.x - 8, y: first.y - 8, width: 16, height: 16)), with: .color(.white))
            }
            if let last = scaled.last {
                context.fill(Path(ellipseIn: CGRect(x: last.x - 10, y: last.y - 10, width: 20, height: 20)), with: .color(tint))
            }
        }
    }
}

private struct FitnessWorkoutActivityView: UIViewControllerRepresentable {
    var activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private enum FitnessWorkoutFallbackShareRenderer {
    static func image(for activity: WeeklyActivity, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: 18))

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 72, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 38, weight: .bold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.82)
            ]

            NSString(string: activity.displayName).draw(
                in: CGRect(x: 72, y: 150, width: size.width - 144, height: 180),
                withAttributes: titleAttributes
            )
            NSString(string: FitnessWeekFormatters.activityDateTime(activity.startDate)).draw(
                in: CGRect(x: 72, y: 340, width: size.width - 144, height: 60),
                withAttributes: bodyAttributes
            )
            NSString(string: "Duration \(FitnessWeekFormatters.duration(activity.duration))").draw(
                in: CGRect(x: 72, y: 470, width: size.width - 144, height: 60),
                withAttributes: bodyAttributes
            )
            if let calories = activity.calories, calories > 0 {
                NSString(string: "Calories \(FitnessWeekFormatters.calories(calories))").draw(
                    in: CGRect(x: 72, y: 540, width: size.width - 144, height: 60),
                    withAttributes: bodyAttributes
                )
            }
            if let distance = activity.distanceMeters, distance > 0 {
                NSString(string: "Distance \(FitnessWeekFormatters.distance(distance))").draw(
                    in: CGRect(x: 72, y: 610, width: size.width - 144, height: 60),
                    withAttributes: bodyAttributes
                )
                if let paceMetric = activity.sharePaceMetric {
                    NSString(string: "\(paceMetric.title) \(paceMetric.value)").draw(
                        in: CGRect(x: 72, y: 680, width: size.width - 144, height: 60),
                        withAttributes: bodyAttributes
                    )
                }
            }
            NSString(string: "Pulsar").draw(
                in: CGRect(x: 72, y: size.height - 150, width: size.width - 144, height: 60),
                withAttributes: bodyAttributes
            )
        }
    }
}

private struct FitnessWeeklyEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(.green.opacity(colorScheme == .dark ? 0.14 : 0.10))
                    .frame(width: 66, height: 66)

                Image(systemName: "figure.run.circle")
                    .font(.system(size: 31, weight: .semibold))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 5) {
                Text("No activities this week")
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(primaryText)

                Text("Start a workout to build your weekly log.")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 190)
        .background(emptyGradient, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .modifier(FitnessGlassSurfaceModifier(cornerRadius: 30, tint: .green))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.14 : 0.78), lineWidth: 1)
        }
    }

    private var emptyGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.09), Color.white.opacity(0.035), Color.green.opacity(0.055)]
                : [Color.white.opacity(0.90), Color(red: 0.95, green: 0.98, blue: 1.00).opacity(0.74), Color.green.opacity(0.055)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.97) : Color(red: 0.07, green: 0.10, blue: 0.14)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.58) : Color(red: 0.36, green: 0.40, blue: 0.48)
    }
}

private struct FitnessActivityLoadingCard: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Loading weekly activities")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .pulsarLiquidGlass(cornerRadius: 30)
    }
}

struct FitnessWeekHistorySheet: View {
    var weeks: [WeekPeriod]
    var selectedWeek: WeekPeriod
    var isLoading: Bool
    var onSelect: (WeekPeriod) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            FitnessWeeklyBackground()

            VStack(alignment: .leading, spacing: 18) {
                header

                if isLoading && weeks.isEmpty {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Loading week history")
                            .pulsarTextStyle(.cardTitle)
                            .foregroundStyle(secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                    .pulsarLiquidGlass(cornerRadius: 30)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(sortedWeeks) { week in
                                FitnessWeekHistoryRow(
                                    week: week,
                                    isSelected: week.id == selectedWeek.id
                                ) {
                                    onSelect(week)
                                }
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Week History")
                        .pulsarTextStyle(.displayMedium)
                        .foregroundStyle(primaryText)

                    Text("Choose a week to review your training rhythm.")
                        .pulsarTextStyle(.label)
                        .foregroundStyle(secondaryText)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(secondaryText)
                        .frame(width: 34, height: 34)
                        .background(closeButtonBackground, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(colorScheme == .dark ? 0.12 : 0.70), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close week history")
            }

            Text("\(selectedWeek.year)")
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.green.opacity(colorScheme == .dark ? 0.14 : 0.10), in: Capsule(style: .continuous))
        }
        .padding(18)
        .background(headerBackground, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .modifier(FitnessGlassSurfaceModifier(cornerRadius: 30, tint: .green))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.15 : 0.78), lineWidth: 1)
        }
    }

    private var sortedWeeks: [WeekPeriod] {
        weeks.sorted { $0.startDate > $1.startDate }
    }

    private var headerBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.10), Color.white.opacity(0.04), Color.green.opacity(0.055)]
                : [Color.white.opacity(0.90), Color(red: 0.94, green: 0.98, blue: 0.96).opacity(0.78), Color.green.opacity(0.055)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var closeButtonBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.11), Color.white.opacity(0.04)]
                : [Color.white.opacity(0.86), Color(red: 0.95, green: 0.98, blue: 1.00).opacity(0.60)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.97) : Color(red: 0.07, green: 0.10, blue: 0.14)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.60) : Color(red: 0.36, green: 0.40, blue: 0.48)
    }
}

private struct FitnessWeekHistoryRow: View {
    var week: WeekPeriod
    var isSelected: Bool
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(week.hasWorkout ? .green.opacity(0.16) : secondaryText.opacity(0.12))
                        .frame(width: 38, height: 38)

                    Circle()
                        .fill(week.hasWorkout ? .green : secondaryText.opacity(0.45))
                        .frame(width: 10, height: 10)
                        .shadow(color: (week.hasWorkout ? Color.green : .clear).opacity(0.72), radius: 8)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("Week \(week.weekNumber)")
                            .pulsarTextStyle(.cardTitle)
                            .monospacedDigit()
                            .foregroundStyle(primaryText)

                        if week.isCurrentWeek {
                            Text("Current")
                                .pulsarTextStyle(.overline)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(.green.opacity(colorScheme == .dark ? 0.15 : 0.11), in: Capsule(style: .continuous))
                        }
                    }

                    Text(FitnessWeekFormatters.dateRange(for: week))
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(secondaryText)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(isSelected ? Color.green : secondaryText.opacity(0.55))
            }
            .padding(14)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .modifier(FitnessGlassSurfaceModifier(cornerRadius: 24, tint: isSelected ? .green : Color(red: 0.68, green: 0.80, blue: 0.92), isInteractive: true))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(isSelected ? Color.green.opacity(0.58) : .white.opacity(colorScheme == .dark ? 0.13 : 0.70), lineWidth: isSelected ? 1.3 : 1)
            }
        }
        .buttonStyle(FitnessWeekPressStyle())
        .accessibilityLabel("Week \(week.weekNumber), \(FitnessWeekFormatters.dateRange(for: week))")
        .accessibilityValue(week.hasWorkout ? "Has workout" : "No workouts")
    }

    private var rowBackground: LinearGradient {
        LinearGradient(
            colors: isSelected
                ? [
                    Color.green.opacity(colorScheme == .dark ? 0.17 : 0.12),
                    Color.white.opacity(colorScheme == .dark ? 0.09 : 0.86)
                ]
                : [
                    Color.white.opacity(colorScheme == .dark ? 0.09 : 0.82),
                    Color.white.opacity(colorScheme == .dark ? 0.035 : 0.48)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.97) : Color(red: 0.07, green: 0.10, blue: 0.14)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.58) : Color(red: 0.36, green: 0.40, blue: 0.48)
    }
}

struct FitnessWeeklyBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.115, green: 0.125, blue: 0.140)

                Image("FitnessBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .saturation(colorScheme == .dark ? 1.0 : 0.78)
                    .brightness(colorScheme == .dark ? 0.02 : 0.06)

                LinearGradient(
                    colors: [
                        Color.black.opacity(colorScheme == .dark ? 0.00 : 0.03),
                        Color.black.opacity(colorScheme == .dark ? 0.05 : 0.08),
                        Color.black.opacity(colorScheme == .dark ? 0.18 : 0.16)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}

struct FitnessSectionHeader<Trailing: View>: View {
    var title: String
    var subtitle: String
    var titleFont: Font = PulsarTypography.Role.sectionTitle.font
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        subtitle: String,
        titleFont: Font = PulsarTypography.Role.sectionTitle.font,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.titleFont = titleFont
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(titleFont)
                    .tracking(PulsarTypography.Role.sectionTitle.tracking)
                    .lineSpacing(PulsarTypography.Role.sectionTitle.lineSpacing)
                    .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(subtitle)
                    .pulsarTextStyle(.screenSubtitle)
                    .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            trailing()
        }
    }
}

extension FitnessSectionHeader where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String,
        titleFont: Font = PulsarTypography.Role.sectionTitle.font
    ) {
        self.init(title: title, subtitle: subtitle, titleFont: titleFont) {
            EmptyView()
        }
    }
}

struct FitnessGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 32
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        PulsarGlassCard(cornerRadius: cornerRadius, contentPadding: padding) {
            content()
        }
    }
}

struct FitnessGlassSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color = Color(red: 0.68, green: 0.80, blue: 0.92)
    var isInteractive = false
    var borderOpacity: Double = 1

    func body(content: Content) -> some View {
        PulsarGlassCard(
            cornerRadius: cornerRadius,
            contentPadding: 0,
            tint: tint.opacity(borderOpacity > 0 ? 0.08 : 0),
            isInteractive: isInteractive
        ) {
            content
        }
    }
}

typealias FitnessCircularGlassSurface = PulsarCircularGlassSurface

struct FitnessPanel<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var padding: CGFloat = 14
    var borderOpacity: Double = 1
    var tint: Color = .green
    @ViewBuilder var content: () -> Content

    var body: some View {
        PulsarGlassCard(cornerRadius: cornerRadius, contentPadding: padding, tint: tint.opacity(0.08 * borderOpacity)) {
            content()
        }
    }
}

struct FitnessWeekPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, proposal: proposal)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * rowSpacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: subviews, proposal: ProposedViewSize(width: bounds.width, height: proposal.height))
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(for subviews: Subviews, proposal: ProposedViewSize) -> [FlowRow] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [FlowRow] = []
        var current = FlowRow()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth = current.items.isEmpty ? size.width : current.width + spacing + size.width

            if proposedWidth > maxWidth, !current.items.isEmpty {
                rows.append(current)
                current = FlowRow()
            }

            current.items.append(FlowItem(subview: subview, size: size))
            current.width = current.items.count == 1 ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
        }

        if !current.items.isEmpty {
            rows.append(current)
        }

        return rows
    }

    private struct FlowRow {
        var items: [FlowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private struct FlowItem {
        var subview: LayoutSubview
        var size: CGSize
    }
}

enum FitnessWeekFormatters {
    static func dateRange(for week: WeekPeriod) -> String {
        "\(monthDayYear.string(from: week.startDate)) - \(monthDayYear.string(from: week.endDate))"
    }

    static func heroDateRange(for week: WeekPeriod) -> String {
        let calendar = Calendar.current
        let sameYear = calendar.component(.year, from: week.startDate) == calendar.component(.year, from: week.endDate)
        if sameYear {
            return "\(monthDay.string(from: week.startDate)) - \(monthDayYear.string(from: week.endDate))"
        }
        return dateRange(for: week)
    }

    static func compactDateRange(for week: WeekPeriod) -> String {
        "\(monthDay.string(from: week.startDate)) - \(monthDay.string(from: week.endDate))"
    }

    static func activityDateTime(_ date: Date) -> String {
        activityDate.string(from: date)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int((interval / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    static func calories(_ value: Double) -> String {
        "\(Int(value.rounded())) kcal"
    }

    static func distance(_ meters: Double) -> String {
        let kilometers = max(0, meters) / 1_000
        if kilometers < 10 {
            return String(format: "%.2f km", kilometers)
        }
        return String(format: "%.1f km", kilometers)
    }

    private static let monthDayYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let activityDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d 'at' h:mm a"
        return formatter
    }()
}

#Preview {
    ScrollView {
        VStack(spacing: 18) {
            FitnessWeekHeaderView(
                week: FitnessWeekCalculator.getWeekPeriod(for: .now, hasWorkout: true),
                canMoveToNextWeek: false,
                isRefreshing: false,
                onPrevious: {},
                onNext: {},
                onCurrent: {}
            )
            FitnessWeekSelectorView(
                weeks: Array(FitnessWeekCalculator.getWeekPeriodsAroundCurrentWeek().suffix(3)),
                selectedWeek: FitnessWeekCalculator.getWeekPeriod(for: .now),
                onShowHistory: {},
                onSelect: { _ in }
            )
            FitnessActivityLogSection(
                week: FitnessWeekCalculator.getWeekPeriod(for: .now),
                activities: [],
                isLoading: false,
                isExpanded: false,
                onToggleExpanded: {},
                onSelectActivity: { _ in }
            )
        }
        .padding(18)
    }
    .background(FitnessWeeklyBackground())
}
