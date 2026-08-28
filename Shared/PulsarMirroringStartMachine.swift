//
//  PulsarMirroringStartMachine.swift
//  Pulsar
//

import Foundation

enum PulsarMirroringStartState: String, Equatable, Sendable {
    case notStarted
    case starting
    case active
    case failed
}

enum PulsarMirroringStartAction: Equatable, Sendable {
    case startAttempt(Int)
    case ignore(reason: String)
}

/// Idempotent Watch-side mirroring startup. One primary `HKWorkoutSession`
/// may enter `startMirroringToCompanionDevice` at most once unless a prior
/// attempt definitively failed.
struct PulsarMirroringStartMachine: Equatable, Sendable {
    private(set) var state: PulsarMirroringStartState = .notStarted
    private(set) var attemptCount = 0

    mutating func beginAttempt() -> PulsarMirroringStartAction {
        switch state {
        case .starting:
            return .ignore(reason: "mirroring already starting")
        case .active:
            return .ignore(reason: "mirroring already active")
        case .notStarted, .failed:
            attemptCount += 1
            state = .starting
            return .startAttempt(attemptCount)
        }
    }

    mutating func completeSuccess() {
        state = .active
    }

    mutating func completeFailure(alreadyMirroring: Bool) {
        state = alreadyMirroring ? .active : .failed
    }

    mutating func reset() {
        self = PulsarMirroringStartMachine()
    }
}

final class PulsarMirroringStartController: @unchecked Sendable {
    private var machine = PulsarMirroringStartMachine()

    var state: PulsarMirroringStartState { machine.state }
    var attemptCount: Int { machine.attemptCount }

    func beginAttempt() -> PulsarMirroringStartAction {
        machine.beginAttempt()
    }

    func completeSuccess() {
        machine.completeSuccess()
    }

    func completeFailure(alreadyMirroring: Bool) {
        machine.completeFailure(alreadyMirroring: alreadyMirroring)
    }

    func reset() {
        machine.reset()
    }
}

