//
//  PulsarWatchConnectivitySendTrace.swift
//  Pulsar
//

import Foundation
import WatchConnectivity

enum PulsarWatchConnectivitySendTrace {
    static func logSend(
        messageType: String,
        messageID: UUID,
        workoutID: UUID?,
        requestID: UUID?,
        source: String,
        attempt: Int,
        reachable: Bool
    ) {
        emit(
            "WC send attempt=\(attempt) messageID=\(messageID.uuidString) messageType=\(messageType) workoutID=\(workoutID?.uuidString ?? "none") requestID=\(requestID?.uuidString ?? "none") source=\(source) reachable=\(reachable)"
        )
    }

    static func logFailure(
        messageType: String,
        messageID: UUID,
        workoutID: UUID?,
        requestID: UUID?,
        source: String,
        attempt: Int,
        error: Error
    ) {
        let nsError = error as NSError
        let timeoutMarker = isTransferTimedOut(nsError) ? " WCErrorCodeTransferTimedOut" : ""
        emit(
            "WC send failed attempt=\(attempt) messageID=\(messageID.uuidString) messageType=\(messageType) workoutID=\(workoutID?.uuidString ?? "none") requestID=\(requestID?.uuidString ?? "none") source=\(source)\(timeoutMarker) domain=\(nsError.domain) code=\(nsError.code) error=\(error.localizedDescription)"
        )
    }

    static func isTransferTimedOut(_ error: NSError) -> Bool {
        if error.domain == WCErrorDomain, error.code == WCError.Code.transferTimedOut.rawValue {
            return true
        }
        let combined = "\(error.domain) \(error.code) \(error.localizedDescription)".lowercased()
        return combined.contains("wcerrcodetransfertimedout") || combined.contains("transfer timed out")
    }

    private static func emit(_ message: String) {
#if os(watchOS)
        PulsarWorkoutStartupTrace.watch(message)
#else
        PulsarWorkoutStartupTrace.phone(message)
#endif
    }
}
