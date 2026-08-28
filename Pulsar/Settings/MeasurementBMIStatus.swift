//
//  MeasurementBMIStatus.swift
//  Pulsar
//

import SwiftUI

enum MeasurementBMIStatus {
    case underweight
    case healthy
    case overweight
    case obese

    init(value: Double) {
        switch value {
        case ..<18.5:
            self = .underweight
        case ..<25:
            self = .healthy
        case ..<30:
            self = .overweight
        default:
            self = .obese
        }
    }

    var label: String {
        switch self {
        case .underweight: "Underweight"
        case .healthy: "Healthy"
        case .overweight: "Overweight"
        case .obese: "Obese"
        }
    }

    var tint: Color {
        SettingsMonochromeDesign.primary
    }
}
