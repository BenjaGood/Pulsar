//
//  MindfulnessContentLibrary.swift
//  Pulsar
//

import Foundation

enum PulsarMindfulnessContentLibrary {
    static let dailyPrompts: [String] = [
        "What felt lighter than expected today?",
        "Where did your body ask for care?",
        "What is one thing you want to carry into tomorrow?",
        "What helped you return to yourself today?"
    ]

    static let breathingPatterns: [PulsarBreathingPattern] = [
        PulsarBreathingPattern(
            preset: .box,
            title: "Box breathing",
            subtitle: "Steady attention with equal phases.",
            phases: [
                PulsarBreathPhase(kind: .inhale, duration: 4, cue: "Inhale"),
                PulsarBreathPhase(kind: .holdFull, duration: 4, cue: "Hold"),
                PulsarBreathPhase(kind: .exhale, duration: 4, cue: "Exhale"),
                PulsarBreathPhase(kind: .holdEmpty, duration: 4, cue: "Rest")
            ],
            defaultDuration: 180
        ),
        PulsarBreathingPattern(
            preset: .relaxation,
            title: "Relaxation breath",
            subtitle: "Longer exhale for a softer nervous system.",
            phases: [
                PulsarBreathPhase(kind: .inhale, duration: 4, cue: "Inhale"),
                PulsarBreathPhase(kind: .exhale, duration: 6, cue: "Release")
            ],
            defaultDuration: 300
        ),
        PulsarBreathingPattern(
            preset: .sleep,
            title: "Sleep breath",
            subtitle: "A quiet 4-7-8 descent.",
            phases: [
                PulsarBreathPhase(kind: .inhale, duration: 4, cue: "Inhale"),
                PulsarBreathPhase(kind: .holdFull, duration: 7, cue: "Suspend"),
                PulsarBreathPhase(kind: .exhale, duration: 8, cue: "Let go")
            ],
            defaultDuration: 300
        ),
        PulsarBreathingPattern(
            preset: .energizing,
            title: "Morning reset",
            subtitle: "Bright, clean breath without pressure.",
            phases: [
                PulsarBreathPhase(kind: .inhale, duration: 6, cue: "Draw in"),
                PulsarBreathPhase(kind: .exhale, duration: 2, cue: "Clear")
            ],
            defaultDuration: 120
        ),
        PulsarBreathingPattern(
            preset: .anxietyCalming,
            title: "Anxiety calming",
            subtitle: "A small inhale and a long exhale.",
            phases: [
                PulsarBreathPhase(kind: .inhale, duration: 2, cue: "Sip in"),
                PulsarBreathPhase(kind: .inhaleTopUp, duration: 1, cue: "A little more"),
                PulsarBreathPhase(kind: .exhale, duration: 7, cue: "Long exhale")
            ],
            defaultDuration: 300
        )
    ]

    static let meditationTemplates: [PulsarMeditationTemplate] = [
        PulsarMeditationTemplate(
            id: "breathing-relaxation",
            title: "Calm Breath",
            subtitle: "A quiet breathing session for downshifting.",
            category: .breathing,
            duration: 300,
            breathingPreset: .relaxation,
            soundscape: "Soft air"
        ),
        PulsarMeditationTemplate(
            id: "stress-reduction-sos",
            title: "Stress Reset",
            subtitle: "Long exhales for a sharper moment.",
            category: .stressReduction,
            duration: 180,
            breathingPreset: .anxietyCalming,
            soundscape: "Still room"
        ),
        PulsarMeditationTemplate(
            id: "focus-clear-attention",
            title: "Clear Focus",
            subtitle: "A minimal attention practice before deep work.",
            category: .focus,
            duration: 600,
            breathingPreset: .box,
            soundscape: nil
        ),
        PulsarMeditationTemplate(
            id: "sleep-deep-release",
            title: "Sleep Descent",
            subtitle: "A softer pace for the end of the day.",
            category: .sleep,
            duration: 480,
            breathingPreset: .sleep,
            soundscape: "Night tone"
        ),
        PulsarMeditationTemplate(
            id: "morning-reset",
            title: "Morning Reset",
            subtitle: "Settle, brighten, and move into the day.",
            category: .morningReset,
            duration: 240,
            breathingPreset: .energizing,
            soundscape: "Dawn"
        ),
        PulsarMeditationTemplate(
            id: "recovery-after-strain",
            title: "Recovery Downshift",
            subtitle: "A post-workout glide back to baseline.",
            category: .recovery,
            duration: 360,
            breathingPreset: .relaxation,
            soundscape: "Low current"
        ),
        PulsarMeditationTemplate(
            id: "deep-relaxation",
            title: "Deep Relaxation",
            subtitle: "Low-stimulation rest with a wide exhale.",
            category: .deepRelaxation,
            duration: 720,
            breathingPreset: .relaxation,
            soundscape: "Warm drone"
        ),
        PulsarMeditationTemplate(
            id: "walking-meditation",
            title: "Walking Meditation",
            subtitle: "A future Watch-ready mindful walk.",
            category: .walking,
            duration: 600,
            breathingPreset: nil,
            soundscape: nil
        ),
        PulsarMeditationTemplate(
            id: "sound-meditation",
            title: "Sound Meditation",
            subtitle: "Follow tone and silence as one surface.",
            category: .sound,
            duration: 600,
            breathingPreset: nil,
            soundscape: "Resonance"
        )
    ]

    static func pattern(for preset: PulsarBreathingPreset?) -> PulsarBreathingPattern? {
        guard let preset else { return nil }
        return breathingPatterns.first { $0.preset == preset }
    }

    static func template(id: String) -> PulsarMeditationTemplate? {
        meditationTemplates.first { $0.id == id }
    }
}
