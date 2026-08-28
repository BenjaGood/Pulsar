//
//  NutritionWorkoutPlan.swift
//  Pulsar
//

import Foundation

enum NutritionWorkoutPlanBasis: String, CaseIterable, Identifiable, Codable, Hashable {
    case usualRoutine
    case newOrIncreasedRoutine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .usualRoutine: "This is my usual routine"
        case .newOrIncreasedRoutine: "This is a new or increased routine"
        }
    }

    var subtitle: String {
        switch self {
        case .usualRoutine:
            "Pulsar models your planned workouts and uses HealthKit only to validate that estimate."
        case .newOrIncreasedRoutine:
            "Pulsar compares your planned routine with recent activity and adds only the expected increase."
        }
    }
}

enum NutritionDailyActivityLevel: String, CaseIterable, Identifiable, Codable, Hashable {
    case mostlySeated
    case someStandingAndWalking
    case activeOnFeet
    case physicallyDemanding

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mostlySeated: "Mostly seated"
        case .someStandingAndWalking: "Some standing and walking"
        case .activeOnFeet: "Active on my feet"
        case .physicallyDemanding: "Physically demanding"
        }
    }

    var subtitle: String {
        switch self {
        case .mostlySeated: "Desk work, driving, or limited daily movement outside workouts."
        case .someStandingAndWalking: "Regular errands, light household activity, or a short commute."
        case .activeOnFeet: "Retail, teaching, caregiving, or frequent walking during the day."
        case .physicallyDemanding: "Manual labor, trades, or consistently heavy daily movement."
        }
    }

    var palAnchor: Double {
        switch self {
        case .mostlySeated: 1.35
        case .someStandingAndWalking: 1.50
        case .activeOnFeet: 1.65
        case .physicallyDemanding: 1.80
        }
    }
}

enum NutritionWorkoutType: String, CaseIterable, Identifiable, Codable, Hashable {
    case gymStrength
    case cycling
    case running
    case walking
    case hiking
    case swimming
    case rowing
    case hiitCircuit
    case teamSport
    case yogaMobility
    case mixedOther

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gymStrength: "Gym / strength"
        case .cycling: "Cycling"
        case .running: "Running"
        case .walking: "Walking"
        case .hiking: "Hiking"
        case .swimming: "Swimming"
        case .rowing: "Rowing"
        case .hiitCircuit: "HIIT / circuit"
        case .teamSport: "Team sport"
        case .yogaMobility: "Yoga / mobility"
        case .mixedOther: "Mixed / other"
        }
    }
}

enum NutritionWorkoutIntensity: String, CaseIterable, Identifiable, Codable, Hashable {
    case light
    case moderate
    case vigorous

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .moderate: "Moderate"
        case .vigorous: "Vigorous"
        }
    }
}

struct NutritionWorkoutPlanEntry: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var workoutType: NutritionWorkoutType
    var daysPerWeek: Int
    var sessionsPerDay: Int
    var minutesPerSession: Int
    var intensity: NutritionWorkoutIntensity
    var requiresReview: Bool

    init(
        id: UUID = UUID(),
        workoutType: NutritionWorkoutType,
        daysPerWeek: Int,
        sessionsPerDay: Int = 1,
        minutesPerSession: Int,
        intensity: NutritionWorkoutIntensity,
        requiresReview: Bool = false
    ) {
        self.id = id
        self.workoutType = workoutType
        self.daysPerWeek = daysPerWeek
        self.sessionsPerDay = sessionsPerDay
        self.minutesPerSession = minutesPerSession
        self.intensity = intensity
        self.requiresReview = requiresReview
    }

    var weeklySessions: Int { daysPerWeek * sessionsPerDay }
    var weeklyMinutes: Int { weeklySessions * minutesPerSession }

    var accessibilitySummary: String {
        "\(workoutType.title), \(daysPerWeek) days per week, \(sessionsPerDay) session\(sessionsPerDay == 1 ? "" : "s") per day, \(minutesPerSession) minutes, \(intensity.title.lowercased()) intensity"
    }
}

struct NutritionWorkoutPlan: Codable, Equatable, Hashable {
    var basis: NutritionWorkoutPlanBasis
    var dailyActivityLevel: NutritionDailyActivityLevel
    var sessions: [NutritionWorkoutPlanEntry]

    static let empty = NutritionWorkoutPlan(
        basis: .usualRoutine,
        dailyActivityLevel: .someStandingAndWalking,
        sessions: []
    )

    var totalSessionsPerWeek: Int {
        sessions.reduce(0) { $0 + $1.weeklySessions }
    }

    var totalMinutesPerWeek: Int {
        sessions.reduce(0) { $0 + $1.weeklyMinutes }
    }

    var workoutMixSummary: String {
        guard !sessions.isEmpty else { return "No planned workouts" }
        let grouped = Dictionary(grouping: sessions, by: \.workoutType)
        return grouped.keys.sorted { $0.title < $1.title }.map { type in
            let entries = grouped[type] ?? []
            let minutes = entries.reduce(0) { $0 + $1.weeklyMinutes }
            return "\(type.title) (\(minutes) min/wk)"
        }.joined(separator: ", ")
    }
}

enum NutritionWorkoutPlanMigration {
    static func legacyEntry(
        sessionsPerWeek: Int,
        trainingType: NutritionPrimaryTrainingType
    ) -> NutritionWorkoutPlanEntry? {
        guard sessionsPerWeek > 0 else { return nil }
        let workoutType: NutritionWorkoutType
        switch trainingType {
        case .strength: workoutType = .gymStrength
        case .endurance: workoutType = .running
        case .teamSport: workoutType = .teamSport
        case .lowImpact: workoutType = .yogaMobility
        case .mixed: workoutType = .mixedOther
        }
        return NutritionWorkoutPlanEntry(
            workoutType: workoutType,
            daysPerWeek: min(max(sessionsPerWeek, 1), 7),
            sessionsPerDay: 1,
            minutesPerSession: 45,
            intensity: .moderate,
            requiresReview: true
        )
    }
}
