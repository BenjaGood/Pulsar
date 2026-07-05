//
//  PulsarActiveWorkoutManager.swift
//  Pulsar
//

import Combine
import SwiftUI

enum PulsarPresentedWorkout: Identifiable, Hashable {
    case run(PulsarOutdoorWorkoutKind)
    case gym
    case watchGym

    var id: String {
        switch self {
        case .run(let kind): "run-\(kind.rawValue)"
        case .gym: "gym"
        case .watchGym: "watch-gym"
        }
    }
}

enum PulsarActiveWorkoutKind: Equatable {
    case run(PulsarOutdoorWorkoutKind)
    case gym
    case watchGym

    init(route: PulsarPresentedWorkout) {
        switch route {
        case .run(let workoutKind):
            self = .run(workoutKind)
        case .gym:
            self = .gym
        case .watchGym:
            self = .watchGym
        }
    }

    var route: PulsarPresentedWorkout {
        switch self {
        case .run(let workoutKind):
            .run(workoutKind)
        case .gym:
            .gym
        case .watchGym:
            .watchGym
        }
    }

    var logType: String {
        switch self {
        case .run(let workoutKind):
            workoutKind.rawValue
        case .gym:
            "gym"
        case .watchGym:
            "watchGym"
        }
    }
}

struct PulsarActiveWorkout: Equatable, Identifiable {
    var id: UUID { sessionID }

    let sessionID: UUID
    var kind: PulsarActiveWorkoutKind
    var phase: String
    var updatedAt: Date

    static func == (lhs: PulsarActiveWorkout, rhs: PulsarActiveWorkout) -> Bool {
        lhs.sessionID == rhs.sessionID &&
            lhs.kind == rhs.kind &&
            lhs.phase == rhs.phase
    }
}

enum PulsarActiveWorkoutPresentation: Equatable, CustomStringConvertible {
    case hidden
    case expanded(UUID)
    case minimized(UUID)

    var sessionID: UUID? {
        switch self {
        case .hidden:
            nil
        case .expanded(let sessionID), .minimized(let sessionID):
            sessionID
        }
    }

    var description: String {
        switch self {
        case .hidden:
            "hidden"
        case .expanded:
            "expanded"
        case .minimized:
            "minimized"
        }
    }
}

@MainActor
final class PulsarActiveWorkoutManager: ObservableObject {
    @Published var presentedWorkout: PulsarPresentedWorkout?
    @Published private(set) var activeWorkout: PulsarActiveWorkout?
    @Published private(set) var presentation: PulsarActiveWorkoutPresentation = .hidden
    @Published private(set) var userMinimizedActiveWorkoutSessionID: UUID?
    @Published private(set) var minimizedRunWorkoutKind: PulsarOutdoorWorkoutKind?
    @Published private(set) var gymSessionViewModel: GymWorkoutSessionViewModel?
    @Published private(set) var isGymWorkoutMinimized = false
    @Published private(set) var adaptiveStrainPlan: AdaptiveStrainPlan?

    private var automaticallyOpenedActiveWorkoutSessionID: UUID?
    private var lastVisiblePresentationBySessionID: [UUID: PulsarActiveWorkoutPresentation] = [:]

    var activeWorkoutSessionID: UUID? {
        activeWorkout?.sessionID
    }

    @discardableResult
    func reconcileActiveWorkoutPresentation(
        route: PulsarPresentedWorkout,
        sessionID: UUID,
        phase: String = "active",
        reason: String
    ) -> Bool {
        let isNewSession = activeWorkout?.sessionID != sessionID
        setActiveWorkout(kind: PulsarActiveWorkoutKind(route: route), sessionID: sessionID, phase: phase)

        if isNewSession {
            userMinimizedActiveWorkoutSessionID = nil
            setPresentation(.hidden, reason: "newSession.\(reason)")
        }

        if userMinimizedActiveWorkoutSessionID == sessionID || presentation == .minimized(sessionID) {
            setPresentation(.minimized(sessionID), reason: reason)
            if presentedWorkout == route {
                presentedWorkout = nil
            }
            PulsarSyncDebugLogger.log("Preserving minimized active workout presentation for session=\(sessionID.uuidString)")
            PulsarSyncDebugLogger.log("Skipped auto-opening active workout route because session is already presented/minimized session=\(sessionID.uuidString) reason=\(reason)")
            return false
        }

        if automaticallyOpenedActiveWorkoutSessionID == sessionID {
            if presentation == .hidden {
                recoverPresentation(for: sessionID, route: route, reason: "duplicateSync.\(reason)")
            } else if presentedWorkout == route {
                setPresentation(.expanded(sessionID), reason: reason)
            }
            PulsarSyncDebugLogger.log("Skipped auto-opening active workout route because session is already presented/minimized session=\(sessionID.uuidString) reason=\(reason)")
            return false
        }

        automaticallyOpenedActiveWorkoutSessionID = sessionID
        userMinimizedActiveWorkoutSessionID = nil
        setPresentation(.expanded(sessionID), reason: reason)
        presentedWorkout = route
        return true
    }

    func minimizeRunWorkout(_ workoutKind: PulsarOutdoorWorkoutKind, sessionID: UUID? = nil) {
        PulsarUIDebugLogger.log("Minimize requested currentSession=\((sessionID ?? activeWorkoutSessionID)?.uuidString ?? "none")")
        guard let resolvedSessionID = sessionID ?? activeWorkoutSessionID else {
            PulsarUIDebugLogger.log("Minimize blocked because active workout sessionID is nil")
            return
        }
        setActiveWorkout(kind: .run(workoutKind), sessionID: resolvedSessionID, phase: "active")
        userMinimizedActiveWorkoutSessionID = resolvedSessionID
        minimizedRunWorkoutKind = workoutKind
        if case .run = presentedWorkout {
            presentedWorkout = nil
        }
        setPresentation(.minimized(resolvedSessionID), reason: "minimizeRun")
    }

    func presentRunWorkout(_ workoutKind: PulsarOutdoorWorkoutKind, sessionID: UUID? = nil) {
        guard let resolvedSessionID = sessionID ?? activeWorkoutSessionID else {
            PulsarStateDebugLogger.log("Refused to present run workout because sessionID was nil type=\(workoutKind.rawValue)")
            return
        }
        setActiveWorkout(kind: .run(workoutKind), sessionID: resolvedSessionID, phase: "active")
        clearUserMinimizedOverrideIfNeeded(sessionID: resolvedSessionID)
        setPresentation(.expanded(resolvedSessionID), reason: "presentRun")
        presentedWorkout = .run(workoutKind)
    }

    func presentRunSummary(_ workoutKind: PulsarOutdoorWorkoutKind, sessionID: UUID) {
        setActiveWorkout(kind: .run(workoutKind), sessionID: sessionID, phase: "finished")
        clearUserMinimizedOverrideIfNeeded(sessionID: sessionID)
        setPresentation(.expanded(sessionID), reason: "presentRunSummary")
        presentedWorkout = .run(workoutKind)
        PulsarStateDebugLogger.log("[PulsarSummary] Run summary presentation retained session=\(sessionID.uuidString) type=\(workoutKind.rawValue)")
    }

    func clearRunWorkout(
        sessionID: UUID? = nil,
        phase: String = "ended",
        source: String = "explicit",
        reason: String = "clearRunWorkout"
    ) {
        guard Self.isTerminalClearPhase(phase) else {
            logBlockedNilTransition(
                sessionID: sessionID,
                phase: phase,
                source: source,
                reason: reason,
                blockedReason: "nonTerminalPhase"
            )
            return
        }
        guard shouldMutateActiveWorkout(sessionID: sessionID) else {
            logBlockedNilTransition(
                sessionID: sessionID,
                phase: phase,
                source: source,
                reason: reason,
                blockedReason: "sessionMismatch"
            )
            return
        }
        minimizedRunWorkoutKind = nil
        if case .run = presentedWorkout {
            presentedWorkout = nil
        }
        clearPresentationStateIfNeeded(
            sessionID: sessionID,
            phase: phase,
            source: source,
            reason: reason
        )
    }

    func startGymWorkout(
        routine: PulsarRoutine,
        workoutWeightUnit: PulsarWeightUnit?,
        historyStore: PulsarGymWorkoutHistoryStore? = nil
    ) {
        PulsarStateDebugLogger.log("Workout start requested type=gym")
        if let gymSessionViewModel, gymSessionViewModel.summary == nil {
            isGymWorkoutMinimized = false
            if let activeWorkout {
                setPresentation(.expanded(activeWorkout.sessionID), reason: "resumeExistingGym")
            }
            return
        }

        gymSessionViewModel = GymWorkoutSessionViewModel(
            routine: routine,
            workoutWeightUnit: workoutWeightUnit,
            historyStore: historyStore,
            adaptiveStrainPlan: adaptiveStrainPlan
        )
        if let sessionID = gymSessionViewModel?.session.id {
            setActiveWorkout(kind: .gym, sessionID: sessionID, phase: "active")
            clearUserMinimizedOverrideIfNeeded(sessionID: sessionID)
            setPresentation(.expanded(sessionID), reason: "startGym")
        }
        isGymWorkoutMinimized = false
    }

    func setAdaptiveStrainPlan(_ plan: AdaptiveStrainPlan?, reason: String) {
        adaptiveStrainPlan = plan
        gymSessionViewModel?.setAdaptiveStrainPlan(plan, reason: reason)
        PulsarStateDebugLogger.log("[PulsarAdaptiveStrainGuard] active workout manager plan updated reason=\(reason) target=\(plan?.recommendedRange.displayText ?? "nil") priority=\(plan?.recoveryPriority.rawValue ?? "nil")")
    }

    func minimizeGymWorkout(sessionID: UUID? = nil) {
        PulsarUIDebugLogger.log("Minimize requested currentSession=\((sessionID ?? gymSessionViewModel?.session.id ?? activeWorkoutSessionID)?.uuidString ?? "none")")
        guard gymSessionViewModel?.summary == nil else {
            completeGymWorkout()
            return
        }
        let resolvedSessionID = sessionID ?? gymSessionViewModel?.session.id ?? activeWorkoutSessionID
        guard let resolvedSessionID else {
            PulsarUIDebugLogger.log("Minimize blocked because active workout sessionID is nil")
            return
        }
        setActiveWorkout(kind: .gym, sessionID: resolvedSessionID, phase: "active")
        userMinimizedActiveWorkoutSessionID = resolvedSessionID
        isGymWorkoutMinimized = true
        if case .gym = presentedWorkout {
            presentedWorkout = nil
        }
        setPresentation(.minimized(resolvedSessionID), reason: "minimizeGym")
    }

    func presentGymWorkout(sessionID: UUID? = nil) {
        guard gymSessionViewModel?.summary == nil else {
            completeGymWorkout()
            return
        }
        let resolvedSessionID = sessionID ?? gymSessionViewModel?.session.id
        guard let resolvedSessionID else {
            PulsarStateDebugLogger.log("Refused to present gym workout because sessionID was nil")
            return
        }
        setActiveWorkout(kind: .gym, sessionID: resolvedSessionID, phase: "active")
        clearUserMinimizedOverrideIfNeeded(sessionID: resolvedSessionID)
        presentedWorkout = .gym
        setPresentation(.expanded(resolvedSessionID), reason: "presentGym")
    }

    func completeGymWorkout() {
        let sessionID = gymSessionViewModel?.session.id
        gymSessionViewModel = nil
        isGymWorkoutMinimized = false
        if case .gym = presentedWorkout {
            presentedWorkout = nil
        }
        clearPresentationStateIfNeeded(
            sessionID: sessionID,
            phase: "ended",
            source: "local",
            reason: "completeGymWorkout"
        )
    }

    func presentWatchGymWorkout(sessionID: UUID? = nil) {
        guard let resolvedSessionID = sessionID ?? activeWorkoutSessionID else {
            PulsarStateDebugLogger.log("Refused to present watch gym workout because sessionID was nil")
            return
        }
        setActiveWorkout(kind: .watchGym, sessionID: resolvedSessionID, phase: "active")
        clearUserMinimizedOverrideIfNeeded(sessionID: resolvedSessionID)
        presentedWorkout = .watchGym
        setPresentation(.expanded(resolvedSessionID), reason: "presentWatchGym")
    }

    func presentWatchGymSummary(sessionID: UUID) {
        setActiveWorkout(kind: .watchGym, sessionID: sessionID, phase: "finished")
        clearUserMinimizedOverrideIfNeeded(sessionID: sessionID)
        setPresentation(.expanded(sessionID), reason: "presentWatchGymSummary")
        presentedWorkout = .watchGym
        PulsarStateDebugLogger.log("[PulsarSummary] Watch gym summary presentation retained session=\(sessionID.uuidString)")
    }

    func minimizeWatchGymWorkout(sessionID: UUID? = nil) {
        PulsarUIDebugLogger.log("Minimize requested currentSession=\((sessionID ?? activeWorkoutSessionID)?.uuidString ?? "none")")
        guard let resolvedSessionID = sessionID ?? activeWorkoutSessionID else {
            PulsarUIDebugLogger.log("Minimize blocked because active workout sessionID is nil")
            return
        }
        setActiveWorkout(kind: .watchGym, sessionID: resolvedSessionID, phase: "active")
        userMinimizedActiveWorkoutSessionID = resolvedSessionID
        if case .watchGym = presentedWorkout {
            presentedWorkout = nil
        }
        setPresentation(.minimized(resolvedSessionID), reason: "minimizeWatchGym")
    }

    func clearWatchGymWorkout(
        sessionID: UUID? = nil,
        phase: String = "ended",
        source: String = "explicit",
        reason: String = "clearWatchGymWorkout"
    ) {
        guard Self.isTerminalClearPhase(phase) else {
            logBlockedNilTransition(
                sessionID: sessionID,
                phase: phase,
                source: source,
                reason: reason,
                blockedReason: "nonTerminalPhase"
            )
            return
        }
        guard shouldMutateActiveWorkout(sessionID: sessionID) else {
            logBlockedNilTransition(
                sessionID: sessionID,
                phase: phase,
                source: source,
                reason: reason,
                blockedReason: "sessionMismatch"
            )
            return
        }
        if case .watchGym = presentedWorkout {
            presentedWorkout = nil
        }
        clearPresentationStateIfNeeded(
            sessionID: sessionID,
            phase: phase,
            source: source,
            reason: reason
        )
    }

    private func setActiveWorkout(kind: PulsarActiveWorkoutKind, sessionID: UUID, phase: String) {
        let isNewSession = activeWorkout?.sessionID != sessionID
        let nextWorkout = PulsarActiveWorkout(
            sessionID: sessionID,
            kind: kind,
            phase: phase,
            updatedAt: Date()
        )
        guard activeWorkout != nextWorkout else { return }
        activeWorkout = nextWorkout
        if case .run(let workoutKind) = kind {
            minimizedRunWorkoutKind = workoutKind
        }
        if isNewSession {
            PulsarStateDebugLogger.log("Active workout created session=\(sessionID.uuidString) type=\(kind.logType)")
        }
        PulsarStateDebugLogger.log("Active workout set session=\(sessionID.uuidString) type=\(kind.logType) phase=\(phase)")
    }

    private func setPresentation(_ nextPresentation: PulsarActiveWorkoutPresentation, reason: String) {
        guard presentation != nextPresentation else { return }
        let previous = presentation
        presentation = nextPresentation
        if let sessionID = nextPresentation.sessionID {
            lastVisiblePresentationBySessionID[sessionID] = nextPresentation
        }
        PulsarUIDebugLogger.log("Presentation changed \(previous.description) -> \(nextPresentation.description) session=\(nextPresentation.sessionID?.uuidString ?? "none") reason=\(reason)")
    }

    private func clearUserMinimizedOverrideIfNeeded(sessionID: UUID?) {
        guard let sessionID else { return }
        if userMinimizedActiveWorkoutSessionID == sessionID {
            userMinimizedActiveWorkoutSessionID = nil
        }
    }

    private func shouldMutateActiveWorkout(sessionID: UUID?) -> Bool {
        guard let sessionID else {
            return activeWorkout == nil
        }
        return activeWorkout?.sessionID == sessionID
    }

    private func clearPresentationStateIfNeeded(
        sessionID: UUID?,
        phase: String,
        source: String,
        reason: String
    ) {
        let previousSessionID = activeWorkout?.sessionID
        let allowed = activeWorkout == nil || activeWorkout?.sessionID == sessionID
        PulsarStateDebugLogger.log("Active workout nil transition requested previousSession=\(previousSessionID?.uuidString ?? "none") incomingSession=\(sessionID?.uuidString ?? "none") phase=\(phase) source=\(source) reason=\(reason) allowed=\(allowed)")
        guard allowed else { return }
        activeWorkout = nil
        automaticallyOpenedActiveWorkoutSessionID = nil
        userMinimizedActiveWorkoutSessionID = nil
        if let sessionID {
            lastVisiblePresentationBySessionID[sessionID] = nil
        }
        setPresentation(.hidden, reason: "clear.\(reason)")
        PulsarStateDebugLogger.log("Active workout nil transition applied previousSession=\(previousSessionID?.uuidString ?? "none") incomingSession=\(sessionID?.uuidString ?? "none") phase=\(phase) source=\(source) reason=\(reason)")
    }

    func reconcilePresentationIntegrity(reason: String) {
        if presentation == .hidden {
            guard let activeWorkout else { return }
            recoverPresentation(for: activeWorkout.sessionID, route: activeWorkout.kind.route, reason: "integrity.\(reason)")
            return
        }

        guard let activeWorkout else {
            PulsarStateDebugLogger.log("Reconciled invalid presentation with nil activeWorkout action=hideWithoutAlert reason=\(reason)")
            setPresentation(.hidden, reason: "invalidPresentation.\(reason)")
            return
        }

        guard presentation.sessionID == activeWorkout.sessionID else {
            PulsarStateDebugLogger.log("Reconciled invalid presentation session mismatch presentationSession=\(presentation.sessionID?.uuidString ?? "none") activeSession=\(activeWorkout.sessionID.uuidString) action=recover reason=\(reason)")
            recoverPresentation(for: activeWorkout.sessionID, route: activeWorkout.kind.route, reason: "sessionMismatch.\(reason)")
            return
        }
    }

    private func recoverPresentation(for sessionID: UUID, route: PulsarPresentedWorkout, reason: String) {
        let preferredPresentation = preferredPresentation(for: sessionID)
        PulsarStateDebugLogger.log("Recovered active workout presentation session=\(sessionID.uuidString) presentation=\(preferredPresentation.description) reason=\(reason)")
        setPresentation(preferredPresentation, reason: "recover.\(reason)")
        if preferredPresentation == .expanded(sessionID) {
            presentedWorkout = route
            automaticallyOpenedActiveWorkoutSessionID = sessionID
        } else if presentedWorkout == route {
            presentedWorkout = nil
        }
    }

    private func preferredPresentation(for sessionID: UUID) -> PulsarActiveWorkoutPresentation {
        if userMinimizedActiveWorkoutSessionID == sessionID {
            return .minimized(sessionID)
        }
        if lastVisiblePresentationBySessionID[sessionID] == .minimized(sessionID) {
            return .minimized(sessionID)
        }
        return .expanded(sessionID)
    }

    private func logBlockedNilTransition(
        sessionID: UUID?,
        phase: String,
        source: String,
        reason: String,
        blockedReason: String
    ) {
        PulsarStateDebugLogger.log("Active workout nil transition blocked previousSession=\(activeWorkoutSessionID?.uuidString ?? "none") incomingSession=\(sessionID?.uuidString ?? "none") phase=\(phase) source=\(source) reason=\(reason) blockedReason=\(blockedReason)")
    }

    private static func isTerminalClearPhase(_ phase: String) -> Bool {
        switch phase {
        case "ended", "finished", "failed", "cancelled", "canceled", "stopped", "completed":
            true
        default:
            false
        }
    }
}

enum PulsarStateDebugLogger {
    static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        guard isEnabled else { return }
        print("[PulsarState] \(message())")
        #endif
    }

    #if DEBUG
    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["PULSAR_STATE_DEBUG_LOGS"] == "1"
    }
    #endif
}
