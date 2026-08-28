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
        case .connected:
            SettingsMonochromeDesign.primary
        case .needsPermission, .notIntroduced:
            SettingsMonochromeDesign.secondary
        case .notAvailable:
            SettingsMonochromeDesign.tertiary
        }
    }

    var isConnected: Bool {
        self == .connected
    }

    var canRequestAuthorization: Bool {
        self != .notAvailable
    }
}

@MainActor
final class HealthKitSettingsStore: ObservableObject {
    @Published private(set) var permissionState: HealthPermissionState
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
            } else if lifecycleStore.hasSeenHealthKitOnboarding {
                permissionState = .connected
            } else {
                permissionState = .notIntroduced
            }
        }
    }

    func requestAuthorization() async {
        do {
            try await gateway.requestAuthorization()
            lifecycleStore.hasSeenHealthKitOnboarding = true
            permissionState = .connected
            lastErrorMessage = nil
        } catch HealthKitGatewayError.healthDataUnavailable {
            permissionState = .notAvailable
            lastErrorMessage = "Health data is not available on this device."
        } catch {
            lifecycleStore.hasSeenHealthKitOnboarding = true
            permissionState = .needsPermission
            lastErrorMessage = "Pulsar could not access Apple Health. You can review permissions in the Health app."
        }
    }

    func resetPermissionIntroduction() {
        lifecycleStore.hasSeenHealthKitOnboarding = false
        refreshStatus()
    }
}
