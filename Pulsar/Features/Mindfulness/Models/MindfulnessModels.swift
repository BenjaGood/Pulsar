//
//  MindfulnessModels.swift
//  Pulsar
//

import Foundation
import SwiftUI

enum PulsarMindfulnessCheckInKind: String, CaseIterable, Codable, Identifiable, Hashable {
    case dailyMood
    case momentaryEmotion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dailyMood: "Daily mood"
        case .momentaryEmotion: "Right now"
        }
    }
}

enum PulsarJournalEmotionLabel: String, CaseIterable, Codable, Identifiable, Hashable {
    case calm
    case grateful
    case hopeful
    case content
    case focused
    case energized
    case tired
    case anxious
    case stressed
    case lonely
    case sad
    case overwhelmed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calm: "Calm"
        case .grateful: "Grateful"
        case .hopeful: "Hopeful"
        case .content: "Content"
        case .focused: "Focused"
        case .energized: "Energized"
        case .tired: "Tired"
        case .anxious: "Anxious"
        case .stressed: "Stressed"
        case .lonely: "Lonely"
        case .sad: "Sad"
        case .overwhelmed: "Overwhelmed"
        }
    }

    var symbolName: String {
        switch self {
        case .calm: "water.waves"
        case .grateful: "sparkles"
        case .hopeful: "sun.max.fill"
        case .content: "leaf.fill"
        case .focused: "scope"
        case .energized: "bolt.fill"
        case .tired: "moon.zzz.fill"
        case .anxious: "waveform.path.ecg"
        case .stressed: "exclamationmark.triangle.fill"
        case .lonely: "person.fill.questionmark"
        case .sad: "cloud.rain.fill"
        case .overwhelmed: "tornado"
        }
    }
}

enum PulsarJournalAssociation: String, CaseIterable, Codable, Identifiable, Hashable {
    case sleep
    case movement
    case work
    case social
    case family
    case productivity
    case gratitude
    case recovery
    case nutrition
    case weather

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: "Sleep"
        case .movement: "Movement"
        case .work: "Work"
        case .social: "Social"
        case .family: "Family"
        case .productivity: "Productivity"
        case .gratitude: "Gratitude"
        case .recovery: "Recovery"
        case .nutrition: "Nutrition"
        case .weather: "Weather"
        }
    }

    var symbolName: String {
        switch self {
        case .sleep: "bed.double.fill"
        case .movement: "figure.walk"
        case .work: "laptopcomputer"
        case .social: "person.2.fill"
        case .family: "house.fill"
        case .productivity: "checkmark.circle.fill"
        case .gratitude: "heart.fill"
        case .recovery: "arrow.clockwise.heart.fill"
        case .nutrition: "fork.knife"
        case .weather: "cloud.sun.fill"
        }
    }
}

struct PulsarDailyJournalEntry: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var date: Date
    var kind: PulsarMindfulnessCheckInKind
    var valence: Double
    var energy: Double
    var stress: Double
    var gratitude: Double
    var anxiety: Double
    var socialConnection: Double
    var productivity: Double
    var sleepPerception: Double
    var emotionLabels: [PulsarJournalEmotionLabel]
    var associations: [PulsarJournalAssociation]
    var note: String?
    var prompt: String?
    var voiceNoteIdentifier: String?
    var healthKitSampleID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: PulsarMindfulnessCheckInKind = .dailyMood,
        valence: Double,
        energy: Double,
        stress: Double,
        gratitude: Double,
        anxiety: Double,
        socialConnection: Double,
        productivity: Double,
        sleepPerception: Double,
        emotionLabels: [PulsarJournalEmotionLabel] = [],
        associations: [PulsarJournalAssociation] = [],
        note: String? = nil,
        prompt: String? = nil,
        voiceNoteIdentifier: String? = nil,
        healthKitSampleID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.valence = Self.clamped(valence, range: -1...1)
        self.energy = Self.clamped01(energy)
        self.stress = Self.clamped01(stress)
        self.gratitude = Self.clamped01(gratitude)
        self.anxiety = Self.clamped01(anxiety)
        self.socialConnection = Self.clamped01(socialConnection)
        self.productivity = Self.clamped01(productivity)
        self.sleepPerception = Self.clamped01(sleepPerception)
        self.emotionLabels = emotionLabels
        self.associations = associations
        self.note = Self.trimmedNote(note)
        self.prompt = Self.trimmedNote(prompt)
        self.voiceNoteIdentifier = Self.trimmedNote(voiceNoteIdentifier)
        self.healthKitSampleID = healthKitSampleID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var moodTitle: String {
        switch valence {
        case 0.55...: "Bright"
        case 0.18..<0.55: "Steady"
        case -0.18..<0.18: "Neutral"
        case -0.55 ..< -0.18: "Heavy"
        default: "Low"
        }
    }

    private static func clamped01(_ value: Double) -> Double {
        clamped(value, range: 0...1)
    }

    private static func clamped(_ value: Double, range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func trimmedNote(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct PulsarDailyJournalDraft: Equatable {
    var id: UUID?
    var date: Date
    var kind: PulsarMindfulnessCheckInKind
    var valence: Double
    var energy: Double
    var stress: Double
    var gratitude: Double
    var anxiety: Double
    var socialConnection: Double
    var productivity: Double
    var sleepPerception: Double
    var emotionLabels: Set<PulsarJournalEmotionLabel>
    var associations: Set<PulsarJournalAssociation>
    var note: String
    var prompt: String?
    var createdAt: Date?

    init(date: Date = Date()) {
        self.id = nil
        self.date = date
        self.kind = .dailyMood
        self.valence = 0
        self.energy = 0.52
        self.stress = 0.35
        self.gratitude = 0.56
        self.anxiety = 0.28
        self.socialConnection = 0.50
        self.productivity = 0.50
        self.sleepPerception = 0.52
        self.emotionLabels = [.calm]
        self.associations = []
        self.note = ""
        self.prompt = PulsarMindfulnessContentLibrary.dailyPrompts.first
        self.createdAt = nil
    }

    init(entry: PulsarDailyJournalEntry) {
        self.id = entry.id
        self.date = entry.date
        self.kind = entry.kind
        self.valence = entry.valence
        self.energy = entry.energy
        self.stress = entry.stress
        self.gratitude = entry.gratitude
        self.anxiety = entry.anxiety
        self.socialConnection = entry.socialConnection
        self.productivity = entry.productivity
        self.sleepPerception = entry.sleepPerception
        self.emotionLabels = Set(entry.emotionLabels)
        self.associations = Set(entry.associations)
        self.note = entry.note ?? ""
        self.prompt = entry.prompt
        self.createdAt = entry.createdAt
    }

    func entry(now: Date = Date()) -> PulsarDailyJournalEntry {
        PulsarDailyJournalEntry(
            id: id ?? UUID(),
            date: date,
            kind: kind,
            valence: valence,
            energy: energy,
            stress: stress,
            gratitude: gratitude,
            anxiety: anxiety,
            socialConnection: socialConnection,
            productivity: productivity,
            sleepPerception: sleepPerception,
            emotionLabels: emotionLabels.sorted { $0.title < $1.title },
            associations: associations.sorted { $0.title < $1.title },
            note: note,
            prompt: prompt,
            createdAt: createdAt ?? now,
            updatedAt: now
        )
    }
}

enum PulsarMeditationCategory: String, CaseIterable, Codable, Identifiable, Hashable {
    case breathing
    case sleep
    case focus
    case anxietyRelief
    case recovery
    case deepRelaxation
    case morningReset
    case walking
    case sound
    case stressReduction

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breathing: "Breathing"
        case .sleep: "Sleep"
        case .focus: "Focus"
        case .anxietyRelief: "Anxiety relief"
        case .recovery: "Recovery"
        case .deepRelaxation: "Deep relaxation"
        case .morningReset: "Morning reset"
        case .walking: "Walking"
        case .sound: "Sound"
        case .stressReduction: "Stress reduction"
        }
    }

    var subtitle: String {
        switch self {
        case .breathing: "Paced breath and body settling."
        case .sleep: "Quiet descent for the end of day."
        case .focus: "Clear attention without intensity."
        case .anxietyRelief: "Long exhale, softer body."
        case .recovery: "Downshift after strain."
        case .deepRelaxation: "Wide, low stimulation rest."
        case .morningReset: "Calm energy before the day opens."
        case .walking: "Mindful movement, future Watch-ready."
        case .sound: "Ambient attention and tone."
        case .stressReduction: "Reset acute stress gently."
        }
    }

    var symbolName: String {
        switch self {
        case .breathing: "lungs.fill"
        case .sleep: "moon.zzz.fill"
        case .focus: "scope"
        case .anxietyRelief: "heart.text.square.fill"
        case .recovery: "arrow.clockwise.heart.fill"
        case .deepRelaxation: "water.waves"
        case .morningReset: "sunrise.fill"
        case .walking: "figure.walk"
        case .sound: "waveform"
        case .stressReduction: "wind"
        }
    }

    var accent: Color {
        switch self {
        case .breathing: Color(red: 0.34, green: 0.72, blue: 1.00)
        case .sleep: Color(red: 0.55, green: 0.62, blue: 0.98)
        case .focus: Color(red: 0.48, green: 0.78, blue: 0.86)
        case .anxietyRelief: Color(red: 0.86, green: 0.68, blue: 1.00)
        case .recovery: Color(red: 0.52, green: 0.82, blue: 0.62)
        case .deepRelaxation: Color(red: 0.38, green: 0.82, blue: 0.76)
        case .morningReset: Color(red: 1.00, green: 0.68, blue: 0.38)
        case .walking: Color(red: 0.56, green: 0.78, blue: 0.44)
        case .sound: Color(red: 0.78, green: 0.70, blue: 1.00)
        case .stressReduction: Color(red: 0.42, green: 0.74, blue: 0.96)
        }
    }
}

enum PulsarBreathingPreset: String, CaseIterable, Codable, Identifiable, Hashable {
    case box
    case relaxation
    case sleep
    case energizing
    case anxietyCalming

    var id: String { rawValue }
}

enum PulsarBreathPhaseKind: String, Codable, Hashable {
    case inhale
    case inhaleTopUp
    case holdFull
    case exhale
    case holdEmpty

    var title: String {
        switch self {
        case .inhale: "Inhale"
        case .inhaleTopUp: "Sip in"
        case .holdFull: "Hold"
        case .exhale: "Exhale"
        case .holdEmpty: "Rest"
        }
    }
}

struct PulsarBreathPhase: Codable, Hashable {
    var kind: PulsarBreathPhaseKind
    var duration: TimeInterval
    var cue: String
}

struct PulsarBreathingPhaseSnapshot: Equatable {
    var phase: PulsarBreathPhase
    var phaseProgress: Double
    var cycleProgress: Double
    var cycleIndex: Int
}

struct PulsarBreathingPattern: Identifiable, Codable, Hashable {
    var preset: PulsarBreathingPreset
    var title: String
    var subtitle: String
    var phases: [PulsarBreathPhase]
    var defaultDuration: TimeInterval

    var id: String { preset.rawValue }

    var cycleDuration: TimeInterval {
        phases.reduce(0) { $0 + max(0, $1.duration) }
    }

    func snapshot(at elapsed: TimeInterval) -> PulsarBreathingPhaseSnapshot? {
        guard !phases.isEmpty, cycleDuration > 0 else { return nil }
        let safeElapsed = max(0, elapsed)
        let cycleElapsed = safeElapsed.truncatingRemainder(dividingBy: cycleDuration)
        var cursor: TimeInterval = 0

        for phase in phases {
            let duration = max(0.01, phase.duration)
            let nextCursor = cursor + duration
            if cycleElapsed <= nextCursor {
                let phaseProgress = min(max((cycleElapsed - cursor) / duration, 0), 1)
                return PulsarBreathingPhaseSnapshot(
                    phase: phase,
                    phaseProgress: phaseProgress,
                    cycleProgress: min(max(cycleElapsed / cycleDuration, 0), 1),
                    cycleIndex: Int(safeElapsed / cycleDuration)
                )
            }
            cursor = nextCursor
        }

        guard let last = phases.last else { return nil }
        return PulsarBreathingPhaseSnapshot(
            phase: last,
            phaseProgress: 1,
            cycleProgress: 1,
            cycleIndex: Int(safeElapsed / cycleDuration)
        )
    }
}

struct PulsarMeditationTemplate: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var category: PulsarMeditationCategory
    var duration: TimeInterval
    var breathingPreset: PulsarBreathingPreset?
    var soundscape: String?

    var durationText: String {
        duration.pulsarMindfulnessDurationText
    }
}

enum PulsarMindfulnessSessionPhase: String, Codable, Hashable {
    case preparing
    case running
    case paused
    case completed
    case cancelled
}

enum PulsarMindfulnessSessionSource: String, Codable, Hashable {
    case iPhone
    case appleWatch
    case healthKit
}

struct PulsarMindfulnessSessionSummary: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var templateID: String
    var title: String
    var category: PulsarMeditationCategory
    var startedAt: Date
    var endedAt: Date
    var duration: TimeInterval
    var completedCycles: Int
    var reflection: String?
    var source: PulsarMindfulnessSessionSource
    var healthKitSampleID: UUID?

    init(
        id: UUID = UUID(),
        templateID: String,
        title: String,
        category: PulsarMeditationCategory,
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        completedCycles: Int,
        reflection: String? = nil,
        source: PulsarMindfulnessSessionSource = .iPhone,
        healthKitSampleID: UUID? = nil
    ) {
        self.id = id
        self.templateID = templateID
        self.title = title
        self.category = category
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = max(0, duration)
        self.completedCycles = max(0, completedCycles)
        self.reflection = PulsarDailyJournalEntry.trimmedSummaryText(reflection)
        self.source = source
        self.healthKitSampleID = healthKitSampleID
    }

    var durationText: String {
        duration.pulsarMindfulnessDurationText
    }
}

struct PulsarMindfulnessTrendPoint: Identifiable, Equatable {
    var id: String { dateKey }
    var date: Date
    var dateKey: String
    var valence: Double?
    var mindfulMinutes: Double
    var hasCheckIn: Bool
}

struct PulsarMindfulnessStreakSummary: Equatable {
    var currentStreak: Int
    var longestStreak: Int
    var hasToday: Bool
    var lastEntryDate: Date?
}

enum PulsarMindfulnessInsightTint: String, Equatable {
    case calm
    case focus
    case recovery
    case amber

    var color: Color {
        switch self {
        case .calm: Color(red: 0.34, green: 0.72, blue: 1.00)
        case .focus: Color(red: 0.48, green: 0.78, blue: 0.86)
        case .recovery: Color(red: 0.52, green: 0.82, blue: 0.62)
        case .amber: Color(red: 1.00, green: 0.68, blue: 0.38)
        }
    }
}

struct PulsarEmotionalInsight: Identifiable, Equatable {
    var id: String
    var title: String
    var body: String
    var evidence: String
    var confidence: Double
    var sampleCount: Int
    var symbolName: String
    var tint: PulsarMindfulnessInsightTint
}

struct PulsarMindfulnessDashboard: Equatable {
    var todayEntry: PulsarDailyJournalEntry?
    var latestSession: PulsarMindfulnessSessionSummary?
    var streak: PulsarMindfulnessStreakSummary
    var trend: [PulsarMindfulnessTrendPoint]
    var insights: [PulsarEmotionalInsight]
    var weeklyMindfulMinutes: Double

    static let empty = PulsarMindfulnessDashboard(
        todayEntry: nil,
        latestSession: nil,
        streak: PulsarMindfulnessStreakSummary(currentStreak: 0, longestStreak: 0, hasToday: false, lastEntryDate: nil),
        trend: [],
        insights: [],
        weeklyMindfulMinutes: 0
    )
}

struct PulsarMindfulnessState: Equatable {
    var entries: [PulsarDailyJournalEntry]
    var sessions: [PulsarMindfulnessSessionSummary]
    var dashboard: PulsarMindfulnessDashboard

    static let empty = PulsarMindfulnessState(entries: [], sessions: [], dashboard: .empty)
}

extension PulsarDailyJournalEntry {
    fileprivate static func trimmedSummaryText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension TimeInterval {
    var pulsarMindfulnessDurationText: String {
        let totalSeconds = Int(max(0, self).rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
        }
        if seconds == 0 {
            return "\(minutes) min"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
