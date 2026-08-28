//
//  MindfulnessHistoryPreviewData.swift
//  Pulsar
//

import Foundation

enum MindfulnessHistoryPreviewData {
    static let august2026 = date(day: 1, hour: 12)
    static let selectedDate = date(day: 17, hour: 9, minute: 41)

    static let entries: [PulsarDailyJournalEntry] = [
        PulsarDailyJournalEntry(
            date: selectedDate,
            valence: 0.35,
            energy: 0.75,
            stress: 0.25,
            gratitude: 1,
            anxiety: 0.25,
            socialConnection: 0.75,
            productivity: 0.75,
            sleepPerception: 0.70,
            emotionLabels: [.calm],
            createdAt: selectedDate,
            updatedAt: selectedDate
        ),
        PulsarDailyJournalEntry(
            date: date(day: 10, hour: 20),
            valence: 0.76,
            energy: 0.86,
            stress: 0.18,
            gratitude: 0.90,
            anxiety: 0.12,
            socialConnection: 0.82,
            productivity: 0.72,
            sleepPerception: 0.78,
            emotionLabels: [.content]
        ),
        PulsarDailyJournalEntry(
            date: date(day: 24, hour: 18),
            valence: 0.12,
            energy: 0.48,
            stress: 0.52,
            gratitude: 0.62,
            anxiety: 0.46,
            socialConnection: 0.58,
            productivity: 0.54,
            sleepPerception: 0.60,
            emotionLabels: []
        )
    ]

    private static func date(
        day: Int,
        hour: Int,
        minute: Int = 0
    ) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(
                timeZone: TimeZone(secondsFromGMT: 0),
                year: 2026,
                month: 8,
                day: day,
                hour: hour,
                minute: minute
            )
        ) ?? Date(timeIntervalSince1970: 0)
    }
}
