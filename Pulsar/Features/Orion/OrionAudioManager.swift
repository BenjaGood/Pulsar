//
//  OrionAudioManager.swift
//  Pulsar
//

import AVFoundation
import Combine
import Foundation

enum OrionGenerationLifecycle: Equatable, Sendable {
    case idle
    case generating(UUID)
    case completed(UUID)
    case failed(UUID)
    case cancelled(UUID)

    var generationID: UUID? {
        switch self {
        case .idle:
            return nil
        case .generating(let id), .completed(let id), .failed(let id), .cancelled(let id):
            return id
        }
    }

    var isGenerating: Bool {
        if case .generating = self {
            return true
        }
        return false
    }
}

enum OrionAudioState: Equatable, Sendable {
    case idle
    case thinkingStart
    case thinkingLoop
    case responseComplete
}

protocol OrionAudioPlaybackManaging: AnyObject {
    var thinkingStartDuration: TimeInterval { get }
    var responseCompleteDuration: TimeInterval { get }

    func playThinkingStartSchedulingLoop()
    func playThinkingLoop()
    func playResponseComplete()
    func stopAll()
    func deactivate()
}

@MainActor
final class OrionAudioManager: ObservableObject {
    @Published private(set) var state: OrionAudioState = .idle

    private let playback: any OrionAudioPlaybackManaging
    private var lifecycleCancellable: AnyCancellable?
    private var interruptionCancellable: AnyCancellable?
    private var startToLoopTask: Task<Void, Never>?
    private var responseCompleteTask: Task<Void, Never>?
    private var latestLifecycle: OrionGenerationLifecycle = .idle
    private var activeAudioGenerationID: UUID?
    private var handledTerminalGenerationID: UUID?
    private var isAppActive = true
    private var isPresentationActive = true

    init(
        notificationCenter: NotificationCenter = .default
    ) {
        self.playback = OrionAVAudioPlaybackEngine()
        observeAudioInterruptions(notificationCenter: notificationCenter)
    }

    init(
        playback: any OrionAudioPlaybackManaging,
        notificationCenter: NotificationCenter = .default
    ) {
        self.playback = playback
        observeAudioInterruptions(notificationCenter: notificationCenter)
    }

    deinit {
        startToLoopTask?.cancel()
        responseCompleteTask?.cancel()
        let playback = playback
        Task { @MainActor in
            playback.stopAll()
            playback.deactivate()
        }
    }

    func bind(to viewModel: OrionChatViewModel) {
        lifecycleCancellable = viewModel.$generationLifecycle
            .dropFirst()
            .sink { [weak self] lifecycle in
                Task { @MainActor in
                    self?.handle(lifecycle)
                }
            }
        handle(viewModel.generationLifecycle)
    }

    func setPresentationActive(_ isActive: Bool) {
        isPresentationActive = isActive
        if isActive {
            resumeIfNeeded()
        } else {
            stopPlayback()
        }
    }

    func setAppIsActive(_ isActive: Bool) {
        isAppActive = isActive
        if isActive {
            resumeIfNeeded()
        } else {
            stopPlayback()
        }
    }

    func handleInterruptionBegan() {
        stopPlayback()
    }

    func handleInterruptionEnded() {
        resumeIfNeeded()
    }

    func handle(_ lifecycle: OrionGenerationLifecycle) {
        latestLifecycle = lifecycle

        switch lifecycle {
        case .idle:
            stopPlayback()
        case .generating(let id):
            guard canPlayAudio else {
                stopPlayback()
                return
            }
            startThinking(for: id)
        case .completed(let id):
            guard markTerminalGenerationHandled(id) else { return }
            activeAudioGenerationID = nil
            guard canPlayAudio else {
                stopPlayback()
                return
            }
            playResponseComplete()
        case .failed(let id), .cancelled(let id):
            _ = markTerminalGenerationHandled(id)
            stopPlayback()
        }
    }

    private var canPlayAudio: Bool {
        isAppActive && isPresentationActive
    }

    private func startThinking(for generationID: UUID) {
        stopPlayback(deactivate: false)
        activeAudioGenerationID = generationID
        state = .thinkingStart
        playback.playThinkingStartSchedulingLoop()
        scheduleLoopStateTransition(for: generationID)
    }

    private func scheduleLoopStateTransition(for generationID: UUID) {
        startToLoopTask?.cancel()
        let duration = max(0, playback.thinkingStartDuration)
        guard duration > 0 else {
            transitionToThinkingLoop(for: generationID)
            return
        }

        startToLoopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await MainActor.run {
                self?.transitionToThinkingLoop(for: generationID)
            }
        }
    }

    private func transitionToThinkingLoop(for generationID: UUID) {
        guard canPlayAudio,
              activeAudioGenerationID == generationID,
              latestLifecycle == .generating(generationID) else {
            return
        }
        state = .thinkingLoop
    }

    private func playResponseComplete() {
        startToLoopTask?.cancel()
        responseCompleteTask?.cancel()
        state = .responseComplete
        playback.playResponseComplete()

        let duration = max(0, playback.responseCompleteDuration)
        responseCompleteTask = Task { [weak self] in
            if duration > 0 {
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            }
            await MainActor.run {
                guard self?.state == .responseComplete else { return }
                self?.state = .idle
                self?.playback.deactivate()
            }
        }
    }

    private func resumeIfNeeded() {
        guard canPlayAudio else { return }
        if case .generating(let id) = latestLifecycle {
            startLoop(for: id)
        }
    }

    private func startLoop(for generationID: UUID) {
        stopPlayback(deactivate: false)
        activeAudioGenerationID = generationID
        state = .thinkingLoop
        playback.playThinkingLoop()
    }

    private func stopPlayback(deactivate: Bool = true) {
        startToLoopTask?.cancel()
        responseCompleteTask?.cancel()
        activeAudioGenerationID = nil
        state = .idle
        playback.stopAll()
        if deactivate {
            playback.deactivate()
        }
    }

    private func markTerminalGenerationHandled(_ id: UUID) -> Bool {
        guard handledTerminalGenerationID != id else {
            return false
        }
        handledTerminalGenerationID = id
        return true
    }

    private func observeAudioInterruptions(notificationCenter: NotificationCenter) {
        interruptionCancellable = notificationCenter.publisher(
            for: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                self.handleAudioInterruption(notification)
            }
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }

        switch type {
        case .began:
            handleInterruptionBegan()
        case .ended:
            handleInterruptionEnded()
        @unknown default:
            stopPlayback()
        }
    }
}

private final class OrionAVAudioPlaybackEngine: OrionAudioPlaybackManaging {
    private enum Cue: CaseIterable {
        case thinkingStart
        case thinkingLoop
        case responseComplete

        var resource: (name: String, extension: String) {
            switch self {
            case .thinkingStart:
                return ("latency_experience_long", "wav")
            case .thinkingLoop:
                return ("latency_loop", "caf")
            case .responseComplete:
                return ("latency_response", "caf")
            }
        }
    }

    private let bundle: Bundle
    private let audioSession: AVAudioSession
    private var players: [Cue: AVAudioPlayer] = [:]

    init(bundle: Bundle = .main, audioSession: AVAudioSession = .sharedInstance()) {
        self.bundle = bundle
        self.audioSession = audioSession
        loadPlayers()
    }

    var thinkingStartDuration: TimeInterval {
        players[.thinkingStart]?.duration ?? 0
    }

    var responseCompleteDuration: TimeInterval {
        players[.responseComplete]?.duration ?? 0
    }

    func playThinkingStartSchedulingLoop() {
        stopAll()
        activate()

        guard let startPlayer = players[.thinkingStart] else {
            playThinkingLoop()
            return
        }

        let startTime = startPlayer.deviceCurrentTime + 0.015
        reset(startPlayer, loops: 0)
        startPlayer.play(atTime: startTime)

        guard let loopPlayer = players[.thinkingLoop] else { return }
        reset(loopPlayer, loops: -1)
        loopPlayer.play(atTime: startTime + startPlayer.duration)
    }

    func playThinkingLoop() {
        stopAll()
        activate()
        guard let loopPlayer = players[.thinkingLoop] else { return }
        reset(loopPlayer, loops: -1)
        loopPlayer.play()
    }

    func playResponseComplete() {
        stopAll()
        activate()
        guard let responsePlayer = players[.responseComplete] else { return }
        reset(responsePlayer, loops: 0)
        responsePlayer.play()
    }

    func stopAll() {
        for player in players.values {
            player.stop()
            player.currentTime = 0
        }
    }

    func deactivate() {
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func loadPlayers() {
        for cue in Cue.allCases {
            let resource = cue.resource
            guard let url = audioURL(named: resource.name, extension: resource.extension),
                  let player = try? AVAudioPlayer(contentsOf: url) else {
                continue
            }
            player.prepareToPlay()
            players[cue] = player
        }
    }

    private func audioURL(named name: String, extension fileExtension: String) -> URL? {
        bundle.url(forResource: name, withExtension: fileExtension, subdirectory: "Audio")
            ?? bundle.url(forResource: name, withExtension: fileExtension, subdirectory: "Features/Orion/Audio")
            ?? bundle.url(forResource: name, withExtension: fileExtension)
    }

    private func activate() {
        do {
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            // Orion audio is ornamental; failures should never block chat.
        }
    }

    private func reset(_ player: AVAudioPlayer, loops: Int) {
        player.stop()
        player.currentTime = 0
        player.numberOfLoops = loops
        player.prepareToPlay()
    }
}
