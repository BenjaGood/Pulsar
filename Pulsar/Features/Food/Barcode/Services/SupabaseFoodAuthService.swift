import Foundation
import OSLog
import Security

nonisolated struct SupabaseFoodSession: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var userID: UUID
    var expiresAt: Date
}

nonisolated protocol FoodAuthenticationServing: Sendable {
    func validSession() async throws -> SupabaseFoodSession
}

nonisolated enum FoodCommunityServiceError: LocalizedError, Equatable, Sendable {
    case notConfigured
    case authenticationFailed
    case anonymousSignInsDisabled
    case unauthorized
    case forbidden
    case migrationMissing
    case datasetNotImported
    case networkUnavailable
    case requestTimedOut
    case serverUnavailable(Int?)
    case decodingFailed
    case invalidResponse
    case requestFailed(Int)
    case unknown

    var errorDescription: String? {
        switch self {
        case .notConfigured, .migrationMissing, .datasetNotImported, .unauthorized, .forbidden,
             .decodingFailed, .invalidResponse, .unknown:
            "Food database temporarily unavailable. Please try again later."
        case .authenticationFailed: "Couldn’t save this product. We kept your information. Please try again."
        case .anonymousSignInsDisabled:
            "Community saving is unavailable because Supabase Anonymous Sign-Ins are disabled. Enable Anonymous Sign-Ins for this Pulsar project, then try again."
        case .networkUnavailable: "You’re offline. Connect to the internet and try again."
        case .requestTimedOut, .serverUnavailable:
            "Couldn’t reach the food database. Please try again."
        case .requestFailed: "The food database is temporarily unavailable. Please try again."
        }
    }

    var diagnosticCode: String {
        switch self {
        case .notConfigured: "notConfigured"
        case .authenticationFailed: "authenticationFailed"
        case .anonymousSignInsDisabled: "anonymousSignInsDisabled"
        case .unauthorized: "unauthorized"
        case .forbidden: "forbidden"
        case .migrationMissing: "migrationMissing"
        case .datasetNotImported: "datasetNotImported"
        case .networkUnavailable: "networkUnavailable"
        case .requestTimedOut: "requestTimedOut"
        case .serverUnavailable(let status): status.map { "serverUnavailable_\($0)" } ?? "serverUnavailable"
        case .decodingFailed: "decodingFailed"
        case .invalidResponse: "invalidResponse"
        case .requestFailed(let status): "requestFailed_\(status)"
        case .unknown: "unknown"
        }
    }

    var httpStatus: Int? {
        switch self {
        case .unauthorized: 401
        case .forbidden: 403
        case .requestFailed(let status), .serverUnavailable(.some(let status)): status
        default: nil
        }
    }
}

actor SupabaseFoodAuthService: FoodAuthenticationServing {
    private let configuration: FoodCommunityConfiguration
    private let session: URLSession
    private let keychainService = "aetherial.Pulsar.food-community"
    private let keychainAccount = "anonymous-session"

    init(configuration: FoodCommunityConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func validSession() async throws -> SupabaseFoodSession {
        if let stored = loadSession() {
            if stored.expiresAt > Date.now.addingTimeInterval(60) {
                return stored
            }
            if let refreshed = try? await refresh(stored) {
                saveSession(refreshed)
                return refreshed
            }
        }
        let created = try await createAnonymousSession()
        saveSession(created)
        return created
    }

    private func createAnonymousSession() async throws -> SupabaseFoodSession {
        let request = try request(path: "auth/v1/signup", method: "POST", body: Data("{}".utf8))
        let (data, response) = try await session.data(for: request)
        return try decodeSession(data: data, response: response)
    }

    private func refresh(_ stored: SupabaseFoodSession) async throws -> SupabaseFoodSession {
        let body = try JSONEncoder().encode(["refresh_token": stored.refreshToken])
        let request = try request(path: "auth/v1/token?grant_type=refresh_token", method: "POST", body: body)
        let (data, response) = try await session.data(for: request)
        return try decodeSession(data: data, response: response)
    }

    private func request(path: String, method: String, body: Data) throws -> URLRequest {
        guard let baseURL = configuration.supabaseURL,
              let anonKey = configuration.supabaseAnonKey else {
            throw FoodCommunityServiceError.notConfigured
        }
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 15
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func decodeSession(data: Data, response: URLResponse) throws -> SupabaseFoodSession {
        guard let http = response as? HTTPURLResponse else {
            throw FoodCommunityServiceError.authenticationFailed
        }
        guard 200..<300 ~= http.statusCode else {
            struct AuthError: Decodable {
                var errorCode: String?
                var msg: String?
                enum CodingKeys: String, CodingKey {
                    case errorCode = "error_code"
                    case msg
                }
            }
            let failure = try? JSONDecoder().decode(AuthError.self, from: data)
            if failure?.errorCode == "anonymous_provider_disabled" {
                Logger.foodDatabase.error("Supabase anonymous auth is disabled (status=\(http.statusCode, privacy: .public), code=anonymous_provider_disabled)")
                throw FoodCommunityServiceError.anonymousSignInsDisabled
            }
            Logger.foodDatabase.error("Supabase auth failed (status=\(http.statusCode, privacy: .public), code=\(failure?.errorCode ?? "unknown", privacy: .public))")
            throw FoodCommunityServiceError.authenticationFailed
        }
        struct Response: Decodable {
            struct User: Decodable { var id: UUID }
            var accessToken: String
            var refreshToken: String
            var expiresIn: TimeInterval
            var user: User

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case expiresIn = "expires_in"
                case user
            }
        }
        let decoded: Response
        do {
            decoded = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            Logger.foodDatabase.error("Supabase auth response could not be decoded (status=success, reason=invalid_response)")
            throw FoodCommunityServiceError.authenticationFailed
        }
        return SupabaseFoodSession(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            userID: decoded.user.id,
            expiresAt: Date.now.addingTimeInterval(decoded.expiresIn)
        )
    }

    private func loadSession() -> SupabaseFoodSession? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SupabaseFoodSession.self, from: data)
    }

    private func saveSession(_ value: SupabaseFoodSession) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let key: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(key as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = key
            attributes.forEach { insert[$0.key] = $0.value }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }
}
