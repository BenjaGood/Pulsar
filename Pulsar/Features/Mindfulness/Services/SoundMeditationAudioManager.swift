//
//  SoundMeditationAudioManager.swift
//  Pulsar
//

import AVFoundation
import Combine
import Foundation

enum SoundPlaybackState: Equatable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case error(SoundPlaybackError)

    var error: SoundPlaybackError? {
        if case .error(let error) = self { return error }
        return nil
    }

    var statusTitle: String {
        switch self {
        case .idle:
            "Ready"
        case .loading:
            "Loading"
        case .ready:
            "Ready"
        case .playing:
            "Playing"
        case .paused:
            "Paused"
        case .error(let error):
            error.statusTitle
        }
    }
}

enum SoundPlaybackError: LocalizedError, Equatable {
    case missingAsset(String)
    case missingLicense(String)
    case commercialUseNotAllowed(String)
    case unsupportedFormat(String)
    case audioSessionFailed(String)
    case playerInitializationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAsset(let fileName):
            "\(fileName) is not bundled yet."
        case .missingLicense(let fileName):
            "Missing license metadata for \(fileName)."
        case .commercialUseNotAllowed(let fileName):
            "\(fileName) is not approved for commercial use."
        case .unsupportedFormat(let fileName):
            "\(fileName) is not a supported local audio format."
        case .audioSessionFailed(let reason):
            "Audio session failed: \(reason)"
        case .playerInitializationFailed(let reason):
            "Soundscape could not be prepared: \(reason)"
        }
    }

    var statusTitle: String {
        switch self {
        case .missingAsset:
            "Missing asset"
        case .missingLicense:
            "Missing license"
        case .commercialUseNotAllowed:
            "Not licensed"
        case .unsupportedFormat:
            "Unsupported"
        case .audioSessionFailed, .playerInitializationFailed:
            "Unavailable"
        }
    }

    var userFacingTitle: String {
        "Audio asset unavailable"
    }

    var userFacingMessage: String {
        switch self {
        case .missingAsset, .missingLicense, .commercialUseNotAllowed, .unsupportedFormat:
            "Missing file or license approval required."
        case .audioSessionFailed, .playerInitializationFailed:
            "Audio could not start. Please try another sound."
        }
    }
}

@MainActor
final class SoundMeditationAudioManager: ObservableObject {
    @Published private(set) var currentSoundscape: Soundscape?
    @Published private(set) var playbackState: SoundPlaybackState = .idle
    private(set) var volume: Double = 0.82

    private var player: AVAudioPlayer?
    private var fadeTask: Task<Void, Never>?
    private var loopingEnabled = true

    var isPlaying: Bool {
        playbackState == .playing
    }

    var playbackError: SoundPlaybackError? {
        playbackState.error
    }

    deinit {
        fadeTask?.cancel()
        player?.stop()
        player = nil
    }

    func prepare(soundscape: Soundscape) {
        fadeTask?.cancel()
        player?.stop()
        player = nil
        currentSoundscape = soundscape

        switch validate(soundscape: soundscape) {
        case .success:
            playbackState = .ready
        case .failure(let error):
            playbackState = .error(error)
        }
    }

    func load(soundscape: Soundscape) {
        log("selected soundscape id=\(soundscape.id)")
        fadeTask?.cancel()
        player?.stop()
        player = nil
        currentSoundscape = soundscape
        playbackState = .loading

        let assetURL: URL
        switch validate(soundscape: soundscape) {
        case .success(let url):
            assetURL = url
        case .failure(let error):
            playbackState = .error(error)
            log("asset validation failed reason=\(error.statusTitle)")
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            log("audio session activated")
        } catch {
            playbackState = .error(.audioSessionFailed(error.localizedDescription))
            log("audio session failed reason=\(error.localizedDescription)")
            return
        }

        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: assetURL)
            audioPlayer.numberOfLoops = soundscape.isLoopable && loopingEnabled ? -1 : 0
            audioPlayer.volume = Float(volume)
            audioPlayer.prepareToPlay()
            player = audioPlayer
            playbackState = .ready
            log("player ready duration=\(audioPlayer.duration)")
        } catch {
            playbackState = .error(.playerInitializationFailed(error.localizedDescription))
            log("player initialization failed reason=\(error.localizedDescription)")
        }
    }

    func play() {
        if player == nil, let currentSoundscape {
            load(soundscape: currentSoundscape)
        }

        guard let player else { return }
        player.currentTime = 0
        player.volume = Float(volume)
        player.play()
        playbackState = .playing
        log("play")
    }

    func pause() {
        guard player?.isPlaying == true else { return }
        player?.pause()
        playbackState = .paused
        log("pause")
    }

    func resume() {
        if player == nil, let currentSoundscape {
            load(soundscape: currentSoundscape)
        }

        guard let player else { return }
        player.play()
        playbackState = .playing
        log("play")
    }

    func stop() {
        fadeTask?.cancel()
        player?.stop()
        player = nil
        playbackState = .idle
        deactivateSession()
        log("stop")
    }

    func fadeIn(duration: TimeInterval) {
        if player == nil, let currentSoundscape {
            load(soundscape: currentSoundscape)
        }

        guard let player else { return }
        player.volume = 0
        player.play()
        playbackState = .playing
        player.setVolume(Float(volume), fadeDuration: duration)
        log("play")
    }

    func fadeOut(duration: TimeInterval) {
        guard let player else { return }
        fadeTask?.cancel()
        player.setVolume(0, fadeDuration: duration)
        fadeTask = Task { [weak self] in
            let nanoseconds = UInt64(max(duration, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.player?.pause()
            self?.playbackState = .paused
        }
    }

    func setVolume(_ volume: Float) {
        setVolume(Double(volume))
    }

    func setVolume(_ volume: Double) {
        let clampedVolume = min(max(volume, 0), 1)
        self.volume = clampedVolume
        player?.volume = Float(clampedVolume)
    }

    func toggleLooping(_ enabled: Bool) {
        loopingEnabled = enabled
        player?.numberOfLoops = enabled ? -1 : 0
    }

    func switchSoundscape(to soundscape: Soundscape, crossfadeDuration: TimeInterval) {
        guard currentSoundscape?.id != soundscape.id else { return }

        let shouldStartPlayback = playbackState == .playing
        guard player != nil else {
            prepare(soundscape: soundscape)
            if shouldStartPlayback {
                fadeIn(duration: crossfadeDuration / 2)
            }
            return
        }

        fade(to: 0, duration: crossfadeDuration / 2) { [weak self] in
            guard let self else { return }
            self.load(soundscape: soundscape)
            if shouldStartPlayback {
                self.fadeIn(duration: crossfadeDuration / 2)
            }
        }
    }

    private func fade(
        to targetVolume: Float,
        duration: TimeInterval,
        completion: @escaping @MainActor () -> Void
    ) {
        fadeTask?.cancel()
        fadeTask = Task { [weak self] in
            guard let self else { return }
            let steps = max(Int(duration / 0.05), 1)
            let startVolume = self.player?.volume ?? Float(self.volume)

            for step in 1...steps {
                guard !Task.isCancelled else { return }
                let progress = Float(step) / Float(steps)
                self.player?.volume = startVolume + (targetVolume - startVolume) * progress
                try? await Task.sleep(nanoseconds: 50_000_000)
            }

            guard !Task.isCancelled else { return }
            self.player?.volume = targetVolume
            completion()
        }
    }

    private func validate(soundscape: Soundscape) -> Result<URL, SoundPlaybackError> {
        let localFileName = soundscape.localFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        log("validating asset file=\(localFileName.isEmpty ? "empty" : localFileName)")

        guard !soundscape.isComingSoon, !localFileName.isEmpty else {
            return .failure(.missingAsset(localFileName.isEmpty ? soundscape.id : localFileName))
        }

        guard isSupportedAudioFile(localFileName) else {
            return .failure(.unsupportedFormat(localFileName))
        }

        guard let license = SoundscapeLicenseCatalog.license(for: localFileName) else {
            return .failure(.missingLicense(localFileName))
        }

        if license.attributionRequired && (license.attributionText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            return .failure(.missingLicense(localFileName))
        }

        guard soundscape.commercialUseAllowed,
              license.commercialUseAllowed,
              SoundscapeLicenseCatalog.canUseCommercially(fileName: localFileName) else {
            return .failure(.commercialUseNotAllowed(localFileName))
        }

        guard let assetURL = bundledURL(for: localFileName) else {
            return .failure(.missingAsset(localFileName))
        }

        return .success(assetURL)
    }

    private func isSupportedAudioFile(_ localFileName: String) -> Bool {
        let fileExtension = URL(fileURLWithPath: localFileName).pathExtension.lowercased()
        return ["m4a", "aac", "mp3", "alac"].contains(fileExtension)
    }

    private func deactivateSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            log("audio session deactivate failed reason=\(error.localizedDescription)")
        }
    }

    private func bundledURL(for localFileName: String) -> URL? {
        let url = URL(fileURLWithPath: localFileName)
        let fileName = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension.isEmpty ? "m4a" : url.pathExtension

        return Bundle.main.url(forResource: fileName, withExtension: fileExtension) ??
            Bundle.main.url(
                forResource: fileName,
                withExtension: fileExtension,
                subdirectory: "Features/Mindfulness/Resources/Soundscapes"
            )
    }

    private func log(_ message: String) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["PULSAR_SOUND_DEBUG_LOGS"] == "1" else { return }
        print("[SoundMeditationAudio] \(message)")
        #endif
    }
}
