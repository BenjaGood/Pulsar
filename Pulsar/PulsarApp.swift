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

    init() {
        AppLifecycleStore().registerFirstLaunchIfNeeded()
        PulsarBackgroundRefreshCoordinator.register()
        PulsarBackgroundRefreshCoordinator.schedule(reason: "appLaunch")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
