//
//  WeeklyMuscleMatrixView.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct WeeklyMuscleMatrixCard: View {
    var viewModel: MuscleMatrixViewModel

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedItem: MuscleMatrixSelection?
    @State private var hasAppeared = false

    var body: some View {
        WeeklyMatrixGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                header
                MuscleMatrixSummaryStrip(summary: viewModel.weeklySummary)
                MuscleMatrixGrid(
                    viewModel: viewModel,
                    hasAppeared: hasAppeared,
                    onSelectCell: selectCell,
                    onSelectRow: selectRow
                )
                MuscleMatrixLegend()
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.56, dampingFraction: 0.86).delay(0.08)) {
                hasAppeared = true
            }
        }
        .sheet(item: $selectedItem) { item in
            MuscleMatrixDetailSheet(selection: item)
                .presentationDetents([.height(300), .medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Weekly Muscle Matrix")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text("Training distribution by day")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            statusBadge
        }
        .accessibilityElement(children: .combine)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.week.isCurrentWeek ? Color.green : PulsarTheme.fitnessTertiaryText(for: colorScheme).opacity(0.60))
                .frame(width: 6, height: 6)
                .shadow(color: (viewModel.week.isCurrentWeek ? Color.green : .clear).opacity(0.48), radius: 7)

            Text(viewModel.week.isCurrentWeek ? "Active" : "Archived")
                .pulsarTextStyle(.overline)
                .lineLimit(1)
        }
        .foregroundStyle(viewModel.week.isCurrentWeek ? Color.green : PulsarTheme.fitnessSecondaryText(for: colorScheme))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(statusBackground, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(statusBorder, lineWidth: 1)
        }
    }

    private func selectCell(_ cell: MuscleMatrixCell) {
        impact()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            selectedItem = .cell(cell)
        }
    }

    private func selectRow(_ summary: MuscleMatrixRowSummary) {
        impact()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
            selectedItem = .row(summary)
        }
    }

    private func impact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private var statusBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.11), Color.white.opacity(0.04), Color.green.opacity(viewModel.week.isCurrentWeek ? 0.10 : 0)]
                : [Color.white.opacity(0.84), Color(red: 0.95, green: 0.98, blue: 1.00).opacity(0.62), Color.green.opacity(viewModel.week.isCurrentWeek ? 0.06 : 0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var statusBorder: Color {
        viewModel.week.isCurrentWeek
            ? Color.green.opacity(colorScheme == .dark ? 0.30 : 0.22)
            : .white.opacity(colorScheme == .dark ? 0.12 : 0.68)
    }

}

private struct WeeklyMatrixGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 32
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(12)
            .modifier(
                FitnessGlassSurfaceModifier(
                    cornerRadius: cornerRadius,
                    tint: Color(red: 0.72, green: 0.82, blue: 0.92),
                    borderOpacity: 0.94
                )
            )
    }
}

private struct MuscleMatrixSummaryStrip: View {
    var summary: WeeklyMuscleSummary
    @Environment(\.colorScheme) private var colorScheme

    private var items: [(symbol: String, value: String, label: String)] {
        [
            ("figure.strengthtraining.traditional", "\(summary.totalSessions)", summary.totalSessions == 1 ? "Activity" : "Activities"),
            ("checkmark.circle.fill", "\(summary.totalSets)", "Sets logged"),
            ("scope", focusPrimary, focusSecondary),
            ("dial.low.fill", "\(summary.balanceScore)%", "Balance")
        ]
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                metricPill(item)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 1)
        .frame(height: 54)
    }

    private func metricPill(_ item: (symbol: String, value: String, label: String)) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: item.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(red: 0.62, green: 0.80, blue: 1.00))
                    .frame(width: 17, height: 17)
                    .background(.white.opacity(colorScheme == .dark ? 0.060 : 0.64), in: Circle())

                Text(item.value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }

            Text(item.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .allowsTightening(true)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(metricBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.085 : 0.64), lineWidth: 1)
        }
    }

    private var metricBackground: Color {
        colorScheme == .dark
            ? .white.opacity(0.045)
            : .white.opacity(0.66)
    }

    private var focusPrimary: String {
        let words = summary.focusArea.split(separator: " ", maxSplits: 1).map(String.init)
        return words.first ?? summary.focusArea
    }

    private var focusSecondary: String {
        let words = summary.focusArea.split(separator: " ", maxSplits: 1).map(String.init)
        guard words.count > 1 else { return "Focus" }
        return words[1].prefix(1).uppercased() + String(words[1].dropFirst())
    }
}

private struct MuscleMatrixGrid: View {
    var viewModel: MuscleMatrixViewModel
    var hasAppeared: Bool
    var onSelectCell: (MuscleMatrixCell) -> Void
    var onSelectRow: (MuscleMatrixRowSummary) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let inset: CGFloat = 8
            let contentWidth = max(0, proxy.size.width - inset * 2)
            let labelWidth = min(max(contentWidth * 0.30, 94), 116)
            let gap: CGFloat = contentWidth < 310 ? 2 : 3
            let cellWidth = floor(max(15, (contentWidth - labelWidth - gap * 7) / 7))
            let usedWidth = labelWidth + cellWidth * 7 + gap * 7

            VStack(spacing: 2) {
                MuscleMatrixHeaderRow(
                    days: viewModel.days,
                    currentDay: viewModel.currentDay,
                    labelWidth: labelWidth,
                    cellWidth: cellWidth,
                    gap: gap
                )

                ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { rowIndex, row in
                    MuscleMatrixRow(
                        viewModel: viewModel,
                        muscleGroup: row.muscleGroup,
                        rowIndex: rowIndex,
                        labelWidth: labelWidth,
                        cellWidth: cellWidth,
                        gap: gap,
                        hasAppeared: hasAppeared,
                        onSelectCell: onSelectCell,
                        onSelectRow: onSelectRow
                    )
                }
            }
            .frame(width: usedWidth, alignment: .center)
            .padding(.horizontal, inset)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(gridBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(colorScheme == .dark ? 0.095 : 0.66), lineWidth: 1)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 18, y: 10)
        }
        .frame(height: 258)
    }

    private var gridBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color.white.opacity(0.050),
                    Color.black.opacity(0.16),
                    Color(red: 0.06, green: 0.09, blue: 0.13).opacity(0.44)
                ]
                : [
                    Color.white.opacity(0.82),
                    Color(red: 0.94, green: 0.97, blue: 1.00).opacity(0.74),
                    Color(red: 0.70, green: 0.82, blue: 1.00).opacity(0.12)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct MuscleMatrixHeaderRow: View {
    var days: [TrainingDay]
    var currentDay: TrainingDay?
    var labelWidth: CGFloat
    var cellWidth: CGFloat
    var gap: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: gap) {
            Text("Muscle Group")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PulsarTheme.fitnessTertiaryText(for: colorScheme))
                .frame(width: labelWidth, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            ForEach(days) { day in
                Text(cellWidth < 26 ? String(day.shortTitle.prefix(1)) : day.shortTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(currentDay == day ? Color.green : PulsarTheme.fitnessSecondaryText(for: colorScheme))
                    .frame(width: cellWidth)
                    .padding(.vertical, 2)
                    .background {
                        if currentDay == day {
                            Capsule(style: .continuous)
                                .fill(PulsarTheme.matrixSelectedDayBackground(for: colorScheme))
                                .overlay {
                                    Capsule(style: .continuous)
                                        .stroke(PulsarTheme.matrixSelectedDayBorder(for: colorScheme).opacity(0.78), lineWidth: 1)
                                }
                        }
                    }
            }
        }
    }
}

private struct MuscleMatrixRow: View {
    var viewModel: MuscleMatrixViewModel
    var muscleGroup: MuscleMatrixGroup
    var rowIndex: Int
    var labelWidth: CGFloat
    var cellWidth: CGFloat
    var gap: CGFloat
    var hasAppeared: Bool
    var onSelectCell: (MuscleMatrixCell) -> Void
    var onSelectRow: (MuscleMatrixRowSummary) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: gap) {
            Button {
                onSelectRow(viewModel.rowSummary(for: muscleGroup))
            } label: {
                HStack(spacing: 7) {
                    rowSymbol

                    Text(muscleGroup.compactName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .frame(width: labelWidth, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            ForEach(Array(viewModel.days.enumerated()), id: \.element) { columnIndex, day in
                let cell = viewModel.cell(for: muscleGroup, day: day)

                Button {
                    onSelectCell(cell)
                } label: {
                    MuscleMatrixCellView(
                        cell: cell,
                        isCurrentDay: viewModel.currentDay == day,
                        availableWidth: cellWidth,
                        delay: Double(rowIndex * 7 + columnIndex) * 0.012,
                        hasAppeared: hasAppeared
                    )
                    .frame(width: cellWidth, height: 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(muscleGroup.displayName), \(day.fullTitle), \(cell.intensity.title)")
            }
        }
    }

    @ViewBuilder
    private var rowSymbol: some View {
        if muscleGroup == .cardio {
            Image(systemName: muscleGroup.symbolName)
                .pulsarTextStyle(.overline)
                .foregroundStyle(muscleGroup.accent)
                .frame(width: 11, height: 11)
                .shadow(color: muscleGroup.accent.opacity(0.22), radius: 5)
        } else {
            Circle()
                .fill(muscleGroup.accent)
                .frame(width: 6, height: 6)
                .shadow(color: muscleGroup.accent.opacity(0.34), radius: 5)
        }
    }
}

private struct MuscleMatrixCellView: View {
    var cell: MuscleMatrixCell
    var isCurrentDay: Bool
    var availableWidth: CGFloat
    var delay: Double
    var hasAppeared: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(cellBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(cellBorder, lineWidth: 1)
                }

            RoundedRectangle(cornerRadius: dotCornerRadius, style: .continuous)
                .fill(fillColor)
                .frame(width: dotSize, height: dotSize)
                .overlay {
                    RoundedRectangle(cornerRadius: dotCornerRadius, style: .continuous)
                        .stroke(strokeColor, lineWidth: cell.intensity == .none ? 0.7 : 1.0)
                }
                .shadow(color: cell.muscleGroup.accent.opacity(glowOpacity), radius: min(cell.intensity.glowRadius, 8))
                .scaleEffect(hasAppeared ? 1 : 0.42)
                .opacity(hasAppeared ? 1 : 0)
                .animation(.spring(response: 0.42, dampingFraction: 0.72).delay(delay), value: hasAppeared)
        }
    }

    private var cellBackground: Color {
        if isCurrentDay {
            return PulsarTheme.matrixSelectedDayBackground(for: colorScheme).opacity(colorScheme == .dark ? 0.84 : 0.72)
        }
        return colorScheme == .dark
            ? .white.opacity(0.030)
            : .white.opacity(0.44)
    }

    private var cellBorder: Color {
        if isCurrentDay {
            return PulsarTheme.matrixSelectedDayBorder(for: colorScheme).opacity(0.74)
        }
        return colorScheme == .dark
            ? .white.opacity(0.050)
            : Color(red: 0.42, green: 0.50, blue: 0.62).opacity(0.12)
    }

    private var fillColor: Color {
        if cell.intensity == .none {
            return PulsarTheme.matrixInactiveDot(for: colorScheme)
        }
        return cell.muscleGroup.accent.opacity(min(cell.intensity.opacity * 0.86, 0.92))
    }

    private var dotBaseSize: CGFloat {
        cell.muscleGroup == .cardio ? 16 : 15
    }

    private var dotSize: CGFloat {
        min(dotBaseSize * cell.intensity.dotScale, max(7, availableWidth - 9))
    }

    private var dotCornerRadius: CGFloat {
        max(3.5, dotSize * 0.34)
    }

    private var strokeColor: Color {
        if cell.intensity == .none {
            return colorScheme == .dark ? .white.opacity(0.10) : Color(red: 0.40, green: 0.46, blue: 0.56).opacity(0.20)
        }
        return colorScheme == .dark ? .white.opacity(strokeOpacity) : cell.muscleGroup.accent.opacity(0.54)
    }

    private var strokeOpacity: Double {
        switch cell.intensity {
        case .none: 0.08
        case .light: 0.18
        case .medium: 0.26
        case .high: 0.36
        }
    }

    private var glowOpacity: Double {
        switch cell.intensity {
        case .none: 0
        case .light: 0.07
        case .medium: 0.14
        case .high: 0.24
        }
    }
}

private struct MuscleMatrixLegend: View {
    @Environment(\.colorScheme) private var colorScheme

    private let items: [(String, MuscleIntensity)] = [
        ("Low", .light),
        ("Medium", .medium),
        ("High", .high)
    ]

    var body: some View {
        HStack(spacing: 9) {
            Text("Intensity")
                .pulsarTextStyle(.overline)
                .foregroundStyle(PulsarTheme.fitnessTertiaryText(for: colorScheme))

            ForEach(items, id: \.0) { item in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(red: 0.58, green: 0.77, blue: 1.0).opacity(min(item.1.opacity * 0.78, 0.78)))
                        .frame(width: 10 * item.1.dotScale, height: 10 * item.1.dotScale)
                    Text(item.0)
                        .pulsarTextStyle(.overline)
                        .foregroundStyle(PulsarTheme.fitnessTertiaryText(for: colorScheme))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .opacity(0.82)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Intensity legend, low, medium, high")
    }
}

private struct MuscleMatrixInsightCard: View {
    var summary: WeeklyMuscleSummary
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle()
                .fill(.white.opacity(colorScheme == .dark ? 0.08 : 0.52))
                .frame(height: 1)

            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.72, green: 0.66, blue: 1.0).opacity(colorScheme == .dark ? 0.14 : 0.12))
                        .frame(width: 32, height: 32)

                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 0.72, green: 0.66, blue: 1.0).opacity(0.92))
                }
                .padding(.top, 1)

                VStack(alignment: .leading, spacing: 5) {
                    Text(summary.insightTitle)
                        .pulsarTextStyle(.label)
                        .foregroundStyle(PulsarTheme.fitnessPrimaryText(for: colorScheme))

                    Text(summary.insight)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(PulsarTheme.fitnessSecondaryText(for: colorScheme))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !insightChips.isEmpty {
                        MuscleMatrixFlowLayout(spacing: 6, rowSpacing: 6) {
                            ForEach(Array(insightChips.enumerated()), id: \.offset) { _, chip in
                                HStack(spacing: 4) {
                                    Image(systemName: chip.symbol)
                                        .pulsarTextStyle(.overline)
                                    Text(chip.label)
                                        .pulsarTextStyle(.overline)
                                }
                                .foregroundStyle(chip.color.opacity(0.90))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(chip.color.opacity(colorScheme == .dark ? 0.090 : 0.075), in: Capsule(style: .continuous))
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var insightChips: [(symbol: String, label: String, color: Color)] {
        var chips: [(String, String, Color)] = []
        if let top = summary.topAreas.first {
            chips.append(("arrow.up.right", "Top \(top)", Color(red: 0.36, green: 0.82, blue: 1.0)))
        }
        if let need = summary.undertrainedAreas.first {
            chips.append(("target", "Needs \(need)", Color(red: 1.0, green: 0.72, blue: 0.32)))
        }
        return chips
    }
}

private struct MuscleMatrixDetailSheet: View {
    var selection: MuscleMatrixSelection

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            capsuleHandle
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.020, green: 0.026, blue: 0.040),
                    Color(red: 0.060, green: 0.050, blue: 0.105),
                    Color.black.opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var capsuleHandle: some View {
        Capsule(style: .continuous)
            .fill(.white.opacity(0.20))
            .frame(width: 44, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 2)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .cell(let cell):
            detailHeader(
                title: cell.muscleGroup.displayName,
                subtitle: "\(cell.day.fullTitle) · \(cell.intensity.title)",
                color: cell.muscleGroup.accent,
                symbol: cell.muscleGroup == .cardio ? cell.muscleGroup.symbolName : "square.grid.3x3.fill"
            )
            detailMetrics(cellMetrics(for: cell))
            exerciseList(cell.exercises)

        case .row(let summary):
            detailHeader(
                title: summary.muscleGroup.displayName,
                subtitle: summary.muscleGroup == .cardio ? "Weekly cardio summary" : "Weekly muscle summary",
                color: summary.muscleGroup.accent,
                symbol: summary.muscleGroup == .cardio ? summary.muscleGroup.symbolName : "chart.bar.fill"
            )
            detailMetrics(rowMetrics(for: summary))
            exerciseList(summary.exercises)
        }
    }

    private func cellMetrics(for cell: MuscleMatrixCell) -> [(String, String)] {
        if cell.muscleGroup == .cardio {
            return [
                ("Minutes", cell.minutes.map(String.init) ?? "0"),
                ("Sessions", cell.exercises.isEmpty ? "0" : "\(cell.exercises.count)"),
                ("Intensity", cell.intensity.title)
            ]
        }

        return [
            ("Sets", "\(cell.sets)"),
            ("Exercises", cell.exercises.isEmpty ? "None" : "\(cell.exercises.count)"),
            ("Minutes", cell.minutes.map(String.init) ?? "—")
        ]
    }

    private func rowMetrics(for summary: MuscleMatrixRowSummary) -> [(String, String)] {
        if summary.muscleGroup == .cardio {
            return [
                ("Total minutes", "\(summary.totalMinutes)"),
                ("Days active", "\(summary.daysTrained)"),
                ("Highest", summary.highestIntensityDay?.shortTitle ?? "—"),
                ("Last", summary.lastTrainedDay?.shortTitle ?? "—")
            ]
        }

        return [
            ("Total sets", "\(summary.totalSets)"),
            ("Days trained", "\(summary.daysTrained)"),
            ("Highest", summary.highestIntensityDay?.shortTitle ?? "—"),
            ("Last", summary.lastTrainedDay?.shortTitle ?? "—")
        ]
    }

    private func detailHeader(title: String, subtitle: String, color: Color, symbol: String) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(color.opacity(0.22))
                    .frame(width: 52, height: 52)
                    .shadow(color: color.opacity(0.34), radius: 14)

                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .pulsarTextStyle(.sectionHeader)
                    .foregroundStyle(.white.opacity(0.96))

                Text(subtitle)
                    .pulsarTextStyle(.label)
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
    }

    private func detailMetrics(_ metrics: [(String, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(metrics, id: \.0) { metric in
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.0)
                        .pulsarTextStyle(.overline)
                        .foregroundStyle(.white.opacity(0.42))
                    Text(metric.1)
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(.white.opacity(0.90))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.070), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.09), lineWidth: 1)
                }
            }
        }
    }

    private func exerciseList(_ exercises: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exercises")
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(.white.opacity(0.46))

            if exercises.isEmpty {
                Text("No exercises logged for this selection.")
                    .pulsarTextStyle(.label)
                    .foregroundStyle(.white.opacity(0.58))
            } else {
                MuscleMatrixFlowLayout(spacing: 7, rowSpacing: 7) {
                    ForEach(exercises, id: \.self) { exercise in
                        Text(exercise)
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(.white.opacity(0.78))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.white.opacity(0.075), in: Capsule(style: .continuous))
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(.white.opacity(0.10), lineWidth: 1)
                            }
                    }
                }
            }
        }
    }
}

private struct MuscleMatrixFlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = rows(proposal: proposal, subviews: subviews)
        let height = rows.reduce(CGFloat.zero) { partial, row in
            partial + row.height
        } + CGFloat(max(rows.count - 1, 0)) * rowSpacing
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = rows(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(proposal: ProposedViewSize, subviews: Subviews) -> [(indices: [Subviews.Index], width: CGFloat, height: CGFloat)] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [(indices: [Subviews.Index], width: CGFloat, height: CGFloat)] = []
        var current: [Subviews.Index] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.isEmpty ? size.width : currentWidth + spacing + size.width
            if proposedWidth > maxWidth, !current.isEmpty {
                rows.append((current, currentWidth, currentHeight))
                current = [index]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                current.append(index)
                currentWidth = proposedWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !current.isEmpty {
            rows.append((current, currentWidth, currentHeight))
        }
        return rows
    }
}

private enum MuscleMatrixPreviewData {
    static var viewModel: MuscleMatrixViewModel {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let week = FitnessWeekCalculator.getWeekPeriod(for: now, calendar: calendar, now: now, hasWorkout: true)
        let activities = [
            WeeklyActivity(
                id: "preview-gym",
                workoutUUID: nil,
                workoutType: "Gym",
                displayName: "Push Day",
                category: .gym,
                startDate: now.addingTimeInterval(-86_400),
                endDate: now.addingTimeInterval(-82_800),
                duration: 3_600,
                calories: nil,
                distanceMeters: nil,
                averageHeartRate: nil,
                maxHeartRate: nil,
                source: .localGym,
                sourceName: "Preview",
                completedSets: 12,
                totalSets: 14,
                mainMuscleGroups: ["Chest", "Shoulders"],
                muscleLoadByMatrixGroup: [.chest: 6, .shoulders: 4, .triceps: 3],
                muscleExercisesByMatrixGroup: [
                    .chest: ["Bench Press"],
                    .shoulders: ["Shoulder Press"],
                    .triceps: ["Rope Pushdown"]
                ]
            ),
            WeeklyActivity(
                id: "preview-run",
                workoutUUID: nil,
                workoutType: "Running",
                displayName: "Running",
                category: .running,
                startDate: now.addingTimeInterval(-172_800),
                endDate: now.addingTimeInterval(-170_400),
                duration: 2_400,
                calories: 280,
                distanceMeters: 5_100,
                averageHeartRate: 142,
                maxHeartRate: 168,
                source: .healthKit,
                sourceName: "Preview"
            )
        ]
        return MuscleMatrixViewModel(week: week, activities: activities, calendar: calendar, now: now)
    }
}

private struct WeeklyMuscleMatrixCardPreview: PreviewProvider {
    static var previews: some View {
        Group {
            WeeklyMuscleMatrixCard(viewModel: MuscleMatrixPreviewData.viewModel)
                .padding()
                .background(Color(.systemGroupedBackground))
                .preferredColorScheme(.light)
                .previewDisplayName("Weekly Matrix Light")

            WeeklyMuscleMatrixCard(viewModel: MuscleMatrixPreviewData.viewModel)
                .padding()
                .background(Color(red: 0.02, green: 0.03, blue: 0.05))
                .preferredColorScheme(.dark)
                .previewDisplayName("Weekly Matrix Dark")
        }
    }
}
