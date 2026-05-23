//
//  OuraAPIClient.swift
//  Pulsar
//

import Foundation

protocol OuraAPIClientProtocol {
    func fetchBundle(startDate: Date, endDate: Date, scopes: Set<OuraScope>, calendar: Calendar) async throws -> OuraRawSyncBundle
}

final class URLSessionOuraAPIClient: OuraAPIClientProtocol {
    private let authService: OuraAuthService
    private let session: URLSession
    private let baseURL: URL

    init(
        authService: OuraAuthService,
        session: URLSession = .shared,
        baseURL: URL = OuraAPIEndpoint.apiBaseURL
    ) {
        self.authService = authService
        self.session = session
        self.baseURL = baseURL
    }

    func fetchBundle(startDate: Date, endDate: Date, scopes: Set<OuraScope>, calendar: Calendar = .current) async throws -> OuraRawSyncBundle {
        let personalInfoResult = try await fetchOptionalIfAllowed(scopes.intersection([.personal, .email]).isEmpty == false, path: "personal_info") {
            try await self.fetchPersonalInfo()
        }
        let dailySleepResult = try await fetchListIfAllowed(scopes.contains(.daily), path: "daily_sleep", startDate: startDate, endDate: endDate, calendar: calendar, type: OuraDailySleep.self)
        let sleepResult = try await fetchListIfAllowed(scopes.contains(.daily), path: "sleep", startDate: startDate, endDate: endDate, calendar: calendar, type: OuraSleepPeriod.self)
        let readinessResult = try await fetchListIfAllowed(scopes.contains(.daily), path: "daily_readiness", startDate: startDate, endDate: endDate, calendar: calendar, type: OuraDailyReadiness.self)
        let activityResult = try await fetchListIfAllowed(scopes.contains(.daily), path: "daily_activity", startDate: startDate, endDate: endDate, calendar: calendar, type: OuraDailyActivity.self)
        let heartRatesResult = try await fetchListIfAllowed(scopes.contains(.heartrate), path: "heartrate", startDate: startDate, endDate: endDate, calendar: calendar, type: OuraHeartRate.self)
        let workoutsResult = try await fetchListIfAllowed(scopes.contains(.workout), path: "workout", startDate: startDate, endDate: endDate, calendar: calendar, type: OuraWorkout.self)
        let sessionsResult = try await fetchListIfAllowed(scopes.contains(.session), path: "session", startDate: startDate, endDate: endDate, calendar: calendar, type: OuraSession.self)
        let spo2Result = try await fetchListIfAllowed(scopes.contains(.spo2), path: "daily_spo2", startDate: startDate, endDate: endDate, calendar: calendar, type: OuraDailySpo2.self)
        let stressResult = try await fetchListIfAllowed(scopes.contains(.daily), path: "daily_stress", startDate: startDate, endDate: endDate, calendar: calendar, type: OuraDailyStress.self)
        let resilienceResult = try await fetchListIfAllowed(scopes.contains(.daily), path: "daily_resilience", startDate: startDate, endDate: endDate, calendar: calendar, type: OuraDailyResilience.self)
        let ringsResult = try await fetchListIfAllowed(scopes.contains(.ringConfiguration), path: "ring_configuration", startDate: startDate, endDate: endDate, calendar: calendar, type: OuraRingConfiguration.self)

        return OuraRawSyncBundle(
            personalInfo: personalInfoResult.value,
            dailySleep: dailySleepResult.values,
            sleepPeriods: sleepResult.values,
            dailyReadiness: readinessResult.values,
            dailyActivity: activityResult.values,
            heartRates: heartRatesResult.values,
            workouts: workoutsResult.values,
            sessions: sessionsResult.values,
            dailySpo2: spo2Result.values,
            dailyStress: stressResult.values,
            dailyResilience: resilienceResult.values,
            ringConfigurations: ringsResult.values,
            endpointDebugRows: [
                personalInfoResult.debugRow,
                dailySleepResult.debugRow,
                sleepResult.debugRow,
                readinessResult.debugRow,
                activityResult.debugRow,
                heartRatesResult.debugRow,
                workoutsResult.debugRow,
                sessionsResult.debugRow,
                spo2Result.debugRow,
                stressResult.debugRow,
                resilienceResult.debugRow,
                ringsResult.debugRow
            ]
        )
    }

    private func fetchPersonalInfo() async throws -> OuraPersonalInfo? {
        let data = try await get(path: "personal_info", queryItems: [])
        if let wrapped = try? OuraJSON.decoder.decode(OuraSingleResponse<OuraPersonalInfo>.self, from: data) {
            return wrapped.data
        }
        return try OuraJSON.decoder.decode(OuraPersonalInfo.self, from: data)
    }

    private func fetchOptionalIfAllowed<Value>(
        _ isAllowed: Bool,
        path: String,
        operation: () async throws -> Value?
    ) async throws -> OuraOptionalFetchResult<Value> {
        guard isAllowed else {
            return OuraOptionalFetchResult(
                value: nil,
                debugRow: debugRow(path: path, count: 0, status: .skipped, detail: "Scope not granted or not requested.")
            )
        }
        do {
            let value = try await operation()
            return OuraOptionalFetchResult(
                value: value,
                debugRow: debugRow(path: path, count: value == nil ? 0 : 1, status: .succeeded, detail: nil)
            )
        } catch let error as OuraAPIError {
            if error.isRecoverableOptionalEndpointFailure {
                PulsarOuraLogger.log("Optional Oura endpoint skipped: \(error.localizedDescription)")
                return OuraOptionalFetchResult(
                    value: nil,
                    debugRow: debugRow(path: path, count: 0, status: .unavailable, detail: error.localizedDescription)
                )
            }
            throw error
        }
    }

    private func fetchListIfAllowed<Value: Codable>(
        _ isAllowed: Bool,
        path: String,
        startDate: Date,
        endDate: Date,
        calendar: Calendar,
        type: Value.Type
    ) async throws -> OuraListFetchResult<Value> {
        guard isAllowed else {
            return OuraListFetchResult(
                values: [],
                debugRow: debugRow(path: path, count: 0, status: .skipped, detail: "Scope not granted or not requested.")
            )
        }
        do {
            let values = try await fetchList(path: path, startDate: startDate, endDate: endDate, calendar: calendar, type: type)
            let newestTimestamp = Self.newestDebugTimestamp(in: values)
            let newestText = newestTimestamp.map { " newest=\($0)" } ?? ""
            PulsarOuraLogger.log("Oura endpoint \(path) succeeded samples=\(values.count)\(newestText)")
            return OuraListFetchResult(
                values: values,
                debugRow: debugRow(path: path, count: values.count, status: .succeeded, detail: newestTimestamp.map { "Newest \($0)" })
            )
        } catch let error as OuraAPIError {
            if error.isRecoverableOptionalEndpointFailure(for: path) || (error.isDecodingFailure && Self.canSkipDecodeFailure(for: path)) {
                PulsarOuraLogger.log("Oura endpoint \(path) unavailable for this account or scope: \(error.localizedDescription)")
                return OuraListFetchResult(
                    values: [],
                    debugRow: debugRow(path: path, count: 0, status: .unavailable, detail: error.localizedDescription)
                )
            }
            PulsarOuraLogger.log("Oura endpoint \(path) failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func fetchList<Value: Codable>(
        path: String,
        startDate: Date,
        endDate: Date,
        calendar: Calendar,
        type: Value.Type
    ) async throws -> [Value] {
        var collected: [Value] = []
        var nextToken: String?

        repeat {
            var queryItems = [
                URLQueryItem(name: "start_date", value: OuraDateParser.dayString(for: startDate, calendar: calendar)),
                URLQueryItem(name: "end_date", value: OuraDateParser.dayString(for: endDate, calendar: calendar))
            ]
            if let nextToken {
                queryItems.append(URLQueryItem(name: "next_token", value: nextToken))
            }
            let data = try await get(path: path, queryItems: queryItems)
            let response: OuraListResponse<Value>
            do {
                response = try OuraJSON.decoder.decode(OuraListResponse<Value>.self, from: data)
            } catch {
                PulsarOuraLogger.log("Oura endpoint \(path) decode failed for \(Value.self): \(error.localizedDescription)")
                throw OuraAPIError.decoding(error.localizedDescription)
            }
            collected.append(contentsOf: response.data)
            nextToken = response.nextToken
        } while nextToken?.isEmpty == false

        return collected
    }

    private func get(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        let token = try await authService.validAccessToken()
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v2").appendingPathComponent("usercollection").appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else {
            throw OuraAPIError.transport("Could not build Oura API URL for \(path).")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OuraAPIError.transport("Oura returned an invalid response.")
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let apiError = OuraAPIError.from(
                    statusCode: httpResponse.statusCode,
                    data: data,
                    retryAfter: retryAfterDate(from: httpResponse)
                )
                if !apiError.isRecoverableOptionalEndpointFailure(for: path) {
                    PulsarOuraLogger.log("Oura endpoint \(path) returned status=\(httpResponse.statusCode)")
                }
                throw apiError
            }
            return data
        } catch let error as OuraAPIError {
            throw error
        } catch {
            throw OuraAPIError.transport(error.localizedDescription)
        }
    }

    private func retryAfterDate(from response: HTTPURLResponse) -> Date? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(value) {
            return Date().addingTimeInterval(seconds)
        }
        return OuraDateParser.dateTime(from: value)
    }

    private static func canSkipDecodeFailure(for path: String) -> Bool {
        [
            "daily_spo2",
            "daily_stress",
            "daily_resilience",
            "session",
            "ring_configuration"
        ].contains(path)
    }

    private static func newestDebugTimestamp<Value>(in values: [Value]) -> Date? {
        values.compactMap { value -> Date? in
            switch value {
            case let activity as OuraDailyActivity:
                return activity.timestamp
            case let heartRate as OuraHeartRate:
                return heartRate.timestamp
            case let workout as OuraWorkout:
                return [workout.endDateTime, workout.startDateTime].compactMap { $0 }.max()
            case let session as OuraSession:
                return [session.endDateTime, session.startDateTime].compactMap { $0 }.max()
            case let sleep as OuraSleepPeriod:
                return [sleep.bedtimeEnd, sleep.bedtimeStart].compactMap { $0 }.max()
            case let ring as OuraRingConfiguration:
                return ring.setUpAt
            default:
                return nil
            }
        }.max()
    }

    private func debugRow(
        path: String,
        count: Int,
        status: OuraEndpointDebugStatus,
        detail: String?
    ) -> OuraEndpointDebugRow {
        OuraEndpointDebugRow(
            path: path,
            title: Self.endpointTitle(for: path),
            sampleCount: count,
            status: status,
            detail: detail
        )
    }

    private static func endpointTitle(for path: String) -> String {
        switch path {
        case "personal_info":
            return "Profile"
        case "daily_sleep":
            return "Daily sleep"
        case "sleep":
            return "Sleep periods"
        case "daily_readiness":
            return "Readiness"
        case "daily_activity":
            return "Activity"
        case "heartrate":
            return "Heart rate"
        case "workout":
            return "Workouts"
        case "session":
            return "Sessions"
        case "daily_spo2":
            return "SpO2"
        case "daily_stress":
            return "Stress"
        case "daily_resilience":
            return "Resilience"
        case "ring_configuration":
            return "Ring"
        default:
            return path
        }
    }

    private struct OuraSingleResponse<Value: Codable>: Codable {
        var data: Value
    }

    private struct OuraOptionalFetchResult<Value> {
        var value: Value?
        var debugRow: OuraEndpointDebugRow
    }

    private struct OuraListFetchResult<Value> {
        var values: [Value]
        var debugRow: OuraEndpointDebugRow
    }
}

private extension OuraAPIError {
    var isRecoverableOptionalEndpointFailure: Bool {
        switch self {
        case .forbidden, .server(statusCode: 404, message: _):
            return true
        default:
            return false
        }
    }

    func isRecoverableOptionalEndpointFailure(for path: String) -> Bool {
        if isRecoverableOptionalEndpointFailure {
            return true
        }

        guard Self.isStressEndpoint(path) else { return false }
        guard case .unauthorized(let message) = self else { return false }
        let normalizedMessage = message.lowercased()
        return normalizedMessage.contains("stress scope") ||
            normalizedMessage.contains("missing scope") ||
            normalizedMessage.contains("missing required scopes")
    }

    var isDecodingFailure: Bool {
        if case .decoding = self { return true }
        return false
    }

    private static func isStressEndpoint(_ path: String) -> Bool {
        path == "daily_stress" || path == "daily_resilience"
    }
}

final class MockOuraAPIClient: OuraAPIClientProtocol {
    var bundle: OuraRawSyncBundle

    init(now: Date = Date(), calendar: Calendar = .current) {
        let day = OuraDateParser.dayString(for: now, calendar: calendar)
        let sleepStart = calendar.date(byAdding: .hour, value: -8, to: now) ?? now.addingTimeInterval(-28_800)
        let sleepEnd = calendar.date(byAdding: .minute, value: -35, to: now) ?? now.addingTimeInterval(-2_100)
        self.bundle = OuraRawSyncBundle(
            personalInfo: OuraPersonalInfo(id: "mock-oura-user", age: nil, weight: nil, height: nil, biologicalSex: nil, email: nil),
            dailySleep: [
                OuraDailySleep(
                    id: "mock-daily-sleep-\(day)",
                    day: day,
                    score: 88,
                    timestamp: now,
                    contributors: OuraDailySleep.Contributors(
                        deepSleep: 86,
                        efficiency: 90,
                        latency: 82,
                        remSleep: 84,
                        restfulness: 87,
                        timing: 78,
                        totalSleep: 91
                    )
                )
            ],
            sleepPeriods: [
                OuraSleepPeriod(
                    id: "mock-sleep-\(day)",
                    day: day,
                    type: "long_sleep",
                    bedtimeStart: sleepStart,
                    bedtimeEnd: sleepEnd,
                    totalSleepDuration: 7.4 * 3_600,
                    timeInBed: 8.0 * 3_600,
                    awakeTime: 36 * 60,
                    restlessPeriods: 12,
                    remSleepDuration: 102 * 60,
                    deepSleepDuration: 88 * 60,
                    lightSleepDuration: 254 * 60,
                    efficiency: 92,
                    averageHeartRate: 57,
                    lowestHeartRate: 49,
                    averageHRV: 62,
                    respiratoryRate: 14.2,
                    temperatureDeviation: 0.1,
                    temperatureTrendDeviation: 0.05,
                    sleepPhase5Min: String(repeating: "2", count: 48) + String(repeating: "1", count: 14) + String(repeating: "3", count: 18) + String(repeating: "4", count: 4)
                )
            ],
            dailyReadiness: [
                OuraDailyReadiness(
                    id: "mock-readiness-\(day)",
                    day: day,
                    score: 86,
                    temperatureDeviation: 0.1,
                    temperatureTrendDeviation: 0.05,
                    timestamp: now,
                    contributors: OuraDailyReadiness.Contributors(
                        activityBalance: 82,
                        bodyTemperature: 91,
                        hrvBalance: 84,
                        previousDayActivity: 75,
                        previousNight: 88,
                        recoveryIndex: 89,
                        restingHeartRate: 87,
                        sleepBalance: 86,
                        sleepRegularity: 78
                    )
                )
            ],
            dailyActivity: [
                OuraDailyActivity(
                    id: "mock-activity-\(day)",
                    day: day,
                    score: 78,
                    activeCalories: 540,
                    totalCalories: 2_340,
                    steps: 8_900,
                    equivalentWalkingDistance: 7_100,
                    highActivityTime: 18 * 60,
                    mediumActivityTime: 46 * 60,
                    lowActivityTime: 210 * 60,
                    sedentaryTime: 510 * 60,
                    targetCalories: 500,
                    timestamp: now
                )
            ],
            heartRates: [
                OuraHeartRate(bpm: 58, source: "sleep", timestamp: sleepStart.addingTimeInterval(3_600)),
                OuraHeartRate(bpm: 72, source: "awake", timestamp: now.addingTimeInterval(-1_800))
            ],
            workouts: [
                OuraWorkout(
                    id: "mock-workout-\(day)",
                    activity: "walking",
                    calories: 180,
                    day: day,
                    distance: 2_400,
                    intensity: "moderate",
                    label: "Walk",
                    source: "automatic",
                    startDateTime: now.addingTimeInterval(-7_200),
                    endDateTime: now.addingTimeInterval(-5_900)
                )
            ],
            sessions: [],
            dailySpo2: [
                OuraDailySpo2(id: "mock-spo2-\(day)", day: day, spo2Percentage: OuraDailySpo2.Spo2Percentage(average: 97.4), breathingDisturbanceIndex: 3)
            ],
            dailyStress: [
                OuraDailyStress(
                    id: "mock-stress-\(day)",
                    day: day,
                    stressHigh: 42 * 60,
                    recoveryHigh: 96 * 60,
                    daySummary: "normal"
                )
            ],
            dailyResilience: [
                OuraDailyResilience(
                    id: "mock-resilience-\(day)",
                    day: day,
                    contributors: OuraDailyResilience.Contributors(
                        sleepRecovery: 0.82,
                        daytimeRecovery: 0.76,
                        stress: 0.68
                    ),
                    level: "strong"
                )
            ],
            ringConfigurations: []
        )
    }

    func fetchBundle(startDate: Date, endDate: Date, scopes: Set<OuraScope>, calendar: Calendar) async throws -> OuraRawSyncBundle {
        bundle
    }
}
