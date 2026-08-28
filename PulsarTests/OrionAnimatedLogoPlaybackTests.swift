//
//  OrionAnimatedLogoPlaybackTests.swift
//  PulsarTests
//

import AVFoundation
import Testing
@testable import Pulsar

@MainActor
struct OrionAnimatedLogoPlaybackTests {
    @Test func mixableSessionPolicyUpgradesDefaultAndPlaybackCategories() {
        #expect(
            OrionDecorativeMediaAudioSessionPolicy.shouldConfigureMixableSession(
                category: .soloAmbient
            )
        )
        #expect(
            OrionDecorativeMediaAudioSessionPolicy.shouldConfigureMixableSession(
                category: .ambient
            )
        )
        #expect(
            OrionDecorativeMediaAudioSessionPolicy.shouldConfigureMixableSession(
                category: .playback
            )
        )
    }

    @Test func mixableSessionPolicyLeavesCaptureAndRecordingCategoriesAlone() {
        #expect(
            !OrionDecorativeMediaAudioSessionPolicy.shouldConfigureMixableSession(
                category: .playAndRecord
            )
        )
        #expect(
            !OrionDecorativeMediaAudioSessionPolicy.shouldConfigureMixableSession(
                category: .record
            )
        )
        #expect(
            !OrionDecorativeMediaAudioSessionPolicy.shouldConfigureMixableSession(
                category: .multiRoute
            )
        )
    }

    @Test func playbackControllerIsSilencedBeforeAnyPlayback() {
        let controller = OrionAnimatedLogoPlaybackController()
        #expect(controller.player.isMuted)
        #expect(controller.player.volume == 0)
        #expect(controller.player.allowsExternalPlayback == false)
        #expect(controller.player.preventsDisplaySleepDuringVideoPlayback == false)
    }

    @Test func bundledOrionLogoHasNoAudioTracks() async throws {
        guard let videoURL = OrionAnimatedLogoPlaybackController.videoURL else {
            Issue.record("Missing bundled Orion animation resource")
            return
        }

        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(audioTracks.isEmpty)
    }

    @Test func silentPlayerItemOmitsAudioMixWhenAssetHasNoAudio() async throws {
        guard let videoURL = OrionAnimatedLogoPlaybackController.videoURL else {
            Issue.record("Missing bundled Orion animation resource")
            return
        }

        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let item = OrionAnimatedLogoPlaybackController.makeSilentPlayerItem(
            asset: asset,
            audioTracks: audioTracks
        )

        #expect(item.audioMix == nil)
    }
}
