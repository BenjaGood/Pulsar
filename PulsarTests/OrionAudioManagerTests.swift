//
//  OrionAudioManagerTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

@MainActor
struct OrionAudioManagerTests {
    @Test func thinkingLifecyclePlaysStartLoopCompletionThenIdles() async throws {
        let playback = RecordingOrionAudioPlayback(
            thinkingStartDuration: 0.001,
            responseCompleteDuration: 0.001
        )
        let manager = OrionAudioManager(
            playback: playback,
            notificationCenter: NotificationCenter()
        )
        let generationID = UUID()

        manager.handle(.generating(generationID))

        #expect(manager.state == .thinkingStart)
        #expect(playback.commands == [
            .stopAll,
            .playThinkingStartSchedulingLoop
        ])

        try await waitFor {
            manager.state == .thinkingLoop
        }

        manager.handle(.completed(generationID))

        #expect(manager.state == .responseComplete)
        #expect(playback.commands.contains(.playResponseComplete))

        try await waitFor {
            manager.state == .idle
        }

        #expect(playback.commands.last == .deactivate)
    }

    @Test func cancellationStopsAudioAndPreventsQueuedLoopTransition() async throws {
        let playback = RecordingOrionAudioPlayback(
            thinkingStartDuration: 1,
            responseCompleteDuration: 0.001
        )
        let manager = OrionAudioManager(
            playback: playback,
            notificationCenter: NotificationCenter()
        )
        let generationID = UUID()

        manager.handle(.generating(generationID))
        manager.handle(.cancelled(generationID))

        #expect(manager.state == .idle)
        #expect(Array(playback.commands.suffix(2)) == [
            .stopAll,
            .deactivate
        ])

        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(manager.state == .idle)
        #expect(!playback.commands.contains(.playThinkingLoop))
        #expect(!playback.commands.contains(.playResponseComplete))
    }

    @Test func backgroundStopsCurrentRunAndIgnoresLateCompletionCue() async throws {
        let playback = RecordingOrionAudioPlayback(
            thinkingStartDuration: 0.001,
            responseCompleteDuration: 0.001
        )
        let manager = OrionAudioManager(
            playback: playback,
            notificationCenter: NotificationCenter()
        )
        let generationID = UUID()

        manager.handle(.generating(generationID))
        try await waitFor {
            manager.state == .thinkingLoop
        }

        manager.setAppIsActive(false)
        let commandCountAfterBackground = playback.commands.count
        manager.handle(.completed(generationID))

        #expect(manager.state == .idle)
        #expect(!Array(playback.commands[commandCountAfterBackground...]).contains(.playResponseComplete))

        manager.setAppIsActive(true)

        #expect(manager.state == .idle)
    }

    @Test func foregroundWhileGenerationIsStillActiveResumesThinkingLoop() {
        let playback = RecordingOrionAudioPlayback(
            thinkingStartDuration: 1,
            responseCompleteDuration: 0.001
        )
        let manager = OrionAudioManager(
            playback: playback,
            notificationCenter: NotificationCenter()
        )
        let generationID = UUID()

        manager.handle(.generating(generationID))
        manager.setAppIsActive(false)
        manager.setAppIsActive(true)

        #expect(manager.state == .thinkingLoop)
        #expect(Array(playback.commands.suffix(2)) == [
            .stopAll,
            .playThinkingLoop
        ])
    }

    @Test func failedGenerationResetsWithoutCompletionCue() async throws {
        let playback = RecordingOrionAudioPlayback(
            thinkingStartDuration: 0.001,
            responseCompleteDuration: 0.001
        )
        let manager = OrionAudioManager(
            playback: playback,
            notificationCenter: NotificationCenter()
        )
        let generationID = UUID()

        manager.handle(.generating(generationID))
        try await waitFor {
            manager.state == .thinkingLoop
        }

        manager.handle(.failed(generationID))

        #expect(manager.state == .idle)
        #expect(Array(playback.commands.suffix(2)) == [
            .stopAll,
            .deactivate
        ])
        #expect(!playback.commands.contains(.playResponseComplete))
    }

    private func waitFor(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutNanoseconds) / 1_000_000_000)
        while !condition() {
            try await Task.sleep(nanoseconds: 10_000_000)
            if Date() >= deadline {
                Issue.record("Timed out waiting for condition")
                return
            }
        }
    }
}

private enum RecordedOrionAudioCommand: Equatable {
    case playThinkingStartSchedulingLoop
    case playThinkingLoop
    case playResponseComplete
    case stopAll
    case deactivate
}

private final class RecordingOrionAudioPlayback: OrionAudioPlaybackManaging {
    let thinkingStartDuration: TimeInterval
    let responseCompleteDuration: TimeInterval
    private(set) var commands: [RecordedOrionAudioCommand] = []

    init(
        thinkingStartDuration: TimeInterval,
        responseCompleteDuration: TimeInterval
    ) {
        self.thinkingStartDuration = thinkingStartDuration
        self.responseCompleteDuration = responseCompleteDuration
    }

    func playThinkingStartSchedulingLoop() {
        commands.append(.playThinkingStartSchedulingLoop)
    }

    func playThinkingLoop() {
        commands.append(.playThinkingLoop)
    }

    func playResponseComplete() {
        commands.append(.playResponseComplete)
    }

    func stopAll() {
        commands.append(.stopAll)
    }

    func deactivate() {
        commands.append(.deactivate)
    }
}
