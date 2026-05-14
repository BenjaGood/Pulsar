//
//  GymSettingsStore.swift
//  Pulsar
//

import Combine
import Foundation

enum GymWeightUnitPreference: String, CaseIterable, Identifiable, Codable, Hashable {
    case followApp
    case kilograms
    case pounds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followApp: "Follow App Units"
        case .kilograms: "Kilograms (kg)"
        case .pounds: "Pounds (lb)"
        }
    }

    var shortTitle: String {
        switch self {
        case .followApp: "Follow App"
        case .kilograms: "kg"
        case .pounds: "lb"
        }
    }

    func resolvedUnit(appUnits: UnitPreference) -> PulsarWeightUnit {
        switch self {
        case .followApp:
            appUnits == .imperial ? .pounds : .kilograms
        case .kilograms:
            .kilograms
        case .pounds:
            .pounds
        }
    }
}

@MainActor
final class GymSettingsStore: ObservableObject {
    @Published private(set) var weightUnitPreference: GymWeightUnitPreference

    private let defaults: UserDefaults
    private let weightUnitPreferenceKey = "pulsar.gym.weightUnitPreference.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let rawValue = defaults.string(forKey: weightUnitPreferenceKey),
           let preference = GymWeightUnitPreference(rawValue: rawValue) {
            weightUnitPreference = preference
        } else {
            weightUnitPreference = .followApp
        }
    }

    func setWeightUnitPreference(_ preference: GymWeightUnitPreference) {
        guard preference != weightUnitPreference else { return }
        weightUnitPreference = preference
        defaults.set(preference.rawValue, forKey: weightUnitPreferenceKey)
    }

    func resolvedWeightUnit(appUnits: UnitPreference) -> PulsarWeightUnit {
        weightUnitPreference.resolvedUnit(appUnits: appUnits)
    }
}
