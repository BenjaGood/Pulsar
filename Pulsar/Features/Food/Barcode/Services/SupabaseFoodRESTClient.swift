import Foundation

actor SupabaseFoodRESTClient {
    private let configuration: FoodCommunityConfiguration
    private let authentication: any FoodAuthenticationServing
    private let session: URLSession

    init(
        configuration: FoodCommunityConfiguration,
        authentication: any FoodAuthenticationServing,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.authentication = authentication
        self.session = session
    }

    func request(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        authenticated: Bool,
        headers: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        guard configuration.validationIssue == nil,
              let baseURL = configuration.supabaseURL,
              let anonKey = configuration.supabaseAnonKey else {
            throw FoodCommunityServiceError.notConfigured
        }
        let bearer = authenticated ? try await authentication.validSession().accessToken : nil
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw FoodCommunityServiceError.invalidResponse
        }
        var request = URLRequest(url: url, timeoutInterval: 18)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        } else if Self.isLegacyJWTAPIKey(anonKey) {
            // Legacy Supabase anon keys are JWTs. Current sb_publishable_ keys
            // must only be sent as `apikey`; treating one as a Bearer JWT is a 401.
            request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        }
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw Self.mapNetworkError(error)
        } catch {
            throw FoodCommunityServiceError.unknown
        }
        guard let http = response as? HTTPURLResponse else {
            throw FoodCommunityServiceError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw Self.mapHTTPError(status: http.statusCode, data: data)
        }
        return (data, http)
    }

    func currentSession() async throws -> SupabaseFoodSession {
        try await authentication.validSession()
    }

    nonisolated static func isLegacyJWTAPIKey(_ value: String) -> Bool {
        value.split(separator: ".", omittingEmptySubsequences: false).count == 3
            && value.hasPrefix("eyJ")
    }

    nonisolated private static func mapNetworkError(_ error: URLError) -> FoodCommunityServiceError {
        switch error.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            .networkUnavailable
        case .timedOut:
            .requestTimedOut
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost,
             .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            .serverUnavailable(nil)
        default:
            .unknown
        }
    }

    nonisolated private static func mapHTTPError(status: Int, data: Data) -> FoodCommunityServiceError {
        struct PostgRESTError: Decodable { var code: String?; var message: String? }
        let details = try? JSONDecoder().decode(PostgRESTError.self, from: data)
        if details?.code == "PGRST202"
            || details?.code == "42P01"
            || details?.code == "42883"
            || details?.message?.localizedCaseInsensitiveContains("schema cache") == true {
            return .migrationMissing
        }
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 408, 504: return .requestTimedOut
        case 500...599: return .serverUnavailable(status)
        default: return .requestFailed(status)
        }
    }
}
