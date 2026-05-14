//
//  WorkoutOption.swift
//  Pulsar
//

import SwiftUI

enum PersonalizedWorkoutKind: String, CaseIterable, Identifiable, Hashable {
    case hiking = "Hiking"
    case running = "Running"
    case walking = "Walking"
    case gym = "Gym"

    var id: String { rawValue }

    var title: String { rawValue }

    var symbolName: String {
        switch self {
        case .hiking: "mountain.2.fill"
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .gym: "dumbbell.fill"
        }
    }

    var accent: WorkoutAccent {
        switch self {
        case .hiking: .terrain
        case .running: .velocity
        case .walking: .balance
        case .gym: .power
        }
    }

    var outdoorWorkoutKind: PulsarOutdoorWorkoutKind? {
        switch self {
        case .running: .running
        case .walking: .walking
        case .hiking: .hiking
        case .gym: nil
        }
    }
}

enum WorkoutAccent: String, Hashable {
    case terrain
    case velocity
    case balance
    case power
    case endurance
    case fire
    case restore
    case water
    case rhythm
    case focus

    var color: Color {
        switch self {
        case .terrain: Color(red: 0.34, green: 0.82, blue: 0.58)
        case .velocity: Color(red: 1.00, green: 0.46, blue: 0.34)
        case .balance: Color(red: 0.44, green: 0.72, blue: 1.00)
        case .power: Color(red: 0.72, green: 0.66, blue: 1.00)
        case .endurance: Color(red: 0.25, green: 0.78, blue: 0.86)
        case .fire: Color(red: 1.00, green: 0.61, blue: 0.25)
        case .restore: Color(red: 0.72, green: 0.82, blue: 0.46)
        case .water: Color(red: 0.34, green: 0.68, blue: 1.00)
        case .rhythm: Color(red: 1.00, green: 0.44, blue: 0.68)
        case .focus: Color(red: 0.68, green: 0.74, blue: 0.84)
        }
    }
}

struct WorkoutOption: Identifiable, Hashable {
    let id: String
    let name: String
    let symbolName: String
    let category: String
    let accent: WorkoutAccent
    let personalizedKind: PersonalizedWorkoutKind?

    var isPersonalized: Bool {
        personalizedKind != nil
    }

    var outdoorWorkoutKind: PulsarOutdoorWorkoutKind? {
        if let personalizedKind {
            return personalizedKind.outdoorWorkoutKind
        }

        switch id {
        case "cycling":
            return .cycling
        case "hiit":
            return .hiit
        case "strength":
            return .strength
        case "yoga":
            return .yoga
        case "pilates":
            return .pilates
        case "swimming":
            return .swimming
        case "rowing":
            return .rowing
        case "dance":
            return .dance
        case "boxing":
            return .boxing
        case "stretching":
            return .stretching
        case "core":
            return .core
        case "mobility":
            return .mobility
        default:
            return nil
        }
    }

    init(
        id: String? = nil,
        name: String,
        symbolName: String,
        category: String,
        accent: WorkoutAccent,
        personalizedKind: PersonalizedWorkoutKind? = nil
    ) {
        self.id = id ?? name.lowercased().replacingOccurrences(of: " ", with: "-")
        self.name = name
        self.symbolName = symbolName
        self.category = category
        self.accent = accent
        self.personalizedKind = personalizedKind
    }
}

extension WorkoutOption {
    static let personalized: [WorkoutOption] = PersonalizedWorkoutKind.allCases.map { workout in
        WorkoutOption(
            name: workout.title,
            symbolName: workout.symbolName,
            category: "Personalized",
            accent: workout.accent,
            personalizedKind: workout
        )
    }

    static let general: [WorkoutOption] = [
        WorkoutOption(name: "Cycling", symbolName: "bicycle", category: "Endurance", accent: .endurance),
        WorkoutOption(name: "HIIT", symbolName: "flame.fill", category: "Intervals", accent: .fire),
        WorkoutOption(name: "Strength", symbolName: "figure.strengthtraining.traditional", category: "Power", accent: .power),
        WorkoutOption(name: "Yoga", symbolName: "figure.yoga", category: "Restore", accent: .restore),
        WorkoutOption(name: "Pilates", symbolName: "figure.core.training", category: "Control", accent: .balance),
        WorkoutOption(name: "Swimming", symbolName: "figure.pool.swim", category: "Water", accent: .water),
        WorkoutOption(name: "Rowing", symbolName: "figure.rower", category: "Endurance", accent: .endurance),
        WorkoutOption(name: "Dance", symbolName: "figure.dance", category: "Rhythm", accent: .rhythm),
        WorkoutOption(name: "Boxing", symbolName: "figure.boxing", category: "Power", accent: .fire),
        WorkoutOption(name: "Stretching", symbolName: "figure.flexibility", category: "Recovery", accent: .restore),
        WorkoutOption(name: "Core", symbolName: "figure.core.training", category: "Stability", accent: .balance),
        WorkoutOption(name: "Mobility", symbolName: "figure.cooldown", category: "Flow", accent: .focus)
    ]
}
