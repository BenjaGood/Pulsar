//
//  PulsarGymCrossDeviceStartFeature.swift
//  Pulsar
//

import Foundation

enum PulsarGymCrossDeviceStartFeature {
    private static let defaultsKey = "pulsar.feature.gymCrossDeviceStart"
    static let isEnabledByDefault = true

    static var isEnabled: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PulsarGymCrossDeviceStart") {
            return true
        }
        if ProcessInfo.processInfo.arguments.contains("-PulsarGymCrossDeviceStartOff") {
            return false
        }
        #endif
        return UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? isEnabledByDefault
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: defaultsKey)
    }
}
