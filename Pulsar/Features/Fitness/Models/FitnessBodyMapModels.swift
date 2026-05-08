//
//  FitnessBodyMapModels.swift
//  Pulsar
//

import Foundation
import SwiftUI

enum BodyViewSide: String, CaseIterable, Identifiable, Hashable {
    case front
    case back

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front: "Front"
        case .back: "Back"
        }
    }

    var scanLabel: String {
        switch self {
        case .front: "Front scan"
        case .back: "Back scan"
        }
    }
}

enum BodyMapAvatarType: String, CaseIterable, Identifiable, Hashable {
    case male
    case female

    var id: String { rawValue }

    init(profile: UserProfile?) {
        self.init(biologicalSex: profile?.resolvedBiologicalSex ?? .notSet)
    }

    init(biologicalSex: BiologicalSex) {
        switch biologicalSex {
        case .female:
            self = .female
        case .male, .notSet, .other:
            self = .male
        }
    }

    func imageName(for side: BodyViewSide) -> String {
        switch (self, side) {
        case (.male, .front): "BodyMapMaleFront"
        case (.male, .back): "BodyMapMaleBack"
        case (.female, .front): "BodyMapFemaleFront"
        case (.female, .back): "BodyMapFemaleBack"
        }
    }

    func aspectRatio(for side: BodyViewSide) -> CGFloat {
        switch (self, side) {
        case (.male, .front): CGFloat(981.0 / 2255.0)
        case (.male, .back): CGFloat(954.0 / 2255.0)
        case (.female, .front): CGFloat(869.0 / 2236.0)
        case (.female, .back): CGFloat(869.0 / 2242.0)
        }
    }
}

enum BodyZone: String, CaseIterable, Hashable, Identifiable {
    case heart
    case chestLeft
    case chestRight
    case shouldersLeft
    case shouldersRight
    case bicepsLeft
    case bicepsRight
    case tricepsLeft
    case tricepsRight
    case forearmsLeft
    case forearmsRight
    case abs
    case obliquesLeft
    case obliquesRight
    case upperBack
    case latsLeft
    case latsRight
    case lowerBack
    case glutesLeft
    case glutesRight
    case quadsLeft
    case quadsRight
    case hamstringsLeft
    case hamstringsRight
    case adductorsLeft
    case adductorsRight
    case calvesLeft
    case calvesRight
    case tibialisLeft
    case tibialisRight
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

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .heart: "Cardio"
        case .chestLeft: "Left Chest"
        case .chestRight: "Right Chest"
        case .shouldersLeft: "Left Shoulder"
        case .shouldersRight: "Right Shoulder"
        case .bicepsLeft: "Left Biceps"
        case .bicepsRight: "Right Biceps"
        case .tricepsLeft: "Left Triceps"
        case .tricepsRight: "Right Triceps"
        case .forearmsLeft: "Left Forearm"
        case .forearmsRight: "Right Forearm"
        case .abs: "Abs"
        case .obliquesLeft: "Left Obliques"
        case .obliquesRight: "Right Obliques"
        case .upperBack: "Upper Back"
        case .latsLeft: "Left Lat"
        case .latsRight: "Right Lat"
        case .lowerBack: "Lower Back"
        case .glutesLeft: "Left Glute"
        case .glutesRight: "Right Glute"
        case .quadsLeft: "Left Quad"
        case .quadsRight: "Right Quad"
        case .hamstringsLeft: "Left Hamstring"
        case .hamstringsRight: "Right Hamstring"
        case .adductorsLeft: "Left Adductors"
        case .adductorsRight: "Right Adductors"
        case .calvesLeft: "Left Calf"
        case .calvesRight: "Right Calf"
        case .tibialisLeft: "Left Tibialis"
        case .tibialisRight: "Right Tibialis"
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
        case .chestLeft, .chestRight, .shouldersLeft, .shouldersRight, .bicepsLeft, .bicepsRight, .tricepsLeft, .tricepsRight, .forearmsLeft, .forearmsRight, .upperBack, .latsLeft, .latsRight, .lowerBack, .chest, .back, .shoulders, .biceps, .triceps:
            Color(red: 0.55, green: 0.62, blue: 1.00)
        case .abs, .obliquesLeft, .obliquesRight, .core:
            Color(red: 1.00, green: 0.70, blue: 0.28)
        case .glutesLeft, .glutesRight, .quadsLeft, .quadsRight, .hamstringsLeft, .hamstringsRight, .adductorsLeft, .adductorsRight, .calvesLeft, .calvesRight, .tibialisLeft, .tibialisRight, .glutes, .quads, .hamstrings, .calves:
            Color(red: 0.24, green: 0.86, blue: 0.72)
        }
    }

    nonisolated var expandedZones: [BodyZone] {
        switch self {
        case .chest:
            [.chestLeft, .chestRight]
        case .back:
            [.upperBack, .latsLeft, .latsRight, .lowerBack]
        case .shoulders:
            [.shouldersLeft, .shouldersRight]
        case .biceps:
            [.bicepsLeft, .bicepsRight]
        case .triceps:
            [.tricepsLeft, .tricepsRight]
        case .core:
            [.abs, .obliquesLeft, .obliquesRight]
        case .glutes:
            [.glutesLeft, .glutesRight]
        case .quads:
            [.quadsLeft, .quadsRight]
        case .hamstrings:
            [.hamstringsLeft, .hamstringsRight]
        case .calves:
            [.calvesLeft, .calvesRight]
        default:
            [self]
        }
    }

    static func zones(forAlias alias: String) -> [BodyZone] {
        let normalized = alias
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return muscleAliases[normalized] ?? []
    }

    private static let muscleAliases: [String: [BodyZone]] = [
        "pecho": BodyZone.chest.expandedZones,
        "chest": BodyZone.chest.expandedZones,
        "pectorals": BodyZone.chest.expandedZones,
        "pecs": BodyZone.chest.expandedZones,
        "tricep": BodyZone.triceps.expandedZones,
        "triceps": BodyZone.triceps.expandedZones,
        "femoral": BodyZone.hamstrings.expandedZones,
        "hamstring": BodyZone.hamstrings.expandedZones,
        "hamstrings": BodyZone.hamstrings.expandedZones,
        "cuadriceps": BodyZone.quads.expandedZones,
        "quadriceps": BodyZone.quads.expandedZones,
        "quad": BodyZone.quads.expandedZones,
        "quads": BodyZone.quads.expandedZones,
        "espalda": BodyZone.back.expandedZones,
        "back": BodyZone.back.expandedZones,
        "lats": BodyZone.back.expandedZones,
        "lat": [.latsLeft, .latsRight],
        "gluteo": BodyZone.glutes.expandedZones,
        "glutes": BodyZone.glutes.expandedZones,
        "glute": BodyZone.glutes.expandedZones,
        "pantorrilla": BodyZone.calves.expandedZones,
        "calves": BodyZone.calves.expandedZones,
        "calf": BodyZone.calves.expandedZones,
        "abs": BodyZone.core.expandedZones,
        "abdomen": BodyZone.core.expandedZones,
        "core": BodyZone.core.expandedZones,
        "hombro": BodyZone.shoulders.expandedZones,
        "shoulder": BodyZone.shoulders.expandedZones,
        "shoulders": BodyZone.shoulders.expandedZones,
        "delts": BodyZone.shoulders.expandedZones,
        "deltoids": BodyZone.shoulders.expandedZones,
        "bicep": BodyZone.biceps.expandedZones,
        "biceps": BodyZone.biceps.expandedZones,
        "forearm": [.forearmsLeft, .forearmsRight],
        "forearms": [.forearmsLeft, .forearmsRight],
        "obliques": [.obliquesLeft, .obliquesRight],
        "oblique": [.obliquesLeft, .obliquesRight],
        "lower back": [.lowerBack],
        "adductors": [.adductorsLeft, .adductorsRight],
        "adductor": [.adductorsLeft, .adductorsRight]
    ]
}

struct TrainedBodyZone: Identifiable, Hashable {
    var zone: BodyZone
    var intensity: Double
    var sessions: Int
    var sourceWorkoutTypes: [String]
    var score: Double = 0
    var exercises: [String] = []

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

    var isTrainingActive: Bool {
        !trainedZones.isEmpty
    }

    var strengthZones: [TrainedBodyZone] {
        trainedZones.filter { $0.zone != .heart }
    }

    var topStrengthZones: [TrainedBodyZone] {
        strengthZones.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.zone.displayName < rhs.zone.displayName
            }
            return lhs.score > rhs.score
        }
    }

    func trainedZone(for zone: BodyZone) -> TrainedBodyZone? {
        trainedZones.first { $0.zone == zone }
    }

    func isZoneActive(_ zone: BodyZone) -> Bool {
        trainedZone(matching: zone) != nil
    }

    func trainedZone(matching zone: BodyZone) -> TrainedBodyZone? {
        trainedZones.first { trainedZone in
            trainedZone.zone == zone
                || trainedZone.zone.expandedZones.contains(zone)
                || zone.expandedZones.contains(trainedZone.zone)
        }
    }
}

struct BodyZoneOverlay: Identifiable {
    let id: String
    let zone: BodyZone
    let displayName: String
    let viewSide: BodyViewSide
    let avatarType: BodyMapAvatarType
    let normalizedFrame: CGRect
    let normalizedPath: [CGPoint]

    init(
        id: String? = nil,
        zone: BodyZone,
        displayName: String? = nil,
        viewSide: BodyViewSide,
        avatarType: BodyMapAvatarType,
        normalizedFrame: CGRect,
        normalizedPath: [CGPoint] = []
    ) {
        self.id = id ?? "\(avatarType.rawValue)-\(viewSide.rawValue)-\(zone.rawValue)"
        self.zone = zone
        self.displayName = displayName ?? zone.displayName
        self.viewSide = viewSide
        self.avatarType = avatarType
        self.normalizedFrame = normalizedFrame
        self.normalizedPath = normalizedPath
    }
}

enum BodyMapOverlayCatalog {
    static func overlays(for avatarType: BodyMapAvatarType, side: BodyViewSide) -> [BodyZoneOverlay] {
        overlays(for: side).map { template in
            BodyZoneOverlay(
                zone: template.zone,
                viewSide: side,
                avatarType: avatarType,
                normalizedFrame: adjusted(template.frame, for: avatarType, side: side)
            )
        }
    }

    private static func overlays(for side: BodyViewSide) -> [(zone: BodyZone, frame: CGRect)] {
        switch side {
        case .front:
            [
                (.heart, frame(centerX: 0.535, centerY: 0.262, width: 0.095, height: 0.060)),
                (.chestLeft, frame(centerX: 0.425, centerY: 0.255, width: 0.210, height: 0.105)),
                (.chestRight, frame(centerX: 0.575, centerY: 0.255, width: 0.210, height: 0.105)),
                (.shouldersLeft, frame(centerX: 0.260, centerY: 0.225, width: 0.155, height: 0.085)),
                (.shouldersRight, frame(centerX: 0.740, centerY: 0.225, width: 0.155, height: 0.085)),
                (.bicepsLeft, frame(centerX: 0.192, centerY: 0.370, width: 0.110, height: 0.185)),
                (.bicepsRight, frame(centerX: 0.808, centerY: 0.370, width: 0.110, height: 0.185)),
                (.forearmsLeft, frame(centerX: 0.118, centerY: 0.485, width: 0.120, height: 0.175)),
                (.forearmsRight, frame(centerX: 0.882, centerY: 0.485, width: 0.120, height: 0.175)),
                (.abs, frame(centerX: 0.500, centerY: 0.405, width: 0.200, height: 0.205)),
                (.obliquesLeft, frame(centerX: 0.390, centerY: 0.405, width: 0.105, height: 0.200)),
                (.obliquesRight, frame(centerX: 0.610, centerY: 0.405, width: 0.105, height: 0.200)),
                (.quadsLeft, frame(centerX: 0.405, centerY: 0.650, width: 0.150, height: 0.215)),
                (.quadsRight, frame(centerX: 0.595, centerY: 0.650, width: 0.150, height: 0.215)),
                (.adductorsLeft, frame(centerX: 0.475, centerY: 0.650, width: 0.075, height: 0.205)),
                (.adductorsRight, frame(centerX: 0.525, centerY: 0.650, width: 0.075, height: 0.205)),
                (.tibialisLeft, frame(centerX: 0.410, centerY: 0.820, width: 0.095, height: 0.175)),
                (.tibialisRight, frame(centerX: 0.590, centerY: 0.820, width: 0.095, height: 0.175)),
                (.calvesLeft, frame(centerX: 0.355, centerY: 0.830, width: 0.090, height: 0.170)),
                (.calvesRight, frame(centerX: 0.645, centerY: 0.830, width: 0.090, height: 0.170))
            ]
        case .back:
            [
                (.upperBack, frame(centerX: 0.500, centerY: 0.270, width: 0.315, height: 0.170)),
                (.latsLeft, frame(centerX: 0.395, centerY: 0.390, width: 0.170, height: 0.210)),
                (.latsRight, frame(centerX: 0.605, centerY: 0.390, width: 0.170, height: 0.210)),
                (.lowerBack, frame(centerX: 0.500, centerY: 0.470, width: 0.235, height: 0.145)),
                (.shouldersLeft, frame(centerX: 0.252, centerY: 0.245, width: 0.165, height: 0.090)),
                (.shouldersRight, frame(centerX: 0.748, centerY: 0.245, width: 0.165, height: 0.090)),
                (.tricepsLeft, frame(centerX: 0.190, centerY: 0.380, width: 0.105, height: 0.190)),
                (.tricepsRight, frame(centerX: 0.810, centerY: 0.380, width: 0.105, height: 0.190)),
                (.forearmsLeft, frame(centerX: 0.118, centerY: 0.500, width: 0.115, height: 0.180)),
                (.forearmsRight, frame(centerX: 0.882, centerY: 0.500, width: 0.115, height: 0.180)),
                (.glutesLeft, frame(centerX: 0.430, centerY: 0.560, width: 0.180, height: 0.135)),
                (.glutesRight, frame(centerX: 0.570, centerY: 0.560, width: 0.180, height: 0.135)),
                (.hamstringsLeft, frame(centerX: 0.410, centerY: 0.690, width: 0.145, height: 0.215)),
                (.hamstringsRight, frame(centerX: 0.590, centerY: 0.690, width: 0.145, height: 0.215)),
                (.calvesLeft, frame(centerX: 0.395, centerY: 0.850, width: 0.115, height: 0.180)),
                (.calvesRight, frame(centerX: 0.605, centerY: 0.850, width: 0.115, height: 0.180))
            ]
        }
    }

    private static func frame(centerX: CGFloat, centerY: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
    }

    private static func adjusted(_ frame: CGRect, for avatarType: BodyMapAvatarType, side: BodyViewSide) -> CGRect {
        guard avatarType == .female else { return frame }

        let yOffset: CGFloat = side == .front ? -0.008 : -0.004
        let widthScale: CGFloat = 0.94
        let heightScale: CGFloat = 0.985
        let newWidth = frame.width * widthScale
        let newHeight = frame.height * heightScale
        return CGRect(
            x: frame.midX - newWidth / 2,
            y: frame.midY - newHeight / 2 + yOffset,
            width: newWidth,
            height: newHeight
        )
    }
}

enum BodyMapAnalyzer {
    nonisolated static func analyze(activities: [WeeklyActivity]) -> BodyMapAnalysis {
        let cardioActivities = activities.filter(isCardioActivity)
        let cardioSessions = cardioActivities.count
        let cardioDuration = cardioActivities.reduce(0) { $0 + $1.duration }
        let strengthZones = strengthTrainedZones(from: activities)

        guard cardioSessions > 0 || !strengthZones.isEmpty else {
            return .empty
        }

        var trainedZones = strengthZones

        if cardioSessions > 0 {
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
                sourceWorkoutTypes: workoutTypes,
                score: Double(cardioSessions),
                exercises: workoutTypes
            )
            trainedZones.append(heartZone)
        }

        return BodyMapAnalysis(
            trainedZones: trainedZones,
            cardioSessions: cardioSessions,
            cardioDuration: cardioDuration
        )
    }

    nonisolated private static func strengthTrainedZones(from activities: [WeeklyActivity]) -> [TrainedBodyZone] {
        var loadByZone: [BodyZone: Double] = [:]
        var sessionsByZone: [BodyZone: Set<String>] = [:]
        var workoutTypesByZone: [BodyZone: Set<String>] = [:]
        var exercisesByZone: [BodyZone: Set<String>] = [:]

        for activity in activities {
            guard !activity.muscleLoadByBodyZone.isEmpty else { continue }
            for (zone, score) in activity.muscleLoadByBodyZone where score > 0 {
                loadByZone[zone, default: 0] += score
                sessionsByZone[zone, default: []].insert(activity.id)
                workoutTypesByZone[zone, default: []].insert(activity.displayName)
                for exercise in activity.muscleExercisesByBodyZone[zone] ?? [] {
                    exercisesByZone[zone, default: []].insert(exercise)
                }
            }
        }

        return loadByZone
            .filter { $0.value > 0 }
            .map { zone, score in
                TrainedBodyZone(
                    zone: zone,
                    intensity: WeeklyMuscleLoadCalculator.normalizedIntensity(for: score),
                    sessions: sessionsByZone[zone]?.count ?? 0,
                    sourceWorkoutTypes: Array(workoutTypesByZone[zone] ?? []).sorted(),
                    score: score,
                    exercises: Array(exercisesByZone[zone] ?? []).sorted()
                )
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.zone.displayName < rhs.zone.displayName
                }
                return lhs.score > rhs.score
            }
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
