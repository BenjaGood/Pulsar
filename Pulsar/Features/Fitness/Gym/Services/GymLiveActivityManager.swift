//
//  GymLiveActivityManager.swift
//  Pulsar
//

import ActivityKit
import Foundation

@MainActor
final class GymLiveActivityManager {
    private var activity: Activity<PulsarGymLiveActivityAttributes>?
    private var lastContentState: PulsarGymLiveActivityAttributes.ContentState?
    private var lastContentUpdateAt: Date?
    private static let elapsedOnlyUpdateInterval: TimeInterval = 10

    func startIfPossible(state: ActiveGymWorkoutState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            PulsarWorkoutStartupTrace.diag(
                "[LiveActivity] start skipped disabled session=\(state.sessionId.uuidString)"
            )
            return
        }
        guard activity == nil else {
            PulsarWorkoutStartupTrace.diag(
                "[LiveActivity] start skipped alreadyRunning session=\(state.sessionId.uuidString)"
            )
            update(state: state)
            return
        }

        if let existingActivity = Activity<PulsarGymLiveActivityAttributes>.activities.first(where: { $0.attributes.sessionId == state.sessionId }) {
            activity = existingActivity
            PulsarWorkoutStartupTrace.diag(
                "[LiveActivity] start reusedExisting session=\(state.sessionId.uuidString)"
            )
            update(state: state)
            return
        }

        let attributes = PulsarGymLiveActivityAttributes(sessionId: state.sessionId)
        let contentState = Self.contentState(from: state)
        activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: contentState, staleDate: Self.activeStaleDate())
        )
        if activity != nil {
            remember(contentState)
            PulsarWorkoutStartupTrace.diag(
                "[LiveActivity] start requested session=\(state.sessionId.uuidString) success=true"
            )
        } else {
            PulsarWorkoutStartupTrace.diag(
                "[LiveActivity] start requested session=\(state.sessionId.uuidString) success=false"
            )
        }
    }

    func update(state: ActiveGymWorkoutState) {
        guard let activity else { return }
        let contentState = Self.contentState(from: state)
        guard shouldUpdate(contentState) else { return }
        remember(contentState)
        let content = ActivityContent(state: contentState, staleDate: Self.activeStaleDate())
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
        lastContentState = nil
        lastContentUpdateAt = nil
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

            PulsarWorkoutStartupTrace.diag(
                "[LiveActivity] endStale session=\(activity.attributes.sessionId.uuidString) keeping=\(activeSessionId?.uuidString ?? "none")"
            )
            let content = ActivityContent(
                state: finishedContentState(from: activeState),
                staleDate: nil
            )
            await activity.end(content, dismissalPolicy: .immediate)
        }
    }

    private static func contentState(from state: ActiveGymWorkoutState) -> PulsarGymLiveActivityAttributes.ContentState {
        PulsarGymLiveActivityAttributes.ContentState(
            routineName: displayRoutineName(state.routineName),
            routineEmoji: state.routineEmoji,
            currentExerciseName: state.currentExercise?.exerciseName ?? "Open gym session",
            progressText: state.progressText,
            exerciseProgressText: state.exerciseProgressText,
            completedSets: state.completedSets,
            totalSets: state.totalSets,
            totalExercises: state.totalExercises,
            elapsedSeconds: state.elapsedSeconds,
            heartRate: state.currentHeartRate,
            activeEnergyKilocalories: state.activeEnergyKilocalories,
            restRemainingSeconds: state.restRemainingSeconds,
            isFinished: state.isFinished
        )
    }

    private func shouldUpdate(_ next: PulsarGymLiveActivityAttributes.ContentState) -> Bool {
        guard let previous = lastContentState else { return true }
        guard next != previous else { return false }

        var previousWithUpdatedElapsed = previous
        previousWithUpdatedElapsed.elapsedSeconds = next.elapsedSeconds
        if previousWithUpdatedElapsed == next {
            guard let lastContentUpdateAt else { return true }
            return Date().timeIntervalSince(lastContentUpdateAt) >= Self.elapsedOnlyUpdateInterval
        }
        return true
    }

    private func remember(_ contentState: PulsarGymLiveActivityAttributes.ContentState) {
        lastContentState = contentState
        lastContentUpdateAt = Date()
    }

    private static func activeStaleDate() -> Date {
        Date().addingTimeInterval(15 * 60)
    }

    private static func finishedContentState(from state: ActiveGymWorkoutState?) -> PulsarGymLiveActivityAttributes.ContentState {
        guard let state else {
            return PulsarGymLiveActivityAttributes.ContentState(
                routineName: "Gym Workout",
                routineEmoji: "🏋️",
                currentExerciseName: "Finished",
                progressText: "Finished",
                exerciseProgressText: "Workout complete",
                completedSets: 0,
                totalSets: 0,
                totalExercises: 0,
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

    private static func displayRoutineName(_ routineName: String) -> String {
        let trimmedName = routineName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return "Gym Workout" }
        if trimmedName.localizedCaseInsensitiveContains("empty gym") {
            return "Gym Workout"
        }
        return trimmedName
    }
}
