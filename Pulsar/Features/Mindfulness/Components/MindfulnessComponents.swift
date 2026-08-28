//
//  MindfulnessComponents.swift
//  Pulsar
//

import Foundation
import SwiftUI

enum MindfulnessVisualStyle {
    static let calmBlue = Color(red: 0.38, green: 0.72, blue: 1.00)
    static let mint = Color(red: 0.38, green: 0.88, blue: 0.72)
    static let lavender = Color(red: 0.70, green: 0.60, blue: 0.98)
    static let softGold = Color(red: 0.94, green: 0.73, blue: 0.38)
    static let softRose = Color(red: 0.96, green: 0.56, blue: 0.60)
    static let neonViolet = Color(red: 0.78, green: 0.30, blue: 1.00)
    static let neonBlue = Color(red: 0.24, green: 0.48, blue: 1.00)
    static let neonAmber = Color(red: 1.00, green: 0.70, blue: 0.12)
    static let neonCyan = Color(red: 0.10, green: 0.72, blue: 1.00)
    static let neonMint = Color(red: 0.16, green: 1.00, blue: 0.58)
    static let neonFlame = Color(red: 1.00, green: 0.46, blue: 0.08)
    static let secondaryText = Color.white.opacity(0.70)
    static let tertiaryText = Color.white.opacity(0.52)

    static func moodColor(for wellnessAverage: Double?) -> Color {
        guard let wellnessAverage else { return Color.white.opacity(0.22) }
        return switch wellnessAverage {
        case 0.74...: mint
        case 0.58..<0.74: calmBlue
        case 0.42..<0.58: softGold
        default: lavender
        }
    }
}

struct PulsarMindfulnessGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 28
    var contentPadding: CGFloat = 18
    var tint: Color?
    @ViewBuilder var content: Content

    init(
        cornerRadius: CGFloat = 28,
        contentPadding: CGFloat = 18,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.contentPadding = contentPadding
        self.tint = tint
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        PulsarGlassCard(
            cornerRadius: cornerRadius,
            contentPadding: contentPadding,
            tint: tint
        ) {
            content
        }
    }
}

struct MindfulnessPageTitleHeader: View {
    var body: some View {
        PulsarTabHeader(
            systemImage: "camera.macro",
            title: "Mindfulness",
            subtitle: "Understand your mind.\nElevate your day.",
            primaryText: .white.opacity(0.96),
            secondaryText: .white.opacity(0.62)
        )
    }
}

struct MindfulnessScenicBackground: View {
    var body: some View {
        Image("MindfulnessBackground")
            .resizable()
            .scaledToFill()
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [.black.opacity(0.48), .black.opacity(0.13), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 280)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.22), .black.opacity(0.66)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 430)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

private enum MindfulnessMoodLevel: Int, CaseIterable, Identifiable {
    case veryLow
    case low
    case neutral
    case good
    case great

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .veryLow: "Very Low"
        case .low: "Low"
        case .neutral: "Neutral"
        case .good: "Good"
        case .great: "Great"
        }
    }

    var valence: Double {
        Double(rawValue - 2) / 2
    }

    var tint: Color {
        switch self {
        case .veryLow: MindfulnessVisualStyle.neonViolet
        case .low: MindfulnessVisualStyle.neonBlue
        case .neutral: MindfulnessVisualStyle.neonAmber
        case .good: MindfulnessVisualStyle.neonCyan
        case .great: MindfulnessVisualStyle.neonMint
        }
    }

    var mouthControlY: CGFloat {
        switch self {
        case .veryLow: 0.38
        case .low: 0.46
        case .neutral: 0.60
        case .good: 0.73
        case .great: 0.82
        }
    }

    static func nearest(to valence: Double) -> MindfulnessMoodLevel {
        allCases.min {
            abs($0.valence - valence) < abs($1.valence - valence)
        } ?? .neutral
    }
}

struct MindfulnessHistorySheet: View {
    var entries: [PulsarDailyJournalEntry]
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date

    @Environment(\.dismiss) private var dismiss
    @State private var fullDayInsightsEntry: PulsarDailyJournalEntry?

    var body: some View {
        ZStack {
            PulsarFitnessMonochromeBackground()

            ViewThatFits(in: .vertical) {
                PulsarGlassEffectGroup(spacing: 8) {
                    MindfulnessHistoryContent(
                        entries: entries,
                        displayedMonth: $displayedMonth,
                        selectedDate: $selectedDate,
                        onClose: dismiss.callAsFunction,
                        onViewFullDayInsights: presentFullDayInsights
                    )
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 10)
                .fixedSize(horizontal: false, vertical: true)

                ScrollView {
                    PulsarGlassEffectGroup(spacing: 8) {
                        MindfulnessHistoryContent(
                            entries: entries,
                            displayedMonth: $displayedMonth,
                            selectedDate: $selectedDate,
                            onClose: dismiss.callAsFunction,
                            onViewFullDayInsights: presentFullDayInsights
                        )
                    }
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .scrollContentBackground(.visible)
                .defaultScrollAnchor(.top)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .pulsarFitnessMonochromeAppearance()
        .sheet(item: $fullDayInsightsEntry) { entry in
            MindfulnessFullDayInsightsView(entry: entry)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.clear)
                .presentationCornerRadius(38)
        }
    }

    private func presentFullDayInsights(_ entry: PulsarDailyJournalEntry) {
        fullDayInsightsEntry = entry
    }
}

struct MindfulnessMoodHistoryCard: View {
    var entries: [PulsarDailyJournalEntry]
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        PulsarMindfulnessGlassCard(
            cornerRadius: 32,
            contentPadding: 16,
            tint: MindfulnessVisualStyle.calmBlue.opacity(0.16)
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        historyTitle
                        Spacer(minLength: 8)
                        historyControls
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        historyTitle
                        historyControls
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                calendarGrid

                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(height: 0.75)

                monthlyInsight
            }
        }
    }

    private var historyTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mood History")
                .font(.headline)
                .foregroundStyle(.white)
            Text(monthStart, format: .dateTime.month(.wide).year())
                .pulsarTextStyle(.caption)
                .foregroundStyle(MindfulnessVisualStyle.secondaryText)
        }
    }

    private var historyControls: some View {
        PulsarGlassEffectGroup(spacing: 6) {
            HStack(spacing: 6) {
                Button("Previous month", systemImage: "chevron.left") {
                    moveMonth(by: -1)
                }
                .labelStyle(.iconOnly)
                .frame(width: 30, height: 30)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())

                Button("Next month", systemImage: "chevron.right") {
                    moveMonth(by: 1)
                }
                .labelStyle(.iconOnly)
                .frame(width: 30, height: 30)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())

                Button("Today") {
                    selectToday()
                }
                .pulsarTextStyle(.captionEmphasis)
                .frame(minHeight: 36)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityHint("Shows the current month and selects today")
            }
            .tint(MindfulnessVisualStyle.calmBlue.opacity(0.12))
            .foregroundStyle(.white)
        }
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: calendarColumns, spacing: 2) {
            ForEach(weekdaySymbols.indices, id: \.self) { index in
                Text(weekdaySymbols[index].short)
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(MindfulnessVisualStyle.tertiaryText)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .accessibilityLabel(weekdaySymbols[index].full)
            }

            ForEach(calendarDays) { day in
                let entry = entriesByDay[calendar.startOfDay(for: day.date)]
                MindfulnessCalendarDayButton(
                    date: day.date,
                    isInDisplayedMonth: day.isInDisplayedMonth,
                    isSelected: calendar.isDate(day.date, inSameDayAs: selectedDate),
                    entry: entry
                ) {
                    select(day)
                }
            }
        }
    }

    private var monthlyInsight: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))

        return layout {
            VStack(alignment: .leading, spacing: 5) {
                Label("Monthly Insight", systemImage: "sparkles")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Text(monthlyInsightText)
                    .pulsarTextStyle(.caption)
                    .foregroundStyle(MindfulnessVisualStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            MindfulnessAverageRing(average: monthlyAverage)
                .frame(
                    maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
                    alignment: .trailing
                )
        }
        .padding(.vertical, 2)
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 36), spacing: 0), count: 7)
    }

    private var weekdaySymbols: [(short: String, full: String)] {
        [
            ("M", "Monday"),
            ("T", "Tuesday"),
            ("W", "Wednesday"),
            ("T", "Thursday"),
            ("F", "Friday"),
            ("S", "Saturday"),
            ("S", "Sunday")
        ]
    }

    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
    }

    private var calendarDays: [MindfulnessCalendarDay] {
        let weekday = calendar.component(.weekday, from: monthStart)
        let daysBeforeMonday = (weekday + 5) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -daysBeforeMonday, to: monthStart) else {
            return []
        }

        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 31
        let requiredCells = daysBeforeMonday + daysInMonth
        let cellCount = requiredCells <= 35 ? 35 : 42

        return (0..<cellCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            return MindfulnessCalendarDay(
                date: date,
                isInDisplayedMonth: calendar.isDate(date, equalTo: monthStart, toGranularity: .month)
            )
        }
    }

    private var entriesByDay: [Date: PulsarDailyJournalEntry] {
        entries.reduce(into: [:]) { result, entry in
            let day = calendar.startOfDay(for: entry.date)
            if result[day] == nil {
                result[day] = entry
            }
        }
    }

    private var monthlyEntries: [PulsarDailyJournalEntry] {
        entries.filter { calendar.isDate($0.date, equalTo: monthStart, toGranularity: .month) }
    }

    private var monthlyAverage: Double? {
        guard !monthlyEntries.isEmpty else { return nil }
        return monthlyEntries.reduce(0) { $0 + $1.wellnessAverage } / Double(monthlyEntries.count)
    }

    private var monthlyInsightText: String {
        guard let monthlyAverage else {
            return "Log a few days this month to reveal a steadier pattern."
        }

        switch monthlyAverage {
        case 0.72...:
            return "Your days were mostly calm, connected, and balanced this month."
        case 0.56..<0.72:
            return "Your month held a steady balance with a few softer days."
        case 0.40..<0.56:
            return "Your signals were mixed this month. Small resets may help create more ease."
        default:
            return "This month carried more strain. Gentle recovery and connection may help."
        }
    }

    private func moveMonth(by value: Int) {
        guard let nextMonth = calendar.date(byAdding: .month, value: value, to: monthStart) else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) {
            displayedMonth = nextMonth
        }
    }

    private func selectToday() {
        let today = Date()
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) {
            selectedDate = today
            displayedMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
        }
    }

    private func select(_ day: MindfulnessCalendarDay) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.20)) {
            selectedDate = day.date
            if !day.isInDisplayedMonth {
                displayedMonth = calendar.dateInterval(of: .month, for: day.date)?.start ?? day.date
            }
        }
    }
}

private struct MindfulnessCalendarDay: Identifiable {
    var date: Date
    var isInDisplayedMonth: Bool

    var id: Date { date }
}

private struct MindfulnessCalendarDayButton: View {
    var date: Date
    var isInDisplayedMonth: Bool
    var isSelected: Bool
    var entry: PulsarDailyJournalEntry?
    var action: () -> Void

    @ScaledMetric(relativeTo: .callout) private var dayCircleSize: CGFloat = 30

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(
                            isSelected
                                ? RadialGradient(
                                    colors: [selectionTint.opacity(0.32), selectionTint.opacity(0.12)],
                                    center: .topLeading,
                                    startRadius: 0,
                                    endRadius: 34
                                )
                                : RadialGradient(
                                    colors: [.clear, .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 1
                                )
                        )

                    if isSelected {
                        Circle()
                            .strokeBorder(selectionTint.opacity(0.78), lineWidth: 1.2)
                            .shadow(color: selectionTint.opacity(0.52), radius: 7)
                    }

                    Text(date, format: .dateTime.day())
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(dayTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.66)
                }
                .frame(width: min(dayCircleSize, 42), height: min(dayCircleSize, 42))

                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: dotColor.opacity(entry == nil ? 0 : 0.58), radius: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dayTextColor: Color {
        guard isInDisplayedMonth else { return .white.opacity(0.30) }
        return isSelected ? .white : .white.opacity(0.84)
    }

    private var dotColor: Color {
        guard isInDisplayedMonth else { return .clear }
        guard let entry else { return .white.opacity(0.22) }
        return MindfulnessMoodLevel.nearest(to: entry.valence).tint
    }

    private var selectionTint: Color {
        guard let entry else { return MindfulnessVisualStyle.calmBlue }
        return MindfulnessMoodLevel.nearest(to: entry.valence).tint
    }

    private var accessibilityValue: String {
        guard let entry else { return "No mood logged" }
        return "Wellness average \(String(format: "%.1f", entry.wellnessAverage * 5)) out of 5"
    }
}

private struct MindfulnessAverageRing: View {
    var average: Double?

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            MindfulnessVisualStyle.moodColor(for: average).opacity(0.09),
                            .clear
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 64
                    )
                )

            Circle()
                .stroke(.white.opacity(0.14), lineWidth: 3)

            Circle()
                .trim(from: 0, to: average ?? 0)
                .stroke(
                    MindfulnessVisualStyle.moodColor(for: average),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: MindfulnessVisualStyle.moodColor(for: average).opacity(0.38), radius: 4)

            VStack(spacing: 0) {
                Text(scoreText)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(MindfulnessVisualStyle.moodColor(for: average))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text("Average")
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(MindfulnessVisualStyle.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .frame(width: 72, height: 72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Monthly average")
        .accessibilityValue(average.map { "\(String(format: "%.1f", $0 * 5)) out of 5" } ?? "No data")
    }

    private var scoreText: String {
        average.map { String(format: "%.1f", $0 * 5) } ?? "--"
    }
}

struct MindfulnessTodayCard: View {
    var dashboard: PulsarMindfulnessDashboard
    var onCheckIn: () -> Void
    var onStartBreathing: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        PulsarMindfulnessGlassCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    MindfulnessBalanceHalo(entry: dashboard.todayEntry)
                        .frame(width: 78, height: 78)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Emotional Balance")
                            .pulsarTextStyle(.sectionTitle)
                        Text(balanceCopy)
                            .pulsarTextStyle(.screenSubtitle)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)
                }

                HStack(spacing: 10) {
                    Button(action: onCheckIn) {
                        Label(dashboard.todayEntry == nil ? "Check in" : "Update", systemImage: "slider.horizontal.3")
                            .pulsarTextStyle(.buttonTitle)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(PulsarMindfulnessActionButtonStyle(tint: balanceTint))

                    Button(action: onStartBreathing) {
                        Image(systemName: "lungs.fill")
                            .pulsarTextStyle(.cardTitle)
                            .frame(width: 52, height: 52)
                    }
                    .buttonStyle(PulsarMindfulnessIconButtonStyle(tint: .blue))
                    .accessibilityLabel("Start breathing")
                }

                HStack(spacing: 10) {
                    MindfulnessMetricPill(
                        title: "Streak",
                        value: dashboard.streak.currentStreak == 1 ? "1 day" : "\(dashboard.streak.currentStreak) days",
                        symbolName: "flame.fill",
                        tint: .orange
                    )
                    MindfulnessMetricPill(
                        title: "This week",
                        value: "\(Int(dashboard.weeklyMindfulMinutes.rounded())) min",
                        symbolName: "timer",
                        tint: .teal
                    )
                }
            }
        }
    }

    private var balanceCopy: String {
        guard let entry = dashboard.todayEntry else {
            return "A low-friction reflection is ready when your day has enough shape."
        }

        let mood = entry.moodTitle.lowercased()
        if entry.stress > 0.62 {
            return "Today feels \(mood), with stress asking for a little extra space."
        }
        if entry.gratitude > 0.68 {
            return "Today feels \(mood), with gratitude clearly present."
        }
        return "Today feels \(mood). Pulsar will keep the signal simple until patterns emerge."
    }

    private var balanceTint: Color {
        guard let entry = dashboard.todayEntry else { return .blue }
        if entry.valence >= 0.25 { return .green }
        if entry.stress > 0.62 { return .orange }
        return .blue
    }
}

struct MindfulnessBalanceHalo: View {
    var entry: PulsarDailyJournalEntry?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        ZStack {
            Circle()
                .fill(haloFill)
                .blur(radius: 8)
                .scaleEffect(phase && !reduceMotion ? 1.08 : 0.96)

            Circle()
                .stroke(haloStroke, lineWidth: 1.4)
                .padding(5)

            Image(systemName: entry == nil ? "sparkles" : "heart.text.square.fill")
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconTint)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }

    private var iconTint: Color {
        guard let entry else { return .blue }
        return entry.valence >= 0 ? .green : .orange
    }

    private var haloFill: RadialGradient {
        RadialGradient(
            colors: [
                iconTint.opacity(0.34),
                iconTint.opacity(0.14),
                Color.white.opacity(0.03)
            ],
            center: .center,
            startRadius: 5,
            endRadius: 42
        )
    }

    private var haloStroke: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(0.66), iconTint.opacity(0.42), .white.opacity(0.08)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct MindfulnessMetricPill: View {
    var title: String
    var value: String
    var symbolName: String
    var tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbolName)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.13), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .pulsarTextStyle(.appBodyEmphasis)
                Text(title)
                    .pulsarTextStyle(.metricLabel)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }
}

struct MindfulnessTrendCard: View {
    var points: [PulsarMindfulnessTrendPoint]

    var body: some View {
        PulsarMindfulnessGlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mood constellation")
                            .pulsarTextStyle(.cardTitle)
                        Text("Seven-day signal")
                            .pulsarTextStyle(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chart.xyaxis.line")
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(.blue)
                }

                MoodConstellationChart(points: points)
                    .frame(height: 120)

                ConsistencyStrip(points: points)
            }
        }
    }
}

struct MoodConstellationChart: View {
    var points: [PulsarMindfulnessTrendPoint]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.white.opacity(0.07))

                Path { path in
                    let midY = proxy.size.height / 2
                    path.move(to: CGPoint(x: 12, y: midY))
                    path.addLine(to: CGPoint(x: max(12, proxy.size.width - 12), y: midY))
                }
                .stroke(.secondary.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))

                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    let position = position(for: point, index: index, size: proxy.size)
                    Circle()
                        .fill(color(for: point))
                        .frame(width: point.hasCheckIn ? 12 : 7, height: point.hasCheckIn ? 12 : 7)
                        .shadow(color: color(for: point).opacity(0.32), radius: 8)
                        .position(position)
                }
            }
        }
        .accessibilityLabel("Seven day mood constellation")
    }

    private func position(for point: PulsarMindfulnessTrendPoint, index: Int, size: CGSize) -> CGPoint {
        let count = max(points.count - 1, 1)
        let x = 18 + (size.width - 36) * CGFloat(index) / CGFloat(count)
        let normalized = CGFloat((point.valence ?? 0) + 1) / 2
        let y = 18 + (size.height - 36) * (1 - normalized)
        return CGPoint(x: x, y: y)
    }

    private func color(for point: PulsarMindfulnessTrendPoint) -> Color {
        guard let valence = point.valence else {
            return .secondary.opacity(0.36)
        }
        if valence > 0.22 { return .green }
        if valence < -0.22 { return .orange }
        return .blue
    }
}

struct ConsistencyStrip: View {
    var points: [PulsarMindfulnessTrendPoint]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(points) { point in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fill(for: point))
                    .frame(height: 8)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(.white.opacity(point.hasCheckIn ? 0.14 : 0.06), lineWidth: 1)
                    }
                    .accessibilityLabel(point.hasCheckIn ? "Check-in logged" : "No check-in")
            }
        }
    }

    private func fill(for point: PulsarMindfulnessTrendPoint) -> Color {
        if point.hasCheckIn && point.mindfulMinutes > 0 { return .green.opacity(0.72) }
        if point.hasCheckIn { return .blue.opacity(0.62) }
        if point.mindfulMinutes > 0 { return .teal.opacity(0.52) }
        return .secondary.opacity(0.18)
    }
}

struct PulsarMindfulnessInsightCard: View {
    var insight: PulsarEmotionalInsight

    var body: some View {
        PulsarMindfulnessGlassCard(cornerRadius: 24) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: insight.symbolName)
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(insight.tint.color)
                    .frame(width: 38, height: 38)
                    .background(insight.tint.color.opacity(0.13), in: Circle())

                VStack(alignment: .leading, spacing: 7) {
                    Text(insight.title)
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(insight.body)
                        .pulsarTextStyle(.screenSubtitle)
                        .foregroundStyle(MindfulnessVisualStyle.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(insight.evidence)
                        .pulsarTextStyle(.metricLabel)
                        .foregroundStyle(MindfulnessVisualStyle.tertiaryText)
                        .padding(.top, 2)
                }
            }
        }
    }
}

struct PulsarMindfulnessActionButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.95), tint.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule(style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: tint.opacity(configuration.isPressed ? 0.28 : 0.16), radius: 18, y: 8)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct PulsarMindfulnessIconButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(tint)
            .background(tint.opacity(0.13), in: Circle())
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.76), value: configuration.isPressed)
    }
}

struct PulsarMindfulnessPressStyle: ButtonStyle {
    var glowColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.035 : 0)
            .shadow(color: glowColor.opacity(configuration.isPressed ? 0.22 : 0), radius: 18, y: 8)
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

#Preview("Mood History Sheet") {
    @Previewable @State var displayedMonth = MindfulnessHistoryPreviewData.august2026
    @Previewable @State var selectedDate = MindfulnessHistoryPreviewData.selectedDate

    MindfulnessHistorySheet(
        entries: MindfulnessHistoryPreviewData.entries,
        displayedMonth: $displayedMonth,
        selectedDate: $selectedDate
    )
}

#Preview(
    "Mood History Sheet — Reference Size",
    traits: .fixedLayout(width: 430, height: 932)
) {
    @Previewable @State var displayedMonth = MindfulnessHistoryPreviewData.august2026
    @Previewable @State var selectedDate = MindfulnessHistoryPreviewData.selectedDate

    MindfulnessHistorySheet(
        entries: MindfulnessHistoryPreviewData.entries,
        displayedMonth: $displayedMonth,
        selectedDate: $selectedDate
    )
}
