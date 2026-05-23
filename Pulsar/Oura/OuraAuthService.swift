//
//  OuraAuthService.swift
//  Pulsar
//

import AuthenticationServices
import Combine
import Foundation
import Security
import UIKit

protocol OuraBackendTokenServicing {
    func checkHealth() async throws -> OuraBackendHealthResponse

    func exchangeAuthorizationCode(
        _ code: String,
        redirectURI: URL,
        requestedScopes: Set<OuraScope>
    ) async throws -> OuraOAuthTokenResponse

    func refreshToken(_ refreshToken: String) async throws -> OuraOAuthTokenResponse
    func revoke(accessToken: String, refreshToken: String?) async throws
}

enum OuraOAuthPresentationPhase: Equatable {
    case openingLogin
    case waitingForCallback
}

final class OuraConnectionStore: ObservableObject {
    @Published private(set) var status: OuraConnectionStatus
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var grantedScopes: Set<OuraScope>

    private let defaults: UserDefaults
    private let tokenStorage: OuraTokenStorage

    init(
        defaults: UserDefaults = .standard,
        tokenStorage: OuraTokenStorage = OuraKeychainTokenStore()
    ) {
        self.defaults = defaults
        self.tokenStorage = tokenStorage
        self.status = OuraConnectionStatus(rawValue: defaults.string(forKey: OuraDefaultsKeys.connectionStatus) ?? "") ?? .notConnected
        self.lastSyncAt = defaults.object(forKey: OuraDefaultsKeys.lastSyncAt) as? Date
        self.lastErrorMessage = defaults.string(forKey: OuraDefaultsKeys.lastErrorMessage)
        let scopes = defaults.stringArray(forKey: OuraDefaultsKeys.lastAuthorizedScopes) ?? []
        self.grantedScopes = Set(scopes.compactMap(OuraScope.init(rawValue:)))
        reconcileWithToken()
    }

    var storedToken: OuraStoredToken? {
        try? tokenStorage.loadToken()
    }

    var isConnected: Bool {
        storedToken != nil && status != .tokenExpired && status != .notConnected
    }

    func markConnecting() {
        update(status: .connecting)
    }

    func markConnected(token: OuraStoredToken) throws {
        try tokenStorage.saveToken(token)
        grantedScopes = token.scopes
        defaults.set(token.scopes.map(\.rawValue).sorted(), forKey: OuraDefaultsKeys.lastAuthorizedScopes)
        defaults.removeObject(forKey: OuraDefaultsKeys.lastErrorMessage)
        lastErrorMessage = nil
        update(status: .connected)
    }

    func markTokenExpired(_ message: String) {
        lastErrorMessage = message
        defaults.set(message, forKey: OuraDefaultsKeys.lastErrorMessage)
        update(status: .tokenExpired)
    }

    func markSyncError(_ message: String) {
        lastErrorMessage = message
        defaults.set(message, forKey: OuraDefaultsKeys.lastErrorMessage)
        update(status: .syncError)
    }

    func markSynced(at date: Date) {
        lastSyncAt = date
        defaults.set(date, forKey: OuraDefaultsKeys.lastSyncAt)
        defaults.removeObject(forKey: OuraDefaultsKeys.lastErrorMessage)
        lastErrorMessage = nil
        if status != .connected {
            update(status: .connected)
        }
    }

    func disconnect() {
        try? tokenStorage.deleteToken()
        defaults.removeObject(forKey: OuraDefaultsKeys.lastSyncAt)
        defaults.removeObject(forKey: OuraDefaultsKeys.lastErrorMessage)
        defaults.removeObject(forKey: OuraDefaultsKeys.lastAuthorizedScopes)
        lastSyncAt = nil
        lastErrorMessage = nil
        grantedScopes = []
        update(status: .notConnected)
    }

    private func update(status: OuraConnectionStatus) {
        self.status = status
        defaults.set(status.rawValue, forKey: OuraDefaultsKeys.connectionStatus)
    }

    private func reconcileWithToken() {
        guard let token = try? tokenStorage.loadToken() else {
            if status != .notConnected {
                update(status: .notConnected)
            }
            return
        }
        grantedScopes = token.scopes
        defaults.set(token.scopes.map(\.rawValue).sorted(), forKey: OuraDefaultsKeys.lastAuthorizedScopes)
        if token.isExpired {
            update(status: .tokenExpired)
        } else if status == .notConnected || status == .connecting {
            update(status: .connected)
        }
    }
}

final class URLSessionOuraBackendTokenClient: OuraBackendTokenServicing {
    private let configuration: OuraIntegrationConfiguration
    private let session: URLSession

    init(configuration: OuraIntegrationConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func checkHealth() async throws -> OuraBackendHealthResponse {
        guard let endpoint = configuration.backendHealthEndpoint else {
            throw OuraAPIError.notConfigured("Configure OuraBackendBaseURL before connecting Oura.")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 6

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OuraAPIError.transport("Oura backend returned an invalid health response.")
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw OuraAPIError.from(statusCode: httpResponse.statusCode, data: data)
            }
            return try OuraJSON.decoder.decode(OuraBackendHealthResponse.self, from: data)
        } catch let error as OuraAPIError {
            throw error
        } catch let error as URLError {
            throw OuraAPIError.transport(Self.backendUnreachableMessage(endpoint: endpoint, error: error))
        } catch {
            throw OuraAPIError.transport(error.localizedDescription)
        }
    }

    func exchangeAuthorizationCode(
        _ code: String,
        redirectURI: URL,
        requestedScopes: Set<OuraScope>
    ) async throws -> OuraOAuthTokenResponse {
        guard let endpoint = configuration.backendTokenExchangeEndpoint else {
            throw OuraAPIError.notConfigured("Configure OuraBackendBaseURL before connecting Oura.")
        }
        PulsarOuraLogger.log("Token exchange started")
        let request = BackendExchangeRequest(
            code: code,
            redirectURI: redirectURI.absoluteString,
            requestedScopes: requestedScopes.map(\.rawValue).sorted()
        )
        do {
            return try await post(request, to: endpoint)
        } catch {
            if Self.isBackendUnreachable(error) {
                PulsarOuraLogger.log("Token exchange failed backend unreachable")
            } else {
                PulsarOuraLogger.log("Token exchange failed")
            }
            throw error
        }
    }

    func refreshToken(_ refreshToken: String) async throws -> OuraOAuthTokenResponse {
        guard let endpoint = configuration.backendRefreshEndpoint else {
            throw OuraAPIError.notConfigured("Configure OuraBackendBaseURL before refreshing Oura tokens.")
        }
        return try await post(BackendRefreshRequest(refreshToken: refreshToken), to: endpoint)
    }

    func revoke(accessToken: String, refreshToken: String?) async throws {
        guard let endpoint = configuration.backendRevokeEndpoint else {
            return
        }
        _ = try await post(
            BackendRevokeRequest(accessToken: accessToken, refreshToken: refreshToken),
            to: endpoint,
            expecting: EmptyBackendResponse.self
        )
    }

    private func post<RequestBody: Encodable, ResponseBody: Decodable>(
        _ body: RequestBody,
        to endpoint: URL,
        expecting: ResponseBody.Type = ResponseBody.self
    ) async throws -> ResponseBody {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw OuraAPIError.transport(Self.backendUnreachableMessage(endpoint: endpoint, error: error))
        } catch {
            throw OuraAPIError.transport(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OuraAPIError.transport("Oura backend returned an invalid response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OuraAPIError.from(statusCode: httpResponse.statusCode, data: data)
        }
        if ResponseBody.self == EmptyBackendResponse.self, data.isEmpty {
            return EmptyBackendResponse() as! ResponseBody
        }
        do {
            return try OuraJSON.decoder.decode(ResponseBody.self, from: data)
        } catch {
            throw OuraAPIError.decoding(error.localizedDescription)
        }
    }

    private struct BackendExchangeRequest: Encodable {
        var code: String
        var redirectURI: String
        var requestedScopes: [String]

        enum CodingKeys: String, CodingKey {
            case code
            case redirectURI = "redirect_uri"
            case requestedScopes = "requested_scopes"
        }
    }

    private struct BackendRefreshRequest: Encodable {
        var refreshToken: String

        enum CodingKeys: String, CodingKey {
            case refreshToken = "refresh_token"
        }
    }

    private struct BackendRevokeRequest: Encodable {
        var accessToken: String
        var refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }
    }

    private struct EmptyBackendResponse: Codable {
        init() {}
    }

    private static func isBackendUnreachable(_ error: Error) -> Bool {
        guard let apiError = error as? OuraAPIError,
              case .transport(let message) = apiError else {
            return false
        }
        return message.localizedCaseInsensitiveContains("backend is not reachable")
    }

    private static func backendUnreachableMessage(endpoint: URL, error _: URLError) -> String {
        let base = "Oura backend is not reachable. Start the local backend or update OuraBackendBaseURL."
        #if targetEnvironment(simulator)
        return "\(base) The iOS Simulator is calling \(endpoint.absoluteString)."
        #else
        if endpoint.host == "127.0.0.1" || endpoint.host == "localhost" {
            return "\(base) On a physical iPhone, 127.0.0.1 points to the phone itself. Use your Mac LAN IP, for example http://<MAC_LOCAL_IP>:8787."
        }
        return "\(base) Confirm your iPhone and Mac are on the same Wi-Fi and macOS firewall allows this port."
        #endif
    }
}

@MainActor
final class OuraAuthService: NSObject {
    static let productionScopes: Set<OuraScope> = OuraScope.pulsarOAuthScopes

    private let configuration: OuraIntegrationConfiguration
    private let tokenStorage: OuraTokenStorage
    private let backendClient: OuraBackendTokenServicing
    let connectionStore: OuraConnectionStore

    private var authenticationSession: ASWebAuthenticationSession?
    private(set) var lastAuthorizationURL: URL?
    private var tokenRefreshTask: Task<OuraStoredToken, Error>?

    init(
        configuration: OuraIntegrationConfiguration = .load(),
        tokenStorage: OuraTokenStorage = OuraKeychainTokenStore(),
        backendClient: OuraBackendTokenServicing? = nil,
        connectionStore: OuraConnectionStore? = nil
    ) {
        self.configuration = configuration
        self.tokenStorage = tokenStorage
        let resolvedConnectionStore = connectionStore ?? OuraConnectionStore(tokenStorage: tokenStorage)
        self.connectionStore = resolvedConnectionStore
        self.backendClient = backendClient ?? URLSessionOuraBackendTokenClient(configuration: configuration)
        super.init()
    }

    var isConfigured: Bool {
        configuration.isReadyForOAuth
    }

    var canStartAuthorization: Bool {
        configuration.canStartAuthorization
    }

    var authorizationConfiguration: OuraIntegrationConfiguration {
        configuration
    }

    func checkBackendHealth() async throws {
        guard !configuration.mockMode else { return }
        guard let healthURL = configuration.backendHealthEndpoint else {
            throw OuraAPIError.notConfigured("Configure OuraBackendBaseURL before connecting Oura.")
        }

        PulsarOuraLogger.log("Runtime target=\(Self.runtimeTargetLabel)")
        PulsarOuraLogger.log("Backend health check started url=\(healthURL.absoluteString)")
        do {
            let health = try await backendClient.checkHealth()
            guard health.isReady else {
                let missing = health.missing?.joined(separator: ", ") ?? "required environment variables"
                let message = "Oura backend is not configured. Set \(missing) before connecting Oura."
                PulsarOuraLogger.log("Backend reachable but not configured missing=\(missing)")
                throw OuraAPIError.notConfigured(message)
            }
            PulsarOuraLogger.log("Backend reachable")
        } catch {
            PulsarOuraLogger.log("Backend unreachable error=\(error.localizedDescription)")
            throw error
        }
    }

    func authorizationURL(state: String) throws -> URL {
        try authorizationURL(state: state, scopes: configuration.requestedScopes)
    }

    func authorizationURL(state: String, scopes: Set<OuraScope>) throws -> URL {
        guard configuration.canStartAuthorization else {
            throw OuraAPIError.notConfigured("Configure OuraOAuthClientID and OuraOAuthRedirectURI before connecting Oura.")
        }

        if configuration.mockMode {
            return URL(string: "aetherial-pulsar://oura/mock?state=\(state)")!
        }

        guard let clientID = configuration.clientID,
              let redirectURI = configuration.redirectURI,
              var components = URLComponents(url: OuraAPIEndpoint.authorize, resolvingAgainstBaseURL: false) else {
            throw OuraAPIError.notConfigured("Oura OAuth configuration is incomplete.")
        }

        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: scopes.map(\.rawValue).sorted().joined(separator: " ")),
            URLQueryItem(name: "state", value: state)
        ]

        guard let url = components.url else {
            throw OuraAPIError.notConfigured("Oura authorization URL could not be built.")
        }
        return url
    }

    func connect(onPresentationPhaseChange: ((OuraOAuthPresentationPhase) -> Void)? = nil) async throws {
        guard configuration.canStartAuthorization else {
            throw OuraAPIError.notConfigured("Oura OAuth is missing the client ID or redirect URI.")
        }
        guard configuration.canExchangeTokens else {
            throw OuraAPIError.notConfigured("Oura backend token exchange is unavailable.")
        }

        try await checkBackendHealth()
        connectionStore.markConnecting()

        if configuration.mockMode {
            let token = OuraStoredToken(
                accessToken: "mock-access-token",
                refreshToken: "mock-refresh-token",
                expiresAt: Date().addingTimeInterval(86_400),
                scopes: configuration.requestedScopes,
                tokenType: "bearer"
            )
            try connectionStore.markConnected(token: token)
            return
        }

        guard let redirectURI = configuration.redirectURI,
              let callbackURLScheme = configuration.callbackURLScheme else {
            throw OuraAPIError.notConfigured("Oura redirect URI must use a registered callback URL scheme.")
        }

        let state = Self.makeState()
        let url = try authorizationURL(state: state)
        lastAuthorizationURL = url
        onPresentationPhaseChange?(.openingLogin)
        let callbackURL = try await startWebAuthentication(
            url: url,
            callbackURLScheme: callbackURLScheme
        ) {
            onPresentationPhaseChange?(.waitingForCallback)
        }
        let callback = try OuraOAuthCallbackParser.parse(callbackURL, expectedState: state)
        let tokenResponse = try await backendClient.exchangeAuthorizationCode(
            callback.code,
            redirectURI: redirectURI,
            requestedScopes: configuration.requestedScopes
        )
        let token = tokenResponse.storedToken(receivedAt: Date(), fallbackScopes: callback.scopes.isEmpty ? configuration.requestedScopes : callback.scopes)
        try connectionStore.markConnected(token: token)
        PulsarOuraLogger.log("Oura OAuth connection completed scopes=\(token.scopes.map(\.rawValue).sorted().joined(separator: ","))")
    }

    func completeOAuth(callbackURL: URL, expectedState: String, receivedAt: Date = Date()) async throws {
        guard let redirectURI = configuration.redirectURI else {
            throw OuraAPIError.notConfigured("Oura redirect URI is not configured.")
        }
        let callback = try OuraOAuthCallbackParser.parse(callbackURL, expectedState: expectedState)
        let tokenResponse = try await backendClient.exchangeAuthorizationCode(
            callback.code,
            redirectURI: redirectURI,
            requestedScopes: configuration.requestedScopes
        )
        let token = tokenResponse.storedToken(
            receivedAt: receivedAt,
            fallbackScopes: callback.scopes.isEmpty ? configuration.requestedScopes : callback.scopes
        )
        try connectionStore.markConnected(token: token)
    }

    func validAccessToken(now: Date = Date()) async throws -> String {
        guard let token = try tokenStorage.loadToken() else {
            connectionStore.markTokenExpired("Connect Oura again to continue syncing.")
            throw OuraAPIError.unauthorized("Oura is not connected.")
        }

        guard token.expiresSoon(now: now) else {
            return token.accessToken
        }

        if let tokenRefreshTask {
            let refreshed = try await tokenRefreshTask.value
            return refreshed.accessToken
        }

        let refreshToken = token.refreshToken
        let fallbackScopes = token.scopes.isEmpty ? configuration.requestedScopes : token.scopes
        PulsarOuraLogger.log("Oura access token refresh started")
        let task = Task { [backendClient] in
            let response = try await backendClient.refreshToken(refreshToken)
            return response.storedToken(receivedAt: now, fallbackScopes: fallbackScopes)
        }
        tokenRefreshTask = task
        do {
            let refreshed = try await task.value
            tokenRefreshTask = nil
            try tokenStorage.saveToken(refreshed)
            try connectionStore.markConnected(token: refreshed)
            PulsarOuraLogger.log("Oura access token refreshed")
            return refreshed.accessToken
        } catch {
            tokenRefreshTask = nil
            connectionStore.markTokenExpired("Oura authorization expired. Connect Oura again.")
            PulsarOuraLogger.log("Oura access token refresh failed: \(error.localizedDescription)")
            throw error
        }
    }

    func disconnect() async {
        let token = try? tokenStorage.loadToken()
        if let accessToken = token?.accessToken {
            do {
                try await backendClient.revoke(accessToken: accessToken, refreshToken: token?.refreshToken)
            } catch {
                PulsarOuraLogger.log("Oura revoke request failed; local credentials will still be removed: \(error.localizedDescription)")
            }
        }
        connectionStore.disconnect()
    }

    private func startWebAuthentication(
        url: URL,
        callbackURLScheme: String,
        onSessionStarted: @escaping () -> Void
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackURLScheme) { callbackURL, error in
                if let callbackURL {
                    PulsarOuraLogger.log("OAuth callback received")
                    continuation.resume(returning: callbackURL)
                    return
                }
                if let error {
                    PulsarOuraLogger.log("ASWebAuthenticationSession failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                PulsarOuraLogger.log("ASWebAuthenticationSession finished without callback URL")
                continuation.resume(throwing: OuraOAuthCallbackError.missingCode)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authenticationSession = session

            PulsarOuraLogger.log("Starting ASWebAuthenticationSession")
            if !session.start() {
                PulsarOuraLogger.log("ASWebAuthenticationSession could not be presented")
                continuation.resume(throwing: OuraAPIError.transport("Oura authorization could not be opened."))
                return
            }
            PulsarOuraLogger.log("ASWebAuthenticationSession started; waiting for callback")
            onSessionStarted()
        }
    }

    private static func makeState() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Data(bytes).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return UUID().uuidString
    }

    private static var runtimeTargetLabel: String {
        #if targetEnvironment(simulator)
        return "iOS Simulator"
        #else
        return "physical iPhone"
        #endif
    }
}

extension OuraAuthService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
