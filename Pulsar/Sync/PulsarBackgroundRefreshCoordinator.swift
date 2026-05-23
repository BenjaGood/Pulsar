//
//  PulsarBackgroundRefreshCoordinator.swift
//  Pulsar
//

import Foundation

#if os(iOS) && canImport(BackgroundTasks)
import BackgroundTasks

enum PulsarBackgroundRefreshCoordinator {
    static let taskIdentifier = "aetherial.Pulsar.health-refresh"
    private static let earliestRefreshDelay: TimeInterval = 15 * 60

    static func register() {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            handle(task)
        }
        PulsarSyncDebugLogger.log("BGAppRefresh registration \(registered ? "succeeded" : "failed") identifier=\(taskIdentifier)")
    }

    static func schedule(reason: String = "scheduled") {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(earliestRefreshDelay)
        do {
            try BGTaskScheduler.shared.submit(request)
            PulsarSyncDebugLogger.log("BGAppRefresh scheduled reason=\(reason) earliest=\(request.earliestBeginDate?.description ?? "none")")
        } catch {
            PulsarSyncDebugLogger.log("BGAppRefresh schedule failed reason=\(reason) error=\(error.localizedDescription)")
        }
    }

    private static func handle(_ task: BGTask) {
        schedule(reason: "reschedule")
        let refreshTask = Task {
            let success = await PulsarBackgroundHealthRefreshRunner().run()
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = {
            refreshTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}

@MainActor
private final class PulsarBackgroundHealthRefreshRunner {
    func run() async -> Bool {
        PulsarSyncDebugLogger.log("Sync requested reason=backgroundRefresh")
        let configuration = OuraIntegrationConfiguration.load()
        let tokenStore = OuraKeychainTokenStore()
        let authService = OuraAuthService(configuration: configuration, tokenStorage: tokenStore)
        guard authService.connectionStore.storedToken != nil else {
            PulsarOuraLogger.log("Background Oura sync skipped because Oura is not connected")
            return true
        }

        let apiClient: OuraAPIClientProtocol = configuration.mockMode
            ? MockOuraAPIClient()
            : URLSessionOuraAPIClient(authService: authService)
        let syncService = OuraSyncService(
            apiClient: apiClient,
            authService: authService,
            connectionStore: authService.connectionStore
        )

        do {
            let mapped = try await syncService.sync(date: Date(), calendar: .current, reason: "backgroundRefresh")
            if let payload = mapped.payload {
                _ = PulsarWatchConnectivitySyncStore.shared.storeLocalPayload(
                    payload,
                    broadcast: false,
                    reason: "OuraBackgroundRefresh"
                )
            }
            return true
        } catch {
            PulsarOuraLogger.log("Background Oura sync failed: \(error.localizedDescription)")
            return false
        }
    }
}
#else
enum PulsarBackgroundRefreshCoordinator {
    static let taskIdentifier = "aetherial.Pulsar.health-refresh"
    static func register() {}
    static func schedule(reason _: String = "scheduled") {}
}
#endif
