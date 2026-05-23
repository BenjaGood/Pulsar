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

struct FitnessWeekRange: Hashable {
    var startOfWeekMonday: Date
    var endOfWeekSunday: Date
    var endExclusive: Date

    var interval: DateInterval {
        DateInterval(start: startOfWeekMonday, end: endExclusive)
    }

    func contains(_ date: Date) -> Bool {
        date >= startOfWeekMonday && date < endExclusive
    }
}

struct WeeklyActivity: Identifiable, Hashable {
    var id: String
    var pulsarWorkoutSessionId: UUID? = nil
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
    var sourceDeviceName: String? = nil
    var trainingType: String? = nil
    var route: [PulsarRunCoordinate] = []
    var splits: [FitnessWorkoutSplit] = []
    var notes: [String] = []
    var metadata: [FitnessWorkoutMetadataItem] = []
    var completedSets: Int? = nil
    var totalSets: Int? = nil
    var mainMuscleGroups: [String] = []
    var muscleLoadByMatrixGroup: [MuscleMatrixGroup: Double] = [:]
    var muscleExercisesByMatrixGroup: [MuscleMatrixGroup: [String]] = [:]

    var durationMinutes: Double { max(0, duration / 60) }

    var effectiveSourceDeviceName: String {
        let trimmed = sourceDeviceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? sourceName : trimmed
    }

    var isRouteWorkout: Bool {
        category.isRouteTraining || !(route.isEmpty && (distanceMeters ?? 0) <= 0)
    }
}

struct FitnessWorkoutSplit: Identifiable, Hashable {
    var id: Int { index }
    var index: Int
    var distanceMeters: Double
    var movingTime: TimeInterval
    var paceSecondsPerKilometer: Double?
    var averageHeartRate: Double?
}

struct FitnessWorkoutMetadataItem: Identifiable, Hashable {
    var id: String { "\(title)-\(value)" }
    var title: String
    var value: String
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

    var isCardioTraining: Bool {
        switch self {
        case .running, .walking, .hiking, .cycling, .hiit, .swimming, .rowing, .dance:
            return true
        case .strength, .gym, .yoga, .recovery, .other:
            return false
        }
    }

    var isRouteTraining: Bool {
        switch self {
        case .running, .walking, .hiking, .cycling:
            return true
        case .strength, .gym, .hiit, .yoga, .swimming, .rowing, .dance, .recovery, .other:
            return false
        }
    }

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
        let calendar = fitnessCalendar(from: calendar)
        return max(1, calendar.component(.weekOfYear, from: date))
    }

    static func getCurrentFitnessWeekRange(now: Date = .now, calendar: Calendar = .current) -> FitnessWeekRange {
        getFitnessWeekRange(for: now, calendar: calendar)
    }

    static func isDateInCurrentFitnessWeek(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        getCurrentFitnessWeekRange(now: now, calendar: calendar).contains(date)
    }

    static func getFitnessWeekRange(for date: Date, calendar: Calendar = .current) -> FitnessWeekRange {
        let calendar = fitnessCalendar(from: calendar)
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let daysSinceMonday = (weekday + 5) % 7
        let start = calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
        let endExclusive = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
        let endSunday = calendar.date(byAdding: .second, value: -1, to: endExclusive) ?? endExclusive.addingTimeInterval(-1)

        return FitnessWeekRange(
            startOfWeekMonday: start,
            endOfWeekSunday: endSunday,
            endExclusive: endExclusive
        )
    }

    static func getWeekPeriod(for date: Date, calendar: Calendar = .current, now: Date = .now, hasWorkout: Bool = false) -> WeekPeriod {
        let calendar = fitnessCalendar(from: calendar)
        let range = getFitnessWeekRange(for: date, calendar: calendar)
        let weekComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let weekNumber = max(1, weekComponents.weekOfYear ?? getCustomWeekNumber(for: date, calendar: calendar))
        let year = weekComponents.yearForWeekOfYear ?? calendar.component(.year, from: range.startOfWeekMonday)
        let currentRange = getCurrentFitnessWeekRange(now: now, calendar: calendar)

        return WeekPeriod(
            weekNumber: weekNumber,
            year: year,
            startDate: range.startOfWeekMonday,
            endDate: range.endOfWeekSunday,
            isCurrentWeek: range.startOfWeekMonday == currentRange.startOfWeekMonday,
            hasWorkout: hasWorkout
        )
    }

    static func getWeekPeriodsAroundCurrentWeek(pastWeeks: Int = 14, futureWeeks: Int = 0, calendar: Calendar = .current, now: Date = .now) -> [WeekPeriod] {
        let calendar = fitnessCalendar(from: calendar)
        let current = getWeekPeriod(for: now, calendar: calendar, now: now)
        let firstStart = calendar.date(byAdding: .day, value: -7 * pastWeeks, to: current.startDate) ?? current.startDate
        let total = pastWeeks + futureWeeks + 1

        return (0..<total).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset * 7, to: firstStart) else { return nil }
            return getWeekPeriod(for: date, calendar: calendar, now: now)
        }
    }

    static func getWeekPeriods(forYear year: Int, calendar: Calendar = .current, now: Date = .now) -> [WeekPeriod] {
        let calendar = fitnessCalendar(from: calendar)
        let interval = yearInterval(for: year, calendar: calendar)
        let finalDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.start
        var date = getWeekPeriod(for: interval.start, calendar: calendar, now: now).startDate
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
        let calendar = fitnessCalendar(from: calendar)
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? calendar.date(byAdding: .year, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    static func previousWeek(before week: WeekPeriod, calendar: Calendar = .current, now: Date = .now) -> WeekPeriod {
        let calendar = fitnessCalendar(from: calendar)
        let date = calendar.date(byAdding: .day, value: -7, to: week.startDate) ?? week.startDate
        return getWeekPeriod(for: date, calendar: calendar, now: now)
    }

    static func nextWeek(after week: WeekPeriod, calendar: Calendar = .current, now: Date = .now) -> WeekPeriod {
        let calendar = fitnessCalendar(from: calendar)
        let date = calendar.date(byAdding: .day, value: 7, to: week.startDate) ?? week.startDate
        return getWeekPeriod(for: date, calendar: calendar, now: now)
    }

    static func fetchEnd(for week: WeekPeriod, calendar: Calendar = .current) -> Date {
        let calendar = fitnessCalendar(from: calendar)
        return getFitnessWeekRange(for: week.startDate, calendar: calendar).endExclusive
    }

    static func contains(_ date: Date, in week: WeekPeriod, calendar: Calendar = .current) -> Bool {
        getFitnessWeekRange(for: week.startDate, calendar: calendar).contains(date)
    }

    static func fitnessCalendar(from calendar: Calendar = .current) -> Calendar {
        var fitnessCalendar = Calendar(identifier: .gregorian)
        fitnessCalendar.locale = calendar.locale
        fitnessCalendar.timeZone = calendar.timeZone
        fitnessCalendar.firstWeekday = 2
        fitnessCalendar.minimumDaysInFirstWeek = 1
        return fitnessCalendar
    }
}
