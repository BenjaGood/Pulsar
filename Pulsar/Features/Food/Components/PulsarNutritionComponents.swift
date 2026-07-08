//
//  PulsarNutritionComponents.swift
//  Pulsar
//

import SwiftUI

struct PulsarNutritionGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 28
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        PulsarGlassCard(cornerRadius: cornerRadius, contentPadding: padding) {
            content
        }
    }
}

struct NutritionPageTitleHeader: View {
    var onAdd: () -> Void

    var body: some View {
        PulsarTabHeader(
            systemImage: "fork.knife",
            title: "Nutrition",
            subtitle: "Track meals. Fuel goals.",
            primaryText: .white.opacity(0.96),
            secondaryText: .white.opacity(0.62),
            onAdd: onAdd,
            addAccessibilityLabel: "Add food"
        )
    }
}

struct NutritionCalorieSummaryCard: View {
    var dashboard: PulsarNutritionDashboard

    private var remainingCaloriesProgress: Double {
        guard dashboard.calorieGoal > 0 else { return 0 }
        return min(max(dashboard.remainingCalories / dashboard.calorieGoal, 0), 1)
    }

    var body: some View {
        PulsarNutritionGlassCard(cornerRadius: 28, padding: 16) {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    NutritionRing(progress: dashboard.caloriesProgress, tint: .orange, lineWidth: 7)
                    VStack(spacing: 1) {
                        Text("\(Int((min(max(dashboard.caloriesProgress, 0), 1) * 100).rounded()))%")
                            .pulsarTextStyle(.label)
                            .monospacedDigit()
                        Text("of goal")
                            .pulsarTextStyle(.overline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Today's calories")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(PulsarNutritionFormatters.calories(dashboard.totals.calories))
                            .pulsarMonospacedMetric(.metricValue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text("cal")
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(.green)
                    }

                    Text("of \(PulsarNutritionFormatters.calories(dashboard.calorieGoal)) cal goal")
                        .pulsarTextStyle(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    NutritionLinearProgressBar(progress: dashboard.caloriesProgress, tint: .orange, height: 5)
                }

                Divider()
                    .frame(height: 70)
                    .overlay(.white.opacity(0.18))

                VStack(alignment: .leading, spacing: 8) {
                    Text(PulsarNutritionFormatters.calories(dashboard.remainingCalories))
                        .pulsarMonospacedMetric(.metricValue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text("cal left")
                        .pulsarTextStyle(.caption)
                        .foregroundStyle(.secondary)
                    NutritionLinearProgressBar(progress: remainingCaloriesProgress, tint: .green, height: 5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct NutritionMacroTripletCard: View {
    var dashboard: PulsarNutritionDashboard

    var body: some View {
        PulsarNutritionGlassCard(cornerRadius: 26, padding: 14) {
            HStack(spacing: 0) {
                NutritionMacroTripletColumn(
                    title: "Protein",
                    value: PulsarNutritionFormatters.grams(dashboard.totals.protein),
                    percent: dashboard.proteinProgress,
                    goal: PulsarNutritionFormatters.grams(dashboard.proteinGoal),
                    symbolName: "leaf.fill",
                    tint: .green
                )
                NutritionMacroDivider()
                NutritionMacroTripletColumn(
                    title: "Carbs",
                    value: PulsarNutritionFormatters.grams(dashboard.totals.carbohydrates),
                    percent: dashboard.carbohydratesProgress,
                    goal: PulsarNutritionFormatters.grams(dashboard.carbohydratesGoal),
                    symbolName: "bolt.fill",
                    tint: .cyan
                )
                NutritionMacroDivider()
                NutritionMacroTripletColumn(
                    title: "Fats",
                    value: PulsarNutritionFormatters.grams(dashboard.totals.fat),
                    percent: dashboard.fatProgress,
                    goal: PulsarNutritionFormatters.grams(dashboard.fatGoal),
                    symbolName: "drop.fill",
                    tint: .purple
                )
            }
        }
    }
}

private struct NutritionMacroTripletColumn: View {
    var title: String
    var value: String
    var percent: Double
    var goal: String
    var symbolName: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PulsarGlassIconCircle(size: 32, tint: tint, systemImage: symbolName, symbolScale: 0.42)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .pulsarTextStyle(.cardTitle)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            HStack(spacing: 5) {
                Text("\(Int((min(max(percent, 0), 1) * 100).rounded()))%")
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(tint)
                    .monospacedDigit()
                Text("•")
                    .pulsarTextStyle(.caption)
                    .foregroundStyle(.tertiary)
                Text("Goal \(goal)")
                    .pulsarTextStyle(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            NutritionLinearProgressBar(progress: percent, tint: tint, height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }
}

private struct NutritionMacroDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.16))
            .frame(width: 1, height: 84)
            .padding(.horizontal, 8)
    }
}

struct NutritionMealsSection: View {
    var categories: [PulsarMealCategory]
    var entriesForCategory: (PulsarMealCategory) -> [PulsarNutritionEntry]
    var onAdd: (PulsarMealCategory) -> Void
    var onEditEntry: (PulsarNutritionEntry) -> Void
    var onDeleteEntry: (PulsarNutritionEntry) -> Void
    var onEditMeals: () -> Void

    @State private var expandedCategoryIDs: Set<UUID> = []

    private var totalCalories: Double {
        categories.reduce(0) { partial, category in
            partial + entriesForCategory(category).reduce(0) { $0 + $1.nutrition.calories }
        }
    }

    var body: some View {
        PulsarNutritionGlassCard(cornerRadius: 28, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Text("Meals")
                        .pulsarTextStyle(.sectionHeader)
                    Spacer()
                    Button(action: onEditMeals) {
                        Label("Edit", systemImage: "pencil")
                            .pulsarTextStyle(.captionEmphasis)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(NutritionIconTextButtonStyle(tint: .green))
                    .accessibilityLabel("Edit meal categories")
                }

                VStack(spacing: 10) {
                    ForEach(categories) { category in
                        NutritionMealRow(
                            category: category,
                            entries: entriesForCategory(category),
                            isExpanded: expandedCategoryIDs.contains(category.id),
                            onToggleExpanded: { toggle(category.id) },
                            onAdd: { onAdd(category) },
                            onEditEntry: onEditEntry,
                            onDeleteEntry: onDeleteEntry
                        )
                    }
                }

                HStack {
                    Text("Total logged")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(PulsarNutritionFormatters.calories(totalCalories)) cal")
                        .pulsarMonospacedMetric(.label)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
        }
    }

    private func toggle(_ id: UUID) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            if expandedCategoryIDs.contains(id) {
                expandedCategoryIDs.remove(id)
            } else {
                expandedCategoryIDs.insert(id)
            }
        }
    }
}

struct NutritionMealRow: View {
    var category: PulsarMealCategory
    var entries: [PulsarNutritionEntry]
    var isExpanded: Bool
    var onToggleExpanded: () -> Void
    var onAdd: () -> Void
    var onEditEntry: (PulsarNutritionEntry) -> Void
    var onDeleteEntry: (PulsarNutritionEntry) -> Void

    private var totals: PulsarNutritionFacts {
        entries.reduce(.zero) { $0 + $1.nutrition }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button(action: onToggleExpanded) {
                    HStack(spacing: 12) {
                        PulsarGlassIconCircle(size: 44, tint: category.tint, systemImage: category.symbolName, symbolScale: 0.38)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.name)
                                .pulsarTextStyle(.label)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            Text("\(entries.count) \(entries.count == 1 ? "item" : "items")")
                                .pulsarTextStyle(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                Text("\(PulsarNutritionFormatters.calories(totals.calories)) cal")
                    .pulsarMonospacedMetric(.captionEmphasis)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .pulsarTextStyle(.label)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(NutritionIconButtonStyle(tint: category.tint, size: 34))
                .accessibilityLabel("Add food to \(category.name)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }

            if isExpanded && !entries.isEmpty {
                VStack(spacing: 8) {
                    ForEach(entries) { entry in
                        NutritionMealEntryRow(
                            entry: entry,
                            tint: category.tint,
                            onEdit: { onEditEntry(entry) },
                            onDelete: { onDeleteEntry(entry) }
                        )
                    }
                }
                .padding(.leading, 12)
            }
        }
    }
}

private struct NutritionMealEntryRow: View {
    var entry: PulsarNutritionEntry
    var tint: Color
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onEdit) {
                HStack(spacing: 10) {
                    PulsarGlassIconCircle(size: 28, tint: tint, systemImage: "fork.knife", symbolScale: 0.40)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.food.name)
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(entry.servingText)
                            .pulsarTextStyle(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text("\(PulsarNutritionFormatters.calories(entry.nutrition.calories)) cal")
                        .pulsarMonospacedMetric(.captionEmphasis)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .pulsarTextStyle(.captionEmphasis)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

struct NutritionTodayCard: View {
    var dashboard: PulsarNutritionDashboard
    var onAddFood: () -> Void

    var body: some View {
        PulsarNutritionGlassCard(cornerRadius: 32) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 16) {
                    NutritionNourishmentHalo(
                        caloriesProgress: dashboard.caloriesProgress,
                        proteinProgress: dashboard.proteinProgress
                    )
                    .frame(width: 94, height: 94)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today’s Nourishment")
                            .pulsarTextStyle(.sectionTitle)
                        Text(todayCopy)
                            .pulsarTextStyle(.screenSubtitle)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    NutritionDailySummaryTile(
                        title: "Calories",
                        value: PulsarNutritionFormatters.calories(dashboard.totals.calories),
                        unit: "cal",
                        caption: "of \(PulsarNutritionFormatters.calories(dashboard.calorieGoal)) goal",
                        tint: .orange,
                        progress: dashboard.caloriesProgress
                    )

                    NutritionDailySummaryTile(
                        title: "Remaining",
                        value: PulsarNutritionFormatters.calories(dashboard.remainingCalories),
                        unit: "cal",
                        caption: "left today",
                        tint: .blue,
                        progress: remainingCaloriesProgress
                    )
                }

                NutritionProteinFocusPanel(
                    consumed: dashboard.totals.protein,
                    goal: dashboard.proteinGoal,
                    progress: dashboard.proteinProgress
                )

                HStack(spacing: 10) {
                    NutritionMacroSummaryBar(
                        title: "Carbs",
                        value: PulsarNutritionFormatters.grams(dashboard.totals.carbohydrates),
                        caption: "Goal \(PulsarNutritionFormatters.grams(dashboard.carbohydratesGoal))",
                        symbolName: "bolt.fill",
                        tint: .teal,
                        progress: dashboard.carbohydratesProgress
                    )

                    NutritionMacroSummaryBar(
                        title: "Fats",
                        value: PulsarNutritionFormatters.grams(dashboard.totals.fat),
                        caption: "Goal \(PulsarNutritionFormatters.grams(dashboard.fatGoal))",
                        symbolName: "drop.circle.fill",
                        tint: .purple,
                        progress: dashboard.fatProgress
                    )
                }

                Button(action: onAddFood) {
                    Label("Log food", systemImage: "plus")
                        .pulsarTextStyle(.buttonTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(NutritionActionButtonStyle(tint: .green))
            }
        }
    }

    private var remainingCaloriesProgress: Double {
        guard dashboard.calorieGoal > 0 else { return 0 }
        return min(max(dashboard.remainingCalories / dashboard.calorieGoal, 0), 1)
    }

    private var todayCopy: String {
        if dashboard.entries.isEmpty {
            return "Start with one quick food. Pulsar keeps calories, protein, carbs, and fats easy to read."
        }
        if dashboard.proteinProgress >= 1 {
            return "Protein is anchored with \(PulsarNutritionFormatters.calories(dashboard.remainingCalories)) calories still available."
        }
        if dashboard.remainingCalories <= 250 {
            return "Calories are nearly complete. Small choices from here are enough."
        }
        return "Your day is updating at a glance as meals are logged."
    }
}

struct NutritionDailySummaryTile: View {
    var title: String
    var value: String
    var unit: String
    var caption: String
    var tint: Color
    var progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .pulsarTextStyle(.metricLabel)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .pulsarMonospacedMetric(.metricValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(unit)
                    .pulsarTextStyle(.metricLabel)
                    .foregroundStyle(tint)
            }

            Text(caption)
                .pulsarTextStyle(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.74)

            NutritionLinearProgressBar(progress: progress, tint: tint, height: 5)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        }
    }
}

struct NutritionProteinFocusPanel: View {
    var consumed: Double
    var goal: Double
    var progress: Double

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                NutritionRing(progress: progress, tint: .green, lineWidth: 8)
                Image(systemName: "figure.strengthtraining.traditional")
                    .pulsarTextStyle(.cardTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.green)
            }
            .frame(width: 56, height: 56)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(PulsarNutritionFormatters.grams(consumed))
                            .pulsarTextStyle(.title)
                            .monospacedDigit()
                        Text("protein consumed")
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Text("\(Int((min(max(progress, 0), 1) * 100).rounded()))%")
                        .pulsarTextStyle(.cardTitle)
                        .monospacedDigit()
                        .foregroundStyle(.green)
                }

                NutritionLinearProgressBar(progress: progress, tint: .green, height: 7)

                Text("Daily anchor \(PulsarNutritionFormatters.grams(goal))")
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.green.opacity(0.20), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Protein consumed \(PulsarNutritionFormatters.grams(consumed)) of \(PulsarNutritionFormatters.grams(goal))")
    }
}

struct NutritionMacroSummaryBar: View {
    var title: String
    var value: String
    var caption: String
    var symbolName: String
    var tint: Color
    var progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(tint.opacity(0.13), in: Circle())

                Text(title)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            Text(value)
                .pulsarTextStyle(.cardTitle)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.76)

            HStack(spacing: 6) {
                NutritionLinearProgressBar(progress: progress, tint: tint, height: 5)
                Text(caption)
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct NutritionLinearProgressBar: View {
    var progress: Double
    var tint: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(tint.opacity(0.13))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.76))
                        .frame(width: proxy.size.width * min(max(progress, 0), 1))
                }
        }
        .frame(height: height)
        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: progress)
    }
}

struct NutritionNourishmentHalo: View {
    var caloriesProgress: Double
    var proteinProgress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.green.opacity(0.24),
                            Color.orange.opacity(0.12),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 58
                    )
                )
                .blur(radius: 7)
                .scaleEffect(pulse && !reduceMotion ? 1.08 : 0.96)

            NutritionRing(progress: proteinProgress, tint: .green, lineWidth: 8)
                .padding(4)
            NutritionRing(progress: caloriesProgress, tint: .orange, lineWidth: 7)
                .padding(18)

            VStack(spacing: 0) {
                Text("\(Int((min(max(proteinProgress, 0), 1) * 100).rounded()))%")
                    .pulsarTextStyle(.captionEmphasis)
                    .monospacedDigit()
                Text("protein")
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(.green)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily progress \(Int((min(max(caloriesProgress, 0), 1) * 100).rounded())) percent calories and \(Int((min(max(proteinProgress, 0), 1) * 100).rounded())) percent protein")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct NutritionRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.45), tint, tint.opacity(0.75)], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .animation(.spring(response: 0.58, dampingFraction: 0.88), value: progress)
    }
}

struct NutritionMetricTile: View {
    var title: String
    var value: String
    var caption: String
    var symbolName: String
    var tint: Color
    var progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbolName)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.13), in: Circle())
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .pulsarTextStyle(.cardTitle)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(title)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(.secondary)
                Text(caption)
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }

            GeometryReader { proxy in
                Capsule()
                    .fill(tint.opacity(0.13))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(tint.opacity(0.72))
                            .frame(width: proxy.size.width * min(max(progress, 0), 1))
                    }
            }
            .frame(height: 5)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }
}

struct NutritionSectionHeader: View {
    var title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .pulsarTextStyle(.sectionHeader)
                if let subtitle {
                    Text(subtitle)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .pulsarTextStyle(.captionEmphasis)
                    .buttonStyle(.borderless)
            }
        }
    }
}

struct NutritionMealMomentCard: View {
    var moment: PulsarNutritionMealMoment
    var entries: [PulsarNutritionEntry]
    var onAdd: () -> Void
    var onEdit: (PulsarNutritionEntry) -> Void
    var onDelete: (PulsarNutritionEntry) -> Void
    var onDuplicate: (PulsarNutritionEntry) -> Void
    var onRepeat: (PulsarNutritionEntry) -> Void
    var onMove: (PulsarNutritionEntry, PulsarNutritionMealMoment) -> Void

    private var totals: PulsarNutritionFacts {
        entries.reduce(.zero) { $0 + $1.nutrition }
    }

    var body: some View {
        PulsarNutritionGlassCard(cornerRadius: 24, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: moment.symbolName)
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(moment.tint)
                        .frame(width: 38, height: 38)
                        .background(moment.tint.opacity(0.13), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(moment.title)
                            .pulsarTextStyle(.cardTitle)
                        Text(entries.isEmpty ? moment.subtitle : "\(PulsarNutritionFormatters.calories(totals.calories)) cal · \(PulsarNutritionFormatters.grams(totals.protein)) protein")
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .pulsarTextStyle(.label)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(NutritionIconButtonStyle(tint: moment.tint, size: 34))
                    .accessibilityLabel("Add food to \(moment.title)")
                }

                if entries.isEmpty {
                    Text(emptyCopy)
                        .pulsarTextStyle(.label)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 10) {
                        ForEach(entries) { entry in
                            NutritionEntryRow(
                                entry: entry,
                                onEdit: { onEdit(entry) },
                                onDelete: { onDelete(entry) },
                                onDuplicate: { onDuplicate(entry) },
                                onRepeat: { onRepeat(entry) },
                                onMove: { destination in onMove(entry, destination) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var emptyCopy: String {
        switch moment {
        case .breakfast: "A breakfast anchor can be as small as yogurt, oats, or any food that helps the day start steady."
        case .lunch: "Add the meal that carried the middle of your day."
        case .dinner: "Close the day with whatever was true, not perfect."
        case .snacks: "Capture small bites, recovery fuel, or anything between meals without turning it into a chore."
        }
    }
}

struct NutritionEntryRow: View {
    var entry: PulsarNutritionEntry
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onDuplicate: () -> Void
    var onRepeat: () -> Void
    var onMove: (PulsarNutritionMealMoment) -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.food.name)
                        .pulsarTextStyle(.label)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(entry.servingText) · \(entry.source.title)")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(PulsarNutritionFormatters.calories(entry.nutrition.calories))
                        .pulsarTextStyle(.label)
                        .monospacedDigit()
                    Text(PulsarNutritionFormatters.grams(entry.nutrition.protein))
                        .pulsarTextStyle(.overline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit", systemImage: "slider.horizontal.3", action: onEdit)
            Button("Repeat today", systemImage: "arrow.clockwise", action: onRepeat)
            Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
            Menu("Move to", systemImage: "arrow.right.arrow.left") {
                ForEach(PulsarNutritionMealMoment.allCases) { moment in
                    Button(moment.title) { onMove(moment) }
                }
            }
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

struct RecoveryAwareTargetsCard: View {
    var dashboard: PulsarNutritionDashboard

    var body: some View {
        PulsarNutritionGlassCard(cornerRadius: 26) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.clockwise.heart.fill")
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(.pink)
                        .frame(width: 40, height: 40)
                        .background(.pink.opacity(0.13), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recovery-aware targets")
                            .pulsarTextStyle(.cardTitle)
                        Text(dashboard.target.rationale)
                            .pulsarTextStyle(.label)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Text("\(dashboard.target.recoveryScore)")
                        .pulsarTextStyle(.sectionHeader)
                        .monospacedDigit()
                        .foregroundStyle(.pink)
                }

                HStack(spacing: 10) {
                    NutritionTargetPill(
                        title: "Fuel",
                        value: "\(PulsarNutritionFormatters.calories(dashboard.target.fuelRange.lowerBound))-\(PulsarNutritionFormatters.calories(dashboard.target.fuelRange.upperBound))",
                        tint: .orange
                    )
                    NutritionTargetPill(
                        title: "Protein",
                        value: "\(PulsarNutritionFormatters.grams(dashboard.target.proteinRange.lowerBound))-\(PulsarNutritionFormatters.grams(dashboard.target.proteinRange.upperBound))",
                        tint: .green
                    )
                    NutritionTargetPill(
                        title: "Water",
                        value: PulsarNutritionFormatters.milliliters(dashboard.target.hydrationTargetMilliliters),
                        tint: .blue
                    )
                }
            }
        }
    }
}

struct NutritionTargetPill: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .pulsarTextStyle(.captionEmphasis)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(title)
                .pulsarTextStyle(.overline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

struct NutritionHydrationCard: View {
    var dashboard: PulsarNutritionDashboard
    var onAddWater: (Double) -> Void
    var onDeleteWater: (PulsarHydrationEntry) -> Void

    var body: some View {
        PulsarNutritionGlassCard(cornerRadius: 26) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 14) {
                    ZStack {
                        NutritionRing(progress: dashboard.hydrationProgress, tint: .blue, lineWidth: 9)
                        Image(systemName: "drop.fill")
                            .pulsarTextStyle(.cardTitle)
                            .foregroundStyle(.blue)
                    }
                    .frame(width: 58, height: 58)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Hydration")
                            .pulsarTextStyle(.cardTitle)
                        Text("\(PulsarNutritionFormatters.milliliters(dashboard.hydrationTotal)) of \(PulsarNutritionFormatters.milliliters(dashboard.target.hydrationTargetMilliliters))")
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    ForEach([250, 350, 500, 750], id: \.self) { amount in
                        Button("+\(amount)ml") {
                            onAddWater(Double(amount))
                        }
                        .pulsarTextStyle(.captionEmphasis)
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }
                }
                .buttonBorderShape(.capsule)

                VStack(spacing: 8) {
                    ForEach(dashboard.hydrationEntries.prefix(4)) { entry in
                        HStack {
                            Text(PulsarNutritionFormatters.milliliters(entry.amountMilliliters))
                                .pulsarTextStyle(.captionEmphasis)
                            Spacer()
                            Text(entry.loggedAt.formatted(date: .omitted, time: .shortened))
                                .pulsarTextStyle(.overline)
                                .foregroundStyle(.secondary)
                            Button(role: .destructive) {
                                onDeleteWater(entry)
                            } label: {
                                Image(systemName: "xmark")
                                    .pulsarTextStyle(.overline)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.06), in: Capsule())
                    }
                }
            }
        }
    }
}

struct NutritionInsightCard: View {
    var insight: PulsarNutritionInsight

    var body: some View {
        PulsarNutritionGlassCard(cornerRadius: 22, padding: 15) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: insight.symbolName)
                    .pulsarTextStyle(.label)
                    .foregroundStyle(insight.kind.tint)
                    .frame(width: 34, height: 34)
                    .background(insight.kind.tint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.title)
                        .pulsarTextStyle(.label)
                    Text(insight.message)
                        .pulsarTextStyle(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct WeeklyNutritionRewindCard: View {
    var dashboard: PulsarNutritionDashboard

    private var averageConsistency: Double {
        guard !dashboard.weeklyPoints.isEmpty else { return 0 }
        return dashboard.weeklyPoints.reduce(0) { $0 + $1.consistency } / Double(dashboard.weeklyPoints.count)
    }

    var body: some View {
        PulsarNutritionGlassCard(cornerRadius: 28) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weekly Nutrition Rewind")
                            .pulsarTextStyle(.cardTitle)
                        Text("Protein, hydration, fiber, and consistency")
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int((averageConsistency * 100).rounded()))%")
                        .pulsarTextStyle(.sectionHeader)
                        .monospacedDigit()
                        .foregroundStyle(.green)
                }

                WeeklyNutritionBars(points: dashboard.weeklyPoints)
                    .frame(height: 118)

                HStack(spacing: 10) {
                    NutritionTargetPill(title: "Protein", value: "Stable", tint: .green)
                    NutritionTargetPill(title: "Hydration", value: "Building", tint: .blue)
                    NutritionTargetPill(title: "Fiber", value: "Gentle", tint: .mint)
                }
            }
        }
    }
}

struct WeeklyNutritionBars: View {
    var points: [PulsarNutritionWeekPoint]

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(points) { point in
                VStack(spacing: 7) {
                    GeometryReader { proxy in
                        VStack {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.green.opacity(0.72), .blue.opacity(0.42)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(height: max(8, proxy.size.height * point.consistency))
                        }
                    }
                    Text(point.date.formatted(.dateTime.weekday(.narrow)))
                        .pulsarTextStyle(.overline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct EatingWindowCard: View {
    var window: PulsarEatingWindow
    var entries: [PulsarNutritionEntry]
    var onToggle: () -> Void

    private var firstEntryHour: Int? {
        entries.map { Calendar.current.component(.hour, from: $0.loggedAt) }.min()
    }

    private var lastEntryHour: Int? {
        entries.map { Calendar.current.component(.hour, from: $0.loggedAt) }.max()
    }

    var body: some View {
        PulsarNutritionGlassCard(cornerRadius: 26) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Eating rhythm")
                            .pulsarTextStyle(.cardTitle)
                        Text(window.isEnabled ? rhythmCopy : "Hidden for now")
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: onToggle) {
                        Image(systemName: window.isEnabled ? "eye.fill" : "eye.slash.fill")
                            .pulsarTextStyle(.label)
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(NutritionIconButtonStyle(tint: .purple, size: 38))
                    .accessibilityLabel(window.isEnabled ? "Hide eating rhythm" : "Show eating rhythm")
                }

                if window.isEnabled {
                    EatingWindowTimeline(
                        startHour: window.startHour,
                        endHour: window.endHour,
                        firstEntryHour: firstEntryHour,
                        lastEntryHour: lastEntryHour
                    )
                    .frame(height: 46)
                }
            }
        }
    }

    private var rhythmCopy: String {
        guard let firstEntryHour, let lastEntryHour else {
            return "Optional context for when food naturally happened today."
        }
        return "Today spans roughly \(hourText(firstEntryHour)) to \(hourText(lastEntryHour)). No pressure, just rhythm."
    }

    private func hourText(_ hour: Int) -> String {
        DateComponents(calendar: .current, hour: hour).date?.formatted(date: .omitted, time: .shortened) ?? "\(hour):00"
    }
}

struct EatingWindowTimeline: View {
    var startHour: Int
    var endHour: Int
    var firstEntryHour: Int?
    var lastEntryHour: Int?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let plannedStart = xPosition(for: startHour, width: width)
            let plannedEnd = xPosition(for: endHour, width: width)
            let actualStart = firstEntryHour.map { xPosition(for: $0, width: width) }
            let actualEnd = lastEntryHour.map { xPosition(for: $0, width: width) }

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.08))
                    .frame(height: 10)
                    .position(x: width / 2, y: 18)

                Capsule()
                    .fill(.purple.opacity(0.24))
                    .frame(width: max(12, plannedEnd - plannedStart), height: 10)
                    .position(x: plannedStart + max(12, plannedEnd - plannedStart) / 2, y: 18)

                if let actualStart, let actualEnd {
                    Capsule()
                        .fill(.purple.opacity(0.72))
                        .frame(width: max(10, actualEnd - actualStart), height: 10)
                        .position(x: actualStart + max(10, actualEnd - actualStart) / 2, y: 18)
                }

                HStack {
                    Text("6 AM")
                    Spacer()
                    Text("Noon")
                    Spacer()
                    Text("Midnight")
                }
                .pulsarTextStyle(.overline)
                .foregroundStyle(.secondary)
                .offset(y: 30)
            }
        }
    }

    private func xPosition(for hour: Int, width: CGFloat) -> CGFloat {
        let clamped = min(max(Double(hour), 6), 24)
        return width * ((clamped - 6) / 18)
    }
}

struct NutritionActionButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [tint.opacity(configuration.isPressed ? 0.72 : 0.92), tint.opacity(0.68)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

struct NutritionIconButtonStyle: ButtonStyle {
    var tint: Color
    var size: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(configuration.isPressed ? 0.18 : 0.12), in: RoundedRectangle(cornerRadius: size * 0.35, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.35, style: .continuous)
                    .stroke(tint.opacity(0.20), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

struct NutritionIconTextButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .background(tint.opacity(configuration.isPressed ? 0.16 : 0.10), in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.20), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

extension PulsarNutritionMealMoment {
    var tint: Color {
        switch self {
        case .breakfast: .orange
        case .lunch: .yellow
        case .dinner: .indigo
        case .snacks: .mint
        }
    }
}

extension PulsarMealCategory {
    var tint: Color { palette.color }
}

private extension PulsarNutritionInsight.Kind {
    var tint: Color {
        switch self {
        case .coachBrief: .green
        case .trend: .blue
        case .timing: .purple
        case .recovery: .pink
        case .weekly: .orange
        }
    }
}
