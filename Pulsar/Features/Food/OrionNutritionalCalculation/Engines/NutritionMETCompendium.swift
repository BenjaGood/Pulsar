//
//  NutritionMETCompendium.swift
//  Pulsar
//

import Foundation

struct NutritionMETValue: Equatable, Hashable {
    var compendiumCode: String
    var met: Double
}

struct NutritionMETCompendiumEntry: Equatable {
    var workoutType: NutritionWorkoutType
    var light: NutritionMETValue
    var moderate: NutritionMETValue
    var vigorous: NutritionMETValue
}

enum NutritionMETCompendium {
    static let version = "2024-adult-compendium-v1"

    static let entries: [NutritionMETCompendiumEntry] = [
        NutritionMETCompendiumEntry(
            workoutType: .gymStrength,
            light: .init(compendiumCode: "02050", met: 3.5),
            moderate: .init(compendiumCode: "02050", met: 5.0),
            vigorous: .init(compendiumCode: "02050", met: 6.0)
        ),
        NutritionMETCompendiumEntry(
            workoutType: .cycling,
            light: .init(compendiumCode: "01010", met: 4.3),
            moderate: .init(compendiumCode: "01030", met: 7.0),
            vigorous: .init(compendiumCode: "01060", met: 9.0)
        ),
        NutritionMETCompendiumEntry(
            workoutType: .running,
            light: .init(compendiumCode: "12020", met: 6.0),
            moderate: .init(compendiumCode: "12030", met: 9.8),
            vigorous: .init(compendiumCode: "12050", met: 11.5)
        ),
        NutritionMETCompendiumEntry(
            workoutType: .walking,
            light: .init(compendiumCode: "17150", met: 3.0),
            moderate: .init(compendiumCode: "17170", met: 3.8),
            vigorous: .init(compendiumCode: "17200", met: 4.8)
        ),
        NutritionMETCompendiumEntry(
            workoutType: .hiking,
            light: .init(compendiumCode: "17080", met: 4.5),
            moderate: .init(compendiumCode: "17080", met: 6.0),
            vigorous: .init(compendiumCode: "17080", met: 7.8)
        ),
        NutritionMETCompendiumEntry(
            workoutType: .swimming,
            light: .init(compendiumCode: "18220", met: 5.0),
            moderate: .init(compendiumCode: "18240", met: 7.0),
            vigorous: .init(compendiumCode: "18260", met: 9.5)
        ),
        NutritionMETCompendiumEntry(
            workoutType: .rowing,
            light: .init(compendiumCode: "19120", met: 4.0),
            moderate: .init(compendiumCode: "19130", met: 7.0),
            vigorous: .init(compendiumCode: "19150", met: 10.0)
        ),
        NutritionMETCompendiumEntry(
            workoutType: .hiitCircuit,
            light: .init(compendiumCode: "02050", met: 5.0),
            moderate: .init(compendiumCode: "02050", met: 7.0),
            vigorous: .init(compendiumCode: "02050", met: 9.0)
        ),
        NutritionMETCompendiumEntry(
            workoutType: .teamSport,
            light: .init(compendiumCode: "15150", met: 4.0),
            moderate: .init(compendiumCode: "15150", met: 6.5),
            vigorous: .init(compendiumCode: "15150", met: 8.5)
        ),
        NutritionMETCompendiumEntry(
            workoutType: .yogaMobility,
            light: .init(compendiumCode: "02100", met: 2.5),
            moderate: .init(compendiumCode: "02100", met: 3.0),
            vigorous: .init(compendiumCode: "02100", met: 4.0)
        ),
        NutritionMETCompendiumEntry(
            workoutType: .mixedOther,
            light: .init(compendiumCode: "02050", met: 3.5),
            moderate: .init(compendiumCode: "02050", met: 5.5),
            vigorous: .init(compendiumCode: "02050", met: 7.5)
        )
    ]

    static func metValue(
        for workoutType: NutritionWorkoutType,
        intensity: NutritionWorkoutIntensity
    ) -> NutritionMETValue {
        guard let entry = entries.first(where: { $0.workoutType == workoutType }) else {
            return NutritionMETValue(compendiumCode: "02050", met: 5.0)
        }
        switch intensity {
        case .light: return entry.light
        case .moderate: return entry.moderate
        case .vigorous: return entry.vigorous
        }
    }

    static func netWorkoutKilocalories(
        met: Double,
        bodyWeightKilograms: Double,
        minutes: Double
    ) -> Double {
        max(met - 1, 0) * 3.5 * bodyWeightKilograms / 200 * minutes
    }
}
