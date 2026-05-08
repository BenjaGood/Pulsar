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
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.34),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.22)
                ],
                relativeTime: 0
            )

            let strongPulse = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.82),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.38)
                ],
                relativeTime: 0.14
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
        softPulse.impactOccurred(intensity: 0.55)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            let strongPulse = UIImpactFeedbackGenerator(style: .medium)
            strongPulse.prepare()
            strongPulse.impactOccurred(intensity: 0.84)
        }
    }
}
