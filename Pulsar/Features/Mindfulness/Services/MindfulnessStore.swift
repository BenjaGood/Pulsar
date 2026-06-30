//
//  MindfulnessStore.swift
//  Pulsar
//

import Combine
import Foundation
import UIKit

@MainActor
final class PulsarMindfulnessStore: ObservableObject {
    @Published private(set) var state: PulsarMindfulnessState
    @Published private(set) var lastPersistenceError: String?

    private let fileStore: PulsarMindfulnessFileStore
    private let insightsEngine: PulsarMindfulnessInsightsEngine
    private let calendar: Calendar

    init(
        fileStore: PulsarMindfulnessFileStore? = nil,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        self.fileStore = fileStore ?? PulsarMindfulnessFileStore()
        self.calendar = calendar
        self.insightsEngine = PulsarMindfulnessInsightsEngine(calendar: calendar)
        let persisted = self.fileStore.load()
        self.state = PulsarMindfulnessState(
            entries: persisted.entries,
            sessions: persisted.sessions,
            dashboard: insightsEngine.dashboard(entries: persisted.entries, sessions: persisted.sessions, now: now)
        )
    }

    var dashboard: PulsarMindfulnessDashboard {
        state.dashboard
    }

    func reload(now: Date = Date()) {
        let persisted = fileStore.load()
        updateState(entries: persisted.entries, sessions: persisted.sessions, now: now)
    }

    func entry(on date: Date = Date()) -> PulsarDailyJournalEntry? {
        state.entries.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    func hasEntry(on date: Date = Date()) -> Bool {
        entry(on: date) != nil
    }

    func draft(for date: Date = Date()) -> PulsarDailyJournalDraft {
        if let entry = entry(on: date) {
            return PulsarDailyJournalDraft(entry: entry)
        }
        return PulsarDailyJournalDraft(date: date)
    }

    func draftForToday(now: Date = Date()) -> PulsarDailyJournalDraft {
        draft(for: now)
    }

    @discardableResult
    func saveCheckIn(
        _ draft: PulsarDailyJournalDraft,
        now: Date = Date(),
        playsHaptic: Bool = true
    ) -> PulsarDailyJournalEntry {
        let entry = draft.entry(now: now)
        var entries = state.entries
        entries.removeAll { existing in
            existing.id == entry.id || calendar.isDate(existing.date, inSameDayAs: entry.date)
        }
        entries.insert(entry, at: 0)
        updateState(entries: entries, sessions: state.sessions, now: now)
        persist()
        if playsHaptic {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        return entry
    }

    @discardableResult
    func saveSession(_ summary: PulsarMindfulnessSessionSummary, now: Date = Date()) -> PulsarMindfulnessSessionSummary {
        var sessions = state.sessions
        sessions.removeAll { existing in
            existing.id == summary.id ||
                (
                    existing.healthKitSampleID != nil &&
                    existing.healthKitSampleID == summary.healthKitSampleID
                )
        }
        sessions.insert(summary, at: 0)
        updateState(entries: state.entries, sessions: sessions, now: now)
        persist()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        return summary
    }

    func deleteEntry(_ entry: PulsarDailyJournalEntry, now: Date = Date()) {
        let entries = state.entries.filter { $0.id != entry.id }
        updateState(entries: entries, sessions: state.sessions, now: now)
        persist()
    }

    func deleteSession(_ session: PulsarMindfulnessSessionSummary, now: Date = Date()) {
        let sessions = state.sessions.filter { $0.id != session.id }
        updateState(entries: state.entries, sessions: sessions, now: now)
        persist()
    }

    private func updateState(
        entries: [PulsarDailyJournalEntry],
        sessions: [PulsarMindfulnessSessionSummary],
        now: Date
    ) {
        let sortedEntries = entries.sorted { $0.date > $1.date }
        let sortedSessions = sessions.sorted { $0.startedAt > $1.startedAt }
        state = PulsarMindfulnessState(
            entries: sortedEntries,
            sessions: sortedSessions,
            dashboard: insightsEngine.dashboard(entries: sortedEntries, sessions: sortedSessions, now: now)
        )
    }

    private func persist() {
        do {
            try fileStore.save(
                PulsarMindfulnessPersistedState(
                    version: 1,
                    entries: state.entries,
                    sessions: state.sessions
                )
            )
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = "Mindfulness data could not be saved locally."
        }
    }
}
