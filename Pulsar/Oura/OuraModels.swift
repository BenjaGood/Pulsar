//
//  OuraModels.swift
//  Pulsar
//

import Foundation

enum PulsarOuraLogger {
    nonisolated static func log(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[PulsarOura] \(message())")
        #endif
    }
}

nonisolated extension OuraScope {
    static let pulsarOAuthScopes: Set<OuraScope> = [
        .email,
        .personal,
        .daily,
        .heartrate,
        .workout,
        .tag,
        .session,
        .spo2
    ]

    static func parseList(_ value: String) -> Set<OuraScope> {
        Set(value.split { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" }
            .compactMap { OuraScope(rawValue: String($0)) })
    }

    var displayName: String {
        switch self {
        case .daily:
            return "Daily sleep, readiness, and activity"
        case .heartrate:
            return "Heart rate"
        case .workout:
            return "Workouts"
        case .spo2:
            return "SpO2"
        case .personal:
            return "Profile"
        case .email:
            return "Email"
        case .tag:
            return "Tags"
        case .session:
            return "Sessions"
        case .ringConfiguration:
            return "Ring configuration"
        }
    }
}

enum OuraAPIEndpoint {
    static let authorize = URL(string: "https://cloud.ouraring.com/oauth/authorize")!
    static let apiBaseURL = URL(string: "https://api.ouraring.com")!
    static let userCollectionBasePath = "/v2/usercollection"
}

nonisolated struct OuraIntegrationConfiguration: Equatable {
    var clientID: String?
    var redirectURI: URL?
    var requestedScopes: Set<OuraScope>
    var backendBaseURL: URL?
    var backendHealthEndpoint: URL?
    var backendTokenExchangeEndpoint: URL?
    var backendRefreshEndpoint: URL?
    var backendRevokeEndpoint: URL?
    var mockMode: Bool

    static let notConfigured = OuraIntegrationConfiguration(mockMode: false)

    init(
        clientID: String? = nil,
        redirectURI: URL? = nil,
        requestedScopes: Set<OuraScope> = OuraScope.pulsarOAuthScopes,
        backendBaseURL: URL? = nil,
        backendHealthEndpoint: URL? = nil,
        backendTokenExchangeEndpoint: URL? = nil,
        backendRefreshEndpoint: URL? = nil,
        backendRevokeEndpoint: URL? = nil,
        mockMode: Bool = false
    ) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.requestedScopes = requestedScopes
        self.backendBaseURL = backendBaseURL
        self.backendHealthEndpoint = backendHealthEndpoint
            ?? Self.endpoint(baseURL: backendBaseURL, path: "health")
        self.backendTokenExchangeEndpoint = backendTokenExchangeEndpoint
            ?? Self.endpoint(baseURL: backendBaseURL, path: "oura/token/exchange")
        self.backendRefreshEndpoint = backendRefreshEndpoint
            ?? Self.endpoint(baseURL: backendBaseURL, path: "oura/token/refresh")
        self.backendRevokeEndpoint = backendRevokeEndpoint
            ?? Self.endpoint(baseURL: backendBaseURL, path: "oura/disconnect")
        self.mockMode = mockMode
    }

    var callbackURLScheme: String? {
        redirectURI?.scheme
    }

    var isReadyForOAuth: Bool {
        canStartAuthorization && canExchangeTokens
    }

    var canStartAuthorization: Bool {
        if mockMode { return true }
        return clientID?.isEmpty == false && redirectURI != nil
    }

    var canExchangeTokens: Bool {
        if mockMode { return true }
        return backendHealthEndpoint != nil && backendTokenExchangeEndpoint != nil && backendRefreshEndpoint != nil
    }

    func missingConfigurationKeys(bundle: Bundle = .main) -> [String] {
        if mockMode { return [] }

        var keys: [String] = []
        if clientID?.isEmpty != false {
            keys.append("OuraOAuthClientID")
        }
        if redirectURI == nil {
            keys.append("OuraOAuthRedirectURI")
        }
        if backendBaseURL == nil && (backendHealthEndpoint == nil || backendTokenExchangeEndpoint == nil || backendRefreshEndpoint == nil) {
            keys.append("OuraBackendBaseURL")
        }
        if let scheme = callbackURLScheme,
           !Self.registeredURLSchemes(bundle: bundle).contains(scheme) {
            keys.append("CFBundleURLTypes.\(scheme)")
        }
        return keys
    }

    nonisolated static func load(bundle: Bundle = .main, defaults: UserDefaults = .standard) -> OuraIntegrationConfiguration {
        let mockMode = defaults.bool(forKey: OuraDefaultsKeys.mockMode) ||
            boolValue(named: "OuraMockMode", bundle: bundle)
        let backendBaseURL = urlValue(named: "OuraBackendBaseURL", bundle: bundle)
        let configuredScopes = stringValue(named: "OuraOAuthScopes", bundle: bundle)
            .map(OuraScope.parseList)
        let requestedScopes = configuredScopes?.isEmpty == false ? configuredScopes! : OuraScope.pulsarOAuthScopes
        return OuraIntegrationConfiguration(
            clientID: stringValue(named: "OuraOAuthClientID", bundle: bundle),
            redirectURI: urlValue(named: "OuraOAuthRedirectURI", bundle: bundle),
            requestedScopes: requestedScopes,
            backendBaseURL: backendBaseURL,
            backendHealthEndpoint: urlValue(named: "OuraBackendHealthURL", bundle: bundle),
            backendTokenExchangeEndpoint: urlValue(named: "OuraBackendTokenExchangeURL", bundle: bundle),
            backendRefreshEndpoint: urlValue(named: "OuraBackendTokenRefreshURL", bundle: bundle),
            backendRevokeEndpoint: urlValue(named: "OuraBackendTokenRevokeURL", bundle: bundle),
            mockMode: mockMode
        )
    }

    private static func stringValue(named key: String, bundle: Bundle) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private static func urlValue(named key: String, bundle: Bundle) -> URL? {
        stringValue(named: key, bundle: bundle).flatMap(URL.init(string:))
    }

    private static func boolValue(named key: String, bundle: Bundle) -> Bool {
        if let value = bundle.object(forInfoDictionaryKey: key) as? Bool {
            return value
        }
        if let value = bundle.object(forInfoDictionaryKey: key) as? String {
            return ["1", "true", "yes"].contains(value.lowercased())
        }
        return false
    }

    private static func registeredURLSchemes(bundle: Bundle) -> Set<String> {
        guard let urlTypes = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return []
        }
        return Set(urlTypes.flatMap { urlType in
            urlType["CFBundleURLSchemes"] as? [String] ?? []
        })
    }

    private static func endpoint(baseURL: URL?, path: String) -> URL? {
        guard let baseURL,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, endpointPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

nonisolated enum OuraDefaultsKeys {
    static let mockMode = "pulsar.oura.mockMode.v1"
    static let connectionStatus = "pulsar.oura.connectionStatus.v1"
    static let lastSyncAt = "pulsar.oura.lastSyncAt.v1"
    static let lastErrorMessage = "pulsar.oura.lastErrorMessage.v1"
    static let lastAuthorizedScopes = "pulsar.oura.lastAuthorizedScopes.v1"
}

enum OuraConnectionStatus: String, Codable, Equatable {
    case notConnected
    case connecting
    case connected
    case syncError
    case tokenExpired
}

struct OuraStoredToken: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var scopes: Set<OuraScope>
    var tokenType: String

    var isExpired: Bool {
        Date() >= expiresAt
    }

    func expiresSoon(now: Date = Date(), leeway: TimeInterval = 300) -> Bool {
        now.addingTimeInterval(leeway) >= expiresAt
    }
}

struct OuraOAuthTokenResponse: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresIn: TimeInterval
    var tokenType: String
    var scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }

    func storedToken(receivedAt: Date = Date(), fallbackScopes: Set<OuraScope>) -> OuraStoredToken {
        let parsedScopes = scope.map(Self.parseScopes)
        let resolvedScopes = parsedScopes?.isEmpty == false ? parsedScopes! : fallbackScopes
        return OuraStoredToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: receivedAt.addingTimeInterval(expiresIn),
            scopes: resolvedScopes,
            tokenType: tokenType
        )
    }

    nonisolated static func parseScopes(_ value: String) -> Set<OuraScope> {
        OuraScope.parseList(value)
    }
}

struct OuraBackendHealthResponse: Codable, Equatable {
    var ok: Bool
    var service: String?
    var configured: Bool?
    var missing: [String]?

    var isReady: Bool {
        ok && configured != false
    }
}

struct OuraOAuthCallback: Equatable {
    var code: String
    var state: String?
    var scopes: Set<OuraScope>
}

enum OuraOAuthCallbackError: LocalizedError, Equatable {
    case accessDenied
    case missingCode
    case stateMismatch
    case oauthError(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Oura authorization was canceled."
        case .missingCode:
            return "Oura did not return an authorization code."
        case .stateMismatch:
            return "Oura authorization could not be verified. Please try again."
        case .oauthError(let error):
            return "Oura authorization failed: \(error)"
        }
    }
}

enum OuraOAuthCallbackParser {
    static func parse(_ url: URL, expectedState: String?) throws -> OuraOAuthCallback {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw OuraOAuthCallbackError.missingCode
        }
        let items = components.queryItems ?? []
        let value: (String) -> String? = { name in
            items.first(where: { $0.name == name })?.value
        }

        if let error = value("error") {
            if error == "access_denied" {
                throw OuraOAuthCallbackError.accessDenied
            }
            throw OuraOAuthCallbackError.oauthError(error)
        }

        let returnedState = value("state")
        if let expectedState, returnedState != expectedState {
            throw OuraOAuthCallbackError.stateMismatch
        }

        guard let code = value("code"), !code.isEmpty else {
            throw OuraOAuthCallbackError.missingCode
        }

        let scopes = value("scope").map(OuraOAuthTokenResponse.parseScopes) ?? []
        return OuraOAuthCallback(code: code, state: returnedState, scopes: scopes)
    }
}

enum OuraAPIError: LocalizedError, Equatable {
    case notConfigured(String)
    case unauthorized(String)
    case forbidden(String)
    case rateLimited(retryAfter: Date?, message: String)
    case server(statusCode: Int, message: String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let message):
            return message
        case .unauthorized(let message):
            return message
        case .forbidden(let message):
            return message
        case .rateLimited(_, let message):
            return message
        case .server(let statusCode, let message):
            return "Oura API error \(statusCode): \(message)"
        case .decoding(let message):
            return "Could not decode Oura data: \(message)"
        case .transport(let message):
            return message
        }
    }

    static func from(statusCode: Int, data: Data, retryAfter: Date? = nil) -> OuraAPIError {
        let response = (try? OuraJSON.decoder.decode(OuraErrorResponse.self, from: data))
        let message = response?.detail ?? response?.errorDescription ?? response?.title ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)

        switch statusCode {
        case 401:
            return .unauthorized(message)
        case 403:
            return .forbidden(message)
        case 429:
            return .rateLimited(retryAfter: retryAfter, message: message)
        default:
            return .server(statusCode: statusCode, message: message)
        }
    }
}

struct OuraErrorResponse: nonisolated Codable, Equatable {
    var status: Int?
    var title: String?
    var detail: String?
    var error: String?
    var errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case status
        case title
        case detail
        case error
        case errorDescription = "error_description"
    }
}

enum OuraJSON {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = OuraDateParser.dateTime(from: value) ?? OuraDateParser.dayDate(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid Oura date: \(value)")
        }
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

enum OuraDateParser {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterWithoutFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dateTime(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return isoFormatter.date(from: value) ?? isoFormatterWithoutFraction.date(from: value)
    }

    static func dayDate(from value: String?, calendar: Calendar = .current) -> Date? {
        guard let value, let parsed = dayFormatter.date(from: value) else { return nil }
        return calendar.startOfDay(for: parsed)
    }

    nonisolated static func dayString(for date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        guard let year = components.year,
              let month = components.month,
              let dayNumber = components.day else { return "" }
        return String(format: "%04d-%02d-%02d", year, month, dayNumber)
    }
}

struct OuraListResponse<Value: Codable>: Codable {
    var data: [Value]
    var nextToken: String?

    enum CodingKeys: String, CodingKey {
        case data
        case nextToken = "next_token"
    }
}

nonisolated struct OuraPersonalInfo: Codable, Equatable {
    var id: String?
    var age: Int?
    var weight: Double?
    var height: Double?
    var biologicalSex: String?
    var email: String?

    enum CodingKeys: String, CodingKey {
        case id
        case age
        case weight
        case height
        case biologicalSex = "biological_sex"
        case email
    }
}

struct OuraDailySleep: Codable, Equatable {
    var id: String?
    var day: String
    var score: Int?
    var timestamp: Date?
    var contributors: Contributors?

    struct Contributors: Codable, Equatable {
        var deepSleep: Int?
        var efficiency: Int?
        var latency: Int?
        var remSleep: Int?
        var restfulness: Int?
        var timing: Int?
        var totalSleep: Int?

        enum CodingKeys: String, CodingKey {
            case deepSleep = "deep_sleep"
            case efficiency
            case latency
            case remSleep = "rem_sleep"
            case restfulness
            case timing
            case totalSleep = "total_sleep"
        }
    }
}

struct OuraSleepPeriod: Codable, Equatable {
    var id: String?
    var day: String
    var type: String?
    var bedtimeStart: Date?
    var bedtimeEnd: Date?
    var totalSleepDuration: TimeInterval?
    var timeInBed: TimeInterval?
    var awakeTime: TimeInterval?
    var restlessPeriods: Int?
    var remSleepDuration: TimeInterval?
    var deepSleepDuration: TimeInterval?
    var lightSleepDuration: TimeInterval?
    var efficiency: Int?
    var averageHeartRate: Double?
    var lowestHeartRate: Double?
    var averageHRV: Double?
    var respiratoryRate: Double?
    var temperatureDeviation: Double?
    var temperatureTrendDeviation: Double?
    var sleepPhase5Min: String?

    enum CodingKeys: String, CodingKey {
        case id
        case day
        case type
        case bedtimeStart = "bedtime_start"
        case bedtimeEnd = "bedtime_end"
        case totalSleepDuration = "total_sleep_duration"
        case timeInBed = "time_in_bed"
        case awakeTime = "awake_time"
        case restlessPeriods = "restless_periods"
        case remSleepDuration = "rem_sleep_duration"
        case deepSleepDuration = "deep_sleep_duration"
        case lightSleepDuration = "light_sleep_duration"
        case efficiency
        case averageHeartRate = "average_heart_rate"
        case lowestHeartRate = "lowest_heart_rate"
        case averageHRV = "average_hrv"
        case respiratoryRate = "respiratory_rate"
        case averageBreath = "average_breath"
        case temperatureDeviation = "temperature_deviation"
        case temperatureTrendDeviation = "temperature_trend_deviation"
        case sleepPhase5Min = "sleep_phase_5_min"
        case appSleepPhase5Min = "app_sleep_phase_5_min"
    }

    init(
        id: String?,
        day: String,
        type: String?,
        bedtimeStart: Date?,
        bedtimeEnd: Date?,
        totalSleepDuration: TimeInterval?,
        timeInBed: TimeInterval?,
        awakeTime: TimeInterval?,
        restlessPeriods: Int?,
        remSleepDuration: TimeInterval?,
        deepSleepDuration: TimeInterval?,
        lightSleepDuration: TimeInterval?,
        efficiency: Int?,
        averageHeartRate: Double?,
        lowestHeartRate: Double?,
        averageHRV: Double?,
        respiratoryRate: Double?,
        temperatureDeviation: Double?,
        temperatureTrendDeviation: Double?,
        sleepPhase5Min: String?
    ) {
        self.id = id
        self.day = day
        self.type = type
        self.bedtimeStart = bedtimeStart
        self.bedtimeEnd = bedtimeEnd
        self.totalSleepDuration = totalSleepDuration
        self.timeInBed = timeInBed
        self.awakeTime = awakeTime
        self.restlessPeriods = restlessPeriods
        self.remSleepDuration = remSleepDuration
        self.deepSleepDuration = deepSleepDuration
        self.lightSleepDuration = lightSleepDuration
        self.efficiency = efficiency
        self.averageHeartRate = averageHeartRate
        self.lowestHeartRate = lowestHeartRate
        self.averageHRV = averageHRV
        self.respiratoryRate = respiratoryRate
        self.temperatureDeviation = temperatureDeviation
        self.temperatureTrendDeviation = temperatureTrendDeviation
        self.sleepPhase5Min = sleepPhase5Min
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        day = try container.decode(String.self, forKey: .day)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        bedtimeStart = try container.decodeIfPresent(Date.self, forKey: .bedtimeStart)
        bedtimeEnd = try container.decodeIfPresent(Date.self, forKey: .bedtimeEnd)
        totalSleepDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .totalSleepDuration)
        timeInBed = try container.decodeIfPresent(TimeInterval.self, forKey: .timeInBed)
        awakeTime = try container.decodeIfPresent(TimeInterval.self, forKey: .awakeTime)
        restlessPeriods = try container.decodeIfPresent(Int.self, forKey: .restlessPeriods)
        remSleepDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .remSleepDuration)
        deepSleepDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .deepSleepDuration)
        lightSleepDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .lightSleepDuration)
        efficiency = try container.decodeIfPresent(Int.self, forKey: .efficiency)
        averageHeartRate = try container.decodeIfPresent(Double.self, forKey: .averageHeartRate)
        lowestHeartRate = try container.decodeIfPresent(Double.self, forKey: .lowestHeartRate)
        averageHRV = try container.decodeIfPresent(Double.self, forKey: .averageHRV)
        respiratoryRate = try container.decodeIfPresent(Double.self, forKey: .averageBreath)
            ?? container.decodeIfPresent(Double.self, forKey: .respiratoryRate)
        temperatureDeviation = try container.decodeIfPresent(Double.self, forKey: .temperatureDeviation)
        temperatureTrendDeviation = try container.decodeIfPresent(Double.self, forKey: .temperatureTrendDeviation)
        sleepPhase5Min = try container.decodeIfPresent(String.self, forKey: .sleepPhase5Min)
            ?? container.decodeIfPresent(String.self, forKey: .appSleepPhase5Min)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(day, forKey: .day)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(bedtimeStart, forKey: .bedtimeStart)
        try container.encodeIfPresent(bedtimeEnd, forKey: .bedtimeEnd)
        try container.encodeIfPresent(totalSleepDuration, forKey: .totalSleepDuration)
        try container.encodeIfPresent(timeInBed, forKey: .timeInBed)
        try container.encodeIfPresent(awakeTime, forKey: .awakeTime)
        try container.encodeIfPresent(restlessPeriods, forKey: .restlessPeriods)
        try container.encodeIfPresent(remSleepDuration, forKey: .remSleepDuration)
        try container.encodeIfPresent(deepSleepDuration, forKey: .deepSleepDuration)
        try container.encodeIfPresent(lightSleepDuration, forKey: .lightSleepDuration)
        try container.encodeIfPresent(efficiency, forKey: .efficiency)
        try container.encodeIfPresent(averageHeartRate, forKey: .averageHeartRate)
        try container.encodeIfPresent(lowestHeartRate, forKey: .lowestHeartRate)
        try container.encodeIfPresent(averageHRV, forKey: .averageHRV)
        try container.encodeIfPresent(respiratoryRate, forKey: .averageBreath)
        try container.encodeIfPresent(temperatureDeviation, forKey: .temperatureDeviation)
        try container.encodeIfPresent(temperatureTrendDeviation, forKey: .temperatureTrendDeviation)
        try container.encodeIfPresent(sleepPhase5Min, forKey: .sleepPhase5Min)
    }
}

struct OuraDailyReadiness: Codable, Equatable {
    var id: String?
    var day: String
    var score: Int?
    var temperatureDeviation: Double?
    var temperatureTrendDeviation: Double?
    var timestamp: Date?
    var contributors: Contributors?

    struct Contributors: Codable, Equatable {
        var activityBalance: Int?
        var bodyTemperature: Int?
        var hrvBalance: Int?
        var previousDayActivity: Int?
        var previousNight: Int?
        var recoveryIndex: Int?
        var restingHeartRate: Int?
        var sleepBalance: Int?
        var sleepRegularity: Int?

        enum CodingKeys: String, CodingKey {
            case activityBalance = "activity_balance"
            case bodyTemperature = "body_temperature"
            case hrvBalance = "hrv_balance"
            case previousDayActivity = "previous_day_activity"
            case previousNight = "previous_night"
            case recoveryIndex = "recovery_index"
            case restingHeartRate = "resting_heart_rate"
            case sleepBalance = "sleep_balance"
            case sleepRegularity = "sleep_regularity"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case day
        case score
        case temperatureDeviation = "temperature_deviation"
        case temperatureTrendDeviation = "temperature_trend_deviation"
        case timestamp
        case contributors
    }
}

struct OuraDailyActivity: Codable, Equatable {
    var id: String?
    var day: String
    var score: Int?
    var activeCalories: Double?
    var totalCalories: Double?
    var steps: Int?
    var equivalentWalkingDistance: Double?
    var highActivityTime: TimeInterval?
    var mediumActivityTime: TimeInterval?
    var lowActivityTime: TimeInterval?
    var sedentaryTime: TimeInterval?
    var targetCalories: Double?
    var timestamp: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case day
        case score
        case activeCalories = "active_calories"
        case totalCalories = "total_calories"
        case steps
        case equivalentWalkingDistance = "equivalent_walking_distance"
        case highActivityTime = "high_activity_time"
        case mediumActivityTime = "medium_activity_time"
        case lowActivityTime = "low_activity_time"
        case sedentaryTime = "sedentary_time"
        case targetCalories = "target_calories"
        case timestamp
    }
}

struct OuraHeartRate: Codable, Equatable {
    var bpm: Double
    var source: String?
    var timestamp: Date
}

struct OuraWorkout: Codable, Equatable {
    var id: String?
    var activity: String?
    var calories: Double?
    var day: String?
    var distance: Double?
    var intensity: String?
    var label: String?
    var source: String?
    var startDateTime: Date?
    var endDateTime: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case activity
        case calories
        case day
        case distance
        case intensity
        case label
        case source
        case startDateTime = "start_datetime"
        case endDateTime = "end_datetime"
    }
}

struct OuraSession: Codable, Equatable {
    var id: String?
    var day: String?
    var type: String?
    var startDateTime: Date?
    var endDateTime: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case day
        case type
        case startDateTime = "start_datetime"
        case endDateTime = "end_datetime"
    }
}

struct OuraDailySpo2: Codable, Equatable {
    var id: String?
    var day: String
    var spo2Percentage: Spo2Percentage?
    var breathingDisturbanceIndex: Double?

    struct Spo2Percentage: Codable, Equatable {
        var average: Double?
    }

    enum CodingKeys: String, CodingKey {
        case id
        case day
        case spo2Percentage = "spo2_percentage"
        case breathingDisturbanceIndex = "breathing_disturbance_index"
    }
}

struct OuraDailyStress: Codable, Equatable {
    var id: String?
    var day: String
    var stressHigh: TimeInterval?
    var recoveryHigh: TimeInterval?
    var daySummary: String?

    enum CodingKeys: String, CodingKey {
        case id
        case day
        case stressHigh = "stress_high"
        case recoveryHigh = "recovery_high"
        case daySummary = "day_summary"
    }
}

struct OuraDailyResilience: Codable, Equatable {
    var id: String?
    var day: String
    var contributors: Contributors?
    var level: String?

    struct Contributors: Codable, Equatable {
        var sleepRecovery: Double?
        var daytimeRecovery: Double?
        var stress: Double?

        enum CodingKeys: String, CodingKey {
            case sleepRecovery = "sleep_recovery"
            case daytimeRecovery = "daytime_recovery"
            case stress
        }
    }
}

struct OuraRingConfiguration: Codable, Equatable {
    var id: String?
    var ringID: String?
    var firmwareVersion: String?
    var hardwareType: String?
    var setUpAt: Date?
    var size: Int?
    var color: String?
    var design: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ringID = "ring_id"
        case firmwareVersion = "firmware_version"
        case hardwareType = "hardware_type"
        case setUpAt = "set_up_at"
        case size
        case color
        case design
    }
}

struct OuraRawSyncBundle: Equatable {
    var personalInfo: OuraPersonalInfo?
    var dailySleep: [OuraDailySleep]
    var sleepPeriods: [OuraSleepPeriod]
    var dailyReadiness: [OuraDailyReadiness]
    var dailyActivity: [OuraDailyActivity]
    var heartRates: [OuraHeartRate]
    var workouts: [OuraWorkout]
    var sessions: [OuraSession]
    var dailySpo2: [OuraDailySpo2]
    var dailyStress: [OuraDailyStress]
    var dailyResilience: [OuraDailyResilience]
    var ringConfigurations: [OuraRingConfiguration]
    var endpointDebugRows: [OuraEndpointDebugRow] = []
}

struct OuraMappedHealthData: Equatable {
    var payload: PulsarDailyMetricsSyncPayload?
    var samples: [CanonicalHealthSample]
    var ringBatteryPercentage: Int?
    var mappedAt: Date
    var debugReport: OuraSyncDebugReport? = nil
}

enum OuraEndpointDebugStatus: String, Equatable {
    case succeeded
    case skipped
    case unavailable
    case failed

    var displayText: String {
        switch self {
        case .succeeded:
            return "OK"
        case .skipped:
            return "Skipped"
        case .unavailable:
            return "Unavailable"
        case .failed:
            return "Failed"
        }
    }
}

nonisolated struct OuraEndpointDebugRow: Equatable {
    var path: String
    var title: String
    var sampleCount: Int
    var status: OuraEndpointDebugStatus
    var detail: String?
}

nonisolated struct OuraDebugValueRow: Equatable {
    var title: String
    var detail: String
    var isAvailable: Bool
}

nonisolated struct OuraSyncDebugReport: Identifiable, Equatable {
    var id = UUID()
    var reason: String
    var dateKey: String
    var windowStartKey: String
    var windowEndKey: String
    var syncedAt: Date
    var scopes: [String]
    var endpointRows: [OuraEndpointDebugRow]
    var providedRows: [OuraDebugValueRow]
    var mappedRows: [OuraDebugValueRow]
    var canonicalSampleRows: [OuraDebugValueRow]
    var summary: String

    static func make(
        reason: String,
        date: Date,
        windowStart: Date,
        windowEnd: Date,
        calendar: Calendar,
        scopes: Set<OuraScope>,
        bundle: OuraRawSyncBundle,
        mapped: OuraMappedHealthData
    ) -> OuraSyncDebugReport {
        let dateKey = OuraDateParser.dayString(for: date, calendar: calendar)
        let endpointRows = bundle.endpointDebugRows.isEmpty
            ? fallbackEndpointRows(for: bundle)
            : bundle.endpointDebugRows
        let providedRows = providedDataRows(bundle: bundle, date: date, dateKey: dateKey, calendar: calendar)
        let mappedRows = mappedDataRows(
            payload: mapped.payload,
            bundle: bundle,
            date: date,
            calendar: calendar
        )
        let canonicalSampleRows = canonicalRows(samples: mapped.samples)
        let unavailableMappedRows = mappedRows.filter { !$0.isAvailable }.map(\.title)
        let availableProvidedRows = providedRows
            .filter { $0.isAvailable && $0.title != "Profile" }
            .map(\.title)
        let summary: String
        if unavailableMappedRows.isEmpty {
            summary = "Oura returned enough data for every mapped Pulsar metric."
        } else if !availableProvidedRows.isEmpty {
            summary = "Oura returned \(availableProvidedRows.joined(separator: ", ")). Missing mapped data for \(unavailableMappedRows.joined(separator: ", ")); Pulsar will use fallback sources for those cards."
        } else {
            summary = "Missing mapped Oura data for \(unavailableMappedRows.joined(separator: ", ")). Pulsar will use fallback sources for those cards."
        }

        return OuraSyncDebugReport(
            reason: reason,
            dateKey: dateKey,
            windowStartKey: OuraDateParser.dayString(for: windowStart, calendar: calendar),
            windowEndKey: OuraDateParser.dayString(for: windowEnd, calendar: calendar),
            syncedAt: mapped.mappedAt,
            scopes: scopes.map(\.rawValue).sorted(),
            endpointRows: endpointRows,
            providedRows: providedRows,
            mappedRows: mappedRows,
            canonicalSampleRows: canonicalSampleRows,
            summary: summary
        )
    }

    static func skipped(reason: String, date: Date, calendar: Calendar, message: String) -> OuraSyncDebugReport {
        let dateKey = OuraDateParser.dayString(for: date, calendar: calendar)
        return OuraSyncDebugReport(
            reason: reason,
            dateKey: dateKey,
            windowStartKey: dateKey,
            windowEndKey: dateKey,
            syncedAt: Date(),
            scopes: [],
            endpointRows: [],
            providedRows: [
                OuraDebugValueRow(title: "Oura sync", detail: message, isAvailable: false)
            ],
            mappedRows: [],
            canonicalSampleRows: [],
            summary: message
        )
    }

    static func failed(
        reason: String,
        date: Date,
        calendar: Calendar,
        error: Error,
        scopes: Set<OuraScope> = []
    ) -> OuraSyncDebugReport {
        let dateKey = OuraDateParser.dayString(for: date, calendar: calendar)
        let message = error.localizedDescription
        return OuraSyncDebugReport(
            reason: reason,
            dateKey: dateKey,
            windowStartKey: dateKey,
            windowEndKey: dateKey,
            syncedAt: Date(),
            scopes: scopes.map(\.rawValue).sorted(),
            endpointRows: [
                OuraEndpointDebugRow(path: "sync", title: "Oura sync", sampleCount: 0, status: .failed, detail: message)
            ],
            providedRows: [
                OuraDebugValueRow(title: "Oura sync", detail: message, isAvailable: false)
            ],
            mappedRows: [],
            canonicalSampleRows: [],
            summary: "Oura sync failed: \(message)"
        )
    }

    private static func fallbackEndpointRows(for bundle: OuraRawSyncBundle) -> [OuraEndpointDebugRow] {
        [
            OuraEndpointDebugRow(path: "personal_info", title: "Profile", sampleCount: bundle.personalInfo == nil ? 0 : 1, status: .succeeded, detail: nil),
            OuraEndpointDebugRow(path: "daily_sleep", title: "Daily sleep", sampleCount: bundle.dailySleep.count, status: .succeeded, detail: nil),
            OuraEndpointDebugRow(path: "sleep", title: "Sleep periods", sampleCount: bundle.sleepPeriods.count, status: .succeeded, detail: nil),
            OuraEndpointDebugRow(path: "daily_readiness", title: "Readiness", sampleCount: bundle.dailyReadiness.count, status: .succeeded, detail: nil),
            OuraEndpointDebugRow(path: "daily_activity", title: "Activity", sampleCount: bundle.dailyActivity.count, status: .succeeded, detail: nil),
            OuraEndpointDebugRow(path: "heartrate", title: "Heart rate", sampleCount: bundle.heartRates.count, status: .succeeded, detail: nil),
            OuraEndpointDebugRow(path: "workout", title: "Workouts", sampleCount: bundle.workouts.count, status: .succeeded, detail: nil),
            OuraEndpointDebugRow(path: "session", title: "Sessions", sampleCount: bundle.sessions.count, status: .succeeded, detail: nil),
            OuraEndpointDebugRow(path: "daily_spo2", title: "SpO2", sampleCount: bundle.dailySpo2.count, status: .succeeded, detail: nil),
            OuraEndpointDebugRow(path: "daily_stress", title: "Stress", sampleCount: bundle.dailyStress.count, status: .succeeded, detail: nil),
            OuraEndpointDebugRow(path: "daily_resilience", title: "Resilience", sampleCount: bundle.dailyResilience.count, status: .succeeded, detail: nil),
            OuraEndpointDebugRow(path: "ring_configuration", title: "Ring", sampleCount: bundle.ringConfigurations.count, status: .succeeded, detail: nil)
        ]
    }

    private static func providedDataRows(
        bundle: OuraRawSyncBundle,
        date: Date,
        dateKey: String,
        calendar: Calendar
    ) -> [OuraDebugValueRow] {
        let dailySleep = bundle.dailySleep.first { $0.day == dateKey }
        let sleepPeriods = bundle.sleepPeriods.filter { $0.day == dateKey }
        let readiness = bundle.dailyReadiness.first { $0.day == dateKey }
        let activity = bundle.dailyActivity.first { $0.day == dateKey }
        let dayHeartRates = bundle.heartRates.filter { sample in
            guard let interval = calendar.dateInterval(of: .day, for: date) else { return true }
            return interval.contains(sample.timestamp)
        }
        let workouts = bundle.workouts.filter { ($0.day ?? dateKey) == dateKey }
        let sessions = bundle.sessions.filter { ($0.day ?? dateKey) == dateKey }
        let spo2 = bundle.dailySpo2.first { $0.day == dateKey }
        let stress = bundle.dailyStress.first { $0.day == dateKey }
        let resilience = bundle.dailyResilience.first { $0.day == dateKey }

        return [
            OuraDebugValueRow(
                title: "Profile",
                detail: bundle.personalInfo == nil ? "No profile row returned." : "Profile row returned.",
                isAvailable: bundle.personalInfo != nil
            ),
            OuraDebugValueRow(
                title: "Daily sleep",
                detail: dailySleep.map { "score \($0.score.map(String.init) ?? "none")" } ?? "No daily_sleep row for \(dateKey).",
                isAvailable: dailySleep != nil
            ),
            OuraDebugValueRow(
                title: "Sleep periods",
                detail: sleepPeriods.isEmpty ? "No sleep rows for \(dateKey)." : sleepPeriods.map(sleepPeriodSummary).joined(separator: " · "),
                isAvailable: !sleepPeriods.isEmpty
            ),
            OuraDebugValueRow(
                title: "Readiness",
                detail: readiness.map { "score \($0.score.map(String.init) ?? "none")" } ?? "No daily_readiness row for \(dateKey).",
                isAvailable: readiness != nil
            ),
            OuraDebugValueRow(
                title: "Activity",
                detail: activity.map(activitySummary) ?? "No daily_activity row for \(dateKey).",
                isAvailable: activity != nil
            ),
            OuraDebugValueRow(
                title: "Heart rate",
                detail: heartRateSummary(dayHeartRates),
                isAvailable: !dayHeartRates.isEmpty
            ),
            OuraDebugValueRow(
                title: "Daytime heart rate",
                detail: heartRateSummary(daytimeHeartRates(dayHeartRates)),
                isAvailable: !daytimeHeartRates(dayHeartRates).isEmpty
            ),
            OuraDebugValueRow(
                title: "Sleep heart rate",
                detail: heartRateSummary(sleepHeartRates(dayHeartRates)),
                isAvailable: !sleepHeartRates(dayHeartRates).isEmpty
            ),
            OuraDebugValueRow(
                title: "Workouts",
                detail: workouts.isEmpty ? "No workout rows for \(dateKey)." : workouts.map(workoutSummary).joined(separator: " · "),
                isAvailable: !workouts.isEmpty
            ),
            OuraDebugValueRow(
                title: "Sessions",
                detail: sessions.isEmpty ? "No session rows for \(dateKey)." : sessions.map { $0.type ?? "session" }.joined(separator: ", "),
                isAvailable: !sessions.isEmpty
            ),
            OuraDebugValueRow(
                title: "SpO2",
                detail: spo2.flatMap { $0.spo2Percentage?.average }.map { "\(format($0))%" } ?? "No daily_spo2 row for \(dateKey).",
                isAvailable: spo2?.spo2Percentage?.average != nil
            ),
            OuraDebugValueRow(
                title: "Stress",
                detail: stress.map(stressSummary) ?? "No daily_stress row for \(dateKey).",
                isAvailable: stress != nil
            ),
            OuraDebugValueRow(
                title: "Resilience",
                detail: resilience.map { $0.level ?? "row returned without level" } ?? "No daily_resilience row for \(dateKey).",
                isAvailable: resilience != nil
            ),
            OuraDebugValueRow(
                title: "Ring",
                detail: bundle.ringConfigurations.isEmpty ? "No ring configuration rows." : bundle.ringConfigurations.map(ringSummary).joined(separator: " · "),
                isAvailable: !bundle.ringConfigurations.isEmpty
            )
        ]
    }

    private static func mappedDataRows(
        payload: PulsarDailyMetricsSyncPayload?,
        bundle: OuraRawSyncBundle,
        date: Date,
        calendar: Calendar
    ) -> [OuraDebugValueRow] {
        [
            OuraDebugValueRow(
                title: "Sleep",
                detail: payload?.sleep.map { "score \($0.score), \(format($0.totalSleepMinutes))m sleep" } ?? "Not mapped from Oura.",
                isAvailable: payload?.sleep != nil
            ),
            OuraDebugValueRow(
                title: "Recovery",
                detail: payload?.recovery.map { "score \($0.score)" } ?? "Not mapped from Oura.",
                isAvailable: payload?.recovery != nil
            ),
            OuraDebugValueRow(
                title: "Strain",
                detail: payload?.strain.map { "score \($0.score)" } ?? "Not mapped from Oura.",
                isAvailable: payload?.strain != nil
            ),
            OuraDebugValueRow(
                title: "Stress",
                detail: payload?.stress.map { "score \($0.score) \($0.levelText)" } ?? "Not mapped from Oura.",
                isAvailable: payload?.stress != nil
            ),
            OuraDebugValueRow(
                title: "Health Monitor",
                detail: payload?.healthMonitor.map(healthMonitorSummary)
                    ?? healthMonitorUnavailableReason(bundle: bundle, date: date, calendar: calendar),
                isAvailable: payload?.healthMonitor != nil
            )
        ]
    }

    private static func canonicalRows(samples: [CanonicalHealthSample]) -> [OuraDebugValueRow] {
        let counts = Dictionary(grouping: samples, by: \.metric.label)
            .mapValues(\.count)
        guard !counts.isEmpty else {
            return [
                OuraDebugValueRow(title: "Canonical samples", detail: "No canonical samples produced.", isAvailable: false)
            ]
        }
        return counts.keys.sorted().map { metric in
            OuraDebugValueRow(title: metric, detail: "\(counts[metric] ?? 0) samples", isAvailable: true)
        }
    }

    private static func sleepPeriodSummary(_ period: OuraSleepPeriod) -> String {
        let duration = period.totalSleepDuration.map { "\(format($0 / 60))m sleep" } ?? "duration none"
        let efficiency = period.efficiency.map { "eff \($0)%" } ?? "eff none"
        return "\(period.type ?? "sleep") \(duration), \(efficiency)"
    }

    private static func activitySummary(_ activity: OuraDailyActivity) -> String {
        let score = activity.score.map { "score \($0)" } ?? "score none"
        let steps = activity.steps.map { "\($0.formatted()) steps" } ?? "steps none"
        let calories = activity.activeCalories.map { "\(format($0)) active cal" } ?? "active cal none"
        return "\(score), \(steps), \(calories)"
    }

    private static func heartRateSummary(_ heartRates: [OuraHeartRate]) -> String {
        guard !heartRates.isEmpty else { return "No heartrate rows for selected day." }
        let values = heartRates.map(\.bpm)
        let average = values.reduce(0, +) / Double(values.count)
        let newest = heartRates.map(\.timestamp).max().map { ", newest \($0)" } ?? ""
        let sourceCounts = Dictionary(grouping: heartRates, by: { $0.source ?? "unknown" })
            .mapValues(\.count)
            .sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: ", ")
        let sourceDetail = sourceCounts.isEmpty ? "" : ", sources \(sourceCounts)"
        return "\(heartRates.count) rows, avg \(format(average)) bpm, min \(format(values.min() ?? 0)), max \(format(values.max() ?? 0))\(sourceDetail)\(newest)"
    }

    private static func daytimeHeartRates(_ heartRates: [OuraHeartRate]) -> [OuraHeartRate] {
        heartRates.filter { sample in
            let source = sample.source?.lowercased() ?? ""
            return source != "sleep"
        }
    }

    private static func sleepHeartRates(_ heartRates: [OuraHeartRate]) -> [OuraHeartRate] {
        heartRates.filter { sample in
            let source = sample.source?.lowercased() ?? ""
            return source == "sleep"
        }
    }

    private static func healthMonitorSummary(_ healthMonitor: PulsarHealthMonitorSyncMetric) -> String {
        let values = healthMonitor.metrics
            .filter { $0.value != nil }
            .map { metric in
                let label: String = {
                    switch metric.kind {
                    case .respiratoryRate:
                        return "RR"
                    case .restingHeartRate:
                        return "RHR"
                    case .hrv:
                        return "HRV"
                    case .oxygenSaturation:
                        return "SpO2"
                    case .wristTemperature:
                        return "Temp"
                    case .sleep:
                        return "Sleep"
                    }
                }()
                return "\(label) \(format(metric.value ?? 0))"
            }
        guard !values.isEmpty else { return "\(healthMonitor.metrics.count) metrics" }
        return "\(values.count) mapped: \(values.joined(separator: ", "))"
    }

    private static func healthMonitorUnavailableReason(
        bundle: OuraRawSyncBundle,
        date: Date,
        calendar: Calendar
    ) -> String {
        let dayHeartRates = bundle.heartRates.filter { sample in
            guard let interval = calendar.dateInterval(of: .day, for: date) else { return true }
            return interval.contains(sample.timestamp)
        }
        let restingCandidates = dayHeartRates
            .filter { sample in
                guard let source = sample.source?.lowercased() else { return false }
                return source == "sleep" || source == "rest"
            }
            .filter { (25...160).contains($0.bpm) }

        if dayHeartRates.isEmpty {
            return "Not mapped: no Oura sleep, readiness, SpO2, or heart-rate rows for Health Monitor."
        }
        if restingCandidates.isEmpty {
            return "Not mapped: Oura heart-rate rows are not sleep/rest samples. Health Monitor has no generic heart-rate tile."
        }
        if restingCandidates.count < 3 {
            return "Not mapped: only \(restingCandidates.count) sleep/rest heart-rate rows; need 3 for resting HR."
        }
        return "Not mapped from Oura."
    }

    private static func workoutSummary(_ workout: OuraWorkout) -> String {
        let activity = workout.activity ?? workout.label ?? "workout"
        let calories = workout.calories.map { "\(format($0)) cal" } ?? "cal none"
        return "\(activity) \(calories)"
    }

    private static func stressSummary(_ stress: OuraDailyStress) -> String {
        let summary = stress.daySummary ?? "summary none"
        let stressMinutes = stress.stressHigh.map { "\(format($0 / 60))m high stress" } ?? "stress none"
        let recoveryMinutes = stress.recoveryHigh.map { "\(format($0 / 60))m recovery" } ?? "recovery none"
        return "\(summary), \(stressMinutes), \(recoveryMinutes)"
    }

    private static func ringSummary(_ ring: OuraRingConfiguration) -> String {
        let details = [
            ring.hardwareType,
            ring.firmwareVersion.map { "fw \($0)" }
        ]
            .compactMap { $0 }
            .joined(separator: ", ")
        return details.isEmpty ? "ring row returned" : details
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}
