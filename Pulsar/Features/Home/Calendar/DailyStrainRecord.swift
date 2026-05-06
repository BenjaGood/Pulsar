//
//  DailyStrainRecord.swift
//  Pulsar
//

import Foundation

struct DailyStrainRecord: Identifiable, Hashable, Codable {
    var id: Date { Calendar.current.startOfDay(for: date) }
    var date: Date
    var strainScore: Int
    var workoutMinutes: Int
    var steps: Int
    var activeEnergyKilocalories: Int
    var confidence: ConfidenceGrade
    var sourceName: String
    var syncedAt: Date

    nonisolated init(
        date: Date,
        strainScore: Int,
        workoutMinutes: Int,
        steps: Int,
        activeEnergyKilocalories: Int,
        confidence: ConfidenceGrade,
        sourceName: String,
        syncedAt: Date = Date()
    ) {
        self.date = date
        self.strainScore = min(100, max(0, strainScore))
        self.workoutMinutes = max(0, workoutMinutes)
        self.steps = max(0, steps)
        self.activeEnergyKilocalories = max(0, activeEnergyKilocalories)
        self.confidence = confidence
        self.sourceName = sourceName
        self.syncedAt = syncedAt
    }

    var normalizedScore: Double {
        min(1, max(0, Double(strainScore) / 100))
    }

    var intensity: StrainIntensity {
        switch strainScore {
        case 1..<35: .low
        case 35..<70: .moderate
        case 70...100: .high
        default: .none
        }
    }
}

enum StrainIntensity: String, Codable {
    case none
    case low
    case moderate
    case high
}

enum MockStrainCalendarData {
    nonisolated static func runtimePlaceholderRecords(firstLaunchDate: Date, today: Date = Date(), calendar: Calendar = .current) -> [DailyStrainRecord] {
        // Runtime placeholder data must never imply history before install or after today.
        let start = calendar.startOfDay(for: firstLaunchDate)
        let end = calendar.startOfDay(for: today)
        guard start < end else { return [] }

        let recentOffsets = [3, 2, 1]
        return recentOffsets.compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: end), date >= start else { return nil }
            return record(on: date, seed: calendar.component(.day, from: date), calendar: calendar)
        }
    }

    nonisolated static func previewRecords(around date: Date = .now, calendar: Calendar = .current) -> [DailyStrainRecord] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date),
               let range = calendar.range(of: .day, in: .month, for: date) else { return [] }

        return range.compactMap { day -> DailyStrainRecord? in
            guard day % 4 != 0,
                   let recordDate = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) else { return nil }
            return record(on: recordDate, seed: day, calendar: calendar)
        }
    }

    nonisolated private static func record(on date: Date, seed: Int, calendar: Calendar) -> DailyStrainRecord {
        let score = min(96, max(12, (seed * 11 + 23) % 101))
        return DailyStrainRecord(
            date: calendar.startOfDay(for: date),
            strainScore: score,
            workoutMinutes: score > 65 ? 62 + seed % 20 : score > 35 ? 34 + seed % 16 : 12 + seed % 10,
            steps: 4_500 + seed * 347,
            activeEnergyKilocalories: 220 + score * 7,
            confidence: score > 70 ? .high : .moderate,
            sourceName: seed % 3 == 0 ? "Apple Watch" : "HealthKit"
        )
    }
}
