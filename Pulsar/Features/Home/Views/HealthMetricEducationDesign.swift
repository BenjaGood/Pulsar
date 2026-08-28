//
//  HealthMetricEducationDesign.swift
//  Pulsar
//

import SwiftUI

enum HealthMetricEducationDesign {
    static let primaryText = Color(red: 0.05, green: 0.07, blue: 0.11)
    static let secondaryText = Color(red: 0.29, green: 0.33, blue: 0.40)
    static let chipBackground = Color(red: 0.96, green: 0.965, blue: 0.975)
    static let dataTileBackground = Color(red: 0.975, green: 0.978, blue: 0.985)

    static func accent(for kind: HealthMetricKind) -> Color {
        switch kind {
        case .respiratoryRate:
            Color(red: 0.19, green: 0.61, blue: 0.40)
        case .restingHeartRate:
            Color(red: 0.86, green: 0.25, blue: 0.34)
        case .hrv:
            Color(red: 0.36, green: 0.42, blue: 0.84)
        case .oxygenSaturation:
            Color(red: 0.12, green: 0.55, blue: 0.73)
        case .wristTemperature:
            Color(red: 0.87, green: 0.46, blue: 0.18)
        case .sleep:
            Color(red: 0.36, green: 0.32, blue: 0.74)
        }
    }
}
