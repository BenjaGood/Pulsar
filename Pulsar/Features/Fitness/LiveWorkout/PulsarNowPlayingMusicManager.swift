//
//  PulsarNowPlayingMusicManager.swift
//  Pulsar
//

import Combine
import Foundation
import MediaPlayer
import MusicKit
import UIKit

@MainActor
final class PulsarNowPlayingMusicManager: ObservableObject {
    @Published private(set) var authorizationStatus = MusicAuthorization.currentStatus
    @Published private(set) var track = PulsarNowPlayingTrack.unavailable()

    private var player: MPMusicPlayerController?
    private var observers: [NSObjectProtocol] = []
    private var hasStartedObserving = false

    func start() async {
        await requestAuthorizationIfNeeded()
        guard authorizationStatus == .authorized else {
            stopObserving()
            updateUnavailableTrackForAuthorizationStatus()
            return
        }
        let player = systemMusicPlayer()
        startObservingIfNeeded(player: player)
        updateTrack()
    }

    func playPause() {
        guard authorizationStatus == .authorized,
              track.isAvailable else { return }
        let player = systemMusicPlayer()
        if player.playbackState == .playing {
            player.pause()
        } else {
            player.play()
        }
        updateTrack()
    }

    func nextTrack() {
        guard authorizationStatus == .authorized,
              track.isAvailable else { return }
        let player = systemMusicPlayer()
        player.skipToNextItem()
        updateTrack()
    }

    func previousTrack() {
        guard authorizationStatus == .authorized,
              track.isAvailable else { return }
        let player = systemMusicPlayer()
        player.skipToPreviousItem()
        updateTrack()
    }

    private func requestAuthorizationIfNeeded() async {
        authorizationStatus = MusicAuthorization.currentStatus
        if authorizationStatus == .notDetermined {
            authorizationStatus = await MusicAuthorization.request()
        }
    }

    private func systemMusicPlayer() -> MPMusicPlayerController {
        if let player {
            return player
        }
        let player = MPMusicPlayerController.systemMusicPlayer
        self.player = player
        return player
    }

    private func startObservingIfNeeded(player: MPMusicPlayerController) {
        guard !hasStartedObserving else { return }
        hasStartedObserving = true

        let notificationCenter = NotificationCenter.default
        observers.append(
            notificationCenter.addObserver(
                forName: .MPMusicPlayerControllerNowPlayingItemDidChange,
                object: player,
                queue: .main
            ) { _ in
                Task { @MainActor [weak self] in self?.updateTrack() }
            }
        )
        observers.append(
            notificationCenter.addObserver(
                forName: .MPMusicPlayerControllerPlaybackStateDidChange,
                object: player,
                queue: .main
            ) { _ in
                Task { @MainActor [weak self] in self?.updateTrack() }
            }
        )
        observers.append(
            notificationCenter.addObserver(
                forName: .MPMusicPlayerControllerVolumeDidChange,
                object: player,
                queue: .main
            ) { _ in
                Task { @MainActor [weak self] in self?.updateTrack() }
            }
        )

        player.beginGeneratingPlaybackNotifications()
    }

    private func stopObserving() {
        let notificationCenter = NotificationCenter.default
        observers.forEach { notificationCenter.removeObserver($0) }
        observers = []
        if hasStartedObserving {
            player?.endGeneratingPlaybackNotifications()
        }
        hasStartedObserving = false
    }

    private func updateTrack() {
        switch authorizationStatus {
        case .denied, .restricted:
            track = .unavailable("Now Playing unavailable", reason: "Apple Music permission denied")
            return
        case .notDetermined:
            track = .unavailable("Now Playing unavailable", reason: "Apple Music permission needed")
            return
        case .authorized:
            break
        @unknown default:
            track = .unavailable("Now Playing unavailable", reason: "Apple Music unavailable")
            return
        }

        let player = systemMusicPlayer()
        guard let item = player.nowPlayingItem else {
            track = .unavailable("Now Playing unavailable", reason: "No music is currently playing")
            return
        }

        let artwork = item.artwork?.image(at: CGSize(width: 128, height: 128))
        let duration = item.playbackDuration
        let progress = duration > 0 ? min(max(player.currentPlaybackTime / duration, 0), 1) : nil
        let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = item.artist?.trimmingCharacters(in: .whitespacesAndNewlines)
        let albumTitle = item.albumTitle?.trimmingCharacters(in: .whitespacesAndNewlines)

        track = PulsarNowPlayingTrack(
            title: title?.isEmpty == false ? title : nil,
            artist: artist?.isEmpty == false ? artist : nil,
            albumTitle: albumTitle?.isEmpty == false ? albumTitle : nil,
            artworkImage: artwork,
            isPlaying: player.playbackState == .playing,
            progress: progress,
            statusText: player.playbackState == .playing ? "Now Playing" : "Music Paused",
            unavailableReason: nil
        )
    }

    private func updateUnavailableTrackForAuthorizationStatus() {
        switch authorizationStatus {
        case .denied, .restricted:
            track = .unavailable("Now Playing unavailable", reason: "Apple Music permission denied")
        case .notDetermined:
            track = .unavailable("Now Playing unavailable", reason: "Apple Music permission needed")
        case .authorized:
            track = .unavailable("Now Playing unavailable", reason: "No music is currently playing")
        @unknown default:
            track = .unavailable("Now Playing unavailable", reason: "Apple Music unavailable")
        }
    }

    deinit {
        let notificationCenter = NotificationCenter.default
        observers.forEach { notificationCenter.removeObserver($0) }
        if hasStartedObserving {
            player?.endGeneratingPlaybackNotifications()
        }
    }
}
