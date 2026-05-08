//
//  FitnessWeeklyComponents.swift
//  Pulsar
//

import SwiftUI

struct FitnessWeekHeaderView: View {
    var week: WeekPeriod
    var canMoveToNextWeek: Bool
    var isRefreshing: Bool
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onCurrent: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fitness")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(primaryText)

                    Text("Weekly training rhythm")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(secondaryText)
                }

                Spacer(minLength: 12)

                if !week.isCurrentWeek {
                    Button(action: onCurrent) {
                        Text("Current Week")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.green.opacity(colorScheme == .dark ? 0.16 : 0.12), in: Capsule(style: .continuous))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(.green.opacity(0.28), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Week \(week.weekNumber)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(primaryText)

                    Text(FitnessWeekFormatters.dateRange(for: week))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(secondaryText)
                }

                Spacer(minLength: 10)

                HStack(spacing: 9) {
                    weekArrow(systemName: "chevron.left", action: onPrevious, isEnabled: true)
                    weekArrow(systemName: "chevron.right", action: onNext, isEnabled: canMoveToNextWeek)
                }
            }

            HStack(spacing: 9) {
                Circle()
                    .fill(week.hasWorkout ? .green : secondaryText.opacity(0.42))
                    .frame(width: 8, height: 8)
                    .shadow(color: (week.hasWorkout ? Color.green : .clear).opacity(0.55), radius: 7)

                Text(week.hasWorkout ? "Workout logged this week" : "No workout logged yet")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(week.hasWorkout ? Color.green.opacity(0.92) : secondaryText)

                Spacer()

                if isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(secondaryText)
                }
            }
        }
        .padding(20)
        .background(headerGradient, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .stroke(borderGradient, lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.10), radius: 24, y: 14)
    }

    private func weekArrow(systemName: String, action: @escaping () -> Void, isEnabled: Bool) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.bold))
                .foregroundStyle(isEnabled ? primaryText : secondaryText.opacity(0.45))
                .frame(width: 40, height: 40)
                .background(arrowBackground(isEnabled: isEnabled), in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(colorScheme == .dark ? 0.14 : 0.60), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(systemName == "chevron.left" ? "Previous week" : "Next week")
    }

    private func arrowBackground(isEnabled: Bool) -> LinearGradient {
        LinearGradient(
            colors: isEnabled
                ? [Color.white.opacity(colorScheme == .dark ? 0.16 : 0.82), Color.white.opacity(colorScheme == .dark ? 0.06 : 0.42)]
                : [Color.white.opacity(colorScheme == .dark ? 0.07 : 0.36), Color.white.opacity(colorScheme == .dark ? 0.03 : 0.18)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var headerGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.11),
                    Color(red: 0.07, green: 0.12, blue: 0.16).opacity(0.90),
                    Color.green.opacity(0.10)
                ]
                : [
                    Color.white.opacity(0.92),
                    Color(red: 0.93, green: 0.98, blue: 0.96).opacity(0.82),
                    Color.green.opacity(0.08)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(colorScheme == .dark ? 0.24 : 0.86),
                .green.opacity(colorScheme == .dark ? 0.18 : 0.24),
                .black.opacity(colorScheme == .dark ? 0.24 : 0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.98) : Color(red: 0.07, green: 0.10, blue: 0.14)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color(red: 0.36, green: 0.40, blue: 0.48)
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
                        .font(.headline.weight(.bold))
                        .foregroundStyle(primaryText)

                    Text("Tap a week or browse history")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryText)
                }

                Spacer()

                Button(action: onShowHistory) {
                    HStack(spacing: 7) {
                        Image(systemName: "calendar")
                            .font(.caption.weight(.bold))
                        Text("View all")
                            .font(.caption.weight(.bold))
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
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.green.opacity(colorScheme == .dark ? 0.15 : 0.11), in: Capsule(style: .continuous))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Week \(week.weekNumber)")
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(primaryText)

                    Text(FitnessWeekFormatters.compactDateRange(for: week))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96, alignment: .leading)
            .background(cardGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Activity Log")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(primaryText)

                    Text(summaryText)
                        .font(.subheadline.weight(.medium))
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
                        FitnessActivityRow(activity: activity)
                    }

                    if activities.count > 4 {
                        Button(action: onToggleExpanded) {
                            HStack(spacing: 8) {
                                Text(isExpanded ? "Show less" : "Show all \(activities.count) activities")
                                    .font(.subheadline.weight(.bold))
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.bold))
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
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: activities)
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
                            .font(.headline.weight(.bold))
                            .foregroundStyle(primaryText)

                        Text(FitnessWeekFormatters.activityDateTime(activity.startDate))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(secondaryText)
                    }

                    Spacer(minLength: 8)

                    Text(activity.sourceName)
                        .font(.caption2.weight(.bold))
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
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowGradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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
                .font(.caption2.weight(.bold))
            Text(value)
                .font(.caption.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(colorScheme == .dark ? .white.opacity(0.74) : Color(red: 0.20, green: 0.24, blue: 0.30))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.white.opacity(colorScheme == .dark ? 0.075 : 0.64), in: Capsule(style: .continuous))
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
                    .font(.headline.weight(.bold))
                    .foregroundStyle(primaryText)

                Text("Start a workout to build your weekly log.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 190)
        .background(emptyGradient, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
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
                .font(.headline.weight(.semibold))
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
                            .font(.headline.weight(.semibold))
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
                        .font(.title.bold())
                        .foregroundStyle(primaryText)

                    Text("Choose a week to review your training rhythm.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(secondaryText)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
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
                .font(.caption.weight(.bold))
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.green.opacity(colorScheme == .dark ? 0.14 : 0.10), in: Capsule(style: .continuous))
        }
        .padding(18)
        .background(headerBackground, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
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
                            .font(.headline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(primaryText)

                        if week.isCurrentWeek {
                            Text("Current")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(.green.opacity(colorScheme == .dark ? 0.15 : 0.11), in: Capsule(style: .continuous))
                        }
                    }

                    Text(FitnessWeekFormatters.dateRange(for: week))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryText)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(isSelected ? Color.green : secondaryText.opacity(0.55))
            }
            .padding(14)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.025, green: 0.045, blue: 0.060),
                        Color(red: 0.025, green: 0.030, blue: 0.055),
                        Color.black
                    ]
                    : [
                        Color(.systemBackground),
                        Color(red: 0.91, green: 0.98, blue: 0.95),
                        Color(red: 0.94, green: 0.96, blue: 1.00)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [.green.opacity(colorScheme == .dark ? 0.24 : 0.16), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 330
            )

            RadialGradient(
                colors: [.cyan.opacity(colorScheme == .dark ? 0.13 : 0.10), .clear],
                center: .bottomLeading,
                startRadius: 40,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}

private struct FitnessWeekPressStyle: ButtonStyle {
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
                onToggleExpanded: {}
            )
        }
        .padding(18)
    }
    .background(FitnessWeeklyBackground())
}
