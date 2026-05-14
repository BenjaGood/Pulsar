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

@MainActor
final class PulsarActiveWorkoutManager: ObservableObject {
    @Published var presentedWorkout: PulsarPresentedWorkout?
    @Published private(set) var minimizedRunWorkoutKind: PulsarOutdoorWorkoutKind?
    @Published private(set) var gymSessionViewModel: GymWorkoutSessionViewModel?
    @Published private(set) var isGymWorkoutMinimized = false

    func minimizeRunWorkout(_ workoutKind: PulsarOutdoorWorkoutKind) {
        minimizedRunWorkoutKind = workoutKind
        if case .run = presentedWorkout {
            presentedWorkout = nil
        }
    }

    func presentRunWorkout(_ workoutKind: PulsarOutdoorWorkoutKind) {
        presentedWorkout = .run(workoutKind)
    }

    func clearRunWorkout() {
        minimizedRunWorkoutKind = nil
        if case .run = presentedWorkout {
            presentedWorkout = nil
        }
    }

    func startGymWorkout(
        routine: PulsarRoutine,
        workoutWeightUnit: PulsarWeightUnit?,
        historyStore: PulsarGymWorkoutHistoryStore? = nil
    ) {
        if let gymSessionViewModel, gymSessionViewModel.summary == nil {
            isGymWorkoutMinimized = false
            return
        }

        gymSessionViewModel = GymWorkoutSessionViewModel(
            routine: routine,
            workoutWeightUnit: workoutWeightUnit,
            historyStore: historyStore
        )
        isGymWorkoutMinimized = false
    }

    func minimizeGymWorkout() {
        guard gymSessionViewModel?.summary == nil else {
            completeGymWorkout()
            return
        }
        isGymWorkoutMinimized = true
        if case .gym = presentedWorkout {
            presentedWorkout = nil
        }
    }

    func presentGymWorkout() {
        guard gymSessionViewModel?.summary == nil else {
            completeGymWorkout()
            return
        }
        presentedWorkout = .gym
    }

    func completeGymWorkout() {
        gymSessionViewModel = nil
        isGymWorkoutMinimized = false
        if case .gym = presentedWorkout {
            presentedWorkout = nil
        }
    }

    func presentWatchGymWorkout() {
        presentedWorkout = .watchGym
    }

    func minimizeWatchGymWorkout() {
        if case .watchGym = presentedWorkout {
            presentedWorkout = nil
        }
    }

    func clearWatchGymWorkout() {
        if case .watchGym = presentedWorkout {
            presentedWorkout = nil
        }
    }
}
