//
//  WorkoutOption.swift
//  Pulsar
//

import SwiftUI

enum PersonalizedWorkoutKind: String, CaseIterable, Identifiable, Hashable {
    case hiking = "Hiking"
    case running = "Running"
    case indoorRunning = "Indoor Running"
    case walking = "Walking"
    case gym = "Gym"

    nonisolated var id: String { rawValue }

    nonisolated var title: String { rawValue }

    nonisolated var symbolName: String {
        catalogEntry?.symbolName ?? "figure.mixed.cardio"
    }

    nonisolated var accent: WorkoutAccent {
        catalogEntry.map { WorkoutAccent.catalogAccent(for: $0) } ?? .focus
    }

    nonisolated var outdoorWorkoutKind: PulsarOutdoorWorkoutKind? {
        switch self {
        case .running: .running
        case .walking: .walking
        case .hiking: .hiking
        case .indoorRunning: .indoorRunning
        case .gym: nil
        }
    }

    nonisolated private var catalogEntry: PulsarWorkoutCatalogEntry? {
        PulsarWorkoutCatalog.entries.first { entry in
            switch entry.destination {
            case .outdoor(let kind):
                return kind == outdoorWorkoutKind
            case .gym:
                return self == .gym
            }
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
    let outdoorWorkoutKind: PulsarOutdoorWorkoutKind?

    nonisolated var isPersonalized: Bool {
        personalizedKind != nil
    }

    nonisolated init(
        id: String? = nil,
        name: String,
        symbolName: String,
        category: String,
        accent: WorkoutAccent,
        personalizedKind: PersonalizedWorkoutKind? = nil,
        outdoorWorkoutKind: PulsarOutdoorWorkoutKind? = nil
    ) {
        self.id = id ?? name.lowercased().replacingOccurrences(of: " ", with: "-")
        self.name = name
        self.symbolName = symbolName
        self.category = category
        self.accent = accent
        self.personalizedKind = personalizedKind
        self.outdoorWorkoutKind = outdoorWorkoutKind ?? personalizedKind?.outdoorWorkoutKind
    }
}

extension WorkoutOption {
    static let personalized: [WorkoutOption] = PulsarWorkoutCatalog.personalizedEntries.map(Self.init(catalogEntry:))

    static let general: [WorkoutOption] = PulsarWorkoutCatalog.moreWorkoutEntries.map(Self.init(catalogEntry:))

    nonisolated private init(catalogEntry entry: PulsarWorkoutCatalogEntry) {
        let personalizedKind = PersonalizedWorkoutKind.allCases.first { kind in
            switch entry.destination {
            case .outdoor(let workoutKind):
                return kind.outdoorWorkoutKind == workoutKind
            case .gym:
                return kind == .gym
            }
        }
        self.init(
            id: entry.id,
            name: entry.displayName,
            symbolName: entry.symbolName,
            category: entry.category,
            accent: WorkoutAccent.catalogAccent(for: entry),
            personalizedKind: entry.section == .personalized ? personalizedKind : nil,
            outdoorWorkoutKind: entry.outdoorWorkoutKind
        )
    }
}

extension WorkoutAccent {
    nonisolated static func catalogAccent(for entry: PulsarWorkoutCatalogEntry) -> WorkoutAccent {
        switch entry.id {
        case PulsarOutdoorWorkoutKind.hiking.rawValue:
            return .terrain
        case PulsarOutdoorWorkoutKind.running.rawValue,
             PulsarOutdoorWorkoutKind.indoorRunning.rawValue:
            return .velocity
        case PulsarOutdoorWorkoutKind.walking.rawValue,
             PulsarOutdoorWorkoutKind.pilates.rawValue,
             PulsarOutdoorWorkoutKind.core.rawValue:
            return .balance
        case "gym",
             PulsarOutdoorWorkoutKind.strength.rawValue:
            return .power
        case PulsarOutdoorWorkoutKind.cycling.rawValue,
             PulsarOutdoorWorkoutKind.rowing.rawValue,
             PulsarOutdoorWorkoutKind.elliptical.rawValue:
            return .endurance
        case PulsarOutdoorWorkoutKind.hiit.rawValue,
             PulsarOutdoorWorkoutKind.boxing.rawValue,
             PulsarOutdoorWorkoutKind.stairClimber.rawValue:
            return .fire
        case PulsarOutdoorWorkoutKind.yoga.rawValue,
             PulsarOutdoorWorkoutKind.stretching.rawValue:
            return .restore
        case PulsarOutdoorWorkoutKind.swimming.rawValue:
            return .water
        case PulsarOutdoorWorkoutKind.dance.rawValue:
            return .rhythm
        case PulsarOutdoorWorkoutKind.mobility.rawValue,
             PulsarOutdoorWorkoutKind.cooldown.rawValue:
            return .focus
        default:
            return .focus
        }
    }
}
