//
//  MindfulnessHistoryContent.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessHistoryContent: View {
    var entries: [PulsarDailyJournalEntry]
    @Binding var displayedMonth: Date
    @Binding var selectedDate: Date
    var onClose: () -> Void
    var onViewFullDayInsights: (PulsarDailyJournalEntry) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calendar) private var calendar
    @State private var entriesByDay: [Date: PulsarDailyJournalEntry]

    init(
        entries: [PulsarDailyJournalEntry],
        displayedMonth: Binding<Date>,
        selectedDate: Binding<Date>,
        onClose: @escaping () -> Void,
        onViewFullDayInsights: @escaping (PulsarDailyJournalEntry) -> Void
    ) {
        self.entries = entries
        self._displayedMonth = displayedMonth
        self._selectedDate = selectedDate
        self.onClose = onClose
        self.onViewFullDayInsights = onViewFullDayInsights
        self._entriesByDay = State(
            initialValue: Self.indexedEntries(entries, calendar: .current)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MindfulnessDesign.historySectionSpacing) {
            MindfulnessHistoryHeader(
                month: monthStart,
                onClose: onClose
            )

            MindfulnessHistoryMonthControls(
                onPrevious: { moveMonth(by: -1) },
                onNext: { moveMonth(by: 1) },
                onToday: selectToday
            )

            MindfulnessHistoryCalendar(
                displayedMonth: monthStart,
                selectedDate: selectedDate,
                entriesByDay: entriesByDay,
                onSelect: select
            )
            .id(monthStart)
            .transition(.opacity)

            MindfulnessMonthlyInsightCard(
                average: monthlyAverage,
                summary: monthlyInsightText
            )

            ZStack(alignment: .top) {
                if let selectedEntry {
                    MindfulnessSelectedDayDetailCard(entry: selectedEntry)
                        .id(selectedEntry.id)
                        .transition(detailTransition)
                } else {
                    MindfulnessHistoryEmptyDayCard(date: selectedDate)
                        .id(calendar.startOfDay(for: selectedDate))
                        .transition(detailTransition)
                }
            }

            if let selectedEntry {
                MindfulnessFullDayInsightsButton {
                    onViewFullDayInsights(selectedEntry)
                }
            }
        }
        .onChange(of: entries) { _, newEntries in
            entriesByDay = Self.indexedEntries(newEntries, calendar: calendar)
        }
    }

    private var monthStart: Date {
        calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
    }

    private var selectedEntry: PulsarDailyJournalEntry? {
        entriesByDay[calendar.startOfDay(for: selectedDate)]
    }

    private var monthlyEntries: [PulsarDailyJournalEntry] {
        entriesByDay.values.filter {
            calendar.isDate($0.date, equalTo: monthStart, toGranularity: .month)
        }
    }

    private var monthlyAverage: Double? {
        guard !monthlyEntries.isEmpty else { return nil }
        return monthlyEntries.reduce(0) { $0 + $1.wellnessAverage }
            / Double(monthlyEntries.count)
    }

    private var monthlyInsightText: String {
        guard let monthlyAverage else {
            return "Log a few days this month to reveal a steadier pattern."
        }

        return switch monthlyAverage {
        case 0.72...:
            "Your days were mostly calm, connected, and balanced this month."
        case 0.56..<0.72:
            "Your month held a steady balance with a few softer days."
        case 0.40..<0.56:
            "Your signals were mixed this month. Small resets may help create more ease."
        default:
            "This month carried more strain. Gentle recovery and connection may help."
        }
    }

    private var detailTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .offset(y: 6))
    }

    private var selectionAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.01)
            : .easeInOut(duration: 0.24)
    }

    private func moveMonth(by value: Int) {
        guard let nextMonth = calendar.date(byAdding: .month, value: value, to: monthStart) else {
            return
        }
        withAnimation(selectionAnimation) {
            displayedMonth = nextMonth
        }
    }

    private func selectToday() {
        let today = Date()
        withAnimation(selectionAnimation) {
            selectedDate = today
            displayedMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
        }
    }

    private func select(_ day: MindfulnessHistoryCalendarDay) {
        withAnimation(selectionAnimation) {
            selectedDate = day.date
            if !day.isInDisplayedMonth {
                displayedMonth = calendar.dateInterval(of: .month, for: day.date)?.start ?? day.date
            }
        }
    }

    private static func indexedEntries(
        _ entries: [PulsarDailyJournalEntry],
        calendar: Calendar
    ) -> [Date: PulsarDailyJournalEntry] {
        entries.reduce(into: [:]) { result, entry in
            let day = calendar.startOfDay(for: entry.date)
            if result[day] == nil {
                result[day] = entry
            }
        }
    }
}
