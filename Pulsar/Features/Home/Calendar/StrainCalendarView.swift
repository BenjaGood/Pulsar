//
//  StrainCalendarView.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct StrainCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var viewModel: StrainCalendarViewModel
    @State private var isShowingInfo = false
    private let onDateSelected: (Date) -> Void

    @MainActor
    init(selectedDate: Date = Date(), records: [DailyStrainRecord] = [], onDateSelected: @escaping (Date) -> Void = { _ in }) {
        let lifecycleStore = AppLifecycleStore()
        _viewModel = StateObject(wrappedValue: StrainCalendarViewModel(
            selectedDate: selectedDate,
            records: records,
            firstLaunchDate: lifecycleStore.firstLaunchDate,
            firstStrainSyncDate: lifecycleStore.firstStrainSyncDate
        ))
        self.onDateSelected = onDateSelected
    }

    @MainActor
    init(viewModel: StrainCalendarViewModel, onDateSelected: @escaping (Date) -> Void = { _ in }) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onDateSelected = onDateSelected
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dragIndicator
                    calendarHero
                    monthHeader
                    calendarCard
                    selectedDaySummary
                    bottomActions
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 26)
            }
            .background(CalendarBackdrop())
            .toolbar(.hidden, for: .navigationBar)
            .alert("Strain Rings", isPresented: $isShowingInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Calendar rings summarize saved daily data. Colored dots mark Sleep, Recovery, Strain, and Stress records when available. Empty days stay quiet until Pulsar has data for that local calendar day.")
            }
        }
    }

    private var dragIndicator: some View {
        Capsule(style: .continuous)
            .fill(.secondary.opacity(colorScheme == .dark ? 0.34 : 0.22))
            .frame(width: 42, height: 5)
            .padding(.bottom, 2)
            .accessibilityHidden(true)
    }

    private var calendarHero: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                PulsarMetricRingTheme.tint(for: .strain).opacity(0.28),
                                PulsarMetricRingTheme.tint(for: .sleep).opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                Image(systemName: "calendar")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(colorScheme == .dark ? 0.95 : 0.86))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Daily Calendar")
                    .font(.title2.weight(.bold))
                Text("Review saved Sleep, Recovery, Strain, and Stress history.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.12 : 0.72),
                            PulsarMetricRingTheme.tint(for: .sleep).opacity(colorScheme == .dark ? 0.09 : 0.13),
                            Color.black.opacity(colorScheme == .dark ? 0.14 : 0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(colorScheme == .dark ? 0.14 : 0.34), lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 18, y: 10)
    }

    private var monthHeader: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy) { viewModel.goToPreviousMonth() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.callout.weight(.bold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canGoToPreviousMonth)
            .opacity(viewModel.canGoToPreviousMonth ? 1 : 0.35)
            .calendarGlass(cornerRadius: 19)
            .accessibilityLabel("Previous month")

            VStack(spacing: 2) {
                Text(viewModel.monthTitle)
                    .font(.title3.weight(.bold))
                    .contentTransition(.numericText())
                Text("\(viewModel.records.count) saved days")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button {
                withAnimation(.snappy) { viewModel.goToNextMonth() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.callout.weight(.bold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canGoToNextMonth)
            .opacity(viewModel.canGoToNextMonth ? 1 : 0.35)
            .calendarGlass(cornerRadius: 19)
            .accessibilityLabel("Next month")
        }
    }

    private var calendarCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                ForEach(viewModel.weekdaySymbols, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary.opacity(0.86))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 2)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 7), spacing: 9) {
                ForEach(viewModel.monthDays) { day in
                    let record = viewModel.record(for: day.date)
                    StrainCalendarDayCell(
                        date: day.date,
                        record: record,
                        isToday: viewModel.isToday(day.date),
                        isSelected: viewModel.isSelected(day.date),
                        isSelectable: viewModel.isDateSelectable(day.date),
                        isInDisplayedMonth: day.isInDisplayedMonth,
                        calendar: viewModel.calendar
                    )
                    .onTapGesture {
                        handleDayTap(day.date, record: record)
                    }
                }
            }
        }
        .padding(15)
        .calendarGlass(cornerRadius: 30)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 16, y: 8)
    }

    private func handleDayTap(_ date: Date, record: DailyStrainRecord?) {
        guard viewModel.isDateSelectable(date) else { return }
        UIImpactFeedbackGenerator(style: record == nil ? .light : .soft).impactOccurred()
        withAnimation(.snappy) { viewModel.selectDate(date) }
        onDateSelected(date)
        dismiss()
    }

    @ViewBuilder
    private var selectedDaySummary: some View {
        if let record = viewModel.selectedRecord {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.selectedDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.headline.weight(.bold))
                        Text("\(record.sourceName) · \(record.confidence.rawValue) confidence")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    CalendarCompositeRing(record: record, size: 62, lineWidth: 7)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                    CalendarSummaryMetric(title: "Sleep", value: record.sleepMinutes.map(minutesText) ?? "--", tint: PulsarMetricRingTheme.tint(for: .sleep))
                    CalendarSummaryMetric(title: "Recovery", value: record.recoveryScore.map(String.init) ?? "--", tint: PulsarMetricRingTheme.tint(for: .recovery))
                    CalendarSummaryMetric(title: "Strain", value: record.strainScore > 0 ? "\(record.strainScore)" : "--", tint: PulsarMetricRingTheme.tint(for: .strain))
                    CalendarSummaryMetric(title: "Stress", value: record.stressScore.map(String.init) ?? "--", tint: PulsarStressRingTheme.tint(for: record.stressScore))
                    CalendarSummaryMetric(title: "Workout", value: "\(record.workoutMinutes)m", tint: PulsarMetricRingTheme.tint(for: .strain))
                    CalendarSummaryMetric(title: "Steps", value: record.steps.formatted(), tint: .secondary)
                }

                Text("Tap any day to make it the active dashboard date.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .calendarGlass(cornerRadius: 28)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            HStack(spacing: 12) {
                Image(systemName: "moonphase.new.moon")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, height: 42)
                    .background(.secondary.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(viewModel.selectedDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.headline.weight(.bold))
                    Text(emptyMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .calendarGlass(cornerRadius: 28)
        }
    }

    private var bottomActions: some View {
        HStack {
            Button {
                withAnimation(.snappy) { viewModel.goToToday() }
                handleDayTap(viewModel.validEndDate, record: viewModel.record(for: viewModel.validEndDate))
            } label: {
                Label("Today", systemImage: "calendar")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 42)
            }
            .buttonStyle(.plain)
            .calendarGlass(cornerRadius: 21)

            Spacer()

            Button {
                isShowingInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3.weight(.medium))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .calendarGlass(cornerRadius: 21)
            .accessibilityLabel("Strain ring information")
        }
    }

    private var emptyMessage: String {
        viewModel.isToday(viewModel.selectedDate) ? "No data recorded yet today." : "No data recorded for this day."
    }

    private func minutesText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder)m" }
        if remainder == 0 { return "\(hours)h" }
        return "\(hours)h \(remainder)m"
    }
}

struct StrainCalendarDayCell: View {
    var date: Date
    var record: DailyStrainRecord?
    var isToday: Bool
    var isSelected: Bool
    var isSelectable: Bool
    var isInDisplayedMonth: Bool
    var calendar: Calendar
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                if let record, record.hasRecordedData, isSelectable {
                    CalendarCompositeRing(record: record, size: 36, lineWidth: 3.4)
                } else {
                    Circle()
                        .stroke(emptyStroke, lineWidth: 1.2)
                        .frame(width: 36, height: 36)
                }

                Text("\(calendar.component(.day, from: date))")
                    .font(.caption.weight(isToday || isSelected ? .bold : .semibold))
                    .monospacedDigit()
                    .foregroundStyle(textColor)
            }

            MetricAvailabilityDots(record: record)
                .opacity(record?.hasRecordedData == true && isSelectable ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .opacity(dayOpacity)
        .background {
            if isSelected && isSelectable {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.15 : 0.68),
                                primaryTint.opacity(colorScheme == .dark ? 0.18 : 0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(primaryTint.opacity(0.42), lineWidth: 1)
                    }
                    .shadow(color: primaryTint.opacity(0.18), radius: 8, y: 4)
            } else if isToday && isSelectable {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PulsarMetricRingTheme.tint(for: .sleep).opacity(0.42), lineWidth: 1)
            }
        }
        .contentShape(isSelectable ? RoundedRectangle(cornerRadius: 16, style: .continuous) : RoundedRectangle(cornerRadius: 0, style: .continuous))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var emptyStroke: Color {
        if !isInDisplayedMonth {
            return .secondary.opacity(colorScheme == .dark ? 0.10 : 0.08)
        }
        return .secondary.opacity(isSelectable ? (colorScheme == .dark ? 0.20 : 0.16) : 0.08)
    }

    private var textColor: Color {
        if !isSelectable { return .secondary.opacity(0.48) }
        if !isInDisplayedMonth { return .secondary.opacity(0.72) }
        return .primary
    }

    private var dayOpacity: Double {
        if !isSelectable { return 0.26 }
        if !isInDisplayedMonth { return 0.56 }
        if record?.hasRecordedData == true { return 1 }
        return 0.72
    }

    private var primaryTint: Color {
        calendarPrimaryTint(for: record)
    }

    private var accessibilityLabel: String {
        guard isSelectable else {
            return "\(date.formatted(date: .abbreviated, time: .omitted)), unavailable"
        }
        var parts: [String] = [date.formatted(.dateTime.month(.wide).day().year())]
        if isSelected { parts.append("selected") }
        if isToday { parts.append("today") }
        if let record, record.hasRecordedData {
            if let sleepScore = record.sleepScore { parts.append("sleep \(sleepScore)") }
            if let recoveryScore = record.recoveryScore { parts.append("recovery \(recoveryScore)") }
            if record.strainScore > 0 { parts.append("strain \(record.strainScore)") }
            if let stressScore = record.stressScore { parts.append("stress \(stressScore)") }
            if record.workoutMinutes > 0 { parts.append("workout data available") }
            return parts.joined(separator: ", ")
        }
        parts.append("no data")
        return parts.joined(separator: ", ")
    }
}

private struct CalendarCompositeRing: View {
    var record: DailyStrainRecord
    var size: CGFloat
    var lineWidth: CGFloat

    var body: some View {
        CalendarScoreRing(
            score: primaryScore,
            tint: calendarPrimaryTint(for: record),
            lineWidth: lineWidth,
            size: size
        )
    }

    private var primaryScore: Int {
        if record.strainScore > 0 { return record.strainScore }
        if let recoveryScore = record.recoveryScore { return recoveryScore }
        if let sleepScore = record.sleepScore { return sleepScore }
        if let stressScore = record.stressScore { return stressScore }
        return 0
    }
}

private struct CalendarScoreRing: View {
    var score: Int
    var tint: Color
    var lineWidth: CGFloat
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(PulsarMetricRingTheme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, Double(score) / 100))
                .stroke(
                    PulsarMetricRingTheme.progressGradient(tint: tint),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: PulsarMetricRingTheme.ringShadow(tint: tint), radius: 4, y: 1)
        }
        .frame(width: size, height: size)
    }
}

private struct MetricAvailabilityDots: View {
    var record: DailyStrainRecord?

    var body: some View {
        HStack(spacing: 2.5) {
            if record?.sleepScore != nil {
                dot(PulsarMetricRingTheme.tint(for: .sleep))
            }
            if record?.recoveryScore != nil {
                dot(PulsarMetricRingTheme.tint(for: .recovery))
            }
            if let record, record.strainScore > 0 {
                dot(PulsarMetricRingTheme.tint(for: .strain))
            }
            if let stressScore = record?.stressScore {
                dot(PulsarStressRingTheme.tint(for: stressScore))
            }
        }
        .frame(height: 5)
    }

    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 4.5, height: 4.5)
    }
}

private struct CalendarSummaryMetric: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint.opacity(0.92))
                .frame(width: 8, height: 8)
                .shadow(color: tint.opacity(0.24), radius: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .monospacedDigit()
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    tint.opacity(0.12),
                    Color.white.opacity(0.06),
                    Color.black.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.8)
        }
    }
}

private func calendarPrimaryTint(for record: DailyStrainRecord?) -> Color {
    guard let record else { return PulsarMetricRingTheme.tint(for: .strain) }
    if record.strainScore > 0 { return PulsarMetricRingTheme.tint(for: .strain) }
    if record.recoveryScore != nil { return PulsarMetricRingTheme.tint(for: .recovery) }
    if record.sleepScore != nil { return PulsarMetricRingTheme.tint(for: .sleep) }
    return PulsarStressRingTheme.tint(for: record.stressScore)
}

private struct CalendarBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.03, green: 0.04, blue: 0.08),
                        Color(red: 0.06, green: 0.08, blue: 0.14),
                        Color(red: 0.01, green: 0.02, blue: 0.05)
                    ]
                    : [
                        Color(.systemBackground),
                        Color(red: 0.94, green: 0.97, blue: 1.00),
                        Color(.secondarySystemBackground)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(PulsarMetricRingTheme.tint(for: .sleep).opacity(colorScheme == .dark ? 0.18 : 0.10))
                .blur(radius: 60)
                .offset(x: -130, y: -220)

            Circle()
                .fill(PulsarMetricRingTheme.tint(for: .strain).opacity(colorScheme == .dark ? 0.16 : 0.08))
                .blur(radius: 70)
                .offset(x: 150, y: 220)
        }
        .ignoresSafeArea()
    }
}

private struct CalendarGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.11 : 0.62),
                                Color.white.opacity(colorScheme == .dark ? 0.045 : 0.28),
                                Color.black.opacity(colorScheme == .dark ? 0.12 : 0.025)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.15 : 0.46),
                                Color.white.opacity(colorScheme == .dark ? 0.055 : 0.16),
                                Color.black.opacity(colorScheme == .dark ? 0.12 : 0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
    }
}

private extension View {
    func calendarGlass(cornerRadius: CGFloat) -> some View {
        modifier(CalendarGlassModifier(cornerRadius: cornerRadius))
    }
}

#Preview("Only Today Available") {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    StrainCalendarView(viewModel: StrainCalendarViewModel(selectedDate: today, records: [], firstLaunchDate: today, today: today, calendar: calendar))
}

#Preview("Few Real Days") {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let start = calendar.date(byAdding: .day, value: -8, to: today) ?? today
    let records = MockStrainCalendarData.previewRecords(around: today, calendar: calendar).filter { record in
        let day = calendar.startOfDay(for: record.date)
        return day >= start && day <= today
    }
    StrainCalendarView(viewModel: StrainCalendarViewModel(selectedDate: today, records: records, firstLaunchDate: start, today: today, calendar: calendar))
}

#Preview("No Records Yet") {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    StrainCalendarView(viewModel: StrainCalendarViewModel(selectedDate: today, records: [], firstLaunchDate: today, today: today, calendar: calendar))
}

#Preview("Month Boundary") {
    let calendar = Calendar.current
    let boundary = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)) ?? Date()
    let start = calendar.date(byAdding: .day, value: -3, to: boundary) ?? boundary
    let records = MockStrainCalendarData.previewRecords(around: start, calendar: calendar) + MockStrainCalendarData.previewRecords(around: boundary, calendar: calendar)
    StrainCalendarView(viewModel: StrainCalendarViewModel(selectedDate: boundary, records: records, firstLaunchDate: start, today: boundary, calendar: calendar))
}

#Preview("Calendar Day") {
    HStack {
        StrainCalendarDayCell(
            date: .now,
            record: MockStrainCalendarData.previewRecords().first,
            isToday: true,
            isSelected: false,
            isSelectable: true,
            isInDisplayedMonth: true,
            calendar: .current
        )
        StrainCalendarDayCell(date: .now, record: nil, isToday: false, isSelected: true, isSelectable: true, isInDisplayedMonth: true, calendar: .current)
        StrainCalendarDayCell(date: .now, record: nil, isToday: false, isSelected: false, isSelectable: false, isInDisplayedMonth: false, calendar: .current)
    }
    .padding()
    .background(PulsarSectionBackground())
}
