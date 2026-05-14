//
//  MeasurementSourceManager.swift
//  Pulsar
//

import Combine
import Foundation

enum MeasurementDeviceType: String, Codable, CaseIterable, Identifiable {
    case appleWatch
    case amazfitHelioRing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleWatch:
            return "Apple Watch"
        case .amazfitHelioRing:
            return "Amazfit Helio Ring"
        }
    }

    var assetName: String {
        switch self {
        case .appleWatch:
            return "AppleWatchDevice"
        case .amazfitHelioRing:
            return "AmazfitHelioRingDevice"
        }
    }
}

enum MeasurementDeviceConnectionStatus: String, Codable, Hashable {
    case connected
    case available
    case setupRequired
    case disconnected

    var label: String {
        switch self {
        case .connected:
            return "Connected"
        case .available:
            return "Available"
        case .setupRequired:
            return "Setup required"
        case .disconnected:
            return "Disconnected"
        }
    }
}

enum MeasurementHealthMetricType: String, Codable, CaseIterable, Identifiable, Hashable {
    case heartRate
    case hrv
    case sleep
    case activity
    case workouts
    case recovery
    case restingHeartRate
    case strain
    case stress

    var id: String { rawValue }

    var label: String {
        switch self {
        case .heartRate:
            return "Heart rate"
        case .hrv:
            return "HRV"
        case .sleep:
            return "Sleep"
        case .activity:
            return "Activity"
        case .workouts:
            return "Workouts"
        case .recovery:
            return "Recovery"
        case .restingHeartRate:
            return "Resting heart rate"
        case .strain:
            return "Strain"
        case .stress:
            return "Stress"
        }
    }
}

struct MeasurementDevice: Identifiable, Codable, Equatable {
    var id: MeasurementDeviceType { type }
    var name: String
    var type: MeasurementDeviceType
    var connectionStatus: MeasurementDeviceConnectionStatus
    var batteryPercentage: Int?
    var isActiveSource: Bool
    var supportedMetrics: [MeasurementHealthMetricType]
    var lastSyncAt: Date?

    var batteryText: String {
        if let batteryPercentage {
            return "Battery \(batteryPercentage)%"
        }
        return "Battery unavailable"
    }

    var canBecomeActiveSource: Bool {
        connectionStatus == .connected || connectionStatus == .available
    }

    var primaryActionTitle: String {
        if isActiveSource { return "Current source" }
        if connectionStatus == .setupRequired { return "Set up device" }
        return "Use as source"
    }
}

@MainActor
final class MeasurementSourceManager: ObservableObject {
    @Published private(set) var activeDeviceType: MeasurementDeviceType
    @Published private(set) var appleWatchBatterySnapshot: AppleWatchBatterySnapshot?

    private let defaults: UserDefaults
    private let syncStore: PulsarWatchConnectivitySyncStore?
    private let activeDeviceKey = "pulsar.measurementSource.activeDevice.v1"
    private var cancellables: Set<AnyCancellable> = []

    init(
        defaults: UserDefaults = .standard,
        syncStore: PulsarWatchConnectivitySyncStore? = nil
    ) {
        let resolvedSyncStore = syncStore ?? PulsarWatchConnectivitySyncStore.shared
        self.defaults = defaults
        self.syncStore = resolvedSyncStore
        self.appleWatchBatterySnapshot = resolvedSyncStore.latestAppleWatchBattery
        if let stored = defaults.string(forKey: activeDeviceKey),
           let deviceType = MeasurementDeviceType(rawValue: stored) {
            if deviceType == .amazfitHelioRing {
                self.activeDeviceType = .appleWatch
                defaults.set(MeasurementDeviceType.appleWatch.rawValue, forKey: activeDeviceKey)
            } else {
                self.activeDeviceType = deviceType
            }
        } else {
            self.activeDeviceType = .appleWatch
        }

        resolvedSyncStore.$latestAppleWatchBattery
            .sink { [weak self] snapshot in
                self?.appleWatchBatterySnapshot = snapshot
            }
            .store(in: &cancellables)
    }

    var activeDevice: MeasurementDevice {
        device(for: activeDeviceType)
    }

    var availableDevices: [MeasurementDevice] {
        MeasurementDeviceType.allCases.map(device(for:))
    }

    func selectActiveDevice(_ device: MeasurementDevice) {
        selectActiveDevice(device.type)
    }

    func selectActiveDevice(_ type: MeasurementDeviceType) {
        guard activeDeviceType != type else { return }
        guard device(for: type).canBecomeActiveSource else { return }
        activeDeviceType = type
        defaults.set(type.rawValue, forKey: activeDeviceKey)
    }

    func refreshDeviceStatus() {
        // Reserved for real device integrations. Battery and third-party status are not faked.
    }

    func device(for type: MeasurementDeviceType) -> MeasurementDevice {
        switch type {
        case .appleWatch:
            return MeasurementDevice(
                name: type.displayName,
                type: type,
                connectionStatus: .connected,
                batteryPercentage: appleWatchBatterySnapshot?.batteryPercentage,
                isActiveSource: activeDeviceType == type,
                supportedMetrics: [.heartRate, .hrv, .sleep, .activity, .workouts, .strain, .stress],
                lastSyncAt: appleWatchBatterySnapshot?.timestamp
            )
        case .amazfitHelioRing:
            return MeasurementDevice(
                name: type.displayName,
                type: type,
                connectionStatus: .setupRequired,
                batteryPercentage: nil,
                isActiveSource: activeDeviceType == type,
                supportedMetrics: [.sleep, .recovery, .hrv, .restingHeartRate],
                lastSyncAt: nil
            )
        }
    }
}
