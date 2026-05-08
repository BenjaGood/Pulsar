//
//  Pulsar_Watch_AppApp.swift
//  Pulsar Watch App Watch App
//
//  Created by Benjamín Gutierrez Mendoza on 03/05/26.
//

import SwiftUI
import WatchKit

@main
struct Pulsar_Watch_App_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchRunAppDelegate.self) private var appDelegate
    @StateObject private var runManager = WatchRunSessionManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(runManager)
        }
    }
}
