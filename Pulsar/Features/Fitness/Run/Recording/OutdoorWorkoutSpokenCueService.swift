//
//  OutdoorWorkoutSpokenCueService.swift
//  Pulsar
//

import AVFoundation
import Foundation

/// Speaks short outdoor-workout progress cues on the iPhone without permanently interrupting media.
@MainActor
final class OutdoorWorkoutSpokenCueService: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var pendingPhrases: [String] = []
    private var isSessionActive = false
    private var isEnabled = false
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        synthesizer.delegate = self
        observeInterruptions()
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        synthesizer.delegate = nil
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            stop(clearPending: true)
        }
    }

    func enqueue(_ phrase: String) {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !trimmed.isEmpty else { return }
        if pendingPhrases.contains(trimmed) || synthesizer.isSpeaking && pendingPhrases.last == trimmed {
            return
        }
        pendingPhrases.append(trimmed)
        speakNextIfNeeded()
    }

    func stop(clearPending: Bool) {
        if clearPending {
            pendingPhrases.removeAll()
        }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        deactivateSession()
    }

    private func speakNextIfNeeded() {
        guard isEnabled else {
            pendingPhrases.removeAll()
            return
        }
        guard !synthesizer.isSpeaking else { return }
        guard !pendingPhrases.isEmpty else {
            deactivateSession()
            return
        }

        let phrase = pendingPhrases.removeFirst()
        do {
            try activateSession()
        } catch {
            PulsarSyncDebugLogger.log("Outdoor audio cue session activation failed error=\(error.localizedDescription)")
            pendingPhrases.removeAll()
            deactivateSession()
            return
        }

        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = preferredVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        let locale = Locale.autoupdatingCurrent
        let languageCode = locale.language.languageCode?.identifier ?? "en"
        if let region = locale.region?.identifier {
            let bcp47 = "\(languageCode)-\(region)"
            if let voice = AVSpeechSynthesisVoice(language: bcp47) {
                return voice
            }
        }
        return AVSpeechSynthesisVoice(language: languageCode)
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playback,
            mode: .voicePrompt,
            options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
        )
        try session.setActive(true)
        isSessionActive = true
    }

    private func deactivateSession() {
        guard isSessionActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            PulsarSyncDebugLogger.log("Outdoor audio cue session deactivation failed error=\(error.localizedDescription)")
        }
        isSessionActive = false
    }

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else {
                return
            }
            Task { @MainActor [self] in
                self.handleInterruption(typeValue)
            }
        }
    }

    private func handleInterruption(_ typeValue: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        switch type {
        case .began:
            synthesizer.stopSpeaking(at: .immediate)
            pendingPhrases.removeAll()
            isSessionActive = false
        case .ended:
            deactivateSession()
        @unknown default:
            break
        }
    }
}

extension OutdoorWorkoutSpokenCueService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            speakNextIfNeeded()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            if pendingPhrases.isEmpty {
                deactivateSession()
            } else {
                speakNextIfNeeded()
            }
        }
    }
}
