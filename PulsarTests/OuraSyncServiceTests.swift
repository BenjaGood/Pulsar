//
//  OuraSyncServiceTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

@MainActor
struct OuraSyncServiceTests {
    @Test func incrementalSyncUsesRecentWindowAfterSuccessfulSync() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date()
        let tokenStore = OuraInMemoryTokenStore(token: validToken())
        let connectionStore = OuraConnectionStore(defaults: ephemeralDefaults(), tokenStorage: tokenStore)
        connectionStore.markSynced(at: Date().addingTimeInterval(-30 * 60))
        let authService = OuraAuthService(
            configuration: testConfiguration(),
            tokenStorage: tokenStore,
            backendClient: FakeBackend(),
            connectionStore: connectionStore
        )
        let client = RecordingOuraAPIClient()
        let service = OuraSyncService(apiClient: client, authService: authService, connectionStore: connectionStore)

        _ = try await service.sync(date: date, calendar: calendar, reason: "appBecameActive")

        let startDate = try #require(client.startDates.first)
        let endDate = try #require(client.endDates.first)
        #expect(OuraDateParser.dayString(for: startDate, calendar: calendar) == OuraDateParser.dayString(for: calendar.date(byAdding: .day, value: -1, to: date)!, calendar: calendar))
        #expect(OuraDateParser.dayString(for: endDate, calendar: calendar) == OuraDateParser.dayString(for: calendar.date(byAdding: .day, value: 1, to: date)!, calendar: calendar))
    }

    @Test func firstIncrementalSyncUsesShortHistoricalLookback() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date()
        let tokenStore = OuraInMemoryTokenStore(token: validToken())
        let connectionStore = OuraConnectionStore(defaults: ephemeralDefaults(), tokenStorage: tokenStore)
        let authService = OuraAuthService(
            configuration: testConfiguration(),
            tokenStorage: tokenStore,
            backendClient: FakeBackend(),
            connectionStore: connectionStore
        )
        let client = RecordingOuraAPIClient()
        let service = OuraSyncService(apiClient: client, authService: authService, connectionStore: connectionStore)

        _ = try await service.sync(date: date, calendar: calendar, reason: "initialAppEntry")

        let startDate = try #require(client.startDates.first)
        #expect(OuraDateParser.dayString(for: startDate, calendar: calendar) == OuraDateParser.dayString(for: calendar.date(byAdding: .day, value: -3, to: date)!, calendar: calendar))
    }

    private func validToken() -> OuraStoredToken {
        OuraStoredToken(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3_600),
            scopes: OuraScope.pulsarOAuthScopes,
            tokenType: "bearer"
        )
    }

    private func testConfiguration() -> OuraIntegrationConfiguration {
        OuraIntegrationConfiguration(
            clientID: "client-id",
            redirectURI: URL(string: "aetherial-pulsar://oura/oauth/callback")!,
            backendBaseURL: URL(string: "https://example.com")!
        )
    }

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "pulsar.tests.oura-sync.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

private final class RecordingOuraAPIClient: OuraAPIClientProtocol {
    private(set) var startDates: [Date] = []
    private(set) var endDates: [Date] = []

    func fetchBundle(startDate: Date, endDate: Date, scopes _: Set<OuraScope>, calendar _: Calendar) async throws -> OuraRawSyncBundle {
        startDates.append(startDate)
        endDates.append(endDate)
        return OuraRawSyncBundle(
            personalInfo: nil,
            dailySleep: [],
            sleepPeriods: [],
            dailyReadiness: [],
            dailyActivity: [],
            heartRates: [],
            workouts: [],
            sessions: [],
            dailySpo2: [],
            dailyStress: [],
            dailyResilience: [],
            ringConfigurations: []
        )
    }
}

private struct FakeBackend: OuraBackendTokenServicing {
    func checkHealth() async throws -> OuraBackendHealthResponse {
        OuraBackendHealthResponse(ok: true, service: "test", configured: true, missing: nil)
    }

    func exchangeAuthorizationCode(_ code: String, redirectURI: URL, requestedScopes: Set<OuraScope>) async throws -> OuraOAuthTokenResponse {
        OuraOAuthTokenResponse(accessToken: "access-\(code)", refreshToken: "refresh", expiresIn: 3_600, tokenType: "bearer", scope: requestedScopes.map(\.rawValue).joined(separator: " "))
    }

    func refreshToken(_ refreshToken: String) async throws -> OuraOAuthTokenResponse {
        OuraOAuthTokenResponse(accessToken: "access", refreshToken: refreshToken, expiresIn: 3_600, tokenType: "bearer", scope: nil)
    }

    func revoke(accessToken _: String, refreshToken _: String?) async throws {}
}
