//
//  WatchGymSessionManager.swift
//  Pulsar Watch App Watch App
//

import Combine
import Foundation
import HealthKit
import OSLog
import WatchKit

@MainActor
final class WatchGymSessionManager: NSObject, ObservableObject {
    static let shared = WatchGymSessionManager()

    @Published private(set) var currentHeartRate: Double?
    @Published private(set) var averageHeartRate: Double?
    @Published private(set) var maxHeartRate: Double?
    @Published private(set) var activeEnergyKilocalories: Double?
    @Published private(set) var message: String?

    private let healthStore = HKHealthStore()
    private let syncStore = PulsarWatchConnectivitySyncStore.shared
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var activeSessionId: UUID?
    private var startedAt: Date?
    private var restTask: Task<Void, Never>?
    private var stateTickTask: Task<Void, Never>?
    private var finishFallbackTask: Task<Void, Never>?
    private var isFinishing = false
    private var lastRestStateSyncAt = Date.distantPast
    private var handledCompanionStartSessionIDs = Set<UUID>()
    private var handledGymStartRequestIDs = Set<UUID>()
    private var pendingGymStartRequest: GymWorkoutStartRequest?
    private var pendingRoutineSnapshot: GymRoutineSnapshotEnvelope?
    /// A callback-only identity used while the HealthKit launch races the
    /// correlated WatchConnectivity request. It must never leave this manager.
    private var provisionalCompanionSessionID: UUID?
    private var didSendWatchRunningAcknowledgement = false
    private var didSendFirstHeartRateEvent = false
    private var lastMirroredMetricsSentAt = Date.distantPast
    private var mirroringUnavailable = false
    private var mirroringStart = PulsarMirroringStartController()
    private var primarySessionGate = PulsarWatchPrimarySessionGate()
    private var isCompanionLaunchInFlight = false
    private var cancellables = Set<AnyCancellable>()

    private var managerObjectToken: String {
        String(describing: ObjectIdentifier(self))
    }

    private override init() {
        super.init()
        PulsarWorkoutStartupTrace.watch("[GymManager] init manager=\(managerObjectToken)")
        syncStore.registerGymActionHandler { [weak self] action in
            Task { @MainActor in
                await self?.handle(action)
            }
        }
        syncStore.$activeGymState
            .compactMap { $0 }
            .sink { [weak self] state in
                Task { @MainActor in
                    await self?.reconcileSynchronizedGymState(state)
                }
            }
            .store(in: &cancellables)
    }

    func handlePrelaunchHint(_ request: GymWorkoutStartRequest) async {
        PulsarWorkoutStartupTrace.watch(
            "prelaunchHint received requestID=\(request.requestID.uuidString) workoutID=\(request.candidateSessionID.uuidString) manager=\(managerObjectToken) primary=\(primaryObjectToken)"
        )
        let now = Date()
        let isTombstoned = syncStore.isActiveWorkoutSessionTombstoned(request.candidateSessionID)
        guard GymWorkoutStartRequestAdmission.accepts(
            requestedAt: request.requestedAt,
            now: now,
            isTombstoned: isTombstoned
        ) else {
            PulsarWorkoutStartupTrace.watch(
                "prelaunchHint rejected requestID=\(request.requestID.uuidString) workoutID=\(request.candidateSessionID.uuidString) age=\(Int(now.timeIntervalSince(request.requestedAt))) tombstoned=\(isTombstoned) reason=staleOrInvalidAuthority"
            )
            return
        }
        let provisionalSessionID = provisionalCompanionSessionID
        let canAdoptLateMetadata = provisionalSessionID != nil &&
            activeSessionId == provisionalSessionID &&
            pendingGymStartRequest == nil &&
            primarySessionGate.requestID == nil
        if let activeSessionId,
           workoutSession != nil || primarySessionGate.isCreating || primarySessionGate.hasPrimarySession,
           activeSessionId != request.candidateSessionID,
           !canAdoptLateMetadata {
            logDuplicateStartIgnored(source: "prelaunchHint", reason: "conflicting workoutID")
            PulsarSyncDebugLogger.log("Watch Gym ignored conflicting prelaunch request request=\(request.requestID.uuidString) activeSession=\(activeSessionId.uuidString)")
            return
        }
        guard handledGymStartRequestIDs.insert(request.requestID).inserted else {
            logDuplicateStartIgnored(source: "prelaunchHint", reason: "requestID already handled")
            return
        }
        if canAdoptLateMetadata, let provisionalSessionID {
            var provisionalState: ActiveGymWorkoutState
            if let currentState = syncStore.activeGymState,
               currentState.sessionId == provisionalSessionID ||
                currentState.sessionId == request.candidateSessionID {
                provisionalState = currentState
            } else {
                provisionalState = Self.companionMetadataPendingState(
                    sessionID: request.candidateSessionID,
                    request: request,
                    startedAt: workoutSession?.startDate ?? startedAt ?? now
                )
            }
            provisionalState.sessionId = request.candidateSessionID
            provisionalState.requestID = request.requestID
            provisionalState.routineId = request.routineID
            provisionalState.routineRevision = request.routineRevision
            provisionalState.workoutKind = request.workoutKind
            provisionalState.startedFrom = .iPhoneRequestedWatchStart
            provisionalState.isLaunchPlaceholder = true
            provisionalState.updatedAt = now
            syncStore.storeActiveGymState(
                provisionalState,
                broadcast: false,
                reason: "watchGymLateStartMetadataAdopted"
            )
            PulsarWorkoutStartupTrace.watch(
                "late start metadata adopted generatedWorkoutID=\(provisionalSessionID.uuidString) workoutID=\(request.candidateSessionID.uuidString) requestID=\(request.requestID.uuidString) routable=false"
            )
            provisionalCompanionSessionID = nil
        } else if var correlatedState = syncStore.activeGymState,
                  correlatedState.sessionId == request.candidateSessionID,
                  correlatedState.isPrelaunchPlaceholder {
            correlatedState.requestID = request.requestID
            correlatedState.routineId = request.routineID
            correlatedState.routineRevision = request.routineRevision
            correlatedState.workoutKind = request.workoutKind
            correlatedState.updatedAt = Date()
            syncStore.storeActiveGymState(
                correlatedState,
                broadcast: false,
                reason: "watchGymStartMetadataCorrelated"
            )
        }
        pendingGymStartRequest = request
        activeSessionId = request.candidateSessionID
        primarySessionGate.adoptIdentity(workoutID: request.candidateSessionID, requestID: request.requestID)
        didSendWatchRunningAcknowledgement = false
        if let pendingRoutineSnapshot,
           pendingRoutineSnapshot.sessionID == request.candidateSessionID,
           pendingRoutineSnapshot.requestID == request.requestID {
            await hydrateRoutineSnapshot(pendingRoutineSnapshot)
        }
        PulsarWorkoutLifecycleLogger.log(
            .watchAppHandlerInvoked,
            sessionID: request.candidateSessionID,
            requestID: request.requestID,
            source: "handlePrelaunchHint",
            role: "watch"
        )
        if let workoutSession,
           workoutSession.state == .running || workoutSession.state == .paused {
            sendWatchRunningAcknowledgementIfNeeded(for: workoutSession)
        } else {
            PulsarWorkoutStartupTrace.watch(
                "prelaunchHint prepared metadata only requestID=\(request.requestID.uuidString) workoutID=\(request.candidateSessionID.uuidString)"
            )
        }
    }

    func hydrateRoutineSnapshot(_ envelope: GymRoutineSnapshotEnvelope) async {
        PulsarWorkoutStartupTrace.watch(
            "routineSnapshot received sessionID=\(envelope.sessionID.uuidString) requestID=\(envelope.requestID.uuidString) doesNotCreateSession=true manager=\(managerObjectToken)"
        )
        guard envelope.isChecksumValid,
              envelope.routinePlan.hasCompleteExerciseDefinition else {
            PulsarSyncDebugLogger.log(
                "[PulsarRoutineSync] source=decodedSnapshotRejected routineID=\(envelope.routineID.uuidString) exerciseCount=\(envelope.routinePlan.exerciseCount) decodedExercises=\(envelope.routinePlan.exercises.count) totalSetCount=\(envelope.routinePlan.totalSetCount)"
            )
            return
        }
        let now = Date()
        let isTombstoned = syncStore.isActiveWorkoutSessionTombstoned(envelope.sessionID)
        guard PulsarWatchConnectivitySyncStore.shouldAcceptEmbeddedGymRoutineSnapshot(
            envelope,
            now: now,
            isTombstoned: isTombstoned
        ) else {
            PulsarSyncDebugLogger.log(
                "Watch Gym rejected routine snapshot with stale or mismatched embedded authority session=\(envelope.sessionID.uuidString) request=\(envelope.requestID.uuidString) tombstoned=\(isTombstoned)"
            )
            return
        }
        if envelope.startRequest == nil {
            guard let request = pendingGymStartRequest else {
                let cached = cachePendingRoutineSnapshotIfPreferred(envelope)
                PulsarSyncDebugLogger.log(
                    "Watch Gym deferred legacy routine snapshot until correlated prelaunch metadata arrives session=\(envelope.sessionID.uuidString) request=\(envelope.requestID.uuidString) cached=\(cached)"
                )
                return
            }
            guard request.candidateSessionID == envelope.sessionID,
                  request.requestID == envelope.requestID,
                  request.routineID == envelope.routineID,
                  request.routineRevision == envelope.revision,
                  GymWorkoutStartRequestAdmission.accepts(
                    requestedAt: request.requestedAt,
                    now: now,
                    isTombstoned: isTombstoned
                  ) else {
                PulsarSyncDebugLogger.log(
                    "Watch Gym rejected legacy routine snapshot without matching admitted prelaunch metadata session=\(envelope.sessionID.uuidString) request=\(envelope.requestID.uuidString)"
                )
                return
            }
        }
        PulsarSyncDebugLogger.log(
            "[PulsarRoutineSync] source=decodedSnapshot routineID=\(envelope.routineID.uuidString) name=\(envelope.routinePlan.name) exerciseCount=\(envelope.routinePlan.exercises.count) totalSetCount=\(envelope.routinePlan.totalSetCount) revision=\(envelope.revision)"
        )
        if let request = pendingGymStartRequest,
           request.candidateSessionID != envelope.sessionID ||
            request.requestID != envelope.requestID ||
            request.routineID != envelope.routineID {
            PulsarSyncDebugLogger.log("Watch Gym rejected routine snapshot for conflicting request incomingSession=\(envelope.sessionID.uuidString) incomingRequest=\(envelope.requestID.uuidString) pendingSession=\(request.candidateSessionID.uuidString) pendingRequest=\(request.requestID.uuidString)")
            return
        }
        guard var state = syncStore.activeGymState,
              state.sessionId == envelope.sessionID else {
            if let activeSessionId, activeSessionId != envelope.sessionID {
                if activeSessionId == provisionalCompanionSessionID {
                    let cached = cachePendingRoutineSnapshotIfPreferred(envelope)
                    PulsarSyncDebugLogger.log("Watch Gym cached routine snapshot while companion identity is provisional incoming=\(envelope.sessionID.uuidString) provisional=\(activeSessionId.uuidString) cached=\(cached)")
                    return
                }
                PulsarSyncDebugLogger.log("Watch Gym rejected routine snapshot for conflicting active session incoming=\(envelope.sessionID.uuidString) active=\(activeSessionId.uuidString)")
                return
            }
            let cached = cachePendingRoutineSnapshotIfPreferred(envelope)
            PulsarSyncDebugLogger.log("Watch Gym cached early routine snapshot session=\(envelope.sessionID.uuidString) request=\(envelope.requestID.uuidString) exerciseCount=\(envelope.routinePlan.exercises.count) totalSetCount=\(envelope.routinePlan.totalSetCount) cached=\(cached)")
            return
        }
        if let stateRequestID = state.requestID,
           stateRequestID != envelope.requestID {
            PulsarSyncDebugLogger.log("Watch Gym rejected routine snapshot for noncanonical request incoming=\(envelope.requestID.uuidString) active=\(stateRequestID.uuidString)")
            return
        }
        if state.requestID == nil {
            guard state.isPrelaunchPlaceholder,
                  state.startedFrom == .iPhoneRequestedWatchStart else {
                PulsarSyncDebugLogger.log("Watch Gym rejected uncorrelated routine snapshot session=\(envelope.sessionID.uuidString) request=\(envelope.requestID.uuidString)")
                return
            }
            state.requestID = envelope.requestID
        }
        let previousActiveSessionID = activeSessionId
        let isReplacingProvisionalIdentity = previousActiveSessionID != nil &&
            previousActiveSessionID == provisionalCompanionSessionID
        if let previousActiveSessionID,
           previousActiveSessionID != envelope.sessionID,
           previousActiveSessionID != provisionalCompanionSessionID {
            PulsarSyncDebugLogger.log("Watch Gym rejected routine snapshot for conflicting active session incoming=\(envelope.sessionID.uuidString) active=\(previousActiveSessionID.uuidString)")
            return
        }
        if state.isPrelaunchPlaceholder || isReplacingProvisionalIdentity {
            activeSessionId = envelope.sessionID
            primarySessionGate.adoptIdentity(
                workoutID: envelope.sessionID,
                requestID: envelope.requestID
            )
            provisionalCompanionSessionID = nil
            if let previousActiveSessionID,
               previousActiveSessionID != envelope.sessionID {
                PulsarWorkoutStartupTrace.watch(
                    "routine snapshot adopted canonical identity generatedWorkoutID=\(previousActiveSessionID.uuidString) workoutID=\(envelope.sessionID.uuidString) requestID=\(envelope.requestID.uuidString)"
                )
            }
        }

        if let appliedRevision = state.routineRevision,
           envelope.revision < appliedRevision,
           !state.exercises.isEmpty {
            PulsarSyncDebugLogger.log(
                "[PulsarRoutineSync] source=decodedSnapshotRejectedStale routineID=\(envelope.routineID.uuidString) incomingRevision=\(envelope.revision) appliedRevision=\(appliedRevision)"
            )
            return
        }

        let currentExercisesByID = Dictionary(uniqueKeysWithValues: state.exercises.map { ($0.id, $0) })
        let exercises = envelope.routinePlan.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { exercise in
                let generated = Self.activeExerciseState(exercise)
                return generated.preservingLiveSetProgress(from: currentExercisesByID[generated.id])
            }
        let totalSets = exercises.reduce(0) { $0 + $1.sets.count }
        let startedAt = state.startedAt
        let elapsed = max(state.elapsedSeconds, Int(Date().timeIntervalSince(startedAt)))

        state.routineId = envelope.routineID
        state.routineName = envelope.routinePlan.name
        state.routineEmoji = envelope.routinePlan.emoji
        state.workoutKind = envelope.resolvedWorkoutKind(
            pendingRequest: pendingGymStartRequest,
            current: state.workoutKind,
            isLaunchPlaceholder: state.isPrelaunchPlaceholder
        )
        state.isLaunchPlaceholder = false
        state.routineRevision = max(state.routineRevision ?? 0, envelope.revision)
        state.exercises = exercises
        state.totalExercises = exercises.count
        state.totalSets = totalSets
        state.completedSets = exercises.reduce(0) { $0 + $1.completedSetCount }
        state.elapsedSeconds = elapsed
        state.updatedAt = Date()
        if pendingRoutineSnapshot?.requestID == envelope.requestID {
            pendingRoutineSnapshot = nil
        }
        syncStore.storeActiveGymState(state, broadcast: true, reason: "watchGymRoutineSnapshotHydrated")
        if let workoutBuilder {
            addMetadata(
                to: workoutBuilder,
                startedFrom: state.startedFrom ?? .iPhoneRequestedWatchStart
            )
        }
        PulsarSyncDebugLogger.log(
            "[PulsarRoutineSync] source=activeRoutineSnapshot routineID=\(state.routineId.uuidString) name=\(state.routineName) exerciseCount=\(state.exercises.count) totalSetCount=\(state.totalSets)"
        )
    }

    @discardableResult
    private func cachePendingRoutineSnapshotIfPreferred(
        _ envelope: GymRoutineSnapshotEnvelope
    ) -> Bool {
        guard PulsarWatchConnectivitySyncStore.shouldReplacePendingGymRoutineSnapshot(
            pendingRoutineSnapshot,
            with: envelope
        ) else { return false }
        pendingRoutineSnapshot = envelope
        return true
    }

    func startFromCompanion(configuration: HKWorkoutConfiguration) async {
        isCompanionLaunchInFlight = true
        defer { isCompanionLaunchInFlight = false }
        PulsarWorkoutStartupTrace.watch(
            "[IncomingStart] incomingWorkoutID=\(pendingGymStartRequest?.candidateSessionID.uuidString ?? syncStore.activeGymState?.sessionId.uuidString ?? "none") incomingRequestID=\(pendingGymStartRequest?.requestID.uuidString ?? "none") currentPrimaryObject=\(primaryObjectToken) currentWorkoutID=\(activeSessionId?.uuidString ?? "none") currentRequestID=\(primarySessionGate.requestID?.uuidString ?? pendingGymStartRequest?.requestID.uuidString ?? "none") currentHKState=\(workoutSession.map { String($0.state.rawValue) } ?? "none") source=startWatchAppConfiguration activity=\(configuration.activityType.rawValue) manager=\(managerObjectToken)"
        )
        PulsarWorkoutStartupTrace.watch(
            "start request workoutID=\(activeSessionId?.uuidString ?? syncStore.activeGymState?.sessionId.uuidString ?? "none") requestID=\(pendingGymStartRequest?.requestID.uuidString ?? "none") source=startWatchAppConfiguration activity=\(configuration.activityType.rawValue) manager=\(managerObjectToken)"
        )
        PulsarWorkoutLifecycleLogger.log(
            .watchAppHandlerInvoked,
            sessionID: activeSessionId,
            requestID: pendingGymStartRequest?.requestID,
            source: "startFromCompanion",
            role: "watch"
        )
        if workoutSession != nil {
            logDuplicateStartIgnored(source: "startWatchAppConfiguration", reason: "HealthKit session already active")
            PulsarSyncDebugLogger.log("Watch Gym companion launch ignored because HealthKit session is already active session=\(activeSessionId?.uuidString ?? "none")")
            return
        }
        if let state = syncStore.activeGymState,
           syncStore.isRoutableActiveGymState(state),
           state.startedFrom == .iPhone {
            activeSessionId = state.sessionId
            startedAt = state.startedAt
            PulsarSyncDebugLogger.log("Watch Gym companion launch joined iPhone session without creating duplicate HealthKit workout session=\(state.sessionId.uuidString)")
            return
        }
        discardStalePendingCompanionRequestIfNeeded(now: Date())
        if let request = pendingGymStartRequest {
            activeSessionId = request.candidateSessionID
            primarySessionGate.adoptIdentity(workoutID: request.candidateSessionID, requestID: request.requestID)
            provisionalCompanionSessionID = nil
        } else if let state = syncStore.activeGymState,
                  !state.isFinished,
                  state.startedFrom == .iPhoneRequestedWatchStart,
                  let requestID = state.requestID,
                  state.isFreshRestoreConfirmation() {
            activeSessionId = state.sessionId
            startedAt = state.startedAt
            primarySessionGate.adoptIdentity(workoutID: state.sessionId, requestID: requestID)
            provisionalCompanionSessionID = nil
            PulsarWorkoutStartupTrace.watch(
                "startWatchApp configuration using correlated state workoutID=\(state.sessionId.uuidString) requestID=\(requestID.uuidString)"
            )
        } else {
            let generatedSessionID = UUID()
            let now = Date()
            activeSessionId = generatedSessionID
            startedAt = now
            provisionalCompanionSessionID = generatedSessionID
            primarySessionGate.adoptIdentity(workoutID: generatedSessionID, requestID: nil)
            syncStore.storeActiveGymState(
                Self.companionMetadataPendingState(sessionID: generatedSessionID, startedAt: now),
                broadcast: false,
                reason: "watchGymHealthKitLaunchAwaitingMetadata"
            )
            PulsarWorkoutStartupTrace.watch(
                "startWatchApp configuration creating primary before WC metadata generatedWorkoutID=\(generatedSessionID.uuidString)"
            )
        }
        await startWorkoutIfNeeded(configuration: configuration, source: "startWatchAppConfiguration")
    }

    private func discardStalePendingCompanionRequestIfNeeded(now: Date) {
        guard let request = pendingGymStartRequest else { return }
        let isTombstoned = syncStore.isActiveWorkoutSessionTombstoned(request.candidateSessionID)
        guard !GymWorkoutStartRequestAdmission.accepts(
            requestedAt: request.requestedAt,
            now: now,
            isTombstoned: isTombstoned
        ) else { return }

        pendingGymStartRequest = nil
        if pendingRoutineSnapshot?.requestID == request.requestID {
            pendingRoutineSnapshot = nil
        }
        guard workoutSession == nil,
              !primarySessionGate.isCreating,
              !primarySessionGate.hasPrimarySession else { return }
        handledGymStartRequestIDs.remove(request.requestID)
        if activeSessionId == request.candidateSessionID {
            activeSessionId = nil
        }
        if primarySessionGate.requestID == request.requestID ||
            primarySessionGate.workoutID == request.candidateSessionID {
            primarySessionGate.reset()
        }
        if let state = syncStore.activeGymState,
           state.sessionId == request.candidateSessionID,
           state.isPrelaunchPlaceholder {
            syncStore.clearActiveGymState(
                reason: "stalePendingCompanionRequest",
                broadcastEndedState: false
            )
        }
        PulsarWorkoutStartupTrace.watch(
            "discarded pending prelaunch before HealthKit callback requestID=\(request.requestID.uuidString) workoutID=\(request.candidateSessionID.uuidString) age=\(Int(now.timeIntervalSince(request.requestedAt))) tombstoned=\(isTombstoned)"
        )
    }

    func noteWorkoutViewAppeared(_ state: ActiveGymWorkoutState) {
        if state.isFinished {
            Task { await finishCurrentWorkoutIfNeeded() }
            return
        }
        guard workoutSession != nil else {
            PulsarWorkoutStartupTrace.watch(
                "received synchronized state without primary session session=\(state.sessionId.uuidString) source=watchGymViewAppear action=reconcileDoNotCreate"
            )
            return
        }
        startStateTicking()
    }

    func startFreeWorkoutFromWatch() async {
        if workoutSession != nil || primarySessionGate.hasPrimarySession || primarySessionGate.isCreating {
            logDuplicateStartIgnored(source: "watchUIStart", reason: "HealthKit session already active")
            return
        }

        let sessionId = UUID()
        let now = Date()
        let state = ActiveGymWorkoutState(
            sessionId: sessionId,
            routineId: sessionId,
            routineName: PulsarGymWorkoutKind.freeWorkout.displayName,
            routineEmoji: "🏋️",
            workoutKind: .freeWorkout,
            startedFrom: .appleWatch,
            startedAt: now,
            elapsedSeconds: 0,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: 0,
            totalSets: 0,
            completedSets: 0,
            currentHeartRate: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            activeEnergyKilocalories: nil,
            restRemainingSeconds: nil,
            restTotalSeconds: nil,
            isHealthKitEnabled: true,
            healthKitStatusMessage: nil,
            isFinished: false,
            updatedAt: now,
            exercises: []
        )

        activeSessionId = sessionId
        startedAt = now
        syncStore.storeActiveGymState(state, broadcast: true, reason: "watchGymFreeWorkoutStarted")
        syncStore.sendGymAction(.startFreeWorkoutFromWatch(sessionId: sessionId))
        startStateTicking()
        await startWorkoutIfNeeded(configuration: Self.gymWorkoutConfiguration, source: "watchUIStart")
    }

    func recoverActiveWorkoutSession(_ session: HKWorkoutSession) {
        let recoveredObject = String(describing: ObjectIdentifier(session))
        PulsarWorkoutStartupTrace.watch(
            "recovery decision source=handleActiveWorkoutRecovery object=\(recoveredObject) companionLaunchInFlight=\(isCompanionLaunchInFlight) isCreating=\(primarySessionGate.isCreating) hasPrimary=\(primarySessionGate.hasPrimarySession) existingPrimary=\(primaryObjectToken) manager=\(managerObjectToken)"
        )
        if isCompanionLaunchInFlight || primarySessionGate.isCreating || primarySessionGate.hasPrimarySession || workoutSession != nil {
            logDuplicateStartIgnored(source: "recovery", reason: "startWatchApp or existing primary owns creation")
            PulsarSyncDebugLogger.log("Watch Gym recovery skipped because an active HealthKit session is already attached session=\(activeSessionId?.uuidString ?? "none")")
            return
        }

        let configuration = session.workoutConfiguration
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self

        workoutSession = session
        workoutBuilder = builder

        let recoveredState = syncStore.consumeGymRestorationCandidate(matching: session.startDate) ?? syncStore.activeGymState.flatMap { state -> ActiveGymWorkoutState? in
            guard syncStore.isRoutableActiveGymState(state),
                  !state.isFinished else { return nil }
            return state
        }
        if let recoveredState {
            activeSessionId = recoveredState.sessionId
            startedAt = session.startDate ?? recoveredState.startedAt
        } else {
            let sessionId = UUID()
            let start = session.startDate ?? Date()
            activeSessionId = sessionId
            startedAt = start
            syncStore.storeActiveGymState(
                ActiveGymWorkoutState(
                    sessionId: sessionId,
                    routineId: sessionId,
                    routineName: "Recovered Workout",
                    routineEmoji: "🏋️",
                    workoutKind: .freeWorkout,
                    startedFrom: .appleWatch,
                    startedAt: start,
                    elapsedSeconds: max(0, Int(Date().timeIntervalSince(start))),
                    currentExerciseIndex: 0,
                    currentSetIndex: 0,
                    totalExercises: 0,
                    totalSets: 0,
                    completedSets: 0,
                    currentHeartRate: nil,
                    averageHeartRate: nil,
                    maxHeartRate: nil,
                    activeEnergyKilocalories: nil,
                    restRemainingSeconds: nil,
                    restTotalSeconds: nil,
                    isHealthKitEnabled: true,
                    healthKitStatusMessage: nil,
                    isFinished: false,
                    updatedAt: Date(),
                    exercises: []
                ),
                broadcast: true,
                reason: "watchGymRecovered"
            )
        }

        startStateTicking()
        applyHealthStatusToActiveState(isEnabled: true)
        message = nil
        primarySessionGate.markCreated(workoutID: activeSessionId, requestID: pendingGymStartRequest?.requestID)
        PulsarWorkoutStartupTrace.watch(
            "[PrimaryReattach] manager=\(managerObjectToken) object=\(recoveredObject) workoutID=\(activeSessionId?.uuidString ?? "none") requestID=\(recoveredState?.requestID?.uuidString ?? pendingGymStartRequest?.requestID.uuidString ?? "none") authority=healthKitRecovery configuration=\(configuration.activityType.rawValue) source=recovery timestamp=\(Date())"
        )
        PulsarWorkoutStartupTrace.watch(
            "[GymRestore] workoutID=\(activeSessionId?.uuidString ?? "none") phase=active revision=\(recoveredState?.lifecycleGeneration ?? 0) source=healthKitRecovery decision=reattach"
        )
        PulsarSyncDebugLogger.log("Watch Gym recovered active HealthKit workout session=\(activeSessionId?.uuidString ?? "none") state=\(session.state.rawValue)")
    }

    func startRoutineFromWatch(_ routine: WatchGymRoutinePlan) async {
        if workoutSession != nil || primarySessionGate.hasPrimarySession || primarySessionGate.isCreating {
            logDuplicateStartIgnored(source: "watchUIStart", reason: "HealthKit session already active")
            return
        }

        let sessionId = UUID()
        let now = Date()
        let exercises = routine.exercises
            .sorted { $0.orderIndex < $1.orderIndex }
            .map(Self.activeExerciseState)
        let totalSets = exercises.reduce(0) { $0 + $1.sets.count }
        let state = ActiveGymWorkoutState(
            sessionId: sessionId,
            routineId: routine.routineId,
            routineName: routine.name,
            routineEmoji: routine.emoji,
            workoutKind: .routine,
            startedFrom: .appleWatch,
            startedAt: now,
            elapsedSeconds: 0,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: exercises.count,
            totalSets: totalSets,
            completedSets: 0,
            currentHeartRate: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            activeEnergyKilocalories: nil,
            restRemainingSeconds: nil,
            restTotalSeconds: nil,
            isHealthKitEnabled: true,
            healthKitStatusMessage: nil,
            isFinished: false,
            updatedAt: now,
            exercises: exercises
        )

        activeSessionId = sessionId
        startedAt = now
        syncStore.storeActiveGymState(state, broadcast: true, reason: "watchGymSavedRoutineStarted")
        syncStore.sendGymAction(.startSavedRoutineFromWatch(sessionId: sessionId, routineId: routine.routineId))
        startStateTicking()
        await startWorkoutIfNeeded(configuration: Self.gymWorkoutConfiguration, source: "watchUIStart")
    }

    func completeSet(
        sessionId: UUID,
        exerciseId: UUID,
        setId: UUID,
        reps: Int? = nil,
        weight: Double? = nil,
        sendsAction: Bool = true
    ) {
        guard var state = syncStore.activeGymState,
              state.sessionId == sessionId,
              !state.isFinished,
              let exerciseIndex = state.exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIndex = state.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
            if sendsAction {
                syncStore.sendGymAction(.completeSet(sessionId: sessionId, exerciseId: exerciseId, setId: setId, reps: reps, weight: weight))
            }
            return
        }

        if state.exercises[exerciseIndex].sets[setIndex].isCompleted {
            return
        }

        let actualReps = max(1, reps ?? state.exercises[exerciseIndex].sets[setIndex].targetReps)
        let actualWeight = max(0, weight ?? state.exercises[exerciseIndex].sets[setIndex].targetWeight)
        state.exercises[exerciseIndex].sets[setIndex].targetReps = actualReps
        state.exercises[exerciseIndex].sets[setIndex].targetWeight = actualWeight
        state.exercises[exerciseIndex].sets[setIndex].isCompleted = true
        state.exercises[exerciseIndex].sets[setIndex].completedAt = Date()
        state.exercises[exerciseIndex].sets[setIndex].completedReps = actualReps
        state.exercises[exerciseIndex].sets[setIndex].completedWeight = actualWeight

        let restDecision = restDecisionAfterCompleting(exerciseIndex: exerciseIndex, setIndex: setIndex, in: state)
        state = normalizedState(state)
        if let restSeconds = restDecision, restSeconds > 0 && state.completedSets < state.totalSets {
            state.restTotalSeconds = restSeconds
            state.restRemainingSeconds = restSeconds
            startRest(seconds: restSeconds, sessionId: sessionId)
        } else {
            stopRest()
            state.restTotalSeconds = nil
            state.restRemainingSeconds = nil
        }

        WKInterfaceDevice.current().play(.success)
        syncStore.storeActiveGymState(
            state,
            broadcast: !state.isPrelaunchPlaceholder,
            reason: "watchGymSetCompleted"
        )
        if sendsAction {
            syncStore.sendGymAction(.completeSet(sessionId: sessionId, exerciseId: exerciseId, setId: setId, reps: actualReps, weight: actualWeight))
        }
    }

    func updateSetValues(
        sessionId: UUID,
        exerciseId: UUID,
        setId: UUID,
        reps: Int? = nil,
        weight: Double? = nil,
        sendsAction: Bool = true,
        playsHaptic: Bool = true
    ) {
        let nextReps = reps.map { max(1, $0) }
        let nextWeight = weight.map { max(0, $0) }
        guard nextReps != nil || nextWeight != nil else { return }

        guard var state = syncStore.activeGymState,
              state.sessionId == sessionId,
              !state.isFinished,
              let exerciseIndex = state.exercises.firstIndex(where: { $0.id == exerciseId }),
              let setIndex = state.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setId }) else {
            if sendsAction {
                syncStore.sendGymAction(.updateSetValues(sessionId: sessionId, exerciseId: exerciseId, setId: setId, reps: nextReps, weight: nextWeight))
            }
            return
        }

        var didUpdate = false
        if let nextReps {
            if state.exercises[exerciseIndex].sets[setIndex].targetReps != nextReps {
                state.exercises[exerciseIndex].sets[setIndex].targetReps = nextReps
                didUpdate = true
            }
            if state.exercises[exerciseIndex].sets[setIndex].isCompleted,
               state.exercises[exerciseIndex].sets[setIndex].completedReps != nextReps {
                state.exercises[exerciseIndex].sets[setIndex].completedReps = nextReps
                didUpdate = true
            }
        }
        if let nextWeight {
            if state.exercises[exerciseIndex].sets[setIndex].targetWeight != nextWeight {
                state.exercises[exerciseIndex].sets[setIndex].targetWeight = nextWeight
                didUpdate = true
            }
            if state.exercises[exerciseIndex].sets[setIndex].isCompleted,
               state.exercises[exerciseIndex].sets[setIndex].completedWeight != nextWeight {
                state.exercises[exerciseIndex].sets[setIndex].completedWeight = nextWeight
                didUpdate = true
            }
        }

        guard didUpdate else { return }
        state = normalizedState(state)
        if playsHaptic {
            WKInterfaceDevice.current().play(.click)
        }
        syncStore.storeActiveGymState(
            state,
            broadcast: !state.isPrelaunchPlaceholder,
            reason: "watchGymSetAdjusted"
        )
        if sendsAction {
            syncStore.sendGymAction(.updateSetValues(sessionId: sessionId, exerciseId: exerciseId, setId: setId, reps: nextReps, weight: nextWeight))
        }
    }

    func skipRest(sessionId: UUID) {
        stopRest()
        if var state = syncStore.activeGymState, state.sessionId == sessionId {
            state.restRemainingSeconds = nil
            state.restTotalSeconds = nil
            state.updatedAt = Date()
            syncStore.storeActiveGymState(
                state,
                broadcast: !state.isPrelaunchPlaceholder,
                reason: "watchGymRestSkipped"
            )
        }
        syncStore.sendGymAction(.skipRestTimer(sessionId: sessionId))
    }

    func finishWorkoutFromUser(sessionId: UUID) async {
        WKInterfaceDevice.current().play(.stop)
        syncStore.sendGymAction(.finishWorkout(sessionId: sessionId))
        await finishCurrentWorkoutIfNeeded()
    }

    func finishCurrentWorkoutIfNeeded() async {
        guard workoutSession != nil || workoutBuilder != nil else {
            markActiveStateFinished(workoutUUID: nil)
            cleanup(preservingFinishState: true)
            return
        }
        requestWorkoutSessionStop(reason: "watchGymFinish")
    }

    private func startWorkoutIfNeeded(configuration: HKWorkoutConfiguration, source: String) async {
        let creationSource = PulsarWatchPrimaryCreationSource(rawValue: source) ?? .unknown
        let requestedWorkoutID = pendingGymStartRequest?.candidateSessionID ?? activeSessionId
        let requestedRequestID = pendingGymStartRequest?.requestID ?? syncStore.activeGymState.flatMap { state in
            state.sessionId == requestedWorkoutID ? state.requestID : nil
        }
        switch PulsarWatchPrimaryCreationAuthority.decision(
            source: creationSource,
            workoutID: requestedWorkoutID,
            requestID: requestedRequestID
        ) {
        case .reject(let reason):
            PulsarWatchPrimaryCreationAuthority.preventCreation(
                source: creationSource,
                workoutID: requestedWorkoutID,
                requestID: requestedRequestID,
                reason: reason
            )
            return
        case .allow:
            break
        }
        switch primarySessionGate.decision(
            requestedWorkoutID: requestedWorkoutID,
            requestedRequestID: requestedRequestID
        ) {
        case .ignore(let reason, _):
            logDuplicateStartIgnored(source: source, reason: reason)
            activeSessionId = activeSessionId ?? requestedWorkoutID
            return
        case .create:
            primarySessionGate.markCreating(workoutID: requestedWorkoutID, requestID: requestedRequestID)
        }

        PulsarWorkoutStartupTrace.watch(
            "start request workoutID=\(requestedWorkoutID?.uuidString ?? "none") requestID=\(requestedRequestID?.uuidString ?? "none") source=\(source) manager=\(managerObjectToken)"
        )

        guard await requestAuthorization() else {
            primarySessionGate.markCreationFailed()
            applyHealthStatusToActiveState(isEnabled: false)
            syncStore.sendGymAction(.requestState())
            return
        }

        // WatchConnectivity can supply A/R while Health authorization is in
        // flight. Re-resolve after the await so the primary never keeps using B.
        let resolvedWorkoutID = pendingGymStartRequest?.candidateSessionID ?? activeSessionId ?? requestedWorkoutID
        let resolvedRequestID = pendingGymStartRequest?.requestID ?? syncStore.activeGymState.flatMap { state in
            state.sessionId == resolvedWorkoutID ? state.requestID : nil
        } ?? requestedRequestID
        activeSessionId = resolvedWorkoutID

        if workoutSession != nil {
            primarySessionGate.markCreated(workoutID: resolvedWorkoutID, requestID: resolvedRequestID)
            logDuplicateStartIgnored(source: source, reason: "session appeared during authorization")
            return
        }

        do {
            didSendWatchRunningAcknowledgement = false
            didSendFirstHeartRateEvent = false
            mirroringUnavailable = false
            mirroringStart.reset()
            currentHeartRate = nil
            averageHeartRate = nil
            maxHeartRate = nil
            activeEnergyKilocalories = nil
            message = nil

            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self

            workoutSession = session
            workoutBuilder = builder
            primarySessionGate.markCreated(
                workoutID: resolvedWorkoutID,
                requestID: resolvedRequestID
            )
            if var state = syncStore.activeGymState,
               state.sessionId == resolvedWorkoutID {
                state.requestID = resolvedRequestID ?? state.requestID
                state.routineRevision = max(
                    state.routineRevision ?? 0,
                    pendingGymStartRequest?.routineRevision ?? 0
                )
                state.lifecycleGeneration = max(state.lifecycleGeneration ?? 0, 1)
                syncStore.storeActiveGymState(
                    state,
                    broadcast: !state.isPrelaunchPlaceholder,
                    reason: "watchGymPrimaryCreated"
                )
            }

            let start = syncStore.activeGymState?.startedAt ?? startedAt ?? Date()
            startedAt = start
            let primaryObject = String(describing: ObjectIdentifier(session))
            PulsarWorkoutStartupTrace.watch(
                "[PrimaryCreate] manager=\(managerObjectToken) object=\(primaryObject) workoutID=\(activeSessionId?.uuidString ?? "none") requestID=\(resolvedRequestID?.uuidString ?? "none") authority=\(creationSource.authorityLabel) configuration=\(configuration.activityType.rawValue) source=\(source) timestamp=\(Date())"
            )
            PulsarWorkoutStartupTrace.diag(
                "[PrimaryCreate] gym object=\(primaryObject) workoutID=\(activeSessionId?.uuidString ?? "none") requestID=\(resolvedRequestID?.uuidString ?? "none") hkState=\(session.state.rawValue) \(PulsarWorkoutStartupTrace.threadTag())"
            )
            PulsarWorkoutLifecycleLogger.log(
                .watchWorkoutSessionCreated,
                sessionID: activeSessionId,
                requestID: resolvedRequestID,
                source: source,
                role: "watch"
            )

            PulsarWorkoutStartupTrace.watch(
                "[MirrorStart] primaryObject=\(primaryObject) workoutID=\(activeSessionId?.uuidString ?? "none") requestID=\(resolvedRequestID?.uuidString ?? "none") attempt=1 source=\(source)"
            )
            let didStartMirroring = await PulsarHealthKitCompanionMirroring.startMirroringToCompanionDevice(
                session,
                controller: mirroringStart,
                reason: "initialWatchStart gym session=\(activeSessionId?.uuidString ?? "none") primaryObject=\(primaryObject)"
            )
            mirroringUnavailable = !didStartMirroring
            PulsarWorkoutStartupTrace.watch(
                "[MirrorStart] primaryObject=\(primaryObject) success=\(didStartMirroring) source=\(source)"
            )
            if mirroringUnavailable, var state = syncStore.activeGymState {
                state.healthKitStatusMessage = "Watch recording; reconnecting"
                syncStore.storeActiveGymState(
                    state,
                    broadcast: !state.isPrelaunchPlaceholder,
                    reason: "watchGymMirroringUnavailable"
                )
            }
            PulsarWorkoutLifecycleLogger.log(
                .watchHealthKitMirroringStarted,
                sessionID: activeSessionId,
                requestID: resolvedRequestID,
                source: source,
                healthKitState: "\(session.state.rawValue)",
                role: "watch"
            )

            PulsarWorkoutStartupTrace.diag(
                "[StartActivity] gym begin session=\(activeSessionId?.uuidString ?? "none") primaryObject=\(primaryObject) hkState=\(session.state.rawValue) \(PulsarWorkoutStartupTrace.threadTag())"
            )
            session.startActivity(with: start)
            PulsarWorkoutStartupTrace.watch("startActivity gym session=\(activeSessionId?.uuidString ?? "none") primaryObject=\(primaryObject)")
            PulsarWorkoutStartupTrace.diag(
                "[StartActivity] gym applied session=\(activeSessionId?.uuidString ?? "none") primaryObject=\(primaryObject) hkState=\(session.state.rawValue) \(PulsarWorkoutStartupTrace.threadTag())"
            )
            try await builder.beginCollection(at: start)
            PulsarWorkoutLifecycleLogger.log(
                .watchHealthKitActivityStarted,
                sessionID: activeSessionId,
                requestID: resolvedRequestID,
                source: source,
                healthKitState: "\(session.state.rawValue)",
                role: "watch"
            )
            addMetadata(to: builder, startedFrom: syncStore.activeGymState?.startedFrom ?? .appleWatch)

            startStateTicking()
            applyHealthStatusToActiveState(isEnabled: true)
            WKInterfaceDevice.current().play(.start)
        } catch {
            primarySessionGate.markCreationFailed()
            message = "Apple Watch could not start Health recording for this gym workout."
            PulsarSyncDebugLogger.log("Watch Gym workout start failed: \(error.localizedDescription)")
            applyHealthStatusToActiveState(isEnabled: false)
            cleanup()
        }
    }

    private func reconcileSynchronizedGymState(_ state: ActiveGymWorkoutState) async {
        guard !state.isFinished else { return }
        if let provisionalSessionID = provisionalCompanionSessionID,
           activeSessionId == provisionalSessionID,
           state.sessionId != provisionalSessionID,
           state.isPrelaunchPlaceholder,
           state.startedFrom == .iPhoneRequestedWatchStart,
           let requestID = state.requestID,
           state.isFreshRestoreConfirmation() {
            activeSessionId = state.sessionId
            primarySessionGate.adoptIdentity(workoutID: state.sessionId, requestID: requestID)
            provisionalCompanionSessionID = nil
            PulsarWorkoutStartupTrace.watch(
                "synchronized launch identity adopted generatedWorkoutID=\(provisionalSessionID.uuidString) workoutID=\(state.sessionId.uuidString) requestID=\(requestID.uuidString) routable=false"
            )
        }
        if let pendingRoutineSnapshot,
           pendingRoutineSnapshot.sessionID == state.sessionId {
            await hydrateRoutineSnapshot(pendingRoutineSnapshot)
            return
        }
        if workoutSession != nil {
            if activeSessionId == state.sessionId {
                return
            }
            logDuplicateStartIgnored(source: "activeGymStateSink", reason: "primary already exists")
            return
        }
        PulsarWorkoutStartupTrace.watch(
            "received synchronized state without primary session session=\(state.sessionId.uuidString) source=activeGymStateSink action=reconcileDoNotCreate"
        )
        PulsarSyncDebugLogger.log(
            "Watch Gym synchronized state ignored for primary creation session=\(state.sessionId.uuidString) startedFrom=\(state.startedFrom?.rawValue ?? "unknown")"
        )
    }

    private func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            message = "Health is unavailable on this Apple Watch."
            return false
        }

        do {
            try await healthStore.requestAuthorization(toShare: Self.healthShareTypes, read: Self.healthReadTypes)
            let workoutStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
            guard workoutStatus != .sharingDenied else {
                message = "Allow Health workout access on Apple Watch to read heart rate."
                return false
            }
            message = nil
            return true
        } catch {
            message = "Allow Health access on Apple Watch to read heart rate and calories."
            return false
        }
    }

    private func updateBuilderStatistics(for collectedTypes: Set<HKSampleType>) {
        guard let builder = workoutBuilder else { return }

        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let statistics = builder.statistics(for: quantityType)
            switch quantityType.identifier {
            case HKQuantityTypeIdentifier.heartRate.rawValue:
                let bpmUnit = HKUnit.count().unitDivided(by: .minute())
                currentHeartRate = statistics?.mostRecentQuantity()?.doubleValue(for: bpmUnit)
                averageHeartRate = statistics?.averageQuantity()?.doubleValue(for: bpmUnit)
                maxHeartRate = statistics?.maximumQuantity()?.doubleValue(for: bpmUnit)
            case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                activeEnergyKilocalories = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie())
            default:
                break
            }
        }

        sendFirstHeartRateEventIfNeeded()
        sendMirroredMetricsIfNeeded()
    }

    private func sendMirroredMetricsIfNeeded() {
        guard let workoutSession,
              let activeSessionId,
              provisionalCompanionSessionID == nil,
              !mirroringUnavailable else { return }
        let now = Date()
        guard now.timeIntervalSince(lastMirroredMetricsSentAt) >= 1 else { return }
        let payload = GymMirroredMetricsPayload(
            sessionID: activeSessionId,
            sampledAt: now,
            currentHeartRate: currentHeartRate,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            activeEnergyKilocalories: activeEnergyKilocalories
        )
        guard let data = GymCrossDeviceCodec.encodeMirroredMetrics(payload) else { return }
        lastMirroredMetricsSentAt = now
        workoutSession.sendToRemoteWorkoutSession(data: data) { _, error in
            if let error {
                PulsarSyncDebugLogger.log(
                    "Watch Gym mirrored metrics send failed session=\(activeSessionId.uuidString) error=\(error.localizedDescription)"
                )
            }
        }
    }

    private func sendWatchRunningAcknowledgementIfNeeded(for session: HKWorkoutSession) {
        guard !didSendWatchRunningAcknowledgement else { return }
        guard let request = pendingGymStartRequest else {
            PulsarSyncDebugLogger.log("Watch Gym deferred running acknowledgement until correlated request arrives session=\(activeSessionId?.uuidString ?? "none")")
            return
        }
        let authoritativeSessionID = request.candidateSessionID
        activeSessionId = authoritativeSessionID
        provisionalCompanionSessionID = nil
        primarySessionGate.adoptIdentity(
            workoutID: authoritativeSessionID,
            requestID: request.requestID
        )

        if var state = syncStore.activeGymState,
           state.sessionId == authoritativeSessionID {
            state.requestID = request.requestID
            state.routineId = request.routineID
            state.routineRevision = max(state.routineRevision ?? 0, request.routineRevision)
            state.workoutKind = request.workoutKind
            state.updatedAt = Date()
            syncStore.storeActiveGymState(
                state,
                broadcast: !state.isPrelaunchPlaceholder,
                reason: "watchGymRunningIdentityCorrelated"
            )
        } else {
            let now = Date()
            var state = Self.companionMetadataPendingState(
                sessionID: authoritativeSessionID,
                request: request,
                startedAt: session.startDate ?? now
            )
            state.healthKitStatusMessage = mirroringUnavailable ? "Watch recording; reconnecting" : "Loading routine from iPhone"
            syncStore.storeActiveGymState(
                state,
                broadcast: false,
                reason: "watchGymGeneratedSessionState"
            )
        }
        if let pendingRoutineSnapshot,
           pendingRoutineSnapshot.sessionID == authoritativeSessionID {
            Task { @MainActor [weak self] in
                await self?.hydrateRoutineSnapshot(pendingRoutineSnapshot)
            }
        }

        let acknowledgement = GymWorkoutStartAcknowledgement(
            requestID: request.requestID,
            candidateSessionID: request.candidateSessionID,
            authoritativeSessionID: authoritativeSessionID,
            healthKitWorkoutUUID: nil,
            sessionState: .running,
            mirroringState: mirroringUnavailable ? .unavailableWatchRecording : .active,
            isWatchGeneratedSessionID: false
        )
        syncStore.sendGymStartAcknowledgement(acknowledgement, reason: "watchGymSessionRunning")
        if !mirroringUnavailable, let data = GymCrossDeviceCodec.encodeAcknowledgement(acknowledgement) {
            session.sendToRemoteWorkoutSession(data: data) { _, error in
                if let error {
                    PulsarSyncDebugLogger.log(
                        "Watch Gym HealthKit start acknowledgement failed session=\(authoritativeSessionID.uuidString) error=\(error.localizedDescription)"
                    )
                } else {
                    PulsarSyncDebugLogger.log(
                        "Watch Gym HealthKit start acknowledgement sent session=\(authoritativeSessionID.uuidString)"
                    )
                }
            }
        }
        didSendWatchRunningAcknowledgement = true

        PulsarWorkoutLifecycleLogger.log(
            .watchWorkoutSessionRunning,
            sessionID: authoritativeSessionID,
            requestID: request.requestID,
            source: "watchGymSessionDelegate",
            healthKitState: "\(session.state.rawValue)",
            role: "watch"
        )
    }

    private func sendFirstHeartRateEventIfNeeded() {
        guard !didSendFirstHeartRateEvent, currentHeartRate != nil else { return }
        didSendFirstHeartRateEvent = true
        PulsarWorkoutLifecycleLogger.log(
            .firstHeartRateSampleReceived,
            sessionID: activeSessionId,
            requestID: pendingGymStartRequest?.requestID,
            source: "watchGymMetrics",
            transport: "healthKit",
            role: "watch"
        )
    }

    private func startStateTicking() {
        stateTickTask?.cancel()
        stateTickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    self?.tickActiveState()
                }
            }
        }
    }

    private func tickActiveState() {
        guard var state = syncStore.activeGymState,
              !state.isFinished else { return }
        let sessionId = activeSessionId ?? state.sessionId
        guard state.sessionId == sessionId,
              state.restRemainingSeconds == nil else { return }
        state = normalizedState(state)
        state.currentHeartRate = currentHeartRate ?? state.currentHeartRate
        state.averageHeartRate = averageHeartRate ?? state.averageHeartRate
        state.maxHeartRate = maxHeartRate ?? state.maxHeartRate
        state.activeEnergyKilocalories = activeEnergyKilocalories ?? state.activeEnergyKilocalories
        state.isHealthKitEnabled = state.isHealthKitEnabled || currentHeartRate != nil || activeEnergyKilocalories != nil
        state.healthKitStatusMessage = message
        syncStore.storeActiveGymState(
            state,
            broadcast: !state.isPrelaunchPlaceholder,
            reason: "watchGymWorkoutTick"
        )
    }

    private func startRest(seconds: Int, sessionId: UUID) {
        restTask?.cancel()
        guard seconds > 0 else { return }
        lastRestStateSyncAt = Date()
        restTask = Task { [weak self] in
            var remaining = seconds
            while remaining > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                remaining -= 1
                await MainActor.run {
                    self?.updateRest(remaining: remaining, total: seconds, sessionId: sessionId)
                }
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                WKInterfaceDevice.current().play(.notification)
                self?.stopRest()
                self?.clearRest(sessionId: sessionId, reason: "watchGymRestFinished")
            }
        }
    }

    private func updateRest(remaining: Int, total: Int, sessionId: UUID) {
        let signpostState = PulsarPerformanceSignposts.gym.beginInterval("rest_tick")
        defer {
            PulsarPerformanceSignposts.gym.endInterval("rest_tick", signpostState)
        }
        guard var state = syncStore.activeGymState,
              state.sessionId == sessionId,
              !state.isFinished else { return }
        state.restRemainingSeconds = max(remaining, 0)
        state.restTotalSeconds = total
        state.currentHeartRate = currentHeartRate ?? state.currentHeartRate
        state.averageHeartRate = averageHeartRate ?? state.averageHeartRate
        state.maxHeartRate = maxHeartRate ?? state.maxHeartRate
        state.activeEnergyKilocalories = activeEnergyKilocalories ?? state.activeEnergyKilocalories
        state.isHealthKitEnabled = state.isHealthKitEnabled || currentHeartRate != nil || activeEnergyKilocalories != nil
        state.healthKitStatusMessage = message
        state.updatedAt = Date()
        let now = Date()
        let shouldBroadcast = now.timeIntervalSince(lastRestStateSyncAt) >= ActiveGymSyncCadencePolicy.reachableRestInterval
        if shouldBroadcast {
            lastRestStateSyncAt = now
        }
        syncStore.storeActiveGymState(
            state,
            broadcast: shouldBroadcast && !state.isPrelaunchPlaceholder,
            reason: "watchGymRestTick"
        )
    }

    private func clearRest(sessionId: UUID, reason: String) {
        guard var state = syncStore.activeGymState, state.sessionId == sessionId else { return }
        state.restRemainingSeconds = nil
        state.restTotalSeconds = nil
        state.updatedAt = Date()
        lastRestStateSyncAt = .distantPast
        syncStore.storeActiveGymState(
            state,
            broadcast: !state.isPrelaunchPlaceholder,
            reason: reason
        )
    }

    private func stopRest() {
        restTask?.cancel()
        restTask = nil
    }

    private func applyHealthStatusToActiveState(isEnabled: Bool) {
        guard var state = syncStore.activeGymState,
              !state.isFinished else { return }
        let sessionId = activeSessionId ?? state.sessionId
        guard state.sessionId == sessionId else { return }
        state.isHealthKitEnabled = isEnabled
        state.healthKitStatusMessage = message
        state.updatedAt = Date()
        syncStore.storeActiveGymState(
            state,
            broadcast: !state.isPrelaunchPlaceholder,
            reason: "watchGymHealthStatusUpdated"
        )
    }

    private func addMetadata(to builder: HKLiveWorkoutBuilder, startedFrom: PulsarWorkoutStartedFrom) {
        guard let state = syncStore.activeGymState,
              !state.isPrelaunchPlaceholder,
              state.sessionId == activeSessionId else {
            PulsarSyncDebugLogger.log(
                "Watch Gym HealthKit metadata deferred until canonical routine hydration session=\(activeSessionId?.uuidString ?? "none")"
            )
            return
        }
        let workoutKind = state.workoutKind ?? PulsarGymWorkoutKind.inferred(
            routineName: state.routineName,
            exerciseCount: state.exercises.count
        )
        let metadata = gymMetadata(
            state: state,
            workoutKind: workoutKind,
            startedFrom: startedFrom
        )
        builder.addMetadata(metadata) { success, error in
            if success {
                PulsarSyncDebugLogger.log("Watch Gym HealthKit metadata added session=\(state.sessionId.uuidString) type=\(workoutKind.rawValue) startedFrom=\(startedFrom.rawValue)")
            } else if let error {
                PulsarSyncDebugLogger.log("Watch Gym HealthKit metadata failed session=\(state.sessionId.uuidString) error=\(error.localizedDescription)")
            }
        }
    }

    private func gymMetadata(
        state: ActiveGymWorkoutState,
        workoutKind: PulsarGymWorkoutKind,
        startedFrom: PulsarWorkoutStartedFrom
    ) -> [String: Any] {
        let displayName = workoutKind == .freeWorkout ? workoutKind.displayName : state.routineName
        var metadata = PulsarWorkoutMetadata.base(
            sessionId: state.sessionId,
            workoutType: workoutKind.rawValue,
            startedFrom: startedFrom
        )
        metadata["PulsarWorkoutCategory"] = workoutKind.categoryName
        metadata["PulsarWorkoutKind"] = workoutKind.rawValue
        metadata["PulsarWorkoutDisplayName"] = displayName
        metadata["PulsarRoutineName"] = state.routineName
        metadata["PulsarRoutineID"] = state.routineId.uuidString
        metadata[PulsarWorkoutMetadata.legacySessionIdKey] = state.sessionId.uuidString
        return metadata
    }

    private func markActiveStateFinished(workoutUUID: UUID?) {
        guard var state = syncStore.activeGymState else { return }
        let sessionId = activeSessionId ?? state.sessionId
        guard state.sessionId == sessionId else { return }
        state = normalizedState(state)
        state.isFinished = true
        state.restRemainingSeconds = nil
        state.restTotalSeconds = nil
        state.currentHeartRate = currentHeartRate ?? state.currentHeartRate
        state.averageHeartRate = averageHeartRate ?? state.averageHeartRate
        state.maxHeartRate = maxHeartRate ?? state.maxHeartRate
        state.activeEnergyKilocalories = activeEnergyKilocalories ?? state.activeEnergyKilocalories
        state.healthKitWorkoutUUID = workoutUUID ?? state.healthKitWorkoutUUID
        state.healthKitStatusMessage = message
        state.lifecycleGeneration = (state.lifecycleGeneration ?? 1) + 1
        state.updatedAt = Date()
        syncStore.storeActiveGymState(
            state,
            broadcast: !state.isPrelaunchPlaceholder,
            reason: workoutUUID == nil ? "watchGymWorkoutFinished" : "watchGymWorkoutFinishedWithHealthKit"
        )
    }

    private func normalizedState(_ state: ActiveGymWorkoutState) -> ActiveGymWorkoutState {
        var next = state
        next.exercises.sort { $0.orderIndex < $1.orderIndex }
        next.totalExercises = next.exercises.count
        next.totalSets = next.exercises.reduce(0) { $0 + $1.sets.count }
        next.completedSets = next.exercises.reduce(0) { total, exercise in
            total + exercise.sets.filter(\.isCompleted).count
        }
        next.elapsedSeconds = max(next.elapsedSeconds, Int(Date().timeIntervalSince(next.startedAt)))

        if let exerciseIndex = next.exercises.firstIndex(where: { !$0.isCompleted }) {
            if let nextAction = next.nextActionIndices {
                next.currentExerciseIndex = nextAction.exerciseIndex
                next.currentSetIndex = nextAction.setIndex
            } else {
                next.currentExerciseIndex = exerciseIndex
                next.currentSetIndex = next.exercises[exerciseIndex].sets.firstIndex(where: { !$0.isCompleted }) ?? 0
            }
        } else if let lastExerciseIndex = next.exercises.indices.last {
            next.currentExerciseIndex = lastExerciseIndex
            next.currentSetIndex = max(next.exercises[lastExerciseIndex].sets.count - 1, 0)
        } else {
            next.currentExerciseIndex = 0
            next.currentSetIndex = 0
        }

        next.updatedAt = Date()
        return next
    }

    private static func activeExerciseState(_ exercise: WatchGymRoutineExercisePlan) -> ActiveGymWorkoutExerciseState {
        ActiveGymWorkoutExerciseState(routinePlan: exercise)
    }

    private func restDecisionAfterCompleting(
        exerciseIndex: Int,
        setIndex: Int,
        in state: ActiveGymWorkoutState
    ) -> Int? {
        let exercise = state.exercises[exerciseIndex]
        guard let groupID = exercise.supersetGroupId else {
            return exercise.plannedRestSeconds
        }

        let members = state.exercises.enumerated()
            .filter { $0.element.supersetGroupId == groupID }
            .sorted {
                ($0.element.supersetOrder ?? $0.element.orderIndex) < ($1.element.supersetOrder ?? $1.element.orderIndex)
            }
        guard members.count >= 2 else {
            return exercise.plannedRestSeconds
        }

        let completedSetNumber = exercise.sets[setIndex].setNumber
        let roundIsComplete = members.allSatisfy { member in
            guard let matchingSet = member.element.sets.first(where: { $0.setNumber == completedSetNumber }) else { return false }
            return matchingSet.isCompleted
        }
        guard roundIsComplete else { return nil }

        let sharedSetCount = max(1, exercise.supersetSharedSetCount ?? members.map { $0.element.sets.count }.max() ?? 1)
        guard completedSetNumber < sharedSetCount else { return nil }
        return exercise.supersetRestSeconds ?? members.compactMap { $0.element.supersetRestSeconds }.first ?? exercise.plannedRestSeconds
    }

    private func handle(_ action: ActiveGymWorkoutAction) async {
        switch action.kind {
        case .finishWorkout:
            PulsarWorkoutLifecycleLogger.log(
                .wcReceive,
                sessionID: action.sessionId,
                device: "Watch",
                messageType: "finishWorkout"
            )
            if activeSessionId == nil,
               let state = syncStore.activeGymState,
               state.sessionId == action.sessionId {
                activeSessionId = state.sessionId
            }
            guard let sessionID = shouldHandleSessionScopedAction(action, reason: "watchGymFinishFromPhone") else { return }
            PulsarWorkoutLifecycleLogger.log(
                .stateTransition,
                sessionID: sessionID,
                workoutType: syncStore.activeGymState?.workoutKind?.rawValue,
                device: "Watch",
                previousState: "active",
                nextState: "finishing"
            )
            PulsarWorkoutLifecycleLogger.log(
                .finishRequested,
                sessionID: sessionID,
                workoutType: syncStore.activeGymState?.workoutKind?.rawValue,
                device: "Watch",
                previousState: "active",
                nextState: "finishing"
            )
            await finishCurrentWorkoutIfNeeded()
        case .requestState:
            guard workoutSession != nil else {
                PulsarSyncDebugLogger.log("Watch Gym requestState ignored because no primary session is active session=\(action.sessionId?.uuidString ?? "none")")
                return
            }
        case .skipRestTimer:
            if let sessionId = shouldHandleSessionScopedAction(action, reason: "watchGymRestSkippedFromPhone") {
                clearRest(sessionId: sessionId, reason: "watchGymRestSkippedFromPhone")
            }
        case .updateSetValues:
            guard let sessionId = shouldHandleSessionScopedAction(action, reason: "watchGymSetAdjustedFromPhone"),
                  let exerciseId = action.exerciseId,
                  let setId = action.setId else { return }
            updateSetValues(sessionId: sessionId, exerciseId: exerciseId, setId: setId, reps: action.setReps, weight: action.setWeight, sendsAction: false, playsHaptic: false)
        case .completeSet:
            guard let sessionId = shouldHandleSessionScopedAction(action, reason: "watchGymSetCompletedFromPhone"),
                  let exerciseId = action.exerciseId,
                  let setId = action.setId else { return }
            completeSet(sessionId: sessionId, exerciseId: exerciseId, setId: setId, reps: action.setReps, weight: action.setWeight, sendsAction: false)
        case .metricsUpdated,
             .requestSavedRoutines,
             .startFreeWorkoutFromWatch,
             .startSavedRoutineFromWatch:
            break
        }
    }

    private func shouldHandleSessionScopedAction(_ action: ActiveGymWorkoutAction, reason: String) -> UUID? {
        guard let incomingSessionId = action.sessionId else {
            PulsarSyncDebugLogger.log("Watch Gym action ignored because it has no session kind=\(action.kind.rawValue) reason=\(reason)")
            return nil
        }
        guard let activeSessionId else {
            PulsarSyncDebugLogger.log("Watch Gym action ignored because no local session is active kind=\(action.kind.rawValue) session=\(incomingSessionId.uuidString) reason=\(reason)")
            return nil
        }
        guard activeSessionId == incomingSessionId else {
            PulsarSyncDebugLogger.log("Watch Gym action ignored because session does not match kind=\(action.kind.rawValue) incoming=\(incomingSessionId.uuidString) active=\(activeSessionId.uuidString) reason=\(reason)")
            return nil
        }
        return incomingSessionId
    }

    private func finishWorkout() async {
        guard !isFinishing, workoutSession != nil || workoutBuilder != nil else { return }
        isFinishing = true
        let builder = workoutBuilder
        let finishingSessionID = activeSessionId
        stateTickTask?.cancel()
        stateTickTask = nil
        finishFallbackTask?.cancel()
        finishFallbackTask = nil
        stopRest()

        let end = Date()
        defer {
            cleanup(preservingFinishState: true)
            isFinishing = false
            PulsarWorkoutLifecycleLogger.log(
                .finishCompleted,
                sessionID: finishingSessionID,
                workoutType: syncStore.lastFinishedGymState?.workoutKind?.rawValue,
                device: "Watch",
                previousState: "finishing",
                nextState: "finished"
            )
            PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Watch Gym HealthKit session ended after builder finish session=\(finishingSessionID?.uuidString ?? "none")")
        }
        do {
            try await builder?.endCollection(at: end)
            let workout = try await builder?.finishWorkout()
            markActiveStateFinished(workoutUUID: workout?.uuid)
            WKInterfaceDevice.current().play(.success)
        } catch {
            message = "Apple Watch saved the local gym state, but Health finish failed."
            PulsarSyncDebugLogger.log("Watch Gym workout finish failed: \(error.localizedDescription)")
            markActiveStateFinished(workoutUUID: nil)
        }
    }

    private func cleanup(preservingFinishState: Bool = false) {
        stateTickTask?.cancel()
        stateTickTask = nil
        finishFallbackTask?.cancel()
        finishFallbackTask = nil
        stopRest()
        PulsarHealthKitWorkoutSessionTeardown.stopAndEnd(
            workoutSession,
            reason: "watchGymCleanup"
        )
        workoutSession = nil
        workoutBuilder = nil
        activeSessionId = nil
        startedAt = nil
        didSendWatchRunningAcknowledgement = false
        didSendFirstHeartRateEvent = false
        lastMirroredMetricsSentAt = .distantPast
        mirroringUnavailable = false
        mirroringStart.reset()
        pendingGymStartRequest = nil
        pendingRoutineSnapshot = nil
        provisionalCompanionSessionID = nil
        primarySessionGate.reset()
        if !preservingFinishState {
            isFinishing = false
        }
    }

    private var primaryObjectToken: String {
        workoutSession.map { String(describing: ObjectIdentifier($0)) }
            ?? (primarySessionGate.isCreating ? "creating" : "none")
    }

    private func logDuplicateStartIgnored(source: String, reason: String) {
        PulsarWorkoutStartupTrace.watch(
            "duplicate start ignored existingPrimary=\(primaryObjectToken) source=\(source) reason=\(reason) requestID=\(pendingGymStartRequest?.requestID.uuidString ?? primarySessionGate.requestID?.uuidString ?? "none") workoutID=\(primarySessionGate.workoutID?.uuidString ?? activeSessionId?.uuidString ?? "none") manager=\(managerObjectToken)"
        )
    }

    private func requestWorkoutSessionStop(reason: String) {
        guard let workoutSession else {
            PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Watch Gym HealthKit stop skipped because session is nil reason=\(reason) session=\(activeSessionId?.uuidString ?? "none")")
            Task { await finishWorkout() }
            return
        }
        switch workoutSession.state {
        case .ended, .stopped:
            PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Watch Gym HealthKit stop skipped because session is already terminal reason=\(reason) state=\(Self.describe(workoutSession.state)) session=\(activeSessionId?.uuidString ?? "none")")
            Task { await finishWorkout() }
        default:
            workoutSession.stopActivity(with: Date())
            PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Watch Gym HealthKit stopActivity requested reason=\(reason) state=\(Self.describe(workoutSession.state)) session=\(activeSessionId?.uuidString ?? "none")")
            finishFallbackTask?.cancel()
            finishFallbackTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(2_500))
                await MainActor.run {
                    guard let self,
                          !self.isFinishing,
                          self.workoutSession != nil || self.workoutBuilder != nil else { return }
                    PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Watch Gym stopped callback timed out; finishing builder fallback session=\(self.activeSessionId?.uuidString ?? "none")")
                    Task { await self.finishWorkout() }
                }
            }
        }
    }

    private static func describe(_ state: HKWorkoutSessionState) -> String {
        switch state {
        case .notStarted:
            "notStarted"
        case .prepared:
            "prepared"
        case .running:
            "running"
        case .paused:
            "paused"
        case .stopped:
            "stopped"
        case .ended:
            "ended"
        @unknown default:
            "unknown(\(state.rawValue))"
        }
    }

    private static var gymWorkoutConfiguration: HKWorkoutConfiguration {
        PulsarWorkoutCatalog.gymWorkoutConfiguration
    }

    private static func companionMetadataPendingState(
        sessionID: UUID,
        request: GymWorkoutStartRequest? = nil,
        startedAt: Date
    ) -> ActiveGymWorkoutState {
        ActiveGymWorkoutState(
            sessionId: sessionID,
            routineId: request?.routineID ?? sessionID,
            routineName: "Loading Routine…",
            routineEmoji: "🏋️",
            workoutKind: request?.workoutKind ?? .routine,
            startedFrom: .iPhoneRequestedWatchStart,
            startedAt: startedAt,
            elapsedSeconds: 0,
            currentExerciseIndex: 0,
            currentSetIndex: 0,
            totalExercises: 0,
            totalSets: 0,
            completedSets: 0,
            currentHeartRate: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            activeEnergyKilocalories: nil,
            restRemainingSeconds: nil,
            restTotalSeconds: nil,
            isHealthKitEnabled: true,
            healthKitStatusMessage: "Loading routine from iPhone",
            isFinished: false,
            updatedAt: startedAt,
            exercises: [],
            requestID: request?.requestID,
            routineRevision: request?.routineRevision,
            lifecycleGeneration: 1,
            isLaunchPlaceholder: true
        )
    }

    private static var healthShareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        [
            HKQuantityTypeIdentifier.activeEnergyBurned
        ].compactMap { HKObjectType.quantityType(forIdentifier: $0) }.forEach { types.insert($0) }
        return types
    }

    private static var healthReadTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = healthShareTypes
        [
            HKQuantityTypeIdentifier.heartRate,
            .activeEnergyBurned
        ].compactMap { HKObjectType.quantityType(forIdentifier: $0) }.forEach { types.insert($0) }
        return types
    }
}

extension WatchGymSessionManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            if toState == .running {
                self.sendWatchRunningAcknowledgementIfNeeded(for: workoutSession)
            } else if toState == .stopped {
                await self.finishWorkout()
            } else if toState == .ended {
                PulsarSyncDebugLogger.log("[PulsarWorkoutLifecycle] Watch Gym HealthKit session ended callback session=\(self.activeSessionId?.uuidString ?? "none")")
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.message = error.localizedDescription
            PulsarSyncDebugLogger.log("Watch Gym workout session failed: \(error.localizedDescription)")
        }
    }
}

extension WatchGymSessionManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            self.updateBuilderStatistics(for: collectedTypes)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
