//
//  OrionAnimatedLogoPlaybackController.swift
//  Pulsar
//

import AVFoundation
import Combine

enum OrionDecorativeMediaAudioSessionPolicy {
    static func shouldConfigureMixableSession(category: AVAudioSession.Category) -> Bool {
        switch category {
        case .playAndRecord, .record, .multiRoute:
            return false
        default:
            return true
        }
    }
}

@MainActor
final class OrionAnimatedLogoPlaybackController: ObservableObject {
    let player: AVQueuePlayer
    @Published private(set) var isReady = false

    private var looper: AVPlayerLooper?
    private var isPreparing = false
    private var isVisible = false
    private var reduceMotion = false
    private var sceneIsActive = true

    init() {
        let player = AVQueuePlayer()
        player.isMuted = true
        player.volume = 0
        player.actionAtItemEnd = .none
        player.allowsExternalPlayback = false
        player.automaticallyWaitsToMinimizeStalling = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        self.player = player
    }

    func prepareIfNeeded() async {
        guard looper == nil, !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }

        guard let videoURL = Self.videoURL else {
            assertionFailure("Missing bundled Orion animation resource")
            return
        }

        let asset = AVURLAsset(url: videoURL)
        do {
            let duration = try await asset.load(.duration)
            guard duration.isValid,
                  !duration.isIndefinite,
                  CMTimeGetSeconds(duration) > 0,
                  !Task.isCancelled else {
                return
            }

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let templateItem = Self.makeSilentPlayerItem(asset: asset, audioTracks: audioTracks)
            looper = AVPlayerLooper(player: player, templateItem: templateItem)
            isReady = true
            synchronizePlayback()
        } catch is CancellationError {
            return
        } catch {
            assertionFailure("Unable to prepare Orion animation: \(error)")
        }
    }

    func updatePresentationState(
        isVisible: Bool,
        reduceMotion: Bool,
        sceneIsActive: Bool
    ) {
        self.isVisible = isVisible
        self.reduceMotion = reduceMotion
        self.sceneIsActive = sceneIsActive
        synchronizePlayback()
    }

    func setVisible(_ isVisible: Bool) {
        self.isVisible = isVisible
        synchronizePlayback()
    }

    func setReduceMotion(_ reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        synchronizePlayback()
    }

    func setSceneActive(_ sceneIsActive: Bool) {
        self.sceneIsActive = sceneIsActive
        synchronizePlayback()
    }

    private func synchronizePlayback() {
        guard looper != nil else { return }

        if reduceMotion {
            player.pause()
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        } else if isVisible, sceneIsActive {
            if player.rate == 0 {
                configureMixableSessionIfSafe()
            }
            player.playImmediately(atRate: 1)
        } else {
            player.pause()
        }
    }

    private func configureMixableSessionIfSafe() {
        let session = AVAudioSession.sharedInstance()
        guard OrionDecorativeMediaAudioSessionPolicy.shouldConfigureMixableSession(
            category: session.category
        ) else {
            return
        }

        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        } catch {
            // Decorative video must never fail the screen if the session cannot be updated.
        }
    }

    static func makeSilentPlayerItem(
        asset: AVAsset,
        audioTracks: [AVAssetTrack]
    ) -> AVPlayerItem {
        let item = AVPlayerItem(asset: asset)
        guard !audioTracks.isEmpty else { return item }

        let mix = AVMutableAudioMix()
        mix.inputParameters = audioTracks.map { track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(0, at: .zero)
            return parameters
        }
        item.audioMix = mix
        return item
    }

    static var videoURL: URL? {
        Bundle.main.url(
            forResource: "orion_monochrome_alpha",
            withExtension: "mov",
            subdirectory: "Resources/Orion"
        ) ?? Bundle.main.url(
            forResource: "orion_monochrome_alpha",
            withExtension: "mov"
        )
    }
}
