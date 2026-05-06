//
//  HealthKitSettingsStore.swift
//  Pulsar
//

import Combine
import Foundation
import HealthKit
import SwiftUI

enum HealthPermissionState: Equatable {
    case notAvailable
    case notIntroduced
    case connected
    case needsPermission

    var title: String {
        switch self {
        case .notAvailable: "Not Available"
        case .notIntroduced: "Not Set Up"
        case .connected: "Connected"
        case .needsPermission: "Needs Permission"
        }
    }

    var tint: Color {
        switch self {
        case .connected: .green
        case .needsPermission: .orange
        case .notIntroduced: .blue
        case .notAvailable: .secondary
        }
    }
}

struct HealthDataSourceItem: Identifiable, Hashable {
    enum Status: String {
        case available = "Available"
        case permissionNeeded = "Permission Needed"
        case noDataYet = "No Data Yet"
        case unsupported = "Unsupported"

        var tint: Color {
            switch self {
            case .available: .green
            case .permissionNeeded: .orange
            case .noDataYet: .blue
            case .unsupported: .secondary
            }
        }
    }

    var id: String { title }
    var title: String
    var description: String
    var symbol: String
    var status: Status
}

@MainActor
final class HealthKitSettingsStore: ObservableObject {
    @Published private(set) var permissionState: HealthPermissionState
    @Published private(set) var dataSources: [HealthDataSourceItem] = []
    @Published private(set) var lastErrorMessage: String?

    private let gateway: HealthKitGateway
    private var lifecycleStore: AppLifecycleStore

    init(gateway: HealthKitGateway = HealthKitGateway(), lifecycleStore: AppLifecycleStore? = nil) {
        self.gateway = gateway
        self.lifecycleStore = lifecycleStore ?? AppLifecycleStore()
        self.permissionState = self.lifecycleStore.hasSeenHealthKitOnboarding ? .needsPermission : .notIntroduced
        refreshStatus()
    }

    func refreshStatus() {
        Task {
            if await !gateway.isAvailable {
                permissionState = .notAvailable
                dataSources = Self.items(status: .unsupported)
            } else if lifecycleStore.hasSeenHealthKitOnboarding {
                permissionState = .connected
                dataSources = Self.items(status: .noDataYet)
            } else {
                permissionState = .notIntroduced
                dataSources = Self.items(status: .permissionNeeded)
            }
        }
    }

    func requestAuthorization() async {
        do {
            try await gateway.requestAuthorization()
            lifecycleStore.hasSeenHealthKitOnboarding = true
            permissionState = .connected
            dataSources = Self.items(status: .noDataYet)
            lastErrorMessage = nil
        } catch HealthKitGatewayError.healthDataUnavailable {
            permissionState = .notAvailable
            dataSources = Self.items(status: .unsupported)
            lastErrorMessage = "Health data is not available on this device."
        } catch {
            lifecycleStore.hasSeenHealthKitOnboarding = true
            permissionState = .needsPermission
            dataSources = Self.items(status: .permissionNeeded)
            lastErrorMessage = "Pulsar could not access Apple Health. You can review permissions in the Health app."
        }
    }

    func resetPermissionIntroduction() {
        lifecycleStore.hasSeenHealthKitOnboarding = false
        refreshStatus()
    }

    private static func items(status: HealthDataSourceItem.Status) -> [HealthDataSourceItem] {
        [
            HealthDataSourceItem(title: "Sleep Analysis", description: "Sleep stages and time asleep from Apple Health.", symbol: "bed.double.fill", status: status),
            HealthDataSourceItem(title: "Heart Rate", description: "Workout and background heart-rate samples.", symbol: "heart.fill", status: status),
            HealthDataSourceItem(title: "Resting Heart Rate", description: "Daily resting heart-rate context.", symbol: "heart.text.square.fill", status: status),
            HealthDataSourceItem(title: "HRV SDNN", description: "Heart-rate variability for recovery trends.", symbol: "waveform.path.ecg", status: status),
            HealthDataSourceItem(title: "Respiratory Rate", description: "Breathing-rate stability from compatible sources.", symbol: "lungs.fill", status: status),
            HealthDataSourceItem(title: "Active Energy Burned", description: "Movement load and daily activity context.", symbol: "flame.fill", status: status),
            HealthDataSourceItem(title: "Workouts", description: "Workout sessions, duration, and source metadata.", symbol: "figure.run", status: status),
            HealthDataSourceItem(title: "Step Count", description: "Daily step totals from iPhone, Apple Watch, or apps.", symbol: "shoeprints.fill", status: status),
            HealthDataSourceItem(title: "Body Mass", description: "Weight values when shared through Apple Health.", symbol: "scalemass.fill", status: status),
            HealthDataSourceItem(title: "Height", description: "Height values when shared through Apple Health.", symbol: "ruler.fill", status: status)
        ]
    }
}
