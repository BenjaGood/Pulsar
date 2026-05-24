//
//  MindfulnessInsightsEngine.swift
//  Pulsar
//

import Foundation

struct PulsarMindfulnessInsightsEngine {
    var calendar: Calendar = .current

    func dashboard(
        entries: [PulsarDailyJournalEntry],
        sessions: [PulsarMindfulnessSessionSummary],
        now: Date = Date()
    ) -> PulsarMindfulnessDashboard {
        let today = calendar.startOfDay(for: now)
        let recentEntries = entries.sorted { $0.date > $1.date }
        let recentSessions = sessions.sorted { $0.startedAt > $1.startedAt }
        let todayEntry = recentEntries.first { calendar.isDate($0.date, inSameDayAs: today) }
        let trend = trendPoints(entries: entries, sessions: sessions, endingAt: today, dayCount: 7)
        let weeklyMindfulMinutes = trend.reduce(0) { $0 + $1.mindfulMinutes }

        return PulsarMindfulnessDashboard(
            todayEntry: todayEntry,
            latestSession: recentSessions.first,
            streak: streakSummary(entries: entries, now: now),
            trend: trend,
            insights: insights(entries: entries, sessions: sessions, trend: trend),
            weeklyMindfulMinutes: weeklyMindfulMinutes
        )
    }

    func trendPoints(
        entries: [PulsarDailyJournalEntry],
        sessions: [PulsarMindfulnessSessionSummary],
        endingAt endDate: Date,
        dayCount: Int
    ) -> [PulsarMindfulnessTrendPoint] {
        let days = (0..<max(dayCount, 1)).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: endDate))
        }

        return days.map { day in
            let key = Self.dateKey(for: day, calendar: calendar)
            let dayEntries = entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
            let daySessions = sessions.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
            let valence = dayEntries.isEmpty ? nil : average(dayEntries.map(\.valence))
            let minutes = daySessions.reduce(0) { $0 + ($1.duration / 60) }
            return PulsarMindfulnessTrendPoint(
                date: day,
                dateKey: key,
                valence: valence,
                mindfulMinutes: minutes,
                hasCheckIn: !dayEntries.isEmpty
            )
        }
    }

    func streakSummary(entries: [PulsarDailyJournalEntry], now: Date = Date()) -> PulsarMindfulnessStreakSummary {
        let daysWithEntries = Set(entries.map { Self.dateKey(for: $0.date, calendar: calendar) })
        let today = calendar.startOfDay(for: now)
        let hasToday = daysWithEntries.contains(Self.dateKey(for: today, calendar: calendar))
        let lastEntryDate = entries.map(\.date).max()

        var currentStreak = 0
        var cursor = hasToday ? today : calendar.date(byAdding: .day, value: -1, to: today) ?? today

        while daysWithEntries.contains(Self.dateKey(for: cursor, calendar: calendar)) {
            currentStreak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        let sortedKeys = daysWithEntries.sorted()
        var longest = 0
        var run = 0
        var previousDate: Date?

        for key in sortedKeys {
            guard let date = Self.date(from: key, calendar: calendar) else { continue }
            if let previousDate,
               calendar.dateComponents([.day], from: previousDate, to: date).day == 1 {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previousDate = date
        }

        return PulsarMindfulnessStreakSummary(
            currentStreak: currentStreak,
            longestStreak: longest,
            hasToday: hasToday,
            lastEntryDate: lastEntryDate
        )
    }

    func insights(
        entries: [PulsarDailyJournalEntry],
        sessions: [PulsarMindfulnessSessionSummary],
        trend: [PulsarMindfulnessTrendPoint]
    ) -> [PulsarEmotionalInsight] {
        let sortedEntries = entries.sorted { $0.date > $1.date }
        let recentEntries = Array(sortedEntries.prefix(14))
        let recentSessions = sessions.filter { session in
            guard let oldestTrendDate = trend.first?.date else { return true }
            return session.startedAt >= oldestTrendDate
        }

        if recentEntries.count < 3 && sessions.count < 2 {
            return [
                PulsarEmotionalInsight(
                    id: "learning-rhythm",
                    title: "Pulsar is learning your rhythm.",
                    body: "A few more check-ins will unlock clearer emotional patterns.",
                    evidence: "\(entries.count) check-ins saved",
                    confidence: 0.28,
                    sampleCount: entries.count,
                    symbolName: "sparkles",
                    tint: .focus
                )
            ]
        }

        var results: [PulsarEmotionalInsight] = []

        if !recentEntries.isEmpty {
            let averageValence = average(recentEntries.map(\.valence))
            let averageStress = average(recentEntries.map(\.stress))

            if averageValence >= 0.18 {
                results.append(
                    PulsarEmotionalInsight(
                        id: "steady-mood",
                        title: "Your mood has been steady lately.",
                        body: "Recent entries lean pleasant without sharp swings.",
                        evidence: "\(recentEntries.count) recent check-ins",
                        confidence: min(0.86, 0.42 + Double(recentEntries.count) * 0.04),
                        sampleCount: recentEntries.count,
                        symbolName: "sun.max.fill",
                        tint: .amber
                    )
                )
            } else if averageStress >= 0.62 {
                results.append(
                    PulsarEmotionalInsight(
                        id: "stress-visible",
                        title: "Stress is showing up in your reflections.",
                        body: "Long-exhale sessions may be useful on days that feel loaded.",
                        evidence: "\(Int((averageStress * 100).rounded()))% average stress signal",
                        confidence: min(0.82, 0.38 + Double(recentEntries.count) * 0.04),
                        sampleCount: recentEntries.count,
                        symbolName: "wind",
                        tint: .calm
                    )
                )
            }
        }

        if recentSessions.count >= 2 {
            let minutes = recentSessions.reduce(0) { $0 + $1.duration / 60 }
            results.append(
                PulsarEmotionalInsight(
                    id: "mindful-minutes",
                    title: "Mindful minutes are building a baseline.",
                    body: "Consistency matters more than session length here.",
                    evidence: "\(Int(minutes.rounded())) min across \(recentSessions.count) sessions",
                    confidence: min(0.88, 0.46 + Double(recentSessions.count) * 0.05),
                    sampleCount: recentSessions.count,
                    symbolName: "figure.mind.and.body",
                    tint: .recovery
                )
            )
        }

        if results.isEmpty {
            results.append(
                PulsarEmotionalInsight(
                    id: "no-reliable-pattern",
                    title: "No reliable pattern yet.",
                    body: "Pulsar will keep the signal quiet until there is enough data.",
                    evidence: "\(entries.count) check-ins, \(sessions.count) sessions",
                    confidence: 0.32,
                    sampleCount: entries.count + sessions.count,
                    symbolName: "chart.xyaxis.line",
                    tint: .focus
                )
            )
        }

        return Array(results.prefix(3))
    }

    static func dateKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func date(from key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
