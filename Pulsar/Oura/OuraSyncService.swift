//
//  OuraSyncService.swift
//  Pulsar
//

import Foundation

protocol OuraSyncServicing {
    func sync(date: Date, calendar: Calendar) async throws -> OuraMappedHealthData
    func sync(date: Date, calendar: Calendar, reason: String) async throws -> OuraMappedHealthData
}

extension OuraSyncServicing {
    func sync(date: Date, calendar: Calendar, reason: String) async throws -> OuraMappedHealthData {
        try await sync(date: date, calendar: calendar)
    }
}

final class OuraSyncService: OuraSyncServicing {
    private static let recentSyncWindow: TimeInterval = 6 * 60 * 60
    private static let automaticSyncReuseWindow: TimeInterval = 10 * 60
    private static let retryBaseDelay: TimeInterval = 45
    private static let retryMaximumDelay: TimeInterval = 5 * 60

    private let apiClient: OuraAPIClientProtocol
    private let authService: OuraAuthService
    private let connectionStore: OuraConnectionStore
    private let mapper: OuraDataMapper
    private var nextAllowedAutomaticSyncAt: Date?
    private var consecutiveFailureCount = 0
    private var recentSuccessfulSync: RecentSuccessfulSync?

    private struct RecentSuccessfulSync {
        var mapped: OuraMappedHealthData
        var completedAt: Date
        var windowStart: Date
        var windowEnd: Date
        var dateKey: String
        var scopeKey: String
        var calendarIdentifier: Calendar.Identifier
        var timeZoneIdentifier: String

        func covers(window: (start: Date, end: Date), dateKey: String, scopeKey: String, calendar: Calendar, now: Date) -> Bool {
            now.timeIntervalSince(completedAt) <= OuraSyncService.automaticSyncReuseWindow &&
                windowStart <= window.start &&
                windowEnd >= window.end &&
                self.dateKey == dateKey &&
                self.scopeKey == scopeKey &&
                calendarIdentifier == calendar.identifier &&
                timeZoneIdentifier == calendar.timeZone.identifier
        }
    }

    init(
        apiClient: OuraAPIClientProtocol,
        authService: OuraAuthService,
        connectionStore: OuraConnectionStore,
        mapper: OuraDataMapper = OuraDataMapper()
    ) {
        self.apiClient = apiClient
        self.authService = authService
        self.connectionStore = connectionStore
        self.mapper = mapper
    }

    convenience init(configuration: OuraIntegrationConfiguration = .load()) {
        let tokenStore = OuraKeychainTokenStore()
        let authService = OuraAuthService(configuration: configuration, tokenStorage: tokenStore)
        let apiClient: OuraAPIClientProtocol = configuration.mockMode
            ? MockOuraAPIClient()
            : URLSessionOuraAPIClient(authService: authService)
        self.init(
            apiClient: apiClient,
            authService: authService,
            connectionStore: authService.connectionStore
        )
    }

    func sync(date: Date, calendar: Calendar = .current) async throws -> OuraMappedHealthData {
        try await sync(date: date, calendar: calendar, reason: "automatic")
    }

    func sync(date: Date, calendar: Calendar = .current, reason: String) async throws -> OuraMappedHealthData {
        let token = authService.connectionStore.storedToken
        guard let token else {
            throw OuraAPIError.unauthorized("Oura is not connected.")
        }

        let scopes = token.scopes.isEmpty ? authService.authorizationConfiguration.requestedScopes : token.scopes
        let now = Date()
        let window = incrementalWindow(for: date, calendar: calendar, now: now)
        let dateKey = OuraDateParser.dayString(for: date, calendar: calendar)
        let scopeKey = scopes.map(\.rawValue).sorted().joined(separator: ",")
        if reason != "manualRefresh",
           let recentSuccessfulSync,
           recentSuccessfulSync.covers(window: window, dateKey: dateKey, scopeKey: scopeKey, calendar: calendar, now: now) {
            PulsarOuraLogger.log("Incremental sync reused recent payload start=\(OuraDateParser.dayString(for: recentSuccessfulSync.windowStart, calendar: calendar)) end=\(OuraDateParser.dayString(for: recentSuccessfulSync.windowEnd, calendar: calendar)) reason=\(reason)")
            return recentSuccessfulSync.mapped
        }
        if reason != "manualRefresh",
           let nextAllowedAutomaticSyncAt,
           now < nextAllowedAutomaticSyncAt {
            let delay = Int(nextAllowedAutomaticSyncAt.timeIntervalSince(now).rounded(.up))
            let message = "Waiting for Oura cloud retry window (\(delay)s)."
            PulsarOuraLogger.log("Incremental sync deferred reason=\(reason) retryIn=\(delay)s")
            throw OuraAPIError.transport(message)
        }
        PulsarOuraLogger.log("Incremental sync started start=\(OuraDateParser.dayString(for: window.start, calendar: calendar)) end=\(OuraDateParser.dayString(for: window.end, calendar: calendar)) reason=\(reason) lastSyncAt=\(connectionStore.lastSyncAt?.description ?? "nil") scopes=\(scopes.map(\.rawValue).sorted().joined(separator: ","))")

        do {
            let bundle = try await apiClient.fetchBundle(
                startDate: window.start,
                endDate: window.end,
                scopes: scopes,
                calendar: calendar
            )
            var mapped = mapper.map(bundle: bundle, for: date, syncedAt: Date())
            mapped.debugReport = OuraSyncDebugReport.make(
                reason: reason,
                date: date,
                windowStart: window.start,
                windowEnd: window.end,
                calendar: calendar,
                scopes: scopes,
                bundle: bundle,
                mapped: mapped
            )
            if let payload = mapped.payload {
                PulsarOuraLogger.log("Oura mapped payload dateKey=\(payload.resolvedDateKey) strain=\(payload.strain != nil) recovery=\(payload.recovery != nil) sleep=\(payload.sleep != nil) stress=\(payload.stress != nil) healthMonitor=\(payload.healthMonitor != nil) strainSamples=\(payload.strain?.analyzedSampleCount ?? 0) strainHRRows=\(payload.strain?.heartRateSampleCount ?? 0) strainWorkoutRows=\(payload.strain?.workoutSampleCount ?? 0) stressTimeline=\(payload.stress?.timelineSamples.count ?? 0)")
            } else {
                PulsarOuraLogger.log("Oura mapped payload empty samples=\(mapped.samples.count)")
            }
            consecutiveFailureCount = 0
            nextAllowedAutomaticSyncAt = nil
            connectionStore.markSynced(at: mapped.mappedAt)
            recentSuccessfulSync = RecentSuccessfulSync(
                mapped: mapped,
                completedAt: mapped.mappedAt,
                windowStart: window.start,
                windowEnd: window.end,
                dateKey: dateKey,
                scopeKey: scopeKey,
                calendarIdentifier: calendar.identifier,
                timeZoneIdentifier: calendar.timeZone.identifier
            )
            PulsarOuraLogger.log("Incremental sync finished updatedMetrics=\(updatedMetricsDescription(mapped)) samples=\(mapped.samples.count)")
            PulsarOuraLogger.log("Oura sync completed payload=\(mapped.payload != nil) samples=\(mapped.samples.count)")
            return mapped
        } catch let error as OuraAPIError {
            switch error {
            case .unauthorized:
                connectionStore.markTokenExpired("Oura authorization expired. Connect Oura again.")
            case .rateLimited(let retryAfter, _):
                nextAllowedAutomaticSyncAt = retryAfter ?? now.addingTimeInterval(Self.retryMaximumDelay)
                connectionStore.markSyncError("Oura rate limit reached. Try again soon.")
            default:
                scheduleRetry(after: now)
                connectionStore.markSyncError(error.localizedDescription)
            }
            PulsarOuraLogger.log("Oura sync failed: \(error.localizedDescription)")
            throw error
        } catch {
            scheduleRetry(after: now)
            connectionStore.markSyncError(error.localizedDescription)
            PulsarOuraLogger.log("Oura sync failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func incrementalWindow(for date: Date, calendar: Calendar, now: Date) -> (start: Date, end: Date) {
        let lookbackDays: Int
        if let lastSyncAt = connectionStore.lastSyncAt,
           now.timeIntervalSince(lastSyncAt) <= Self.recentSyncWindow {
            lookbackDays = -1
        } else {
            lookbackDays = -3
        }
        let start = calendar.date(byAdding: .day, value: lookbackDays, to: date) ?? date
        let end = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        return (start, end)
    }

    private func scheduleRetry(after now: Date) {
        consecutiveFailureCount += 1
        let multiplier = pow(2.0, Double(max(0, consecutiveFailureCount - 1)))
        let delay = min(Self.retryMaximumDelay, Self.retryBaseDelay * multiplier)
        nextAllowedAutomaticSyncAt = now.addingTimeInterval(delay)
    }

    private func updatedMetricsDescription(_ mapped: OuraMappedHealthData) -> String {
        let metrics = Set(mapped.samples.map(\.metric.label))
        guard !metrics.isEmpty else {
            return mapped.payload == nil ? "none" : "daily"
        }
        return metrics.sorted().joined(separator: ",")
    }
}
