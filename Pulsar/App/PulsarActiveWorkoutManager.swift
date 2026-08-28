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
    let kind: PulsarActiveWorkoutKind
    var phase: String
    var updatedAt: Date

    static func == (lhs: PulsarActiveWorkout, rhs: PulsarActiveWorkout) -> Bool {
        lhs.sessionID == rhs.sessionID &&
            lhs.kind == rhs.kind &&
            lhs.phase == rhs.phase
    }
}

struct PulsarDismissedWorkoutPresentation: Equatable {
    let workout: PulsarPresentedWorkout
    let sessionID: UUID
}

/// The sheet identity is the canonical workout session, not the route name.
/// A new Watch Gym session must therefore create a new presentation identity,
/// while repeated packets for the same session update the existing sheet.
struct PulsarPresentedWorkoutItem: Identifiable, Equatable, Hashable {
    let workout: PulsarPresentedWorkout
    let sessionID: UUID

    var id: UUID { sessionID }
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

/// Modal route and presentation mode are one published value so SwiftUI never
/// observes an expanded workout without its sheet item (or vice versa).
enum PulsarActiveWorkoutPresentationState: Equatable {
    case hidden
    case launchOwned(UUID)
    case handoffPending(PulsarPresentedWorkoutItem)
    case expanded(PulsarPresentedWorkoutItem)
    case dismissing(PulsarPresentedWorkoutItem)
    case minimizing(UUID)
    case minimized(UUID)

    var presentation: PulsarActiveWorkoutPresentation {
        switch self {
        case .hidden:
            .hidden
        case .launchOwned(let sessionID):
            .expanded(sessionID)
        case .handoffPending(let item):
            .expanded(item.sessionID)
        case .expanded(let item):
            .expanded(item.sessionID)
        case .dismissing(let item):
            .expanded(item.sessionID)
        case .minimizing(let sessionID):
            .expanded(sessionID)
        case .minimized(let sessionID):
            .minimized(sessionID)
        }
    }

    var item: PulsarPresentedWorkoutItem? {
        guard case .expanded(let item) = self else { return nil }
        return item
    }

    var handoffPendingItem: PulsarPresentedWorkoutItem? {
        guard case .handoffPending(let item) = self else { return nil }
        return item
    }

    var minimizingSessionID: UUID? {
        guard case .minimizing(let sessionID) = self else { return nil }
        return sessionID
    }

    var diagnosticName: String {
        switch self {
        case .hidden: "hidden"
        case .launchOwned: "launchOwned"
        case .handoffPending: "handoffPending"
        case .expanded: "expanded"
        case .dismissing: "dismissing"
        case .minimizing: "minimizing"
        case .minimized: "minimized"
        }
    }
}

@MainActor
final class PulsarActiveWorkoutManager: ObservableObject {
    static let shared = PulsarActiveWorkoutManager()

    @Published private(set) var presentationState: PulsarActiveWorkoutPresentationState = .hidden
    @Published private(set) var activeWorkout: PulsarActiveWorkout?
    @Published private(set) var userMinimizedActiveWorkoutSessionID: UUID?
    @Published private(set) var minimizedRunWorkoutKind: PulsarOutdoorWorkoutKind?
    @Published private(set) var gymSessionViewModel: GymWorkoutSessionViewModel?
    @Published private(set) var isGymWorkoutMinimized = false
    @Published private(set) var adaptiveStrainPlan: AdaptiveStrainPlan?

    private var automaticallyOpenedActiveWorkoutSessionID: UUID?
    private var lastVisiblePresentationBySessionID: [UUID: PulsarActiveWorkoutPresentation] = [:]
    private var pendingDismissedWorkouts: [PulsarDismissedWorkoutPresentation] = []
    private var rootPresentationHandoffReason: String?
    /// Fitness full-screen launch cover currently hosts the live workout UI.
    /// Reconcile must not publish a competing root sheet while this is true.
    private var launchCoverOwnsPresentation = false
    private(set) var presentationCommitCount = 0
    private(set) var retainedFinishedWatchGymSessionID: UUID?

    var isLaunchCoverOwningPresentation: Bool {
        launchCoverOwnsPresentation
    }

    var presentation: PulsarActiveWorkoutPresentation {
        presentationState.presentation
    }

    var presentedWorkoutItem: PulsarPresentedWorkoutItem? {
        presentationState.item
    }

    /// Compatibility surface for existing call sites and tests. All writes are
    /// translated into the atomic presentation state above.
    var presentedWorkout: PulsarPresentedWorkout? {
        get { presentedWorkoutItem?.workout }
        set {
            guard let newValue else {
                setPresentation(.hidden, reason: "presentedWorkoutBindingCleared")
                return
            }
            guard let sessionID = presentation.sessionID ?? activeWorkout?.sessionID else {
                PulsarStateDebugLogger.log("Refused workout sheet route without a canonical session route=\(newValue.id)")
                return
            }
            setExpandedPresentation(
                route: newValue,
                sessionID: sessionID,
                reason: "presentedWorkoutBindingSet"
            )
        }
    }

    var isRootPresentationHandoffDeferred: Bool {
        rootPresentationHandoffReason != nil
    }

    func consumePendingDismissedWorkout() -> PulsarDismissedWorkoutPresentation? {
        guard !pendingDismissedWorkouts.isEmpty else { return nil }
        return pendingDismissedWorkouts.removeFirst()
    }

    /// UIKit can coalesce dismissal callbacks while a stale sheet is being
    /// replaced. Drain older identities so the single callback for the current
    /// sheet cannot be consumed by an obsolete session record.
    func consumePendingDismissedCurrentWorkout() -> PulsarDismissedWorkoutPresentation? {
        while let dismissal = consumePendingDismissedWorkout() {
            guard isCurrentWorkout(dismissal) else {
                PulsarUIDebugLogger.log(
                    "Drained stale workout dismissal dismissedSession=\(dismissal.sessionID.uuidString) currentSession=\(activeWorkout?.sessionID.uuidString ?? "none") route=\(dismissal.workout.id)"
                )
                continue
            }
            return dismissal
        }
        return nil
    }

    func isCurrentWorkout(_ dismissal: PulsarDismissedWorkoutPresentation) -> Bool {
        guard let activeWorkout,
              activeWorkout.sessionID == dismissal.sessionID else { return false }
        return activeWorkout.kind == PulsarActiveWorkoutKind(route: dismissal.workout)
    }

    var activeWorkoutSessionID: UUID? {
        activeWorkout?.sessionID
    }

    func updatePresentedWorkoutItemFromSheet(_ item: PulsarPresentedWorkoutItem?) {
        guard let item else {
            // UIKit may write nil after a programmatic minimize. Only an
            // actually expanded sheet may begin an interactive dismissal.
            guard case .expanded(let currentItem) = presentationState else { return }
            commitPresentationState(
                .dismissing(currentItem),
                reason: "sheetBindingDismissed"
            )
            return
        }
        setExpandedPresentation(
            route: item.workout,
            sessionID: item.sessionID,
            reason: "sheetBindingPresented"
        )
    }

    /// Begins a transition owned by a Fitness full-screen launch flow. While
    /// active, the manager may attach the canonical session but cannot ask the
    /// root to present a sheet over that still-present cover.
    func beginRootPresentationHandoff(reason: String) {
        guard rootPresentationHandoffReason == nil else { return }
        rootPresentationHandoffReason = reason
        PulsarUIDebugLogger.log("Root workout presentation deferred reason=\(reason)")
        PulsarPerformanceDiagnostics.event("workout.handoff.begin")
    }

    /// Marks the Fitness gym launch cover as the live host. Watch gym
    /// activation must keep this owner instead of dismissing into a root sheet.
    func beginLaunchCoverOwnership(reason: String) {
        launchCoverOwnsPresentation = true
        PulsarUIDebugLogger.log("Launch cover owns live workout presentation reason=\(reason)")
        PulsarPerformanceDiagnostics.event("workout.launchOwner.begin")
    }

    func endLaunchCoverOwnership(reason: String) {
        guard launchCoverOwnsPresentation else { return }
        launchCoverOwnsPresentation = false
        PulsarUIDebugLogger.log("Launch cover released live workout presentation reason=\(reason)")
    }

    /// Called only from the launch cover's actual `onDismiss` completion.
    /// Returning true means the canonical session was exposed to the root in
    /// this call and Fitness should not start a competing full refresh.
    @discardableResult
    func completeRootPresentationHandoff(reason: String) -> Bool {
        guard let deferralReason = rootPresentationHandoffReason else { return false }
        rootPresentationHandoffReason = nil

        guard let item = presentationState.handoffPendingItem,
              let activeWorkout,
              activeWorkout.sessionID == item.sessionID,
              activeWorkout.kind.route == item.workout,
              userMinimizedActiveWorkoutSessionID != item.sessionID else {
            PulsarUIDebugLogger.log("Root workout presentation handoff completed without route begin=\(deferralReason) end=\(reason)")
            return false
        }

        automaticallyOpenedActiveWorkoutSessionID = item.sessionID
        PulsarWorkoutStartupTrace.diag(
            "[WorkoutUI] sheetItemPublished session=\(item.sessionID.uuidString) begin=\(deferralReason) end=\(reason) \(PulsarWorkoutStartupTrace.threadTag())"
        )
        commitPresentationState(
            .expanded(item),
            reason: "handoff.\(reason)"
        )
        PulsarUIDebugLogger.log("Root workout presentation handoff completed session=\(item.sessionID.uuidString) begin=\(deferralReason) end=\(reason)")
        PulsarPerformanceDiagnostics.checkpoint("workout.handoff.presented")
        return true
    }

    func cancelRootPresentationHandoff(reason: String) {
        guard rootPresentationHandoffReason != nil || presentationState.handoffPendingItem != nil else { return }
        let pendingSessionID = presentationState.handoffPendingItem?.sessionID
        rootPresentationHandoffReason = nil
        if let pendingSessionID {
            if activeWorkout?.sessionID == pendingSessionID {
                requestMinimizedPresentation(
                    sessionID: pendingSessionID,
                    reason: "cancelledHandoff.\(reason)"
                )
            } else {
                commitPresentationState(.hidden, reason: "cancelledHandoff.\(reason)")
            }
        }
        PulsarUIDebugLogger.log("Root workout presentation handoff cancelled reason=\(reason)")
        PulsarPerformanceDiagnostics.event("workout.handoff.cancel")
    }

    /// Resolves a launch cover that disappeared without first handing its live
    /// workout to the root presenter. This preserves the canonical session and
    /// exposes it through the mini player instead of leaving an ownerless
    /// expanded/no-item state.
    @discardableResult
    func reconcileLaunchOwnerDismissal(reason: String) -> Bool {
        let sessionID: UUID
        switch presentationState {
        case .launchOwned(let ownedSessionID), .minimizing(let ownedSessionID):
            sessionID = ownedSessionID
        case .hidden, .handoffPending, .expanded, .dismissing, .minimized:
            return false
        }

        guard finalizeMinimizedPresentation(
            sessionID: sessionID,
            expectedWorkout: nil,
            reason: "launchOwnerDismissed.\(reason)"
        ) else { return false }
        PulsarUIDebugLogger.log("Launch-owned workout minimized after owner dismissal session=\(sessionID.uuidString) reason=\(reason)")
        return true
    }

    /// Finalizes a root workout sheet transition only after UIKit confirms that
    /// the presentation has left the hierarchy. Until this callback, the
    /// coarse presentation remains expanded so bottom chrome stays suppressed.
    @discardableResult
    func finalizeWorkoutPresentationDismissal(
        _ dismissal: PulsarDismissedWorkoutPresentation,
        reason: String
    ) -> Bool {
        guard isCurrentWorkout(dismissal) else { return false }
        switch presentationState {
        case .dismissing(let item) where item.sessionID == dismissal.sessionID:
            break
        case .minimizing(let sessionID) where sessionID == dismissal.sessionID:
            break
        case .minimized(let sessionID) where sessionID == dismissal.sessionID:
            return true
        default:
            return false
        }
        return finalizeMinimizedPresentation(
            sessionID: dismissal.sessionID,
            expectedWorkout: dismissal.workout,
            reason: "rootPresentationDismissed.\(reason)"
        )
    }

    @discardableResult
    func reconcileVerifiedWatchGymWorkout(
        sessionID: UUID,
        phase: String,
        reason: String
    ) -> Bool {
        guard PulsarWorkoutStartCoordinator.shared.isCrossDeviceGymStartVerified else {
            PulsarStateDebugLogger.log("Refused verified watch gym presentation without coordinator verification session=\(sessionID.uuidString) reason=\(reason)")
            return false
        }
        return reconcileActiveWorkoutPresentation(
            route: .watchGym,
            sessionID: sessionID,
            phase: phase,
            reason: reason
        )
    }

    @discardableResult
    func reconcileActiveWorkoutPresentation(
        route: PulsarPresentedWorkout,
        sessionID: UUID,
        phase: String = "active",
        reason: String
    ) -> Bool {
        if Self.isLivePresentationPhase(phase),
           !Self.canPresentLiveWorkout(sessionID: sessionID) {
            PulsarStateDebugLogger.log(
                "Refused live reconcile without lifecycle authority session=\(sessionID.uuidString) route=\(route.id) phase=\(phase) reason=\(reason) policy=\(PulsarWorkoutStartCoordinator.shared.presentationPolicy)"
            )
            return false
        }

        let incomingKind = PulsarActiveWorkoutKind(route: route)
        if let activeWorkout,
           activeWorkout.sessionID == sessionID,
           activeWorkout.kind != incomingKind {
            PulsarWorkoutStartupTrace.lifecycle(
                "[WorkoutReconcile] incomingWorkoutID=\(sessionID.uuidString) canonicalWorkoutID=\(sessionID.uuidString) incomingRequestID=none canonicalRequestID=\(PulsarWorkoutStartCoordinator.shared.currentTransaction?.requestID?.uuidString ?? "none") source=activeWorkoutManager decision=rejectIdentityMutation reason=routeConflict canonicalType=\(activeWorkout.kind.logType) incomingType=\(incomingKind.logType)"
            )
            return false
        }

        let isNewSession = activeWorkout?.sessionID != sessionID
        if isNewSession, userMinimizedActiveWorkoutSessionID != nil {
            userMinimizedActiveWorkoutSessionID = nil
        }
        guard setActiveWorkout(kind: incomingKind, sessionID: sessionID, phase: phase) else {
            return false
        }

        if isNewSession {
            setPresentation(.hidden, reason: "newSession.\(reason)")
        }

        if presentationState.minimizingSessionID == sessionID {
            PulsarSyncDebugLogger.log("Skipped auto-opening active workout route because dismissal is pending session=\(sessionID.uuidString) reason=\(reason)")
            return false
        }

        if userMinimizedActiveWorkoutSessionID == sessionID || presentation == .minimized(sessionID) {
            setPresentation(.minimized(sessionID), reason: reason)
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
        if userMinimizedActiveWorkoutSessionID != nil {
            userMinimizedActiveWorkoutSessionID = nil
        }
        setExpandedPresentation(route: route, sessionID: sessionID, reason: reason)
        return presentedWorkoutItem?.sessionID == sessionID
    }

    func minimizeRunWorkout(_ workoutKind: PulsarOutdoorWorkoutKind, sessionID: UUID? = nil) {
        PulsarUIDebugLogger.log("Minimize requested currentSession=\((sessionID ?? activeWorkoutSessionID)?.uuidString ?? "none")")
        guard let resolvedSessionID = sessionID ?? activeWorkoutSessionID else {
            PulsarUIDebugLogger.log("Minimize blocked because active workout sessionID is nil")
            return
        }
        if let activeWorkout {
            guard activeWorkout.sessionID == resolvedSessionID,
                  activeWorkout.kind == .run(workoutKind) else {
                PulsarUIDebugLogger.log("Minimize run blocked by canonical identity mismatch requestedSession=\(resolvedSessionID.uuidString) currentSession=\(activeWorkout.sessionID.uuidString)")
                return
            }
        } else {
            guard Self.canPresentLiveWorkout(sessionID: resolvedSessionID) else {
                PulsarUIDebugLogger.log("Minimize run blocked without lifecycle authority session=\(resolvedSessionID.uuidString)")
                return
            }
        }
        guard setActiveWorkout(kind: .run(workoutKind), sessionID: resolvedSessionID, phase: "active") else {
            return
        }
        requestMinimizedPresentation(sessionID: resolvedSessionID, reason: "minimizeRun")
    }

    func presentRunWorkout(_ workoutKind: PulsarOutdoorWorkoutKind, sessionID: UUID? = nil) {
        guard let resolvedSessionID = sessionID ?? activeWorkoutSessionID else {
            PulsarStateDebugLogger.log("Refused to present run workout because sessionID was nil type=\(workoutKind.rawValue)")
            return
        }
        guard Self.canPresentLiveWorkout(sessionID: resolvedSessionID) else {
            PulsarStateDebugLogger.log(
                "Refused live run presentation without lifecycle authority session=\(resolvedSessionID.uuidString) type=\(workoutKind.rawValue) policy=\(PulsarWorkoutStartCoordinator.shared.presentationPolicy)"
            )
            return
        }
        guard let activeWorkout,
              activeWorkout.sessionID == resolvedSessionID,
              activeWorkout.kind == .run(workoutKind) else {
            PulsarStateDebugLogger.log("Refused to present run workout without matching canonical runtime session=\(resolvedSessionID.uuidString) type=\(workoutKind.rawValue)")
            return
        }
        clearUserMinimizedOverrideIfNeeded(sessionID: resolvedSessionID)
        setPresentation(.expanded(resolvedSessionID), reason: "presentRun")
        presentedWorkout = .run(workoutKind)
    }

    func presentRunSummary(_ workoutKind: PulsarOutdoorWorkoutKind, sessionID: UUID) {
        guard PulsarWorkoutStartCoordinator.shared.canPresentSummary(sessionID: sessionID) else {
            PulsarWorkoutLifecycleLogger.log(
                .summaryPresentationBlocked,
                sessionID: sessionID,
                workoutType: workoutKind.rawValue,
                source: "presentRunSummary",
                detail: "reason=sessionNeverReachedActive"
            )
            return
        }
        guard setActiveWorkout(kind: .run(workoutKind), sessionID: sessionID, phase: "finished") else {
            return
        }
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
        if let sessionID {
            PulsarWorkoutStartCoordinator.shared.markSessionEnded(
                sessionID: sessionID,
                reason: reason
            )
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
                setLaunchOwnedPresentation(
                    sessionID: activeWorkout.sessionID,
                    reason: "resumeExistingGym"
                )
            }
            return
        }

        let sessionID = UUID()
        switch PulsarWorkoutStartCoordinator.shared.requestStart(
            sessionID: sessionID,
            kind: .gym,
            source: "GymWorkoutLaunchFlow",
            workoutType: PulsarGymWorkoutKind.inferred(
                routineName: routine.name,
                exerciseCount: routine.exercises.count
            ).rawValue
        ) {
        case .granted:
            break
        case .duplicateStart, .alreadyActive:
            isGymWorkoutMinimized = false
            if let activeWorkout {
                setLaunchOwnedPresentation(
                    sessionID: activeWorkout.sessionID,
                    reason: "resumeExistingGymStart"
                )
            }
            return
        case .rejectedConflict:
            PulsarStateDebugLogger.log("Gym workout start rejected because another workout is active requestedSession=\(sessionID.uuidString)")
            return
        }

        gymSessionViewModel = GymWorkoutSessionViewModel(
            routine: routine,
            workoutWeightUnit: workoutWeightUnit,
            historyStore: historyStore,
            adaptiveStrainPlan: adaptiveStrainPlan,
            sessionID: sessionID
        )
        if let sessionID = gymSessionViewModel?.session.id {
            setActiveWorkout(kind: .gym, sessionID: sessionID, phase: "starting")
            clearUserMinimizedOverrideIfNeeded(sessionID: sessionID)
            setLaunchOwnedPresentation(sessionID: sessionID, reason: "startGym")
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
        guard gymSessionViewModel?.isFinishing != true else {
            PulsarUIDebugLogger.log("Minimize Gym blocked while workout finish is in progress")
            return
        }
        let resolvedSessionID = sessionID ?? gymSessionViewModel?.session.id ?? activeWorkoutSessionID
        guard let resolvedSessionID else {
            PulsarUIDebugLogger.log("Minimize blocked because active workout sessionID is nil")
            return
        }
        guard let activeWorkout,
              activeWorkout.sessionID == resolvedSessionID,
              activeWorkout.kind == .gym,
              gymSessionViewModel?.session.id == resolvedSessionID else {
            PulsarUIDebugLogger.log("Minimize Gym blocked by canonical identity mismatch requestedSession=\(resolvedSessionID.uuidString) currentSession=\(activeWorkoutSessionID?.uuidString ?? "none")")
            return
        }
        requestMinimizedPresentation(sessionID: resolvedSessionID, reason: "minimizeGym")
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
        guard let activeWorkout,
              activeWorkout.sessionID == resolvedSessionID,
              activeWorkout.kind == .gym,
              gymSessionViewModel?.session.id == resolvedSessionID else {
            PulsarStateDebugLogger.log("Refused to present Gym workout without matching canonical runtime session=\(resolvedSessionID.uuidString)")
            return
        }
        clearUserMinimizedOverrideIfNeeded(sessionID: resolvedSessionID)
        presentedWorkout = .gym
        setPresentation(.expanded(resolvedSessionID), reason: "presentGym")
    }

    func completeGymWorkout() {
        let sessionID = gymSessionViewModel?.session.id
        gymSessionViewModel = nil
        isGymWorkoutMinimized = false
        if let sessionID {
            PulsarWorkoutStartCoordinator.shared.markSessionEnded(
                sessionID: sessionID,
                reason: "completeGymWorkout"
            )
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
        guard Self.canPresentLiveWorkout(sessionID: resolvedSessionID) else {
            PulsarStateDebugLogger.log(
                "Refused live watch gym presentation without lifecycle authority session=\(resolvedSessionID.uuidString) policy=\(PulsarWorkoutStartCoordinator.shared.presentationPolicy)"
            )
            return
        }
        guard let activeWorkout,
              activeWorkout.sessionID == resolvedSessionID,
              activeWorkout.kind == .watchGym else {
            PulsarStateDebugLogger.log("Refused to present Watch Gym workout without matching canonical runtime session=\(resolvedSessionID.uuidString)")
            return
        }
        clearUserMinimizedOverrideIfNeeded(sessionID: resolvedSessionID)
        presentedWorkout = .watchGym
        setPresentation(.expanded(resolvedSessionID), reason: "presentWatchGym")
        PulsarWorkoutStartupTrace.phone(
            "live UI presented watch gym session=\(resolvedSessionID.uuidString)"
        )
        PulsarWorkoutStartupTrace.phone("active manager session object attached session=\(resolvedSessionID.uuidString)")
    }

    func presentWatchGymSummary(sessionID: UUID) {
        if retainedFinishedWatchGymSessionID == sessionID,
           activeWorkout?.sessionID == sessionID,
           activeWorkout?.phase == "finished" {
            PulsarWorkoutStartupTrace.diag(
                "[Presentation] summaryRetain duplicateNoOp session=\(sessionID.uuidString) state=\(presentationState.diagnosticName) launchOwned=\(launchCoverOwnsPresentation)"
            )
            return
        }
        guard PulsarWorkoutStartCoordinator.shared.canPresentSummary(sessionID: sessionID) else {
            PulsarWorkoutLifecycleLogger.log(
                .summaryPresentationBlocked,
                sessionID: sessionID,
                source: "presentWatchGymSummary",
                detail: "reason=sessionNeverReachedActive"
            )
            return
        }
        guard setActiveWorkout(kind: .watchGym, sessionID: sessionID, phase: "finished") else {
            return
        }
        clearUserMinimizedOverrideIfNeeded(sessionID: sessionID)
        retainedFinishedWatchGymSessionID = sessionID
        if launchCoverOwnsPresentation {
            setLaunchOwnedPresentation(sessionID: sessionID, reason: "presentWatchGymSummary.launchOwned")
            PulsarStateDebugLogger.log("[PulsarSummary] Watch gym summary retained on launch cover session=\(sessionID.uuidString)")
            PulsarWorkoutStartupTrace.diag(
                "[Presentation] retain launchOwned reason=workoutEnded session=\(sessionID.uuidString) \(PulsarWorkoutStartupTrace.threadTag())"
            )
            return
        }
        setPresentation(.expanded(sessionID), reason: "presentWatchGymSummary")
        PulsarStateDebugLogger.log("[PulsarSummary] Watch gym summary presentation retained session=\(sessionID.uuidString)")
    }

    func minimizeWatchGymWorkout(sessionID: UUID? = nil) {
        PulsarUIDebugLogger.log("Minimize requested currentSession=\((sessionID ?? activeWorkoutSessionID)?.uuidString ?? "none")")
        guard let canonicalWorkout = activeWorkout,
              case .watchGym = canonicalWorkout.kind else {
            PulsarUIDebugLogger.log("Minimize blocked because no canonical Watch Gym runtime is attached")
            return
        }
        guard canonicalWorkout.phase != "finished" else {
            PulsarUIDebugLogger.log("Minimize Watch Gym blocked because the canonical workout is finished")
            return
        }
        let canonicalSessionID = canonicalWorkout.sessionID
        if let sessionID, sessionID != canonicalSessionID {
            PulsarWorkoutStartupTrace.lifecycle(
                "[WorkoutReconcile] incomingWorkoutID=\(sessionID.uuidString) canonicalWorkoutID=\(canonicalSessionID.uuidString) incomingRequestID=none canonicalRequestID=\(PulsarWorkoutStartCoordinator.shared.currentTransaction?.requestID?.uuidString ?? "none") source=minimizeWatchGym decision=rejectIdentityMutation reason=presentationTransition"
            )
            return
        }
        if presentation == .minimized(canonicalSessionID),
           userMinimizedActiveWorkoutSessionID == canonicalSessionID,
           presentedWorkout == nil {
            return
        }
        requestMinimizedPresentation(sessionID: canonicalSessionID, reason: "minimizeWatchGym")
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
        if let sessionID {
            PulsarWorkoutStartCoordinator.shared.markSessionEnded(
                sessionID: sessionID,
                reason: reason
            )
        }
        clearPresentationStateIfNeeded(
            sessionID: sessionID,
            phase: phase,
            source: source,
            reason: reason
        )
    }

    func resetForTesting() {
        presentationState = .hidden
        activeWorkout = nil
        userMinimizedActiveWorkoutSessionID = nil
        minimizedRunWorkoutKind = nil
        gymSessionViewModel = nil
        isGymWorkoutMinimized = false
        adaptiveStrainPlan = nil
        automaticallyOpenedActiveWorkoutSessionID = nil
        lastVisiblePresentationBySessionID = [:]
        pendingDismissedWorkouts = []
        rootPresentationHandoffReason = nil
        launchCoverOwnsPresentation = false
        presentationCommitCount = 0
        retainedFinishedWatchGymSessionID = nil
    }

    @discardableResult
    private func setActiveWorkout(kind: PulsarActiveWorkoutKind, sessionID: UUID, phase: String) -> Bool {
        if let transaction = PulsarWorkoutStartCoordinator.shared.currentTransaction,
           transaction.sessionID == sessionID || transaction.authoritativeSessionID == sessionID,
           transaction.kind != kind {
            PulsarStateDebugLogger.log(
                "Refused active workout kind that conflicts with lifecycle authority session=\(sessionID.uuidString) canonicalType=\(transaction.kind.logType) incomingType=\(kind.logType) phase=\(phase)"
            )
            return false
        }
        if let activeWorkout,
           activeWorkout.sessionID == sessionID,
           activeWorkout.kind != kind {
            PulsarStateDebugLogger.log(
                "Refused active workout kind mutation session=\(sessionID.uuidString) canonicalType=\(activeWorkout.kind.logType) incomingType=\(kind.logType) phase=\(phase)"
            )
            return false
        }
        let isNewSession = activeWorkout?.sessionID != sessionID
        if isNewSession, presentation.sessionID != nil {
            setPresentation(.hidden, reason: "activeSessionIdentityChanged")
        }
        let nextWorkout = PulsarActiveWorkout(
            sessionID: sessionID,
            kind: kind,
            phase: phase,
            updatedAt: Date()
        )
        guard activeWorkout != nextWorkout else { return true }
        activeWorkout = nextWorkout
        PulsarPerformanceDiagnostics.checkpoint("workout.managerAttachment")
        PulsarWorkoutStartupTrace.phone(
            "active manager session attached session=\(sessionID.uuidString) type=\(kind.logType) phase=\(phase)"
        )
        if case .run(let workoutKind) = kind {
            minimizedRunWorkoutKind = workoutKind
        }
        if isNewSession {
            PulsarStateDebugLogger.log("Active workout created session=\(sessionID.uuidString) type=\(kind.logType)")
        }
        PulsarStateDebugLogger.log("Active workout set session=\(sessionID.uuidString) type=\(kind.logType) phase=\(phase)")
        return true
    }

    private func setPresentation(_ nextPresentation: PulsarActiveWorkoutPresentation, reason: String) {
        switch nextPresentation {
        case .hidden:
            commitPresentationState(.hidden, reason: reason)
        case .minimized(let sessionID):
            commitPresentationState(.minimized(sessionID), reason: reason)
        case .expanded(let sessionID):
            guard let route = activeWorkout?.kind.route else {
                PulsarStateDebugLogger.log("Refused expanded presentation without active workout session=\(sessionID.uuidString) reason=\(reason)")
                return
            }
            setExpandedPresentation(route: route, sessionID: sessionID, reason: reason)
        }
    }

    private func setExpandedPresentation(
        route: PulsarPresentedWorkout,
        sessionID: UUID,
        reason: String
    ) {
        let item = PulsarPresentedWorkoutItem(workout: route, sessionID: sessionID)
        guard let activeWorkout,
              activeWorkout.sessionID == sessionID,
              activeWorkout.kind.route == route else {
            PulsarStateDebugLogger.log("Refused workout presentation that does not match the canonical runtime session=\(sessionID.uuidString) route=\(route.id) reason=\(reason)")
            return
        }
        if launchCoverOwnsPresentation {
            setLaunchOwnedPresentation(sessionID: sessionID, reason: "launchOwned.\(reason)")
            PulsarUIDebugLogger.log("Launch cover retained live workout route session=\(sessionID.uuidString) reason=\(reason)")
            return
        }
        if rootPresentationHandoffReason != nil {
            commitPresentationState(.handoffPending(item), reason: "deferred.\(reason)")
            PulsarUIDebugLogger.log("Deferred root workout route session=\(sessionID.uuidString) reason=\(reason)")
            return
        }
        commitPresentationState(.expanded(item), reason: reason)
    }

    private func setLaunchOwnedPresentation(sessionID: UUID, reason: String) {
        guard activeWorkout?.sessionID == sessionID else {
            PulsarStateDebugLogger.log("Refused launch-owned presentation without canonical runtime session=\(sessionID.uuidString) reason=\(reason)")
            return
        }
        commitPresentationState(.launchOwned(sessionID), reason: reason)
    }

    private func requestMinimizedPresentation(sessionID: UUID, reason: String) {
        switch presentationState {
        case .expanded(let item):
            guard item.sessionID == sessionID else {
                logMismatchedMinimizePresentation(
                    requestedSessionID: sessionID,
                    currentSessionID: item.sessionID,
                    reason: reason
                )
                return
            }
            commitPresentationState(.minimizing(sessionID), reason: reason)
        case .dismissing(let item):
            guard item.sessionID == sessionID else {
                logMismatchedMinimizePresentation(
                    requestedSessionID: sessionID,
                    currentSessionID: item.sessionID,
                    reason: reason
                )
                return
            }
            commitPresentationState(.minimizing(sessionID), reason: reason)
        case .launchOwned(let ownedSessionID):
            guard ownedSessionID == sessionID else {
                logMismatchedMinimizePresentation(
                    requestedSessionID: sessionID,
                    currentSessionID: ownedSessionID,
                    reason: reason
                )
                return
            }
            commitPresentationState(.minimizing(sessionID), reason: reason)
        case .handoffPending(let item):
            guard item.sessionID == sessionID else {
                logMismatchedMinimizePresentation(
                    requestedSessionID: sessionID,
                    currentSessionID: item.sessionID,
                    reason: reason
                )
                return
            }
            commitPresentationState(.minimizing(sessionID), reason: reason)
        case .minimizing(let pendingSessionID):
            guard pendingSessionID == sessionID else {
                logMismatchedMinimizePresentation(
                    requestedSessionID: sessionID,
                    currentSessionID: pendingSessionID,
                    reason: reason
                )
                return
            }
        case .minimized(let minimizedSessionID):
            guard minimizedSessionID == sessionID else {
                logMismatchedMinimizePresentation(
                    requestedSessionID: sessionID,
                    currentSessionID: minimizedSessionID,
                    reason: reason
                )
                return
            }
        case .hidden:
            // Restored sessions and other non-modal owners have no UIKit
            // dismissal callback to wait for.
            _ = finalizeMinimizedPresentation(
                sessionID: sessionID,
                expectedWorkout: nil,
                reason: reason
            )
        }
    }

    private func logMismatchedMinimizePresentation(
        requestedSessionID: UUID,
        currentSessionID: UUID,
        reason: String
    ) {
        PulsarStateDebugLogger.log(
            "Refused minimize across presentation identities requestedSession=\(requestedSessionID.uuidString) presentationSession=\(currentSessionID.uuidString) reason=\(reason)"
        )
    }

    @discardableResult
    private func finalizeMinimizedPresentation(
        sessionID: UUID,
        expectedWorkout: PulsarPresentedWorkout?,
        reason: String
    ) -> Bool {
        guard let activeWorkout,
              activeWorkout.sessionID == sessionID else { return false }
        if let expectedWorkout,
           activeWorkout.kind.route != expectedWorkout {
            return false
        }

        switch activeWorkout.kind {
        case .run(let workoutKind):
            if minimizedRunWorkoutKind != workoutKind {
                minimizedRunWorkoutKind = workoutKind
            }
        case .gym:
            guard gymSessionViewModel?.session.id == sessionID,
                  gymSessionViewModel?.summary == nil else { return false }
            if !isGymWorkoutMinimized {
                isGymWorkoutMinimized = true
            }
        case .watchGym:
            guard activeWorkout.phase != "finished" else { return false }
        }

        if userMinimizedActiveWorkoutSessionID != sessionID {
            userMinimizedActiveWorkoutSessionID = sessionID
        }
        commitPresentationState(.minimized(sessionID), reason: reason)
        return presentation == .minimized(sessionID)
    }

    private func commitPresentationState(
        _ nextState: PulsarActiveWorkoutPresentationState,
        reason: String
    ) {
        guard presentationState != nextState else { return }
        let previousState = presentationState
        let previous = previousState.presentation
        let next = nextState.presentation

        if let dismissedItem = previousState.item,
           dismissedItem.id != nextState.item?.id {
            pendingDismissedWorkouts.append(
                PulsarDismissedWorkoutPresentation(
                    workout: dismissedItem.workout,
                    sessionID: dismissedItem.sessionID
                )
            )
        }

        presentationState = nextState
        presentationCommitCount += 1
        PulsarWorkoutStartupTrace.count("[PublishRate] presentationState")
        switch nextState {
        case .expanded(let item):
            lastVisiblePresentationBySessionID[item.sessionID] = .expanded(item.sessionID)
            launchCoverOwnsPresentation = false
        case .minimized(let sessionID):
            lastVisiblePresentationBySessionID[sessionID] = .minimized(sessionID)
            launchCoverOwnsPresentation = false
        case .hidden, .dismissing, .minimizing:
            launchCoverOwnsPresentation = false
        case .launchOwned, .handoffPending:
            break
        }
        PulsarPerformanceDiagnostics.event("workout.manager.presentation")
        PulsarUIDebugLogger.log("Presentation changed \(previous.description) -> \(next.description) session=\(next.sessionID?.uuidString ?? "none") reason=\(reason)")
        PulsarWorkoutStartupTrace.diag(
            "[Presentation] \(diagLabel(previousState)) -> \(diagLabel(nextState)) coarse=\(previous.description)->\(next.description) session=\(next.sessionID?.uuidString ?? "none") reason=\(reason) \(PulsarWorkoutStartupTrace.threadTag())"
        )
    }

    private func diagLabel(_ state: PulsarActiveWorkoutPresentationState) -> String {
        switch state {
        case .hidden: "hidden"
        case .launchOwned: "launchOwned"
        case .handoffPending: "handoffPending"
        case .expanded: "expanded"
        case .dismissing: "dismissing"
        case .minimizing: "minimizing"
        case .minimized: "minimized"
        }
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
        setPresentation(.hidden, reason: "clear.\(reason)")
        retainedFinishedWatchGymSessionID = nil
        if activeWorkout != nil {
            activeWorkout = nil
        }
        automaticallyOpenedActiveWorkoutSessionID = nil
        if userMinimizedActiveWorkoutSessionID != nil {
            userMinimizedActiveWorkoutSessionID = nil
        }
        if let sessionID {
            lastVisiblePresentationBySessionID[sessionID] = nil
        }
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

    /// Live presentation is allowed only when the lifecycle authority has reached
    /// active for this session, or the session is the current in-progress start.
    private static func canPresentLiveWorkout(sessionID: UUID) -> Bool {
        let coordinator = PulsarWorkoutStartCoordinator.shared
        if coordinator.didReachActive(sessionID: sessionID) {
            return true
        }
        switch coordinator.presentationPolicy {
        case .live, .loading:
            // Allow connecting/live UI for the in-flight session only.
            return coordinator.currentTransaction.map {
                $0.sessionID == sessionID || $0.authoritativeSessionID == sessionID
            } ?? false
        case .hidden, .summaryEligible, .failed, .cancelled:
            // Watch-originated sessions may mark reached-active without a local
            // transaction; otherwise refuse inventing live UI.
            return false
        }
    }

    private static func isLivePresentationPhase(_ phase: String) -> Bool {
        switch phase {
        case "active", "running", "paused", "mirroring", "watchSessionRunning":
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
