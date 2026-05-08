//
//  PulsarRunQuickStartIntent.swift
//  Pulsar
//

import AppIntents

struct StartPulsarRunIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Pulsar Run"
    static var description = IntentDescription("Opens Pulsar directly into the running experience.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // The app opens into Pulsar; routing the exact screen is handled by the in-app run entry points.
        // TODO: Wire this intent to a dedicated deep-link router once Pulsar adds global URL/app-intent navigation.
        .result()
    }
}

struct PulsarRunShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartPulsarRunIntent(),
            phrases: [
                "Start a run in \(.applicationName)",
                "Begin running with \(.applicationName)"
            ],
            shortTitle: "Start Run",
            systemImageName: "figure.run"
        )
    }
}
