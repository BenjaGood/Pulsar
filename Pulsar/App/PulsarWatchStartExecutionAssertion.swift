//
//  PulsarWatchStartExecutionAssertion.swift
//  Pulsar
//

import UIKit

/// Keeps the iPhone process running across `startWatchApp` / mirroring handshake.
/// `startWatchApp` commonly bounces the iPhone scene inactive; without an
/// assertion the process can be suspended and Xcode reports SIGKILL (code 9).
@MainActor
final class PulsarWatchStartExecutionAssertion {
    static let shared = PulsarWatchStartExecutionAssertion()

    private var taskID: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    func begin(reason: String) {
        end(reason: "replaced")
        PulsarWorkoutStartupTrace.phone("execution assertion begin reason=\(reason)")
        taskID = UIApplication.shared.beginBackgroundTask(withName: "pulsar.watchStart.\(reason)") { [weak self] in
            Task { @MainActor in
                PulsarWorkoutStartupTrace.phone("execution assertion expired reason=\(reason)")
                self?.end(reason: "expired")
            }
        }
    }

    func end(reason: String) {
        guard taskID != .invalid else { return }
        let ending = taskID
        taskID = .invalid
        PulsarWorkoutStartupTrace.phone("execution assertion end reason=\(reason)")
        UIApplication.shared.endBackgroundTask(ending)
    }
}
