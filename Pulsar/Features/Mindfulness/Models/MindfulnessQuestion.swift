//
//  MindfulnessQuestion.swift
//  Pulsar
//

import Foundation

enum MindfulnessQuestion: String, CaseIterable, Identifiable {
    case energy
    case stress
    case gratitude
    case anxiety
    case social
    case productivity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .energy: "Energy"
        case .stress: "Stress"
        case .gratitude: "Gratitude"
        case .anxiety: "Anxiety"
        case .social: "Social"
        case .productivity: "Productivity"
        }
    }

    var subtitle: String {
        switch self {
        case .energy: "How would you rate your energy right now?"
        case .stress: "How much stress are you carrying right now?"
        case .gratitude: "How connected do you feel to gratitude?"
        case .anxiety: "How present is anxiety for you right now?"
        case .social: "How connected do you feel to other people?"
        case .productivity: "How satisfied are you with your focus today?"
        }
    }

    var symbolName: String {
        switch self {
        case .energy: "bolt.fill"
        case .stress: "water.waves"
        case .gratitude: "heart"
        case .anxiety: "cloud"
        case .social: "person.2"
        case .productivity: "scope"
        }
    }

    var keyPath: WritableKeyPath<PulsarDailyJournalDraft, Double> {
        switch self {
        case .energy: \PulsarDailyJournalDraft.energy
        case .stress: \PulsarDailyJournalDraft.stress
        case .gratitude: \PulsarDailyJournalDraft.gratitude
        case .anxiety: \PulsarDailyJournalDraft.anxiety
        case .social: \PulsarDailyJournalDraft.socialConnection
        case .productivity: \PulsarDailyJournalDraft.productivity
        }
    }

    func rating(in draft: PulsarDailyJournalDraft) -> Double {
        let storedValue = min(max(draft[keyPath: keyPath], 0), 1)
        return Double(Int((storedValue * 4).rounded()) + 1)
    }

    func store(rating: Double, in draft: inout PulsarDailyJournalDraft) {
        let clampedRating = min(max(rating.rounded(), 1), 5)
        draft[keyPath: keyPath] = (clampedRating - 1) / 4
    }

    func rating(in entry: PulsarDailyJournalEntry) -> Int {
        let storedValue = switch self {
        case .energy: entry.energy
        case .stress: entry.stress
        case .gratitude: entry.gratitude
        case .anxiety: entry.anxiety
        case .social: entry.socialConnection
        case .productivity: entry.productivity
        }
        return Int((min(max(storedValue, 0), 1) * 4).rounded()) + 1
    }
}
