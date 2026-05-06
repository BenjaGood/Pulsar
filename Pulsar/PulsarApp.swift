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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
