//
//  StrainCalendarViewModel.swift
//  Pulsar
//

import Combine
import Foundation

struct StrainCalendarDay: Identifiable, Hashable {
    var id: Date { date }
    var date: Date
    var isInDisplayedMonth: Bool
}

@MainActor
final class StrainCalendarViewModel: ObservableObject {
    @Published private(set) var displayedMonth: Date
    @Published private(set) var selectedDate: Date
    @Published private(set) var records: [DailyStrainRecord]
    @Published private(set) var recordsByDay: [Date: DailyStrainRecord]

    let calendar: Calendar
    let firstLaunchDate: Date
    let firstStrainSyncDate: Date?
    let validEndDate: Date

    init(
        selectedDate: Date = Date(),
        records: [DailyStrainRecord] = [],
        firstLaunchDate: Date = Date(),
        firstStrainSyncDate: Date? = nil,
        today: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.calendar = calendar
        self.firstLaunchDate = calendar.startOfDay(for: firstLaunchDate)
        self.firstStrainSyncDate = firstStrainSyncDate.map { calendar.startOfDay(for: $0) }
        self.validEndDate = calendar.startOfDay(for: today)
        let validEndDate = self.validEndDate

        let candidateRecords = records
            .filter { calendar.startOfDay(for: $0.date) <= validEndDate }
            .map { record in
                DailyStrainRecord(
                    date: calendar.startOfDay(for: record.date),
                    dateKey: record.dateKey,
                    calendar: calendar,
                    sleepScore: record.sleepScore,
                    sleepMinutes: record.sleepMinutes,
                    recoveryScore: record.recoveryScore,
                    stressScore: record.stressScore,
                    stressTimelineSamples: record.stressTimelineSamples,
                    strainScore: record.strainScore,
                    respiratoryRate: record.respiratoryRate,
                    respiratoryRateStatus: record.respiratoryRateStatus,
                    restingHeartRate: record.restingHeartRate,
                    restingHeartRateStatus: record.restingHeartRateStatus,
                    hrv: record.hrv,
                    hrvStatus: record.hrvStatus,
                    oxygenSaturation: record.oxygenSaturation,
                    oxygenSaturationStatus: record.oxygenSaturationStatus,
                    wristTemperatureDeviation: record.wristTemperatureDeviation,
                    wristTemperatureStatus: record.wristTemperatureStatus,
                    sleepDurationStatus: record.sleepDurationStatus,
                    workoutMinutes: record.workoutMinutes,
                    steps: record.steps,
                    activeEnergyKilocalories: record.activeEnergyKilocalories,
                    confidence: record.confidence,
                    sourceName: record.sourceName,
                    syncedAt: record.syncedAt
                )
            }
        var recordsByDay: [Date: DailyStrainRecord] = [:]
        for record in candidateRecords {
            let day = calendar.startOfDay(for: record.date)
            recordsByDay[day] = recordsByDay[day].map { $0.merged(with: record, calendar: calendar) } ?? record
        }
        let normalizedRecords = recordsByDay.values.sorted { $0.date < $1.date }
        self.records = normalizedRecords
        self.recordsByDay = recordsByDay

        let safeSelectedDate = Self.clamp(
            calendar.startOfDay(for: selectedDate),
            start: Self.validStartDate(records: normalizedRecords, firstLaunchDate: self.firstLaunchDate, firstStrainSyncDate: self.firstStrainSyncDate, validEndDate: self.validEndDate, calendar: calendar),
            end: self.validEndDate
        )
        self.selectedDate = safeSelectedDate
        self.displayedMonth = calendar.dateInterval(of: .month, for: safeSelectedDate)?.start ?? safeSelectedDate
    }

    var validStartDate: Date {
        Self.validStartDate(
            records: records,
            firstLaunchDate: firstLaunchDate,
            firstStrainSyncDate: firstStrainSyncDate,
            validEndDate: validEndDate,
            calendar: calendar
        )
    }

    var monthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide).year())
    }

    var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let firstIndex = calendar.firstWeekday - 1
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }

    var selectedRecord: DailyStrainRecord? {
        record(for: selectedDate)
    }

    var monthDays: [StrainCalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingCount = (firstWeekday - calendar.firstWeekday + 7) % 7
        let displayedDays = dayRange.compactMap { day -> StrainCalendarDay? in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) else { return nil }
            return StrainCalendarDay(date: date, isInDisplayedMonth: true)
        }

        let leadingDays = (0..<leadingCount).compactMap { offset -> StrainCalendarDay? in
            guard let date = calendar.date(byAdding: .day, value: offset - leadingCount, to: monthInterval.start) else { return nil }
            return StrainCalendarDay(date: date, isInDisplayedMonth: false)
        }

        let cells = leadingDays + displayedDays
        let trailingCount = (7 - cells.count % 7) % 7
        let trailingDays = (0..<trailingCount).compactMap { offset -> StrainCalendarDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: monthInterval.end) else { return nil }
            return StrainCalendarDay(date: calendar.startOfDay(for: date), isInDisplayedMonth: false)
        }

        return cells + trailingDays
    }

    var canGoToPreviousMonth: Bool {
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth),
              let previousInterval = calendar.dateInterval(of: .month, for: previousMonth) else { return false }
        return previousInterval.end > validStartDate
    }

    var canGoToNextMonth: Bool {
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth),
              let nextInterval = calendar.dateInterval(of: .month, for: nextMonth) else { return false }
        return nextInterval.start <= validEndDate
    }

    func record(for date: Date) -> DailyStrainRecord? {
        guard isDateSelectable(date) else { return nil }
        return recordsByDay[calendar.startOfDay(for: date)]
    }

    func isToday(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: validEndDate)
    }

    func isSelected(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }

    func isDateSelectable(_ date: Date) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= validStartDate && day <= validEndDate
    }

    func selectDate(_ date: Date) {
        guard isDateSelectable(date) else { return }
        let day = calendar.startOfDay(for: date)
        selectedDate = day
        if let month = calendar.dateInterval(of: .month, for: day)?.start,
           !calendar.isDate(month, equalTo: displayedMonth, toGranularity: .month) {
            displayedMonth = month
        }
    }

    func goToPreviousMonth() {
        guard canGoToPreviousMonth else { return }
        moveMonth(by: -1)
    }

    func goToNextMonth() {
        guard canGoToNextMonth else { return }
        moveMonth(by: 1)
    }

    func goToToday() {
        selectedDate = Self.clamp(validEndDate, start: validStartDate, end: validEndDate)
        displayedMonth = calendar.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
    }

    private func moveMonth(by value: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        displayedMonth = calendar.dateInterval(of: .month, for: newMonth)?.start ?? newMonth
    }

    private static func validStartDate(
        records: [DailyStrainRecord],
        firstLaunchDate: Date,
        firstStrainSyncDate: Date?,
        validEndDate: Date,
        calendar: Calendar
    ) -> Date {
        let earliestRecordDate = records.map { calendar.startOfDay(for: $0.date) }.min()
        let start = earliestRecordDate ?? firstStrainSyncDate ?? firstLaunchDate
        return min(calendar.startOfDay(for: start), validEndDate)
    }

    private static func clamp(_ date: Date, start: Date, end: Date) -> Date {
        min(max(date, start), end)
    }
}
