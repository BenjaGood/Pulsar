//
//  OuraDeviceSourceProvider.swift
//  Pulsar
//

import Foundation

final class OuraDeviceSourceProvider: HealthDataSource {
    let sourceID: HealthSourceID = .ouraRing
    let displayName = "Oura Ring"
    let supportedMetrics: Set<MeasurementHealthMetricType> = [
        .sleep,
        .recovery,
        .readiness,
        .hrv,
        .restingHeartRate,
        .heartRate,
        .respiratoryRate,
        .oxygenSaturation,
        .activity,
        .workouts,
        .stress,
        .temperature,
        .cycle
    ]

    private let configuration: OuraIntegrationConfiguration
    private let connectionStore: OuraConnectionStore
    private let syncService: OuraSyncServicing

    init(
        configuration: OuraIntegrationConfiguration = .load(),
        connectionStore: OuraConnectionStore,
        syncService: OuraSyncServicing
    ) {
        self.configuration = configuration
        self.connectionStore = connectionStore
        self.syncService = syncService
    }

    convenience init(configuration: OuraIntegrationConfiguration = .load()) {
        let tokenStore = OuraKeychainTokenStore()
        let authService = OuraAuthService(configuration: configuration, tokenStorage: tokenStore)
        let apiClient: OuraAPIClientProtocol = configuration.mockMode
            ? MockOuraAPIClient()
            : URLSessionOuraAPIClient(authService: authService)
        let syncService = OuraSyncService(
            apiClient: apiClient,
            authService: authService,
            connectionStore: authService.connectionStore
        )
        self.init(
            configuration: configuration,
            connectionStore: authService.connectionStore,
            syncService: syncService
        )
    }

    func snapshot() -> HealthSourceSnapshot {
        HealthSourceSnapshot(
            sourceID: sourceID,
            connectionState: connectionState,
            syncState: connectionStore.status == .syncError
                ? .failed(message: connectionStore.lastErrorMessage ?? "Oura sync failed.")
                : .idle,
            supportedMetrics: supportedMetrics,
            lastSyncAt: connectionStore.lastSyncAt,
            batteryPercentage: nil
        )
    }

    func sync(_ request: HealthSyncRequest) async throws -> HealthSyncResult {
        let targetDate = request.interval.end.addingTimeInterval(-1)
        let mapped = try await syncService.sync(date: targetDate, calendar: .current)
        let requestedSamples = mapped.samples.filter { request.metrics.contains($0.metric) }
        return HealthSyncResult(
            sourceID: sourceID,
            samples: requestedSamples,
            syncedAt: mapped.mappedAt,
            batteryPercentage: mapped.ringBatteryPercentage
        )
    }

    private var connectionState: SourceConnectionState {
        guard configuration.isReadyForOAuth else { return .setupRequired }

        switch connectionStore.status {
        case .notConnected:
            return .setupRequired
        case .connecting:
            return .syncing
        case .connected:
            let grantedScopes = connectionStore.grantedScopes.isEmpty
                ? configuration.requestedScopes
                : connectionStore.grantedScopes
            let missingScopes = Self.requiredScopes.subtracting(grantedScopes)
            if !missingScopes.isEmpty {
                return .missingScopes(missingScopes)
            }
            return .connected
        case .syncError:
            return .syncError(connectionStore.lastErrorMessage ?? "Oura sync failed.")
        case .tokenExpired:
            return .authExpired
        }
    }

    static let requiredScopes: Set<OuraScope> = OuraAuthService.productionScopes
}
