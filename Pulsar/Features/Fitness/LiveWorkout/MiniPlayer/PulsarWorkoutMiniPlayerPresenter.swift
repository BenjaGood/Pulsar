import Combine
import Foundation

@MainActor
enum PulsarLocalGymMiniPlayerClockUpdates {
    static func publisher(for clock: GymWorkoutSessionClock?) -> AnyPublisher<Int, Never> {
        guard let clock else {
            return Empty(completeImmediately: false).eraseToAnyPublisher()
        }
        return clock.$elapsedSeconds
            .removeDuplicates()
            .dropFirst()
            .eraseToAnyPublisher()
    }
}

struct PulsarLocalGymMiniPlayerContentProjection: Equatable {
    var sessionID: UUID
    var routineName: String
    var focusedExerciseName: String?
    var completedSets: Int
    var totalSets: Int
    var hasSummary: Bool
    var currentHeartRate: Double?
}

private struct PulsarLocalGymMiniPlayerSessionProjection: Equatable {
    var sessionID: UUID
    var routineName: String
    var focusedExerciseName: String?
    var completedSets: Int
    var totalSets: Int

    init(session: PulsarGymWorkoutSession, focusTarget: GymWorkoutSetFocusTarget?) {
        sessionID = session.id
        routineName = session.routineName
        focusedExerciseName = focusTarget.flatMap { target in
            session.exercises.first(where: { $0.id == target.exerciseID })?.exerciseName
        } ?? session.exercises.first(where: { !$0.isCompleted })?.exerciseName
        completedSets = session.exercises.reduce(0) { count, exercise in
            count + exercise.completedSetCount
        }
        totalSets = session.exercises.reduce(0) { count, exercise in
            count + exercise.sets.count
        }
    }
}

@MainActor
enum PulsarLocalGymMiniPlayerContentUpdates {
    static func publisher(
        for viewModel: GymWorkoutSessionViewModel?
    ) -> AnyPublisher<PulsarLocalGymMiniPlayerContentProjection, Never> {
        guard let viewModel else {
            return Empty(completeImmediately: false).eraseToAnyPublisher()
        }

        return publisher(
            session: viewModel.$session,
            focusTarget: viewModel.$focusTarget,
            hasSummary: viewModel.$summary.map { $0 != nil },
            currentHeartRate: viewModel.$currentHeartRate
        )
    }

    static func publisher<Session, FocusTarget, Summary, HeartRate>(
        session: Session,
        focusTarget: FocusTarget,
        hasSummary: Summary,
        currentHeartRate: HeartRate
    ) -> AnyPublisher<PulsarLocalGymMiniPlayerContentProjection, Never>
    where
        Session: Publisher,
        Session.Output == PulsarGymWorkoutSession,
        Session.Failure == Never,
        FocusTarget: Publisher,
        FocusTarget.Output == GymWorkoutSetFocusTarget?,
        FocusTarget.Failure == Never,
        Summary: Publisher,
        Summary.Output == Bool,
        Summary.Failure == Never,
        HeartRate: Publisher,
        HeartRate.Output == Double?,
        HeartRate.Failure == Never
    {
        let sessionProjection = Publishers.CombineLatest(session, focusTarget)
            .map { session, focusTarget in
                PulsarLocalGymMiniPlayerSessionProjection(
                    session: session,
                    focusTarget: focusTarget
                )
            }
            .removeDuplicates()

        return Publishers.CombineLatest3(
            sessionProjection,
            hasSummary.removeDuplicates(),
            currentHeartRate.removeDuplicates()
        )
            .map { session, hasSummary, currentHeartRate in
                PulsarLocalGymMiniPlayerContentProjection(
                    sessionID: session.sessionID,
                    routineName: session.routineName,
                    focusedExerciseName: session.focusedExerciseName,
                    completedSets: session.completedSets,
                    totalSets: session.totalSets,
                    hasSummary: hasSummary,
                    currentHeartRate: currentHeartRate
                )
            }
            .removeDuplicates()
            .dropFirst()
            .eraseToAnyPublisher()
    }
}

@MainActor
enum PulsarWorkoutMiniPlayerPresenter {
    static func run(
        activeWorkout: PulsarActiveWorkout,
        snapshot: PulsarRunMetricSnapshot,
        syncedSessionID: UUID?
    ) -> PulsarWorkoutMiniPlayerState? {
        guard case .run(let workoutKind) = activeWorkout.kind,
              isActive(snapshot.phase),
              snapshot.pulsarWorkoutSessionId == activeWorkout.sessionID || syncedSessionID == activeWorkout.sessionID,
              snapshot.pulsarWorkoutSessionId != nil else { return nil }

        let paceText = PulsarRunFormatters.paceOrSpeed(
            workoutKind: workoutKind,
            paceSecondsPerKilometer: snapshot.currentPaceSecondsPerKilometer,
            speedMetersPerSecond: snapshot.distanceMeters / max(snapshot.movingTime, 1)
        )
        return PulsarWorkoutMiniPlayerState(
            id: "run-\(workoutKind.rawValue)-\(activeWorkout.sessionID.uuidString)",
            sessionID: activeWorkout.sessionID,
            kind: .run(workoutKind),
            title: workoutKind.displayName,
            symbol: workoutKind.systemImageName,
            status: snapshot.phase == .paused ? .paused : .live,
            elapsedText: PulsarRunFormatters.duration(snapshot.elapsedTime),
            secondaryMetrics: PulsarWorkoutMiniPlayerMetricPolicy.runMetrics(
                workoutKind: workoutKind,
                heartRate: snapshot.currentHeartRate,
                distanceMeters: snapshot.distanceMeters,
                paceText: paceText,
                calories: snapshot.activeEnergyKilocalories,
                steps: snapshot.stepCount,
                cadence: snapshot.cadenceStepsPerMinute,
                source: snapshot.source.label
            )
        )
    }

    static func gym(
        activeWorkout: PulsarActiveWorkout,
        viewModel: GymWorkoutSessionViewModel?,
        isMinimized: Bool
    ) -> PulsarWorkoutMiniPlayerState? {
        guard activeWorkout.kind == .gym,
              let viewModel,
              viewModel.summary == nil,
              viewModel.session.id == activeWorkout.sessionID,
              isMinimized else { return nil }

        let focusedExerciseName = viewModel.focusTarget.flatMap { target in
            viewModel.session.exercises.first(where: { $0.id == target.exerciseID })?.exerciseName
        } ?? viewModel.session.exercises.first(where: { !$0.isCompleted })?.exerciseName
        return PulsarWorkoutMiniPlayerState(
            id: "gym-\(viewModel.session.id.uuidString)",
            sessionID: viewModel.session.id,
            kind: .gym,
            title: viewModel.session.routineName,
            symbol: "dumbbell.fill",
            status: .live,
            elapsedText: PulsarGymFormatters.duration(viewModel.elapsedSeconds),
            secondaryMetrics: PulsarWorkoutMiniPlayerMetricPolicy.gymMetrics(
                exerciseName: focusedExerciseName,
                completedSets: viewModel.completedSetsCount,
                totalSets: viewModel.totalSetsCount,
                heartRate: viewModel.currentHeartRate
            )
        )
    }

    static func watchGym(
        activeWorkout: PulsarActiveWorkout,
        state: ActiveGymWorkoutState?,
        isRoutable: Bool,
        hasLocalGymSession: Bool
    ) -> PulsarWorkoutMiniPlayerState? {
        guard activeWorkout.kind == .watchGym,
              let state,
              state.sessionId == activeWorkout.sessionID,
              !state.isFinished,
              isRoutable,
              !hasLocalGymSession else { return nil }

        return PulsarWorkoutMiniPlayerState(
            id: "watch-gym-\(state.sessionId.uuidString)",
            sessionID: state.sessionId,
            kind: .watchGym,
            title: state.workoutKind == .freeWorkout
                ? PulsarGymWorkoutKind.freeWorkout.displayName
                : state.routineName,
            symbol: "applewatch",
            status: .live,
            elapsedText: PulsarGymFormatters.duration(state.elapsedSeconds),
            secondaryMetrics: PulsarWorkoutMiniPlayerMetricPolicy.gymMetrics(
                exerciseName: state.workoutKind == .freeWorkout ? nil : state.currentExercise?.exerciseName,
                completedSets: state.completedSets,
                totalSets: state.workoutKind == .freeWorkout ? 0 : state.totalSets,
                heartRate: state.currentHeartRate
            )
        )
    }

    /// Presentation ownership is stronger than a transient transport snapshot.
    /// If a verified Watch gym is minimized between WC packets, keep a compact
    /// reopen affordance instead of leaving the global accessory empty.
    static func watchGymFallback(
        activeWorkout: PulsarActiveWorkout
    ) -> PulsarWorkoutMiniPlayerState? {
        guard activeWorkout.kind == .watchGym,
              activeWorkout.phase != "finished",
              activeWorkout.phase != "ended" else { return nil }
        return PulsarWorkoutMiniPlayerState(
            id: "watch-gym-fallback-\(activeWorkout.sessionID.uuidString)",
            sessionID: activeWorkout.sessionID,
            kind: .watchGym,
            title: "Gym Workout",
            symbol: "applewatch",
            status: .live,
            elapsedText: "Live",
            secondaryMetrics: []
        )
    }

    static func synced(
        activeWorkout: PulsarActiveWorkout,
        state: PulsarActiveWorkoutSyncState?
    ) -> PulsarWorkoutMiniPlayerState? {
        guard let state,
              state.sessionId == activeWorkout.sessionID,
              state.phase.isLive else { return nil }

        switch state.kind {
        case .outdoor(let workoutKind):
            let paceText = PulsarRunFormatters.paceOrSpeed(
                workoutKind: workoutKind,
                paceSecondsPerKilometer: state.currentPaceSecondsPerKilometer,
                speedMetersPerSecond: state.averageSpeedMetersPerSecond
            )
            return PulsarWorkoutMiniPlayerState(
                id: "sync-run-\(workoutKind.rawValue)-\(state.sessionId.uuidString)",
                sessionID: state.sessionId,
                kind: .run(workoutKind),
                title: workoutKind.displayName,
                symbol: state.lastUpdatedFrom.isAppleWatchRecorder ? "applewatch" : workoutKind.systemImageName,
                status: status(for: state.phase),
                elapsedText: PulsarRunFormatters.duration(TimeInterval(state.elapsedSeconds)),
                secondaryMetrics: PulsarWorkoutMiniPlayerMetricPolicy.runMetrics(
                    workoutKind: workoutKind,
                    heartRate: state.currentHeartRate,
                    distanceMeters: state.distanceMeters ?? 0,
                    paceText: paceText,
                    calories: state.activeEnergyKilocalories,
                    steps: state.stepCount,
                    cadence: state.cadenceStepsPerMinute,
                    source: state.startedFrom.displayName
                )
            )
        case .gym:
            return PulsarWorkoutMiniPlayerState(
                id: "sync-gym-\(state.kind.workoutTypeRawValue)-\(state.sessionId.uuidString)",
                sessionID: state.sessionId,
                kind: .watchGym,
                title: state.displayName,
                symbol: "applewatch",
                status: status(for: state.phase),
                elapsedText: PulsarRunFormatters.duration(TimeInterval(state.elapsedSeconds)),
                secondaryMetrics: PulsarWorkoutMiniPlayerMetricPolicy.gymMetrics(
                    exerciseName: nil,
                    completedSets: 0,
                    totalSets: 0,
                    heartRate: state.currentHeartRate
                )
            )
        }
    }

    private static func status(for phase: PulsarActiveWorkoutSyncPhase) -> PulsarWorkoutMiniPlayerState.LiveStatus {
        switch phase {
        case .starting: .preparing
        case .active, .resumed: .live
        case .paused: .paused
        case .ending, .ended, .cancelled: .saving
        case .failed: .disconnected
        }
    }

    private static func isActive(_ phase: PulsarRunPhase) -> Bool {
        switch phase {
        case .running, .paused, .finishing, .connectingToWatch: true
        case .idle, .requestingPermissions, .countingDown, .finished, .failed: false
        }
    }
}
