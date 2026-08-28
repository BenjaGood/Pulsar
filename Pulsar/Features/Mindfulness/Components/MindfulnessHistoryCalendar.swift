//
//  MindfulnessHistoryCalendar.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessHistoryCalendar: View {
    var displayedMonth: Date
    var selectedDate: Date
    var entriesByDay: [Date: PulsarDailyJournalEntry]
    var onSelect: (MindfulnessHistoryCalendarDay) -> Void

    @Environment(\.calendar) private var calendar

    var body: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(weekdaySymbols.indices, id: \.self) { index in
                Text(weekdaySymbols[index].short)
                    .font(.caption)
                    .foregroundStyle(MindfulnessDesign.tertiaryText)
                    .frame(maxWidth: .infinity, minHeight: 20)
                    .accessibilityLabel(weekdaySymbols[index].full)
            }

            ForEach(calendarDays) { day in
                MindfulnessHistoryDayButton(
                    date: day.date,
                    isInDisplayedMonth: day.isInDisplayedMonth,
                    isSelected: calendar.isDate(day.date, inSameDayAs: selectedDate),
                    entry: entriesByDay[calendar.startOfDay(for: day.date)],
                    action: { onSelect(day) }
                )
            }
        }
    }

    private var columns: [GridItem] {
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

    private var calendarDays: [MindfulnessHistoryCalendarDay] {
        let monthStart = calendar.dateInterval(of: .month, for: displayedMonth)?.start
            ?? displayedMonth
        let weekday = calendar.component(.weekday, from: monthStart)
        let daysBeforeMonday = (weekday + 5) % 7
        guard let gridStart = calendar.date(
            byAdding: .day,
            value: -daysBeforeMonday,
            to: monthStart
        ) else {
            return []
        }

        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 31
        let requiredCells = daysBeforeMonday + daysInMonth
        let cellCount = requiredCells <= 35 ? 35 : 42

        return (0..<cellCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }
            return MindfulnessHistoryCalendarDay(
                date: date,
                isInDisplayedMonth: calendar.isDate(
                    date,
                    equalTo: monthStart,
                    toGranularity: .month
                )
            )
        }
    }
}
