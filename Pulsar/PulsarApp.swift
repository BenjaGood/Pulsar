//
//  PulsarApp.swift
//  Pulsar
//
//  Created by Benjamín Gutierrez Mendoza on 03/05/26.
//

import SwiftUI
import UIKit

@main
struct PulsarApp: App {
    @UIApplicationDelegateAdaptor(PulsarAppDelegate.self) private var appDelegate

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    init() {
        guard !Self.isRunningUnitTests else { return }
        PulsarPerformanceSignposts.beginLaunchToHomeUseful()
        AppLifecycleStore().registerFirstLaunchIfNeeded()
        PulsarBackgroundRefreshCoordinator.register()
        PulsarBackgroundRefreshCoordinator.schedule(reason: "appLaunch")
        PulsarWorkoutMirroringCoordinator.shared.initializeAtLaunch()
        GymMirroredSessionBridge.shared.initializeAtLaunch()
    }

    var body: some Scene {
        WindowGroup {
            if Self.isRunningUnitTests {
                Color.clear
            } else {
                ContentView()
            }
        }
    }
}
