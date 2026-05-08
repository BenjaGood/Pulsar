//
//  FitnessWeekModels.swift
//  Pulsar
//

import Foundation
import SwiftUI

struct WeekPeriod: Identifiable, Hashable {
    var weekNumber: Int
    var year: Int
    var startDate: Date
    var endDate: Date
    var isCurrentWeek: Bool
    var hasWorkout: Bool

    var id: String { "\(year)-\(weekNumber)" }
}

struct WeeklyActivity: Identifiable, Hashable {
    var id: String
    var workoutUUID: UUID?
    var workoutType: String
    var displayName: String
    var category: WeeklyActivityCategory
    var startDate: Date
    var endDate: Date
    var duration: TimeInterval
    var calories: Double?
    var distanceMeters: Double?
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var source: WeeklyActivitySource
    var sourceName: String
    var completedSets: Int? = nil
    var totalSets: Int? = nil
    var mainMuscleGroups: [String] = []
    var muscleLoadByBodyZone: [BodyZone: Double] = [:]
    var muscleExercisesByBodyZone: [BodyZone: [String]] = [:]

    var durationMinutes: Double { max(0, duration / 60) }
}

enum WeeklyActivitySource: String, Hashable {
    case healthKit = "HealthKit"
    case localRun = "Pulsar"
    case localGym = "Pulsar Gym"
}

enum WeeklyActivityCategory: String, Hashable {
    case running
    case walking
    case hiking
    case cycling
    case strength
    case gym
    case hiit
    case yoga
    case swimming
    case rowing
    case dance
    case recovery
    case other

    var symbolName: String {
        switch self {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .hiking: "mountain.2.fill"
        case .cycling: "bicycle"
        case .strength, .gym: "dumbbell.fill"
        case .hiit: "flame.fill"
        case .yoga: "figure.yoga"
        case .swimming: "figure.pool.swim"
        case .rowing: "figure.rower"
        case .dance: "figure.dance"
        case .recovery: "figure.cooldown"
        case .other: "figure.mixed.cardio"
        }
    }

    var accent: Color {
        switch self {
        case .running: Color(red: 1.00, green: 0.46, blue: 0.34)
        case .walking: Color(red: 0.44, green: 0.72, blue: 1.00)
        case .hiking: Color(red: 0.34, green: 0.82, blue: 0.58)
        case .cycling: Color(red: 0.25, green: 0.78, blue: 0.86)
        case .strength, .gym: Color(red: 0.72, green: 0.66, blue: 1.00)
        case .hiit: Color(red: 1.00, green: 0.61, blue: 0.25)
        case .yoga, .recovery: Color(red: 0.72, green: 0.82, blue: 0.46)
        case .swimming: Color(red: 0.34, green: 0.68, blue: 1.00)
        case .rowing: Color(red: 0.25, green: 0.78, blue: 0.86)
        case .dance: Color(red: 1.00, green: 0.44, blue: 0.68)
        case .other: Color(red: 0.68, green: 0.74, blue: 0.84)
        }
    }
}

enum FitnessWeekCalculator {
    static func getCustomWeekNumber(for date: Date, calendar: Calendar = .current) -> Int {
        let normalizedDate = calendar.startOfDay(for: date)
        let januaryFirst = startOfYear(for: normalizedDate, calendar: calendar)
        let dayDifference = calendar.dateComponents([.day], from: januaryFirst, to: normalizedDate).day ?? 0
        return max(1, dayDifference / 7 + 1)
    }

    static func getWeekPeriod(for date: Date, calendar: Calendar = .current, now: Date = .now, hasWorkout: Bool = false) -> WeekPeriod {
        let normalizedDate = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: normalizedDate)
        let weekNumber = getCustomWeekNumber(for: normalizedDate, calendar: calendar)
        let januaryFirst = startOfYear(for: normalizedDate, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: (weekNumber - 1) * 7, to: januaryFirst) ?? januaryFirst
        let decemberThirtyFirst = endOfYear(for: normalizedDate, calendar: calendar)
        let uncappedEnd = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let end = min(uncappedEnd, decemberThirtyFirst)
        let currentWeek = getCustomWeekNumber(for: now, calendar: calendar)
        let currentYear = calendar.component(.year, from: now)

        return WeekPeriod(
            weekNumber: weekNumber,
            year: year,
            startDate: start,
            endDate: end,
            isCurrentWeek: year == currentYear && weekNumber == currentWeek,
            hasWorkout: hasWorkout
        )
    }

    static func getWeekPeriodsAroundCurrentWeek(pastWeeks: Int = 14, futureWeeks: Int = 0, calendar: Calendar = .current, now: Date = .now) -> [WeekPeriod] {
        let current = getWeekPeriod(for: now, calendar: calendar, now: now)
        let firstStart = calendar.date(byAdding: .day, value: -7 * pastWeeks, to: current.startDate) ?? current.startDate
        let total = pastWeeks + futureWeeks + 1

        return (0..<total).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset * 7, to: firstStart) else { return nil }
            return getWeekPeriod(for: date, calendar: calendar, now: now)
        }
    }

    static func getWeekPeriods(forYear year: Int, calendar: Calendar = .current, now: Date = .now) -> [WeekPeriod] {
        let interval = yearInterval(for: year, calendar: calendar)
        let finalDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        var date = interval.start
        var periods: [WeekPeriod] = []

        while date <= finalDay {
            let period = getWeekPeriod(for: date, calendar: calendar, now: now)
            periods.append(period)
            guard let nextDate = calendar.date(byAdding: .day, value: 7, to: period.startDate),
                  nextDate > date else { break }
            date = nextDate
        }

        return periods
    }

    static func yearInterval(for year: Int, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? calendar.date(byAdding: .year, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    static func previousWeek(before week: WeekPeriod, calendar: Calendar = .current, now: Date = .now) -> WeekPeriod {
        let date = calendar.date(byAdding: .day, value: -1, to: week.startDate) ?? week.startDate
        return getWeekPeriod(for: date, calendar: calendar, now: now)
    }

    static func nextWeek(after week: WeekPeriod, calendar: Calendar = .current, now: Date = .now) -> WeekPeriod {
        let date = calendar.date(byAdding: .day, value: 7, to: week.startDate) ?? week.startDate
        return getWeekPeriod(for: date, calendar: calendar, now: now)
    }

    static func fetchEnd(for week: WeekPeriod, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: week.endDate) ?? week.endDate
    }

    static func contains(_ date: Date, in week: WeekPeriod, calendar: Calendar = .current) -> Bool {
        date >= week.startDate && date < fetchEnd(for: week, calendar: calendar)
    }

    private static func startOfYear(for date: Date, calendar: Calendar) -> Date {
        let year = calendar.component(.year, from: date)
        return calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? calendar.startOfDay(for: date)
    }

    private static func endOfYear(for date: Date, calendar: Calendar) -> Date {
        let year = calendar.component(.year, from: date)
        return calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? calendar.startOfDay(for: date)
    }
}
