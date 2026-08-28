//
//  MindfulnessEmotion.swift
//  Pulsar
//

import Foundation

enum MindfulnessEmotion: String, CaseIterable, Identifiable {
    case calm
    case happy
    case neutral
    case anxious
    case stressed
    case sad

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var valence: Double {
        switch self {
        case .calm: 0.35
        case .happy: 0.82
        case .neutral: 0
        case .anxious: -0.28
        case .stressed: -0.58
        case .sad: -0.84
        }
    }

    var persistedLabel: PulsarJournalEmotionLabel? {
        switch self {
        case .calm: .calm
        case .happy: .content
        case .neutral: nil
        case .anxious: .anxious
        case .stressed: .stressed
        case .sad: .sad
        }
    }

    func apply(to draft: inout PulsarDailyJournalDraft) {
        draft.valence = valence
        draft.emotionLabels = persistedLabel.map { [$0] } ?? []
    }

    static func selected(in draft: PulsarDailyJournalDraft) -> MindfulnessEmotion {
        selected(labels: draft.emotionLabels, valence: draft.valence)
    }

    static func selected(in entry: PulsarDailyJournalEntry) -> MindfulnessEmotion {
        selected(labels: Set(entry.emotionLabels), valence: entry.valence)
    }

    private static func selected(
        labels: Set<PulsarJournalEmotionLabel>,
        valence: Double
    ) -> MindfulnessEmotion {
        if labels.contains(.calm) { return .calm }
        if !labels.isDisjoint(with: [.content, .hopeful, .energized]) { return .happy }
        if labels.contains(.anxious) { return .anxious }
        if !labels.isDisjoint(with: [.stressed, .overwhelmed]) { return .stressed }
        if !labels.isDisjoint(with: [.sad, .lonely]) { return .sad }

        return switch valence {
        case 0.58...: .happy
        case 0.16..<0.58: .calm
        case -0.14..<0.16: .neutral
        case -0.40 ..< -0.14: .anxious
        case -0.70 ..< -0.40: .stressed
        default: .sad
        }
    }
}
