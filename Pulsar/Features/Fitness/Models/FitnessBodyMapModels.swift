//
//  FitnessBodyMapModels.swift
//  Pulsar
//

import Foundation
import SwiftUI

enum BodyZone: String, CaseIterable, Hashable, Identifiable {
    case heart
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case core
    case glutes
    case quads
    case hamstrings
    case calves

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .heart: "Cardio"
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .core: "Core"
        case .glutes: "Glutes"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .calves: "Calves"
        }
    }

    var accent: Color {
        switch self {
        case .heart:
            Color(red: 1.00, green: 0.27, blue: 0.38)
        case .chest, .back, .shoulders, .biceps, .triceps:
            Color(red: 0.55, green: 0.62, blue: 1.00)
        case .core:
            Color(red: 1.00, green: 0.70, blue: 0.28)
        case .glutes, .quads, .hamstrings, .calves:
            Color(red: 0.24, green: 0.86, blue: 0.72)
        }
    }
}

struct TrainedBodyZone: Identifiable, Hashable {
    var zone: BodyZone
    var intensity: Double
    var sessions: Int
    var sourceWorkoutTypes: [String]

    var id: BodyZone { zone }
}

struct BodyMapAnalysis: Hashable {
    var trainedZones: [TrainedBodyZone]
    var cardioSessions: Int
    var cardioDuration: TimeInterval

    nonisolated static let empty = BodyMapAnalysis(trainedZones: [], cardioSessions: 0, cardioDuration: 0)

    var isCardioActive: Bool {
        cardioSessions > 0
    }

    func trainedZone(for zone: BodyZone) -> TrainedBodyZone? {
        trainedZones.first { $0.zone == zone }
    }
}

enum BodyMapAnalyzer {
    nonisolated static func analyze(activities: [WeeklyActivity]) -> BodyMapAnalysis {
        let cardioActivities = activities.filter(isCardioActivity)
        let cardioSessions = cardioActivities.count
        let cardioDuration = cardioActivities.reduce(0) { $0 + $1.duration }

        guard cardioSessions > 0 else {
            return .empty
        }

        let intensity: Double
        switch cardioSessions {
        case 1:
            intensity = 0.3
        case 2:
            intensity = 0.6
        default:
            intensity = 1.0
        }

        let workoutTypes = Array(Set(cardioActivities.map(\.displayName))).sorted()
        let heartZone = TrainedBodyZone(
            zone: .heart,
            intensity: intensity,
            sessions: cardioSessions,
            sourceWorkoutTypes: workoutTypes
        )

        return BodyMapAnalysis(
            trainedZones: [heartZone],
            cardioSessions: cardioSessions,
            cardioDuration: cardioDuration
        )
    }

    nonisolated private static func isCardioActivity(_ activity: WeeklyActivity) -> Bool {
        switch activity.category {
        case .running, .walking, .hiking, .cycling, .hiit, .swimming, .rowing, .dance:
            return true
        case .strength, .gym, .yoga, .recovery, .other:
            break
        }

        let searchable = "\(activity.workoutType) \(activity.displayName)".lowercased()
        let cardioKeywords = [
            "aerobic",
            "cardio",
            "cycle",
            "cycling",
            "elliptical",
            "hike",
            "hiking",
            "row",
            "rowing",
            "run",
            "running",
            "stair",
            "swim",
            "swimming",
            "walk",
            "walking"
        ]

        return cardioKeywords.contains { searchable.contains($0) }
    }
}
