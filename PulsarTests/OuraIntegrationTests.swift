//
//  OuraIntegrationTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

@MainActor
struct OuraIntegrationTests {
    @Test func authorizationURLUsesOfficialEndpointAndRequestedScopes() throws {
        let service = OuraAuthService(
            configuration: testConfiguration(),
            tokenStorage: OuraInMemoryTokenStore(),
            backendClient: FakeOuraBackendTokenClient()
        )

        let url = try service.authorizationURL(state: "state-123", scopes: [.email, .personal, .daily, .heartrate, .workout, .tag, .session, .spo2])
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        #expect(components.scheme == "https")
        #expect(components.host == "cloud.ouraring.com")
        #expect(components.path == "/oauth/authorize")
        #expect(query["response_type"] == "code")
        #expect(query["client_id"] == "client-id")
        #expect(query["redirect_uri"] == "aetherial-pulsar://oura/oauth/callback")
        #expect(query["state"] == "state-123")
        #expect(query["scope"] == "daily email heartrate personal session spo2 tag workout")
        #expect(query["code_challenge"] == nil)
        #expect(query["code_challenge_method"] == nil)
    }

    @Test func oauthCallbackParsesCodeScopesAndRejectsStateMismatch() throws {
        let callbackURL = try #require(URL(string: "aetherial-pulsar://oura/oauth/callback?code=abc123&state=expected&scope=personal%20daily%20heartrate"))
        let callback = try OuraOAuthCallbackParser.parse(callbackURL, expectedState: "expected")

        #expect(callback.code == "abc123")
        #expect(callback.state == "expected")
        #expect(callback.scopes == [.personal, .daily, .heartrate])

        let mismatchedURL = try #require(URL(string: "aetherial-pulsar://oura/oauth/callback?code=abc123&state=wrong"))
        do {
            _ = try OuraOAuthCallbackParser.parse(mismatchedURL, expectedState: "expected")
            Issue.record("Expected state mismatch to throw")
        } catch let error as OuraOAuthCallbackError {
            #expect(error == .stateMismatch)
        }
    }

    @Test func completeOAuthStoresTokenFromBackendExchange() async throws {
        let defaults = ephemeralDefaults()
        let tokenStore = OuraInMemoryTokenStore()
        let backend = FakeOuraBackendTokenClient(
            exchangeResponse: OuraOAuthTokenResponse(
                accessToken: "access-from-exchange",
                refreshToken: "refresh-from-exchange",
                expiresIn: 3_600,
                tokenType: "bearer",
                scope: "personal daily heartrate"
            )
        )
        let connectionStore = OuraConnectionStore(defaults: defaults, tokenStorage: tokenStore)
        let service = OuraAuthService(
            configuration: testConfiguration(),
            tokenStorage: tokenStore,
            backendClient: backend,
            connectionStore: connectionStore
        )
        let callbackURL = try #require(URL(string: "aetherial-pulsar://oura/oauth/callback?code=oauth-code&state=state-1&scope=personal%20daily"))
        let receivedAt = Date(timeIntervalSinceReferenceDate: 10_000)

        try await service.completeOAuth(callbackURL: callbackURL, expectedState: "state-1", receivedAt: receivedAt)

        let stored = try #require(try tokenStore.loadToken())
        #expect(backend.exchangedCode == "oauth-code")
        #expect(stored.accessToken == "access-from-exchange")
        #expect(stored.refreshToken == "refresh-from-exchange")
        #expect(stored.scopes == [.personal, .daily, .heartrate])
        #expect(connectionStore.status == .connected)
    }

    @Test func validAccessTokenRefreshesExpiringToken() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 20_000)
        let tokenStore = OuraInMemoryTokenStore(token: OuraStoredToken(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: now.addingTimeInterval(60),
            scopes: [.daily, .heartrate],
            tokenType: "bearer"
        ))
        let backend = FakeOuraBackendTokenClient(
            refreshResponse: OuraOAuthTokenResponse(
                accessToken: "new-access",
                refreshToken: "new-refresh",
                expiresIn: 7_200,
                tokenType: "bearer",
                scope: nil
            )
        )
        let connectionStore = OuraConnectionStore(defaults: ephemeralDefaults(), tokenStorage: tokenStore)
        let service = OuraAuthService(
            configuration: testConfiguration(),
            tokenStorage: tokenStore,
            backendClient: backend,
            connectionStore: connectionStore
        )

        let accessToken = try await service.validAccessToken(now: now)

        let stored = try #require(try tokenStore.loadToken())
        #expect(accessToken == "new-access")
        #expect(backend.refreshedToken == "old-refresh")
        #expect(stored.refreshToken == "new-refresh")
        #expect(stored.scopes == [.daily, .heartrate])
        #expect(connectionStore.status == .connected)
    }

    @Test func concurrentExpiringTokenRequestsShareSingleRefresh() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 22_000)
        let tokenStore = OuraInMemoryTokenStore(token: OuraStoredToken(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: now.addingTimeInterval(60),
            scopes: [.daily],
            tokenType: "bearer"
        ))
        let backend = FakeOuraBackendTokenClient(
            refreshResponse: OuraOAuthTokenResponse(
                accessToken: "new-access",
                refreshToken: "new-refresh",
                expiresIn: 7_200,
                tokenType: "bearer",
                scope: nil
            ),
            refreshDelayNanoseconds: 50_000_000
        )
        let service = OuraAuthService(
            configuration: testConfiguration(),
            tokenStorage: tokenStore,
            backendClient: backend,
            connectionStore: OuraConnectionStore(defaults: ephemeralDefaults(), tokenStorage: tokenStore)
        )

        async let first = service.validAccessToken(now: now)
        async let second = service.validAccessToken(now: now)
        async let third = service.validAccessToken(now: now)

        let tokens = try await [first, second, third]

        #expect(Set(tokens) == ["new-access"])
        #expect(backend.refreshCallCount == 1)
    }

    @Test func emptyTokenScopeFallsBackToRequestedScopes() throws {
        let token = OuraOAuthTokenResponse(
            accessToken: "access",
            refreshToken: "refresh",
            expiresIn: 3_600,
            tokenType: "bearer",
            scope: ""
        ).storedToken(fallbackScopes: [.daily, .heartrate])

        #expect(token.scopes == [.daily, .heartrate])
    }

    @Test func decodesCurrentOuraSleepAndResilienceShapes() throws {
        let sleepJSON = Data("""
        {
          "data": [
            {
              "id": "sleep-1",
              "day": "2026-05-20",
              "type": "long_sleep",
              "bedtime_start": "2026-05-20T00:15:00-06:00",
              "bedtime_end": "2026-05-20T07:30:00-06:00",
              "total_sleep_duration": 24600,
              "time_in_bed": 26100,
              "average_breath": 14.2,
              "sleep_phase_5_min": "223344"
            }
          ],
          "next_token": null
        }
        """.utf8)
        let resilienceJSON = Data("""
        {
          "data": [
            {
              "id": "resilience-1",
              "day": "2026-05-20",
              "level": "solid",
              "contributors": {
                "sleep_recovery": 0.82,
                "daytime_recovery": 0.76,
                "stress": 0.68
              }
            }
          ],
          "next_token": null
        }
        """.utf8)

        let sleep = try OuraJSON.decoder.decode(OuraListResponse<OuraSleepPeriod>.self, from: sleepJSON).data
        let resilience = try OuraJSON.decoder.decode(OuraListResponse<OuraDailyResilience>.self, from: resilienceJSON).data

        #expect(sleep.first?.respiratoryRate == 14.2)
        #expect(sleep.first?.sleepPhase5Min == "223344")
        #expect(resilience.first?.contributors?.sleepRecovery == 0.82)
        #expect(resilience.first?.contributors?.daytimeRecovery == 0.76)
        #expect(resilience.first?.contributors?.stress == 0.68)
    }

    @Test func refreshFailureMarksTokenExpired() async throws {
        let now = Date(timeIntervalSinceReferenceDate: 25_000)
        let tokenStore = OuraInMemoryTokenStore(token: OuraStoredToken(
            accessToken: "expired-access",
            refreshToken: "expired-refresh",
            expiresAt: now.addingTimeInterval(-60),
            scopes: [.daily],
            tokenType: "bearer"
        ))
        let backend = FakeOuraBackendTokenClient(refreshError: OuraAPIError.unauthorized("invalid refresh token"))
        let connectionStore = OuraConnectionStore(defaults: ephemeralDefaults(), tokenStorage: tokenStore)
        let service = OuraAuthService(
            configuration: testConfiguration(),
            tokenStorage: tokenStore,
            backendClient: backend,
            connectionStore: connectionStore
        )

        do {
            _ = try await service.validAccessToken(now: now)
            Issue.record("Expected refresh failure")
        } catch let error as OuraAPIError {
            #expect(error == .unauthorized("invalid refresh token"))
        }

        #expect(backend.refreshedToken == "expired-refresh")
        #expect(connectionStore.status == .tokenExpired)
    }

    @Test func missingBackendConfigurationCanBuildAuthURLButIsNotReadyForExchange() throws {
        let configuration = OuraIntegrationConfiguration(
            clientID: "client-id",
            redirectURI: URL(string: "aetherial-pulsar://oura/oauth/callback")
        )
        let service = OuraAuthService(
            configuration: configuration,
            tokenStorage: OuraInMemoryTokenStore(),
            backendClient: FakeOuraBackendTokenClient()
        )

        #expect(service.canStartAuthorization)
        #expect(!service.isConfigured)
        #expect(try service.authorizationURL(state: "state").host == "cloud.ouraring.com")
    }

    @Test func configurationDerivesBackendEndpointsFromBaseURLAndUsesConfiguredScopes() throws {
        let configuration = OuraIntegrationConfiguration(
            clientID: "client-id",
            redirectURI: URL(string: "aetherial-pulsar://oura/oauth/callback"),
            requestedScopes: OuraScope.parseList("email personal daily heartrate workout tag session spo2"),
            backendBaseURL: URL(string: "https://pulsar.example.test/api")
        )
        let service = OuraAuthService(
            configuration: configuration,
            tokenStorage: OuraInMemoryTokenStore(),
            backendClient: FakeOuraBackendTokenClient()
        )

        #expect(configuration.isReadyForOAuth)
        #expect(configuration.backendHealthEndpoint?.absoluteString == "https://pulsar.example.test/api/health")
        #expect(configuration.backendTokenExchangeEndpoint?.absoluteString == "https://pulsar.example.test/api/oura/token/exchange")
        #expect(configuration.backendRefreshEndpoint?.absoluteString == "https://pulsar.example.test/api/oura/token/refresh")
        #expect(configuration.backendRevokeEndpoint?.absoluteString == "https://pulsar.example.test/api/oura/disconnect")
        let url = try service.authorizationURL(state: "state")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let scopes = components.queryItems?.first(where: { $0.name == "scope" })?.value
        #expect(scopes == "daily email heartrate personal session spo2 tag workout")
    }

    @Test func productionScopesDoNotIncludeRingConfigurationByDefault() {
        #expect(!OuraAuthService.productionScopes.contains(.ringConfiguration))
        #expect(OuraScope.parseList("daily ring_configuration") == [.daily, .ringConfiguration])
    }

    @Test func connectOuraStopsBeforeLoginWhenBackendIsUnreachable() async throws {
        let defaults = ephemeralDefaults()
        let tokenStore = OuraInMemoryTokenStore()
        let backend = FakeOuraBackendTokenClient(
            healthError: OuraAPIError.transport("Oura backend is not reachable. Start the local backend or update OuraBackendBaseURL.")
        )
        let connectionStore = OuraConnectionStore(defaults: defaults, tokenStorage: tokenStore)
        let service = OuraAuthService(
            configuration: testConfiguration(),
            tokenStorage: tokenStore,
            backendClient: backend,
            connectionStore: connectionStore
        )

        do {
            try await service.connect()
            Issue.record("Expected backend health check to stop OAuth")
        } catch let error as OuraAPIError {
            #expect(error == .transport("Oura backend is not reachable. Start the local backend or update OuraBackendBaseURL."))
        }

        #expect(backend.healthCheckCount == 1)
        #expect(backend.exchangedCode == nil)
        #expect(service.lastAuthorizationURL == nil)
        #expect(connectionStore.status == .notConnected)
    }

    @Test func connectOuraShowsReachableBackendAlertWhenHealthFails() async throws {
        let defaults = ephemeralDefaults()
        let configuration = testConfiguration()
        let tokenStore = OuraInMemoryTokenStore()
        let backend = FakeOuraBackendTokenClient(
            healthError: OuraAPIError.transport("Oura backend is not reachable. Start the local backend or update OuraBackendBaseURL.")
        )
        let authService = OuraAuthService(
            configuration: configuration,
            tokenStorage: tokenStore,
            backendClient: backend,
            connectionStore: OuraConnectionStore(defaults: defaults, tokenStorage: tokenStore)
        )
        let manager = MeasurementSourceManager(
            defaults: defaults,
            syncStore: nil,
            ouraAuthService: authService,
            ouraSyncService: FakeOuraSyncService(),
            sourcePriorityStore: HealthSourcePriorityStore(defaults: defaults),
            ouraConfiguration: configuration
        )

        await manager.connectOura()

        let alert = try #require(manager.ouraConnectionAlert)
        #expect(alert.kind == .connectionFailed)
        #expect(alert.message.contains("Oura backend is not reachable"))
        #expect(backend.healthCheckCount == 1)
        #expect(backend.exchangedCode == nil)
        #expect(!manager.isPrimaryActionDisabled(for: manager.device(for: .ouraRing)))
    }

    @Test func connectOuraWithMissingConfigurationShowsAlertAndKeepsButtonEnabled() async throws {
        let defaults = ephemeralDefaults()
        let configuration = OuraIntegrationConfiguration.notConfigured
        let tokenStore = OuraInMemoryTokenStore()
        let authService = OuraAuthService(
            configuration: configuration,
            tokenStorage: tokenStore,
            backendClient: FakeOuraBackendTokenClient(),
            connectionStore: OuraConnectionStore(defaults: defaults, tokenStorage: tokenStore)
        )
        let manager = MeasurementSourceManager(
            defaults: defaults,
            syncStore: nil,
            ouraAuthService: authService,
            ouraSyncService: FakeOuraSyncService(),
            sourcePriorityStore: HealthSourcePriorityStore(defaults: defaults),
            ouraConfiguration: configuration
        )

        await manager.connectOura()

        let alert = try #require(manager.ouraConnectionAlert)
        #expect(alert.kind == .configurationMissing)
        #expect(alert.message.contains("Oura connection is not configured yet. Backend token exchange is required before login can start."))
        #expect(alert.message.contains("OuraOAuthClientID"))
        #expect(alert.message.contains("OuraBackendBaseURL"))
        #expect(!manager.isPrimaryActionDisabled(for: manager.device(for: .ouraRing)))
        if case .failed(let message) = manager.ouraConnectionFlowState {
            #expect(message.contains("Backend token exchange is required"))
        } else {
            Issue.record("Expected failed Oura connection flow state")
        }
    }

    @Test func ouraPrimaryActionIsDisabledOnlyWhileConnectionIsInProgress() async throws {
        let defaults = ephemeralDefaults()
        defaults.set("ouraRing", forKey: "pulsar.measurementSource.activeDevice.v1")
        let manager = MeasurementSourceManager(
            defaults: defaults,
            syncStore: nil,
            ouraSyncService: FakeOuraSyncService(),
            sourcePriorityStore: HealthSourcePriorityStore(defaults: defaults),
            ouraConfiguration: .notConfigured
        )
        let disconnectedOura = manager.device(for: .ouraRing)

        #expect(disconnectedOura.isActiveSource)
        #expect(disconnectedOura.connectionStatus == .setupRequired)
        #expect(!manager.isPrimaryActionDisabled(for: disconnectedOura))
    }

    @Test func measurementSourceManagerSwitchesBetweenConnectedWearablesAndPersistsSelection() throws {
        let defaults = ephemeralDefaults()
        let tokenStore = OuraInMemoryTokenStore(token: OuraStoredToken(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3_600),
            scopes: [.daily, .heartrate],
            tokenType: "bearer"
        ))
        let connectionStore = OuraConnectionStore(defaults: defaults, tokenStorage: tokenStore)
        let configuration = testConfiguration()
        let authService = OuraAuthService(
            configuration: configuration,
            tokenStorage: tokenStore,
            backendClient: FakeOuraBackendTokenClient(),
            connectionStore: connectionStore
        )
        let manager = MeasurementSourceManager(
            defaults: defaults,
            syncStore: nil,
            ouraAuthService: authService,
            ouraSyncService: FakeOuraSyncService(),
            sourcePriorityStore: HealthSourcePriorityStore(defaults: defaults),
            ouraConfiguration: configuration
        )

        #expect(manager.activeDeviceType == .appleWatch)
        #expect(manager.device(for: .ouraRing).canBecomeActiveSource)

        manager.selectActiveDevice(.ouraRing)

        #expect(manager.activeDeviceType == .ouraRing)
        #expect(manager.device(for: .ouraRing).isActiveSource)
        #expect(defaults.string(forKey: "pulsar.measurementSource.activeDevice.v1") == "ouraRing")

        manager.selectActiveDevice(.appleWatch)

        #expect(manager.activeDeviceType == .appleWatch)
        #expect(manager.device(for: .appleWatch).isActiveSource)

        manager.selectActiveDevice(.airPodsPro3)

        #expect(manager.activeDeviceType == .appleWatch)
    }

    @Test func apiErrorHandlingClassifiesUnauthorizedRateLimitAndForbidden() throws {
        let unauthorized = OuraAPIError.from(
            statusCode: 401,
            data: Data(#"{"detail":"token expired"}"#.utf8)
        )
        let rateLimitDate = Date(timeIntervalSinceReferenceDate: 30_000)
        let rateLimited = OuraAPIError.from(
            statusCode: 429,
            data: Data(#"{"title":"Too Many Requests"}"#.utf8),
            retryAfter: rateLimitDate
        )
        let forbidden = OuraAPIError.from(
            statusCode: 403,
            data: Data(#"{"error_description":"missing scope"}"#.utf8)
        )

        #expect(unauthorized == .unauthorized("token expired"))
        #expect(rateLimited == .rateLimited(retryAfter: rateLimitDate, message: "Too Many Requests"))
        #expect(forbidden == .forbidden("missing scope"))
    }

    @Test func mockOuraBundleMapsIntoPulsarMetricsAndSamples() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let date = noonUTC(year: 2026, month: 2, day: 5)
        let syncedAt = date.addingTimeInterval(3_600)
        let client = MockOuraAPIClient(now: date, calendar: calendar)
        let bundle = try await client.fetchBundle(
            startDate: date.addingTimeInterval(-86_400),
            endDate: date.addingTimeInterval(86_400),
            scopes: OuraAuthService.productionScopes,
            calendar: calendar
        )

        let mapped = OuraDataMapper(calendar: calendar).map(bundle: bundle, for: date, syncedAt: syncedAt)
        let payload = try #require(mapped.payload)

        #expect(payload.sourceDevice == .ouraRing)
        #expect(payload.sleep?.score == 88)
        #expect(payload.recovery?.score == 86)
        #expect((payload.strain?.score ?? 0) > 0)
        #expect((payload.strain?.score ?? 0) < 78)
        #expect(payload.stress?.sourceNames == ["Oura Ring"])
        #expect(payload.recovery?.wristTemperatureDeviation == 0.05)
        #expect(payload.healthMonitor?.metrics.contains(where: { $0.kind == .hrv && $0.value == 62 }) == true)
        #expect(payload.healthMonitor?.metrics.contains(where: { metric in
            metric.kind == .wristTemperature &&
                metric.value == 0.05 &&
                metric.comparisonText.contains("not absolute body temperature")
        }) == true)
        let containsOuraSleepSample = mapped.samples.contains { sample in
            sample.metric == .sleep && sample.sourceID == .ouraRing
        }
        let containsAwakeHeartRate = mapped.samples.contains { sample in
            sample.metric == .heartRate && sample.value == 72
        }
        #expect(containsOuraSleepSample)
        #expect(containsAwakeHeartRate)
    }

    @Test func mapperComputesOuraActivityStrainFromLoadWhenReadinessIsMissing() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let date = noonUTC(year: 2026, month: 5, day: 20)
        let syncedAt = date.addingTimeInterval(45 * 60)
        let day = OuraDateParser.dayString(for: date, calendar: calendar)
        let bundle = OuraRawSyncBundle(
            personalInfo: nil,
            dailySleep: [],
            sleepPeriods: [],
            dailyReadiness: [],
            dailyActivity: [
                OuraDailyActivity(
                    id: "activity-\(day)",
                    day: day,
                    score: 92,
                    activeCalories: 108,
                    totalCalories: 1_980,
                    steps: 1_326,
                    equivalentWalkingDistance: 1_080,
                    highActivityTime: 0,
                    mediumActivityTime: 12 * 60,
                    lowActivityTime: 46 * 60,
                    sedentaryTime: 680 * 60,
                    targetCalories: 500,
                    timestamp: date
                )
            ],
            heartRates: [
                OuraHeartRate(bpm: 64, source: "awake", timestamp: date)
            ],
            workouts: [],
            sessions: [],
            dailySpo2: [],
            dailyStress: [],
            dailyResilience: [],
            ringConfigurations: []
        )

        let mapped = OuraDataMapper(calendar: calendar).map(bundle: bundle, for: date, syncedAt: syncedAt)
        let payload = try #require(mapped.payload)
        let strain = try #require(payload.strain)
        let report = OuraSyncDebugReport.make(
            reason: "manualRefresh",
            date: date,
            windowStart: date.addingTimeInterval(-86_400),
            windowEnd: date.addingTimeInterval(86_400),
            calendar: calendar,
            scopes: OuraAuthService.productionScopes,
            bundle: bundle,
            mapped: mapped
        )
        let strainRow = try #require(report.mappedRows.first { $0.title == "Strain" })

        #expect(strain.score < 30)
        #expect(strain.steps == 1_326)
        #expect(strain.activitySampleCount == 1)
        #expect(strain.heartRateSampleCount == 1)
        #expect(strain.workoutSampleCount == 0)
        #expect(strain.analyzedSampleCount == 2)
        #expect(payload.recovery == nil)
        #expect(payload.hasValidStrain)
        #expect(!payload.hasCompleteDailyScores)
        #expect(mapped.samples.contains { $0.metric == .activity && $0.sourceID == .ouraRing && $0.value == 1_326 })
        #expect(strainRow.isAvailable)
        #expect(strainRow.detail != "score 92")
        #expect(report.providedRows.first { $0.title == "Daytime heart rate" }?.isAvailable == true)
        #expect(report.providedRows.first { $0.title == "Sleep heart rate" }?.isAvailable == false)
        #expect(report.summary.contains("Oura returned Activity, Heart rate"))
        #expect(!report.summary.contains("Strain"))
    }

    @Test func mapperDerivesHealthMonitorRestingHeartRateFromSleepHeartRateRows() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let date = noonUTC(year: 2026, month: 5, day: 20)
        let syncedAt = date.addingTimeInterval(600)
        let bundle = OuraRawSyncBundle(
            personalInfo: nil,
            dailySleep: [],
            sleepPeriods: [],
            dailyReadiness: [],
            dailyActivity: [],
            heartRates: [
                OuraHeartRate(bpm: 58, source: "sleep", timestamp: date.addingTimeInterval(-4 * 60 * 60)),
                OuraHeartRate(bpm: 52, source: "sleep", timestamp: date.addingTimeInterval(-3 * 60 * 60)),
                OuraHeartRate(bpm: 55, source: "sleep", timestamp: date.addingTimeInterval(-2 * 60 * 60)),
                OuraHeartRate(bpm: 101, source: "awake", timestamp: date.addingTimeInterval(60 * 60))
            ],
            workouts: [],
            sessions: [],
            dailySpo2: [],
            dailyStress: [],
            dailyResilience: [],
            ringConfigurations: []
        )

        let mapped = OuraDataMapper(calendar: calendar).map(bundle: bundle, for: date, syncedAt: syncedAt)
        let payload = try #require(mapped.payload)
        let healthMonitor = try #require(payload.healthMonitor)
        let restingHeartRate = try #require(healthMonitor.metrics.first { $0.kind == .restingHeartRate })
        let report = OuraSyncDebugReport.make(
            reason: "manualRefresh",
            date: date,
            windowStart: date.addingTimeInterval(-86_400),
            windowEnd: date.addingTimeInterval(86_400),
            calendar: calendar,
            scopes: OuraAuthService.productionScopes,
            bundle: bundle,
            mapped: mapped
        )

        #expect(restingHeartRate.value == 52)
        #expect(restingHeartRate.sourceNames == ["Oura Ring"])
        #expect(payload.sleep == nil)
        #expect(payload.recovery == nil)
        #expect(mapped.samples.contains { $0.metric == .restingHeartRate && $0.value == 52 })
        #expect(mapped.samples.filter { $0.metric == .heartRate }.count == 4)
        #expect(report.providedRows.first { $0.title == "Sleep heart rate" }?.detail.contains("3 rows") == true)
        #expect(report.providedRows.first { $0.title == "Daytime heart rate" }?.detail.contains("1 rows") == true)
    }

    @Test func mapperBuildsRawOuraStressFromHeartRateAndRecoverySignalsWithoutDailyStress() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let date = noonUTC(year: 2026, month: 5, day: 20)
        let syncedAt = date.addingTimeInterval(600)
        let day = OuraDateParser.dayString(for: date, calendar: calendar)
        let sleep = OuraSleepPeriod(
            id: "sleep-\(day)",
            day: day,
            type: "long_sleep",
            bedtimeStart: date.addingTimeInterval(-8 * 60 * 60),
            bedtimeEnd: date.addingTimeInterval(-60 * 60),
            totalSleepDuration: 7 * 60 * 60,
            timeInBed: 7.5 * 60 * 60,
            awakeTime: 30 * 60,
            restlessPeriods: 2,
            remSleepDuration: 90 * 60,
            deepSleepDuration: 70 * 60,
            lightSleepDuration: 260 * 60,
            efficiency: 93,
            averageHeartRate: 57,
            lowestHeartRate: 52,
            averageHRV: 62,
            respiratoryRate: 14.1,
            temperatureDeviation: nil,
            temperatureTrendDeviation: nil,
            sleepPhase5Min: nil
        )
        let bundle = OuraRawSyncBundle(
            personalInfo: nil,
            dailySleep: [],
            sleepPeriods: [sleep],
            dailyReadiness: [
                OuraDailyReadiness(
                    id: "readiness-\(day)",
                    day: day,
                    score: 80,
                    temperatureDeviation: nil,
                    temperatureTrendDeviation: nil,
                    timestamp: date,
                    contributors: nil
                )
            ],
            dailyActivity: [],
            heartRates: [
                OuraHeartRate(bpm: 78, source: "awake", timestamp: date.addingTimeInterval(5 * 60)),
                OuraHeartRate(bpm: 82, source: "awake", timestamp: date.addingTimeInterval(20 * 60)),
                OuraHeartRate(bpm: 86, source: "awake", timestamp: date.addingTimeInterval(35 * 60))
            ],
            workouts: [],
            sessions: [],
            dailySpo2: [],
            dailyStress: [],
            dailyResilience: [],
            ringConfigurations: []
        )

        let payload = try #require(OuraDataMapper(calendar: calendar).map(bundle: bundle, for: date, syncedAt: syncedAt).payload)
        let stress = try #require(payload.stress)

        #expect(stress.sourceNames == ["Oura Ring"])
        #expect(stress.recentHeartRate == 86)
        #expect(stress.restingHeartRate == 52)
        #expect(stress.hrvSDNN == 62)
        #expect(stress.nonActivityStress != nil)
        #expect(stress.activityAdjustedStress != nil)
        #expect(stress.confidence != .missing)
        #expect(stress.timelineSamples.count >= 2)
    }

    @Test func mapperDoesNotEmitCurrentStressForOuraDailyStressOnly() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let date = noonUTC(year: 2026, month: 5, day: 20)
        let day = OuraDateParser.dayString(for: date, calendar: calendar)
        let bundle = OuraRawSyncBundle(
            personalInfo: nil,
            dailySleep: [],
            sleepPeriods: [],
            dailyReadiness: [],
            dailyActivity: [],
            heartRates: [],
            workouts: [],
            sessions: [],
            dailySpo2: [],
            dailyStress: [
                OuraDailyStress(
                    id: "stress-\(day)",
                    day: day,
                    stressHigh: 90 * 60,
                    recoveryHigh: 30 * 60,
                    daySummary: "stressful"
                )
            ],
            dailyResilience: [],
            ringConfigurations: []
        )

        let mapped = OuraDataMapper(calendar: calendar).map(bundle: bundle, for: date, syncedAt: date.addingTimeInterval(600))

        #expect(mapped.payload?.stress == nil)
    }

    @Test func mapperTreatsInvalidOuraRestingHeartRateAsMissingWithoutDroppingSleep() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let date = noonUTC(year: 2026, month: 5, day: 20)
        let syncedAt = date.addingTimeInterval(600)
        let day = OuraDateParser.dayString(for: date, calendar: calendar)
        let bedtimeStart = date.addingTimeInterval(-8 * 60 * 60)
        let bedtimeEnd = date.addingTimeInterval(-30 * 60)
        let bundle = OuraRawSyncBundle(
            personalInfo: nil,
            dailySleep: [
                OuraDailySleep(
                    id: "daily-sleep-\(day)",
                    day: day,
                    score: 82,
                    timestamp: date,
                    contributors: OuraDailySleep.Contributors(
                        deepSleep: 84,
                        efficiency: 90,
                        latency: 88,
                        remSleep: 82,
                        restfulness: 79,
                        timing: 80,
                        totalSleep: 83
                    )
                )
            ],
            sleepPeriods: [
                OuraSleepPeriod(
                    id: "sleep-\(day)",
                    day: day,
                    type: "long_sleep",
                    bedtimeStart: bedtimeStart,
                    bedtimeEnd: bedtimeEnd,
                    totalSleepDuration: 7 * 60 * 60,
                    timeInBed: 7.5 * 60 * 60,
                    awakeTime: 30 * 60,
                    restlessPeriods: 2,
                    remSleepDuration: 95 * 60,
                    deepSleepDuration: 72 * 60,
                    lightSleepDuration: 253 * 60,
                    efficiency: 93,
                    averageHeartRate: 0,
                    lowestHeartRate: 0,
                    averageHRV: 64,
                    respiratoryRate: 14.1,
                    temperatureDeviation: 0.02,
                    temperatureTrendDeviation: 0.02,
                    sleepPhase5Min: nil
                )
            ],
            dailyReadiness: [
                OuraDailyReadiness(
                    id: "readiness-\(day)",
                    day: day,
                    score: 80,
                    temperatureDeviation: 0.02,
                    temperatureTrendDeviation: 0.02,
                    timestamp: date,
                    contributors: OuraDailyReadiness.Contributors(
                        activityBalance: 83,
                        bodyTemperature: 91,
                        hrvBalance: 78,
                        previousDayActivity: 80,
                        previousNight: 82,
                        recoveryIndex: 84,
                        restingHeartRate: 0,
                        sleepBalance: 86,
                        sleepRegularity: 81
                    )
                )
            ],
            dailyActivity: [],
            heartRates: [],
            workouts: [],
            sessions: [],
            dailySpo2: [],
            dailyStress: [],
            dailyResilience: [],
            ringConfigurations: []
        )

        let mapped = OuraDataMapper(calendar: calendar).map(bundle: bundle, for: date, syncedAt: syncedAt)
        let payload = try #require(mapped.payload)
        let sleep = try #require(payload.sleep)
        let recovery = try #require(payload.recovery)
        let healthMonitor = try #require(payload.healthMonitor)
        let restingHeartRate = try #require(healthMonitor.metrics.first { $0.kind == .restingHeartRate })
        let sleepMetric = try #require(healthMonitor.metrics.first { $0.kind == .sleep })

        #expect(payload.hasValidSleep)
        #expect(payload.hasValidHealthMonitor)
        #expect(sleep.score == 82)
        #expect(abs(sleep.totalSleepMinutes - 420) < 0.1)
        #expect(recovery.restingHeartRate == nil)
        #expect(restingHeartRate.value == nil)
        #expect(restingHeartRate.status == .noData)
        #expect(restingHeartRate.comparisonText.contains("valid sleep/rest"))
        #expect(sleepMetric.value == 420)
        #expect(mapped.samples.contains { $0.metric == .sleep && $0.sourceID == .ouraRing })
        #expect(!mapped.samples.contains { $0.metric == .restingHeartRate && $0.value == 0 })
    }

    @Test func apiClientSkipsRingConfigurationWhenScopeIsNotGranted() async throws {
        let tokenStore = OuraInMemoryTokenStore(token: OuraStoredToken(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3_600),
            scopes: OuraAuthService.productionScopes,
            tokenType: "bearer"
        ))
        let authService = OuraAuthService(
            configuration: testConfiguration(),
            tokenStorage: tokenStore,
            backendClient: FakeOuraBackendTokenClient(),
            connectionStore: OuraConnectionStore(defaults: ephemeralDefaults(), tokenStorage: tokenStore)
        )
        let recorder = OuraAPIRequestRecorder()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingOuraURLProtocol.self]
        configuration.httpAdditionalHeaders = ["OuraAPIRequestRecorderID": recorder.id.uuidString]
        RecordingOuraURLProtocol.register(recorder)
        defer { RecordingOuraURLProtocol.unregister(recorder) }
        let session = URLSession(configuration: configuration)
        let client = URLSessionOuraAPIClient(
            authService: authService,
            session: session,
            baseURL: URL(string: "https://oura.example.test")!
        )

        _ = try await client.fetchBundle(
            startDate: noonUTC(year: 2026, month: 2, day: 4),
            endDate: noonUTC(year: 2026, month: 2, day: 6),
            scopes: OuraAuthService.productionScopes,
            calendar: Calendar(identifier: .gregorian)
        )

        #expect(!recorder.paths.contains("/v2/usercollection/ring_configuration"))
    }

    @Test func apiClientSkipsStressScopeGatedResilienceEndpoint() async throws {
        let tokenStore = OuraInMemoryTokenStore(token: OuraStoredToken(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3_600),
            scopes: OuraAuthService.productionScopes,
            tokenType: "bearer"
        ))
        let authService = OuraAuthService(
            configuration: testConfiguration(),
            tokenStorage: tokenStore,
            backendClient: FakeOuraBackendTokenClient(),
            connectionStore: OuraConnectionStore(defaults: ephemeralDefaults(), tokenStorage: tokenStore)
        )
        let recorder = OuraAPIRequestRecorder()
        recorder.setResponse(
            pathSuffix: "/daily_resilience",
            statusCode: 401,
            body: Data(#"{"status":401,"title":"Missing Scopes","detail":"Token is not authorized access stress scope."}"#.utf8)
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingOuraURLProtocol.self]
        configuration.httpAdditionalHeaders = ["OuraAPIRequestRecorderID": recorder.id.uuidString]
        RecordingOuraURLProtocol.register(recorder)
        defer { RecordingOuraURLProtocol.unregister(recorder) }
        let session = URLSession(configuration: configuration)
        let client = URLSessionOuraAPIClient(
            authService: authService,
            session: session,
            baseURL: URL(string: "https://oura.example.test")!
        )

        let bundle = try await client.fetchBundle(
            startDate: noonUTC(year: 2026, month: 5, day: 20),
            endDate: noonUTC(year: 2026, month: 5, day: 20),
            scopes: OuraAuthService.productionScopes,
            calendar: Calendar(identifier: .gregorian)
        )

        #expect(recorder.paths.contains("/v2/usercollection/daily_resilience"))
        #expect(bundle.dailyResilience.isEmpty)
    }

    @Test func apiClientDoesNotSkipUnauthorizedCoreDailyEndpoint() async throws {
        let tokenStore = OuraInMemoryTokenStore(token: OuraStoredToken(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3_600),
            scopes: OuraAuthService.productionScopes,
            tokenType: "bearer"
        ))
        let authService = OuraAuthService(
            configuration: testConfiguration(),
            tokenStorage: tokenStore,
            backendClient: FakeOuraBackendTokenClient(),
            connectionStore: OuraConnectionStore(defaults: ephemeralDefaults(), tokenStorage: tokenStore)
        )
        let recorder = OuraAPIRequestRecorder()
        recorder.setResponse(
            pathSuffix: "/daily_sleep",
            statusCode: 401,
            body: Data(#"{"status":401,"title":"Invalid Access Token","detail":"token expired"}"#.utf8)
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingOuraURLProtocol.self]
        configuration.httpAdditionalHeaders = ["OuraAPIRequestRecorderID": recorder.id.uuidString]
        RecordingOuraURLProtocol.register(recorder)
        defer { RecordingOuraURLProtocol.unregister(recorder) }
        let session = URLSession(configuration: configuration)
        let client = URLSessionOuraAPIClient(
            authService: authService,
            session: session,
            baseURL: URL(string: "https://oura.example.test")!
        )

        do {
            _ = try await client.fetchBundle(
                startDate: noonUTC(year: 2026, month: 5, day: 20),
                endDate: noonUTC(year: 2026, month: 5, day: 20),
                scopes: OuraAuthService.productionScopes,
                calendar: Calendar(identifier: .gregorian)
            )
            Issue.record("Expected unauthorized core endpoint to fail the sync")
        } catch let error as OuraAPIError {
            #expect(error == .unauthorized("token expired"))
        }
    }

    @Test func sourcePriorityFallsBackWhenCurrentSourceIsStale() {
        let now = Date(timeIntervalSinceReferenceDate: 40_000)
        let resolved = HealthSourcePriorityResolver.resolve(
            category: .sleepRecovery,
            preference: HealthSourcePreference(currentSource: .ouraRing, fallbackEnabled: true),
            snapshots: [
                snapshot(.ouraRing, metrics: [.sleep, .recovery], lastSyncAt: now.addingTimeInterval(-72 * 60 * 60)),
                snapshot(.appleWatch, metrics: [.sleep, .recovery], lastSyncAt: now.addingTimeInterval(-15 * 60))
            ],
            now: now
        )

        #expect(resolved.currentSource == .ouraRing)
        #expect(resolved.displayedSource == .appleWatch)
        #expect(resolved.isFallback)
    }

    @Test func ouraPayloadFilterRespectsUserWorkoutPreference() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let date = noonUTC(year: 2026, month: 2, day: 5)
        let client = MockOuraAPIClient(now: date, calendar: calendar)
        let bundle = try await client.fetchBundle(startDate: date, endDate: date, scopes: OuraAuthService.productionScopes, calendar: calendar)
        let payload = try #require(OuraDataMapper(calendar: calendar).map(bundle: bundle, for: date).payload)
        let defaults = ephemeralDefaults()
        let priorityStore = HealthSourcePriorityStore(defaults: defaults)
        priorityStore.setCurrentSource(.ouraRing, for: .sleepRecovery)
        priorityStore.setCurrentSource(.appleWatch, for: .workoutsActivity)
        let snapshots = [
            snapshot(.ouraRing, metrics: [.sleep, .recovery, .readiness, .heartRate, .hrv, .restingHeartRate], lastSyncAt: date),
            snapshot(.appleWatch, metrics: [.workouts, .activity, .strain], lastSyncAt: date)
        ]

        let filtered = try #require(OuraPriorityPayloadFilter.filteredPayload(from: payload, priorityStore: priorityStore, snapshots: snapshots, now: date))

        #expect(filtered.sleep != nil)
        #expect(filtered.recovery != nil)
        #expect(filtered.strain == nil)
    }

    @Test func deduplicationKeepsCurrentSourceForOverlappingSamples() {
        let start = Date(timeIntervalSinceReferenceDate: 50_000)
        let apple = sample(
            id: "apple-hrv",
            metric: .hrv,
            source: .appleWatch,
            start: start,
            end: start.addingTimeInterval(60),
            value: 48,
            syncedAt: start.addingTimeInterval(5)
        )
        let oura = sample(
            id: "oura-hrv",
            metric: .hrv,
            source: .ouraRing,
            start: start.addingTimeInterval(30),
            end: start.addingTimeInterval(90),
            value: 61,
            syncedAt: start.addingTimeInterval(1)
        )

        let deduped = HealthSampleDeduplicator.deduplicate([apple, oura], sourcePriority: [.ouraRing, .appleWatch])

        #expect(deduped.count == 1)
        #expect(deduped.first?.sourceID == .ouraRing)
        #expect(deduped.first?.value == 61)
    }

    private func testConfiguration() -> OuraIntegrationConfiguration {
        OuraIntegrationConfiguration(
            clientID: "client-id",
            redirectURI: URL(string: "aetherial-pulsar://oura/oauth/callback"),
            backendHealthEndpoint: URL(string: "https://pulsar.example.test/health"),
            backendTokenExchangeEndpoint: URL(string: "https://pulsar.example.test/oura/exchange"),
            backendRefreshEndpoint: URL(string: "https://pulsar.example.test/oura/refresh"),
            backendRevokeEndpoint: URL(string: "https://pulsar.example.test/oura/revoke")
        )
    }

    private func ephemeralDefaults() -> UserDefaults {
        let suiteName = "PulsarOuraTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func noonUTC(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return components.date ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    private func snapshot(
        _ sourceID: HealthSourceID,
        connectionState: SourceConnectionState = .connected,
        metrics: Set<MeasurementHealthMetricType>,
        lastSyncAt: Date?
    ) -> HealthSourceSnapshot {
        HealthSourceSnapshot(
            sourceID: sourceID,
            connectionState: connectionState,
            syncState: .idle,
            supportedMetrics: metrics,
            lastSyncAt: lastSyncAt,
            batteryPercentage: nil
        )
    }

    private func sample(
        id: String,
        metric: MeasurementHealthMetricType,
        source: HealthSourceID,
        start: Date,
        end: Date?,
        value: Double,
        syncedAt: Date
    ) -> CanonicalHealthSample {
        CanonicalHealthSample(
            id: id,
            metric: metric,
            sourceID: source,
            sourceRecordID: id,
            startAt: start,
            endAt: end,
            value: value,
            unit: "ms",
            syncedAt: syncedAt
        )
    }
}

private final class OuraAPIRequestRecorder: @unchecked Sendable {
    let id = UUID()
    private let lock = NSLock()
    private var recordedPaths: [String] = []
    private var responseOverrides: [String: (statusCode: Int, body: Data)] = [:]

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedPaths
    }

    func append(path: String) {
        lock.lock()
        recordedPaths.append(path)
        lock.unlock()
    }

    func setResponse(pathSuffix: String, statusCode: Int, body: Data) {
        lock.lock()
        responseOverrides[pathSuffix] = (statusCode, body)
        lock.unlock()
    }

    func response(for path: String) -> (statusCode: Int, body: Data)? {
        lock.lock()
        defer { lock.unlock() }
        return responseOverrides.first(where: { path.hasSuffix($0.key) })?.value
    }
}

private final class RecordingOuraURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var recorders: [String: OuraAPIRequestRecorder] = [:]

    static func register(_ recorder: OuraAPIRequestRecorder) {
        lock.lock()
        recorders[recorder.id.uuidString] = recorder
        lock.unlock()
    }

    static func unregister(_ recorder: OuraAPIRequestRecorder) {
        lock.lock()
        recorders.removeValue(forKey: recorder.id.uuidString)
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "oura.example.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let recorder: OuraAPIRequestRecorder?
        if let url = request.url {
            let recorderID = request.value(forHTTPHeaderField: "OuraAPIRequestRecorderID")
            Self.lock.lock()
            recorder = recorderID.flatMap { Self.recorders[$0] }
            Self.lock.unlock()
            recorder?.append(path: url.path)
        } else {
            recorder = nil
        }

        let responseOverride = request.url.map { recorder?.response(for: $0.path) } ?? nil
        let statusCode = responseOverride?.statusCode ?? 200
        let body: Data
        if let responseBody = responseOverride?.body {
            body = responseBody
        } else if request.url?.path.hasSuffix("/personal_info") == true {
            body = Data(#"{"data":{}}"#.utf8)
        } else {
            body = Data(#"{"data":[]}"#.utf8)
        }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://oura.example.test")!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class FakeOuraBackendTokenClient: OuraBackendTokenServicing {
    var healthResponse: OuraBackendHealthResponse
    var exchangeResponse: OuraOAuthTokenResponse
    var refreshResponse: OuraOAuthTokenResponse
    var healthError: Error?
    var exchangeError: Error?
    var refreshError: Error?
    var refreshDelayNanoseconds: UInt64
    var healthCheckCount = 0
    var refreshCallCount = 0
    var exchangedCode: String?
    var refreshedToken: String?
    var revokedAccessToken: String?
    var revokedRefreshToken: String?

    init(
        healthResponse: OuraBackendHealthResponse = OuraBackendHealthResponse(
            ok: true,
            service: "pulsar-oura-backend",
            configured: true,
            missing: nil
        ),
        exchangeResponse: OuraOAuthTokenResponse = OuraOAuthTokenResponse(
            accessToken: "exchange-access",
            refreshToken: "exchange-refresh",
            expiresIn: 3_600,
            tokenType: "bearer",
            scope: nil
        ),
        refreshResponse: OuraOAuthTokenResponse = OuraOAuthTokenResponse(
            accessToken: "refresh-access",
            refreshToken: "refresh-refresh",
            expiresIn: 3_600,
            tokenType: "bearer",
            scope: nil
        ),
        healthError: Error? = nil,
        exchangeError: Error? = nil,
        refreshError: Error? = nil,
        refreshDelayNanoseconds: UInt64 = 0
    ) {
        self.healthResponse = healthResponse
        self.exchangeResponse = exchangeResponse
        self.refreshResponse = refreshResponse
        self.healthError = healthError
        self.exchangeError = exchangeError
        self.refreshError = refreshError
        self.refreshDelayNanoseconds = refreshDelayNanoseconds
    }

    func checkHealth() async throws -> OuraBackendHealthResponse {
        healthCheckCount += 1
        if let healthError { throw healthError }
        return healthResponse
    }

    func exchangeAuthorizationCode(
        _ code: String,
        redirectURI: URL,
        requestedScopes: Set<OuraScope>
    ) async throws -> OuraOAuthTokenResponse {
        exchangedCode = code
        if let exchangeError { throw exchangeError }
        return exchangeResponse
    }

    func refreshToken(_ refreshToken: String) async throws -> OuraOAuthTokenResponse {
        refreshCallCount += 1
        if refreshDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: refreshDelayNanoseconds)
        }
        refreshedToken = refreshToken
        if let refreshError { throw refreshError }
        return refreshResponse
    }

    func revoke(accessToken: String, refreshToken: String?) async throws {
        revokedAccessToken = accessToken
        revokedRefreshToken = refreshToken
    }
}

private struct FakeOuraSyncService: OuraSyncServicing {
    func sync(date: Date, calendar: Calendar) async throws -> OuraMappedHealthData {
        OuraMappedHealthData(
            payload: nil,
            samples: [],
            ringBatteryPercentage: nil,
            mappedAt: date
        )
    }
}
