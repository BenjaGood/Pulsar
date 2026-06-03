//
//  HeartbeatHapticsManager.swift
//  Pulsar
//

import Combine
import CoreHaptics
import UIKit

@MainActor
final class HeartbeatHapticsManager: ObservableObject {
    private var engine: CHHapticEngine?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    func prepare() {
        guard supportsHaptics else { return }

        do {
            if engine == nil {
                engine = try CHHapticEngine()
            }
            try engine?.start()
        } catch {
            engine = nil
        }
    }

    func playHeartbeat() {
        guard supportsHaptics else {
            playFallbackHeartbeat()
            return
        }

        if engine == nil {
            prepare()
        }

        guard let engine else {
            playFallbackHeartbeat()
            return
        }

        do {
            let softPulse = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.22),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.12)
                ],
                relativeTime: 0
            )

            let strongPulse = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.38),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.20)
                ],
                relativeTime: 0.10
            )

            let pattern = try CHHapticPattern(events: [softPulse, strongPulse], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            playFallbackHeartbeat()
        }
    }

    private func playFallbackHeartbeat() {
        let softPulse = UIImpactFeedbackGenerator(style: .soft)
        softPulse.prepare()
        softPulse.impactOccurred(intensity: 0.35)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            let strongPulse = UIImpactFeedbackGenerator(style: .light)
            strongPulse.prepare()
            strongPulse.impactOccurred(intensity: 0.55)
        }
    }
}
