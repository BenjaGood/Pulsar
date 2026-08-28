//
//  PulsarWatchConnectivityTransportPolicy.swift
//  Pulsar
//

import Foundation

enum PulsarWatchConnectivityMessageClass: String, Sendable {
    /// User-expecting commands. `sendMessage` when reachable.
    case interactive
    /// Overwrite latest value. Prefer `updateApplicationContext`.
    case latestState
    /// Events that must eventually arrive. `transferUserInfo` only.
    case durable
}

enum PulsarWatchConnectivityTransportPolicy {
    static func messageClass(
        messageType: String,
        reason: String = "",
        actionKind: String? = nil
    ) -> PulsarWatchConnectivityMessageClass {
        let type = messageType.lowercased()
        let kind = (actionKind ?? "").lowercased()
        let combined = "\(type) \(reason) \(kind)"

        if kind == "finishworkout" || kind == "pause" || kind == "resume" {
            return .durable
        }
        if type.contains("finish") || type.contains("terminal") || combined.contains("finishworkout") {
            return .durable
        }
        if ["pause", "resume"].contains(kind) {
            return .interactive
        }
        if type.contains("prelaunch") || type.contains("acknowledgement") {
            return .interactive
        }
        if kind == "requeststate" || type.contains("requeststate") {
            return .interactive
        }
        if kind == "completeset" || kind == "updatesetvalues" || kind == "skipresttimer" {
            return .interactive
        }
        if type.contains("heartbeat") || type.contains("activegym") || type.contains("activeworkout") {
            return .latestState
        }
        if kind == "metricsupdated" || reason.localizedCaseInsensitiveContains("tick") {
            return .latestState
        }
        if kind == "requestsavedroutines" {
            return .interactive
        }
        if kind.contains("startfree") || kind.contains("startsaved") {
            return .durable
        }
        return .interactive
    }

    static func usesInteractiveSend(
        messageType: String,
        reason: String = "",
        actionKind: String? = nil,
        isReachable: Bool,
        hasLiveWorkout: Bool
    ) -> Bool {
        guard isReachable else { return false }
        let classification = messageClass(messageType: messageType, reason: reason, actionKind: actionKind)
        if classification == .latestState { return false }
        if hasLiveWorkout, messageType.lowercased().contains("heartbeat") { return false }
        if hasLiveWorkout, (actionKind ?? "").lowercased() == "requestsavedroutines" { return false }
        return classification == .interactive || classification == .durable
    }

    static func usesLatestStateOverwrite(messageType: String, reason: String = "") -> Bool {
        messageClass(messageType: messageType, reason: reason) == .latestState
    }

    static func usesDurableTransfer(
        messageType: String,
        reason: String = "",
        actionKind: String? = nil
    ) -> Bool {
        messageClass(messageType: messageType, reason: reason, actionKind: actionKind) == .durable
    }

    static func allowsRetry(
        messageType: String,
        reason: String = "",
        actionKind: String? = nil
    ) -> Bool {
        let classification = messageClass(messageType: messageType, reason: reason, actionKind: actionKind)
        switch classification {
        case .durable:
            return true
        case .interactive:
            return actionKind?.lowercased() == "finishworkout"
        case .latestState:
            return false
        }
    }

    static func controlOutranksTelemetry(controlType: String, telemetryType: String) -> Bool {
        let control = messageClass(messageType: controlType)
        let telemetry = messageClass(messageType: telemetryType)
        return control != .latestState && telemetry == .latestState
    }
}
