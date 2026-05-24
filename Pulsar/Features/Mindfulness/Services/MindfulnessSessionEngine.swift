//
//  MindfulnessSessionEngine.swift
//  Pulsar
//

import Combine
import Foundation
import UIKit

enum PulsarBreathingHapticsLevel: String, CaseIterable, Identifiable {
    case none
    case minimal
    case prominent

    var id: String { rawValue }
}

@MainActor
final class PulsarMeditationSessionEngine: ObservableObject {
    @Published private(set) var phase: PulsarMindfulnessSessionPhase = .preparing
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var summary: PulsarMindfulnessSessionSummary?

    let template: PulsarMeditationTemplate
    let breathingPattern: PulsarBreathingPattern?

    private let haptics: PulsarBreathingHapticsManager
    private let sessionID = UUID()
    private var startedAt = Date()
    private var pausedAt: Date?
    private var accumulatedPauseDuration: TimeInterval = 0
    private var tickerTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var lastHapticPhaseKind: PulsarBreathPhaseKind?

    init(
        template: PulsarMeditationTemplate,
        breathingPattern: PulsarBreathingPattern? = nil,
        hapticsLevel: PulsarBreathingHapticsLevel = .minimal
    ) {
        self.template = template
        self.breathingPattern = breathingPattern ?? PulsarMindfulnessContentLibrary.pattern(for: template.breathingPreset)
        self.haptics = PulsarBreathingHapticsManager(level: hapticsLevel, category: template.category)
    }

    deinit {
        tickerTask?.cancel()
        preparationTask?.cancel()
    }

    var remaining: TimeInterval {
        max(0, template.duration - elapsed)
    }

    var progress: Double {
        guard template.duration > 0 else { return 1 }
        return min(max(elapsed / template.duration, 0), 1)
    }

    func start() {
        guard phase == .preparing else { return }
        startedAt = Date()
        elapsed = 0
        summary = nil
        haptics.prepare()
        preparationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            self?.beginRunning()
        }
    }

    func pause() {
        guard phase == .running else { return }
        elapsed = currentElapsed(at: Date())
        pausedAt = Date()
        phase = .paused
        haptics.pause()
    }

    func resume() {
        guard phase == .paused else { return }
        if let pausedAt {
            accumulatedPauseDuration += Date().timeIntervalSince(pausedAt)
        }
        self.pausedAt = nil
        phase = .running
        haptics.resume()
    }

    func finish(reflection: String? = nil) {
        guard phase == .running || phase == .paused || phase == .preparing else { return }
        let endedAt = Date()
        let duration = currentElapsed(at: endedAt)
        elapsed = duration
        phase = .completed
        tickerTask?.cancel()
        preparationTask?.cancel()
        summary = PulsarMindfulnessSessionSummary(
            id: sessionID,
            templateID: template.id,
            title: template.title,
            category: template.category,
            startedAt: startedAt,
            endedAt: endedAt,
            duration: duration,
            completedCycles: completedCycles(at: duration),
            reflection: reflection
        )
        haptics.complete()
    }

    func cancel() {
        phase = .cancelled
        tickerTask?.cancel()
        preparationTask?.cancel()
        haptics.cancel()
    }

    func currentElapsed(at date: Date) -> TimeInterval {
        switch phase {
        case .running:
            return max(0, date.timeIntervalSince(startedAt) - accumulatedPauseDuration)
        case .paused:
            guard let pausedAt else { return elapsed }
            return max(0, pausedAt.timeIntervalSince(startedAt) - accumulatedPauseDuration)
        case .preparing:
            return 0
        case .completed, .cancelled:
            return elapsed
        }
    }

    func breathingSnapshot(at date: Date) -> PulsarBreathingPhaseSnapshot? {
        breathingPattern?.snapshot(at: currentElapsed(at: date))
    }

    private func beginRunning() {
        guard phase == .preparing else { return }
        startedAt = Date()
        phase = .running
        haptics.start()
        startTicker()
    }

    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                self?.tick()
            }
        }
    }

    private func tick() {
        guard phase == .running else { return }
        let now = Date()
        elapsed = currentElapsed(at: now)

        if let snapshot = breathingSnapshot(at: now), snapshot.phase.kind != lastHapticPhaseKind {
            lastHapticPhaseKind = snapshot.phase.kind
            haptics.cue(for: snapshot.phase.kind)
        }

        if elapsed >= template.duration {
            finish()
        }
    }

    private func completedCycles(at duration: TimeInterval) -> Int {
        guard let breathingPattern, breathingPattern.cycleDuration > 0 else {
            return Int(max(0, duration / 60).rounded(.down))
        }
        return Int(max(0, duration / breathingPattern.cycleDuration).rounded(.down))
    }
}

@MainActor
final class PulsarBreathingHapticsManager {
    private let level: PulsarBreathingHapticsLevel
    private let category: PulsarMeditationCategory

    init(level: PulsarBreathingHapticsLevel, category: PulsarMeditationCategory) {
        self.level = level
        self.category = category
    }

    func prepare() {
        guard level != .none else { return }
        UIImpactFeedbackGenerator(style: .soft).prepare()
    }

    func start() {
        guard level != .none else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
    }

    func cue(for phase: PulsarBreathPhaseKind) {
        guard level != .none else { return }
        guard category != .sleep || phase == .exhale else { return }

        switch phase {
        case .inhale, .inhaleTopUp:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: level == .prominent ? 0.45 : 0.28)
        case .holdFull, .holdEmpty:
            guard level == .prominent else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.22)
        case .exhale:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: level == .prominent ? 0.62 : 0.38)
        }
    }

    func pause() {
        guard level != .none else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func resume() {
        guard level != .none else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.36)
    }

    func complete() {
        guard level != .none, category != .sleep, category != .deepRelaxation else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func cancel() {
        guard level != .none else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.28)
    }
}
