//
//  StrainCalendarView.swift
//  Pulsar
//

import SwiftUI

struct StrainCalendarView: View {
    @Environment(\.dismiss) private var dismiss
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
                VStack(spacing: 18) {
                    monthHeader
                    calendarCard
                    selectedDaySummary
                    bottomActions
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 26)
            }
            .background(PulsarSectionBackground())
            .toolbar(.hidden, for: .navigationBar)
            .alert("Strain Rings", isPresented: $isShowingInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Each ring summarizes the day’s strain score. Empty rings mean no record. Larger, brighter rings indicate higher training load from workouts and background movement.")
            }
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) { viewModel.goToPreviousMonth() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canGoToPreviousMonth)
            .opacity(viewModel.canGoToPreviousMonth ? 1 : 0.35)
            .pulsarLiquidGlass(cornerRadius: 20)
            .accessibilityLabel("Previous month")

            Text(viewModel.monthTitle)
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())

            Button {
                withAnimation(.snappy) { viewModel.goToNextMonth() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canGoToNextMonth)
            .opacity(viewModel.canGoToNextMonth ? 1 : 0.35)
            .pulsarLiquidGlass(cornerRadius: 20)
            .accessibilityLabel("Next month")
        }
    }

    private var calendarCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(viewModel.weekdaySymbols, id: \.self) { weekday in
                    Text(weekday)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(viewModel.monthDays) { day in
                    StrainCalendarDayCell(
                        date: day.date,
                        record: viewModel.record(for: day.date),
                        isToday: viewModel.isToday(day.date),
                        isSelected: viewModel.isSelected(day.date),
                        isSelectable: day.isInDisplayedMonth && viewModel.isDateSelectable(day.date),
                        isInDisplayedMonth: day.isInDisplayedMonth,
                        calendar: viewModel.calendar
                    )
                    .onTapGesture {
                        guard day.isInDisplayedMonth && viewModel.isDateSelectable(day.date) else { return }
                        withAnimation(.snappy) { viewModel.selectDate(day.date) }
                    }
                }
            }
        }
        .padding(16)
        .pulsarLiquidGlass(cornerRadius: 30)
    }

    @ViewBuilder
    private var selectedDaySummary: some View {
        if let record = viewModel.selectedRecord {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.selectedDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.headline)
                        Text("\(record.sourceName) · \(record.confidence.rawValue) confidence")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StrainRing(score: record.strainScore, lineWidth: 8, size: 54)
                }

                HStack(spacing: 10) {
                    CalendarSummaryMetric(title: "Strain", value: "\(record.strainScore)")
                    CalendarSummaryMetric(title: "Workout", value: "\(record.workoutMinutes)m")
                    CalendarSummaryMetric(title: "Steps", value: record.steps.formatted())
                    CalendarSummaryMetric(title: "Energy", value: "\(record.activeEnergyKilocalories)")
                }
            }
            .padding(16)
            .pulsarLiquidGlass(cornerRadius: 26)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.selectedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.headline)
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pulsarLiquidGlass(cornerRadius: 26)
        }
    }

    private var bottomActions: some View {
        HStack {
            Button {
                withAnimation(.snappy) { viewModel.goToToday() }
            } label: {
                Label("Today", systemImage: "calendar")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 42)
            }
            .buttonStyle(.plain)
            .pulsarLiquidGlass(cornerRadius: 21)

            Spacer()

            Button {
                onDateSelected(viewModel.selectedDate)
                dismiss()
            } label: {
                Label("View Day", systemImage: "checkmark")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 42)
            }
            .buttonStyle(.plain)
            .pulsarLiquidGlass(cornerRadius: 21)

            Button {
                isShowingInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3.weight(.medium))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .pulsarLiquidGlass(cornerRadius: 21)
            .accessibilityLabel("Strain ring information")
        }
    }

    private var emptyMessage: String {
        viewModel.isToday(viewModel.selectedDate) ? "No strain data recorded yet today." : "No strain data recorded for this day."
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

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let record, isSelectable {
                    StrainRing(score: record.strainScore, lineWidth: 4, size: 34)
                } else {
                    Circle()
                        .stroke(.secondary.opacity(isSelectable ? 0.18 : 0.08), lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                }

                Text("\(calendar.component(.day, from: date))")
                    .font(.caption.weight(isToday || isSelected ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isSelectable ? .primary : .secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .opacity(isSelectable ? 1 : 0.32)
        .background {
            if isSelected && isSelectable {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.tint.opacity(0.14))
            } else if isToday && isSelectable {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.tint.opacity(0.45), lineWidth: 1)
            }
        }
        .contentShape(isSelectable ? RoundedRectangle(cornerRadius: 16, style: .continuous) : RoundedRectangle(cornerRadius: 0, style: .continuous))
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        guard isSelectable else {
            return "\(date.formatted(date: .abbreviated, time: .omitted)), unavailable"
        }
        if let record {
            return "\(date.formatted(date: .abbreviated, time: .omitted)), strain \(record.strainScore)"
        }
        return "\(date.formatted(date: .abbreviated, time: .omitted)), no strain data"
    }
}

private struct StrainRing: View {
    var score: Int
    var lineWidth: CGFloat
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, Double(score) / 100))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }

    private var color: Color {
        switch score {
        case 1..<35: .mint.opacity(0.75)
        case 35..<70: .blue
        case 70...100: .orange
        default: .secondary.opacity(0.25)
        }
    }
}

private struct CalendarSummaryMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
