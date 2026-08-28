//
//  PulsarWorkoutHandshakeLogGate.swift
//  Pulsar
//

import Foundation

/// Suppresses verbose dashboard/source-router diagnostics while a Watch
/// workout handshake or remote reconciliation is in flight.
enum PulsarWorkoutHandshakeLogGate {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var suppress = false

    static var suppressNonWorkoutDiagnostics: Bool {
        lock.lock()
        defer { lock.unlock() }
        return suppress
    }

    static func setSuppressNonWorkoutDiagnostics(_ value: Bool) {
        lock.lock()
        suppress = value
        lock.unlock()
    }
}
