//
//  PulsarApp.swift
//  Pulsar
//
//  Created by Benjamín Gutierrez Mendoza on 03/05/26.
//

import SwiftUI

@main
struct PulsarApp: App {
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
