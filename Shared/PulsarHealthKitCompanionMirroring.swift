//
//  PulsarHealthKitCompanionMirroring.swift
//  Pulsar
//

import Foundation
import HealthKit

enum PulsarHealthKitCompanionMirroring {
#if os(watchOS)
    /// Starts HealthKit companion mirroring exactly once per primary session
    /// unless a previous attempt definitively failed.
    static func startMirroringToCompanionDevice(
        _ session: HKWorkoutSession,
        controller: PulsarMirroringStartController,
        reason: String
    ) async -> Bool {
        let object = String(describing: ObjectIdentifier(session))
        let previous = controller.state
        switch controller.beginAttempt() {
        case .ignore(let ignoreReason):
            PulsarWorkoutStartupTrace.watch(
                "[MirrorStart] attempt ignored because \(ignoreReason) primaryObject=\(object) state=\(previous.rawValue) reason=\(reason)"
            )
            PulsarWorkoutStartupTrace.diag(
                "[MirrorStart] await skipped because \(ignoreReason) primaryObject=\(object) state=\(previous.rawValue) hkState=\(session.state.rawValue) \(PulsarWorkoutStartupTrace.threadTag())"
            )
            return controller.state == .active
        case .startAttempt(let attempt):
            let startedAt = Date()
            PulsarWorkoutStartupTrace.watch(
                "[MirrorStart] primaryObject=\(object) attempt=\(attempt) state=\(previous.rawValue)->starting reason=\(reason)"
            )
            PulsarWorkoutStartupTrace.diag(
                "[MirrorStart] await begin attempt=\(attempt) primaryObject=\(object) hkState=\(session.state.rawValue) \(PulsarWorkoutStartupTrace.threadTag()) reason=\(reason)"
            )
            do {
                try await session.startMirroringToCompanionDevice()
                controller.completeSuccess()
                PulsarWorkoutStartupTrace.watch(
                    "[MirrorStart] attempt=\(attempt) completion success primaryObject=\(object)"
                )
                PulsarWorkoutStartupTrace.diag(
                    "[MirrorStart] await end success attempt=\(attempt) elapsedMs=\(PulsarWorkoutStartupTrace.elapsedMs(since: startedAt)) primaryObject=\(object) hkState=\(session.state.rawValue) \(PulsarWorkoutStartupTrace.threadTag())"
                )
                PulsarSyncDebugLogger.log("\(reason) mirroring started attempt=\(attempt)")
                return true
            } catch {
                let alreadyMirroring = isAlreadyMirroringError(error)
                controller.completeFailure(alreadyMirroring: alreadyMirroring)
                if alreadyMirroring {
                    PulsarWorkoutStartupTrace.watch(
                        "[MirrorStart] attempt=\(attempt) completion alreadyMirroring primaryObject=\(object)"
                    )
                    PulsarWorkoutStartupTrace.diag(
                        "[MirrorStart] await end alreadyMirroring attempt=\(attempt) elapsedMs=\(PulsarWorkoutStartupTrace.elapsedMs(since: startedAt)) primaryObject=\(object) hkState=\(session.state.rawValue) \(PulsarWorkoutStartupTrace.threadTag())"
                    )
                    return true
                }
                PulsarWorkoutStartupTrace.watch(
                    "[MirrorStart] attempt=\(attempt) completion failure primaryObject=\(object) error=\(error.localizedDescription)"
                )
                PulsarWorkoutStartupTrace.diag(
                    "[MirrorStart] await end failure attempt=\(attempt) elapsedMs=\(PulsarWorkoutStartupTrace.elapsedMs(since: startedAt)) primaryObject=\(object) hkState=\(session.state.rawValue) error=\(error.localizedDescription) \(PulsarWorkoutStartupTrace.threadTag())"
                )
                PulsarSyncDebugLogger.log(
                    "\(reason) mirroring failed attempt=\(attempt) error=\(error.localizedDescription)"
                )
                return false
            }
        }
    }

    private static func isAlreadyMirroringError(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("already") && (text.contains("mirror") || text.contains("companion"))
    }
#endif
}
