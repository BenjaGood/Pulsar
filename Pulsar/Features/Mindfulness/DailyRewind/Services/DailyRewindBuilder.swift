//
//  DailyRewindBuilder.swift
//  Pulsar
//

import Foundation

struct DailyRewindBuilder {
    var calendar: Calendar = .current

    func build(
        date: Date = Date(),
        dashboard: HomeDashboard,
        mindfulness state: PulsarMindfulnessState,
        generatedAt: Date = Date()
    ) -> PulsarDailyRewind {
        let dayInterval = interval(for: date)
        let todayEntry = state.entries.first { calendar.isDate($0.date, inSameDayAs: date) }
        let sessions = state.sessions.filter { dayInterval.contains($0.startedAt) }
        let mindfulMinutes = sessions.reduce(0) { $0 + $1.duration / 60 }
        let workouts = dashboard.strain.workouts.filter { dayInterval.contains($0.startDate) }
        let workoutMinutes = workouts.reduce(0) { $0 + $1.durationMinutes }
        let stressScore = dashboard.stress.dailyAverageScore ?? dashboard.stress.score
        let hrv = dashboard.recovery.hrvSDNN ?? dashboard.strain.hrvSDNNMilliseconds ?? dashboard.stress.lastHRV
        let sleepMinutes = dashboard.sleep.totalSleepMinutes

        let cards = makeCards(
            dashboard: dashboard,
            entry: todayEntry,
            mindfulMinutes: mindfulMinutes,
            sessionCount: sessions.count,
            workoutCount: workouts.count,
            workoutMinutes: workoutMinutes,
            stressScore: stressScore,
            hrv: hrv,
            sleepMinutes: sleepMinutes
        )
        let highlights = makeHighlights(cards: cards, hrv: hrv, sleepMinutes: sleepMinutes)
        let availability = availability(for: dashboard, entry: todayEntry, mindfulMinutes: mindfulMinutes, highlights: highlights)

        return PulsarDailyRewind(
            date: date,
            dateKey: DailyRewindDateKey.string(for: date, calendar: calendar),
            availability: availability,
            headline: headline(entry: todayEntry, availability: availability),
            subtitle: subtitle(for: dashboard, entry: todayEntry, mindfulMinutes: mindfulMinutes),
            highlights: highlights,
            cards: cards,
            insight: insight(
                dashboard: dashboard,
                mindfulness: state.dashboard,
                entry: todayEntry,
                mindfulMinutes: mindfulMinutes,
                workoutCount: workouts.count,
                stressScore: stressScore
            ),
            generatedAt: generatedAt
        )
    }

    private func makeCards(
        dashboard: HomeDashboard,
        entry: PulsarDailyJournalEntry?,
        mindfulMinutes: Double,
        sessionCount: Int,
        workoutCount: Int,
        workoutMinutes: Double,
        stressScore: Int?,
        hrv: Double?,
        sleepMinutes: Double
    ) -> [DailyRewindCard] {
        [
            movementCard(dashboard: dashboard, workoutCount: workoutCount, workoutMinutes: workoutMinutes),
            recoveryCard(dashboard: dashboard, hrv: hrv, sleepMinutes: sleepMinutes),
            mindfulnessCard(entry: entry, mindfulMinutes: mindfulMinutes, sessionCount: sessionCount),
            stressCard(dashboard: dashboard, stressScore: stressScore, entry: entry),
            energyCard(dashboard: dashboard, entry: entry),
            reflectionCard(entry: entry)
        ]
    }

    private func movementCard(
        dashboard: HomeDashboard,
        workoutCount: Int,
        workoutMinutes: Double
    ) -> DailyRewindCard {
        let steps = dashboard.strain.steps
        let activeEnergy = dashboard.strain.activeEnergyKilocalories
        let hasMovement = steps > 0 || workoutCount > 0 || activeEnergy != nil
        let subtitle: String
        if workoutCount > 0 {
            subtitle = "\(workoutCount) workout\(workoutCount == 1 ? "" : "s") · \(Int(workoutMinutes.rounded())) min"
        } else if let activeEnergy {
            subtitle = "\(Int(activeEnergy.rounded())) active cal"
        } else {
            subtitle = "Movement appears here when Health data is available"
        }

        return DailyRewindCard(
            kind: .movement,
            title: "Movement",
            value: steps > 0 ? "\(steps.formatted()) steps" : "No steps yet",
            subtitle: subtitle,
            symbolName: "figure.walk",
            tint: .green,
            state: hasMovement ? .ready : .placeholder
        )
    }

    private func recoveryCard(
        dashboard: HomeDashboard,
        hrv: Double?,
        sleepMinutes: Double
    ) -> DailyRewindCard {
        let hasRecovery = dashboard.recovery.analyzedSampleCount > 0 || dashboard.recovery.score > 0 || hrv != nil || sleepMinutes > 0
        let value = dashboard.recovery.score > 0 ? "\(dashboard.recovery.score)" : "Building"
        let subtitle: String
        if let hrv {
            subtitle = "HRV \(Int(hrv.rounded())) ms"
        } else if sleepMinutes > 0 {
            subtitle = "\(formatMinutes(sleepMinutes)) asleep"
        } else {
            subtitle = "Recovery context needs overnight signals"
        }

        return DailyRewindCard(
            kind: .recovery,
            title: "Recovery",
            value: value,
            subtitle: subtitle,
            symbolName: "arrow.clockwise.heart.fill",
            tint: .teal,
            state: hasRecovery ? .ready : .placeholder
        )
    }

    private func mindfulnessCard(
        entry: PulsarDailyJournalEntry?,
        mindfulMinutes: Double,
        sessionCount: Int
    ) -> DailyRewindCard {
        let hasMindfulness = mindfulMinutes > 0 || entry != nil
        let value = mindfulMinutes > 0 ? "\(Int(mindfulMinutes.rounded())) min" : (entry == nil ? "Open" : "Checked in")
        let subtitle: String
        if sessionCount > 0 {
            subtitle = "\(sessionCount) session\(sessionCount == 1 ? "" : "s") completed today"
        } else if let entry {
            subtitle = "Mood logged as \(entry.moodTitle.lowercased())"
        } else {
            subtitle = "Breathing and meditation sessions will land here"
        }

        return DailyRewindCard(
            kind: .mindfulness,
            title: "Mindfulness",
            value: value,
            subtitle: subtitle,
            symbolName: "figure.mind.and.body",
            tint: .blue,
            state: hasMindfulness ? .ready : .placeholder
        )
    }

    private func stressCard(
        dashboard: HomeDashboard,
        stressScore: Int?,
        entry: PulsarDailyJournalEntry?
    ) -> DailyRewindCard {
        let value: String
        let state: DailyRewindDataState
        if let stressScore {
            value = "\(stressScore)"
            state = .ready
        } else if let entry {
            value = "\(Int((entry.stress * 100).rounded()))"
            state = .ready
        } else {
            value = "No signal"
            state = .placeholder
        }

        return DailyRewindCard(
            kind: .stress,
            title: "Stress",
            value: value,
            subtitle: dashboard.stress.level?.rawValue ?? "Journal stress can fill this in tonight",
            symbolName: "waveform.path.ecg",
            tint: .pink,
            state: state
        )
    }

    private func energyCard(
        dashboard: HomeDashboard,
        entry: PulsarDailyJournalEntry?
    ) -> DailyRewindCard {
        if let activeEnergy = dashboard.strain.activeEnergyKilocalories {
            return DailyRewindCard(
                kind: .energy,
                title: "Energy",
                value: "\(Int(activeEnergy.rounded())) cal",
                subtitle: "Active energy from Health",
                symbolName: "bolt.fill",
                tint: .orange,
                state: .ready
            )
        }

        if let entry {
            return DailyRewindCard(
                kind: .energy,
                title: "Energy",
                value: "\(Int((entry.energy * 100).rounded()))",
                subtitle: "Logged from today’s check-in",
                symbolName: "bolt.fill",
                tint: .orange,
                state: .ready
            )
        }

        return DailyRewindCard(
            kind: .energy,
            title: "Energy",
            value: "Not set",
            subtitle: "Add a check-in to capture perceived energy",
            symbolName: "bolt.fill",
            tint: .orange,
            state: .placeholder
        )
    }

    private func reflectionCard(entry: PulsarDailyJournalEntry?) -> DailyRewindCard {
        guard let entry else {
            return DailyRewindCard(
                kind: .reflection,
                title: "Reflection",
                value: "Ready",
                subtitle: "Before the day ends, how did you feel today?",
                symbolName: "square.and.pencil",
                tint: .purple,
                state: .placeholder
            )
        }

        let emotion = entry.emotionLabels.first?.title ?? entry.moodTitle
        return DailyRewindCard(
            kind: .reflection,
            title: "Reflection",
            value: entry.moodTitle,
            subtitle: "Today feels \(emotion.lowercased()).",
            symbolName: "checkmark.seal.fill",
            tint: .purple,
            state: .ready
        )
    }

    private func makeHighlights(
        cards: [DailyRewindCard],
        hrv: Double?,
        sleepMinutes: Double
    ) -> [DailyRewindHighlight] {
        var highlights = cards.map {
            DailyRewindHighlight(
                id: $0.kind.rawValue,
                title: $0.title,
                value: $0.value,
                caption: $0.subtitle,
                symbolName: $0.symbolName,
                tint: $0.tint,
                state: $0.state
            )
        }

        if let hrv {
            highlights.insert(
                DailyRewindHighlight(
                    id: "hrv",
                    title: "HRV",
                    value: "\(Int(hrv.rounded())) ms",
                    caption: "A small recovery signal from your day",
                    symbolName: "heart.text.square.fill",
                    tint: .teal,
                    state: .ready
                ),
                at: min(2, highlights.count)
            )
        }

        if sleepMinutes > 0 {
            highlights.insert(
                DailyRewindHighlight(
                    id: "sleep",
                    title: "Sleep context",
                    value: formatMinutes(sleepMinutes),
                    caption: "Last night’s rest shaped today’s recovery",
                    symbolName: "moon.zzz.fill",
                    tint: .indigo,
                    state: .ready
                ),
                at: min(3, highlights.count)
            )
        }

        return Array(highlights.prefix(7))
    }

    private func availability(
        for dashboard: HomeDashboard,
        entry: PulsarDailyJournalEntry?,
        mindfulMinutes: Double,
        highlights: [DailyRewindHighlight]
    ) -> DailyRewindAvailability {
        let readyCount = highlights.filter { $0.state == .ready }.count
        guard readyCount > 0 else { return .noData }
        if dashboard.usingSampleData || entry != nil || mindfulMinutes > 0 || readyCount >= 3 {
            return .ready
        }
        return .partial
    }

    private func headline(entry: PulsarDailyJournalEntry?, availability: DailyRewindAvailability) -> String {
        if let entry {
            return "Your day feels \(entry.moodTitle.lowercased())"
        }

        switch availability {
        case .ready, .partial:
            return "Time to rewind your day"
        case .noData:
            return "A quiet rewind is ready"
        }
    }

    private func subtitle(
        for dashboard: HomeDashboard,
        entry: PulsarDailyJournalEntry?,
        mindfulMinutes: Double
    ) -> String {
        if entry != nil {
            return "Movement, recovery, and reflection are folded into one calm close."
        }
        if mindfulMinutes > 0 {
            return "Your mindfulness work is already part of tonight’s reflection."
        }
        if dashboard.strain.steps > 0 || dashboard.recovery.score > 0 || dashboard.stress.score != nil {
            return "Review movement, recovery, and mindfulness before closing the day."
        }
        return "Start with a simple check-in and Pulsar will connect more signals over time."
    }

    private func insight(
        dashboard: HomeDashboard,
        mindfulness: PulsarMindfulnessDashboard,
        entry: PulsarDailyJournalEntry?,
        mindfulMinutes: Double,
        workoutCount: Int,
        stressScore: Int?
    ) -> DailyRewindInsight {
        if let insight = mindfulness.insights.first {
            return DailyRewindInsight(
                title: insight.title,
                body: insight.body,
                evidence: insight.evidence,
                symbolName: insight.symbolName,
                tint: tint(for: insight.tint)
            )
        }

        if let stressScore, stressScore >= 70 {
            return DailyRewindInsight(
                title: "Stress asked for a softer landing",
                body: "Tonight is a good moment for a short breathing reset before sleep.",
                evidence: "Stress score \(stressScore)",
                symbolName: "wind",
                tint: .pink
            )
        }

        if workoutCount > 0 {
            return DailyRewindInsight(
                title: "Movement gave the day structure",
                body: "Your activity is ready to compare with mood once tonight’s reflection is saved.",
                evidence: "\(workoutCount) workout\(workoutCount == 1 ? "" : "s") logged",
                symbolName: "figure.run",
                tint: .green
            )
        }

        if mindfulMinutes > 0 {
            return DailyRewindInsight(
                title: "Mindfulness is already in the day",
                body: "A short session can be enough signal for Pulsar to notice evening patterns.",
                evidence: "\(Int(mindfulMinutes.rounded())) mindful minutes",
                symbolName: "figure.mind.and.body",
                tint: .blue
            )
        }

        if let entry {
            return DailyRewindInsight(
                title: "Reflection completed the loop",
                body: "Pulsar will use this entry to make future emotional trends more personal.",
                evidence: "Mood logged as \(entry.moodTitle.lowercased())",
                symbolName: "checkmark.seal.fill",
                tint: .purple
            )
        }

        return DailyRewindInsight(
            title: "A simple check-in is enough",
            body: "Add how the day felt and Pulsar will begin connecting mood, stress, recovery, and movement.",
            evidence: "Waiting for tonight’s reflection",
            symbolName: "sparkles",
            tint: .indigo
        )
    }

    private func tint(for insightTint: PulsarMindfulnessInsightTint) -> DailyRewindTint {
        switch insightTint {
        case .calm: .blue
        case .focus: .teal
        case .recovery: .green
        case .amber: .orange
        }
    }

    private func interval(for date: Date) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 60 * 60)
        return DateInterval(start: start, end: end)
    }

    private func formatMinutes(_ minutes: Double) -> String {
        let rounded = Int(minutes.rounded())
        let hours = rounded / 60
        let remainingMinutes = rounded % 60
        if hours > 0 {
            return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
        }
        return "\(rounded) min"
    }
}
