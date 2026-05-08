//
//  GymLiveActivityManager.swift
//  Pulsar
//

import ActivityKit
import Foundation

@MainActor
final class GymLiveActivityManager {
    private var activity: Activity<PulsarGymLiveActivityAttributes>?

    func startIfPossible(state: ActiveGymWorkoutState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else {
            update(state: state)
            return
        }

        if let existingActivity = Activity<PulsarGymLiveActivityAttributes>.activities.first(where: { $0.attributes.sessionId == state.sessionId }) {
            activity = existingActivity
            update(state: state)
            return
        }

        let attributes = PulsarGymLiveActivityAttributes(sessionId: state.sessionId)
        activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: Self.contentState(from: state), staleDate: nil)
        )
    }

    func update(state: ActiveGymWorkoutState) {
        guard let activity else { return }
        let content = ActivityContent(state: Self.contentState(from: state), staleDate: nil)
        Task {
            await activity.update(content)
        }
    }

    func end(state: ActiveGymWorkoutState) {
        let content = ActivityContent(state: Self.contentState(from: state), staleDate: nil)
        let activity = activity
        Task {
            await activity?.end(content, dismissalPolicy: .immediate)
            await Self.endStaleActivitiesIfNeeded(activeState: nil)
        }
        self.activity = nil
    }

    static func endStaleActivitiesIfNeeded(activeState: ActiveGymWorkoutState?) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let stateStillLooksActive = activeState?.isFinished == false &&
            Date().timeIntervalSince(activeState?.updatedAt ?? .distantPast) < 6 * 60 * 60
        let activeSessionId = stateStillLooksActive ? activeState?.sessionId : nil

        for activity in Activity<PulsarGymLiveActivityAttributes>.activities {
            if let activeSessionId, activity.attributes.sessionId == activeSessionId {
                continue
            }

            let content = ActivityContent(
                state: finishedContentState(from: activeState),
                staleDate: nil
            )
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }

    private static func contentState(from state: ActiveGymWorkoutState) -> PulsarGymLiveActivityAttributes.ContentState {
        PulsarGymLiveActivityAttributes.ContentState(
            routineName: state.routineName,
            currentExerciseName: state.currentExercise?.exerciseName ?? "Open Gym",
            progressText: state.progressText,
            exerciseProgressText: state.exerciseProgressText,
            elapsedSeconds: state.elapsedSeconds,
            heartRate: state.currentHeartRate,
            activeEnergyKilocalories: state.activeEnergyKilocalories,
            restRemainingSeconds: state.restRemainingSeconds,
            isFinished: state.isFinished
        )
    }

    private static func finishedContentState(from state: ActiveGymWorkoutState?) -> PulsarGymLiveActivityAttributes.ContentState {
        guard let state else {
            return PulsarGymLiveActivityAttributes.ContentState(
                routineName: "Gym Workout",
                currentExerciseName: "Finished",
                progressText: "Finished",
                exerciseProgressText: "Workout complete",
                elapsedSeconds: 0,
                heartRate: nil,
                activeEnergyKilocalories: nil,
                restRemainingSeconds: nil,
                isFinished: true
            )
        }

        var content = contentState(from: state)
        content.isFinished = true
        content.restRemainingSeconds = nil
        return content
    }
}
