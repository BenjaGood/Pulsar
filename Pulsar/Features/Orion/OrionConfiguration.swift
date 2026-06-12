//
//  OrionConfiguration.swift
//  Pulsar
//

import Foundation

struct OrionConfiguration: Equatable, Sendable {
    var backendBaseURL: URL?
    var chatPath: String
    var mockMode: Bool
    var timeoutSeconds: TimeInterval

    static let notConfigured = OrionConfiguration()

    init(
        backendBaseURL: URL? = nil,
        chatPath: String = "/orion/chat",
        mockMode: Bool = false,
        timeoutSeconds: TimeInterval = 30
    ) {
        self.backendBaseURL = backendBaseURL
        self.chatPath = chatPath.isEmpty ? "/orion/chat" : chatPath
        self.mockMode = mockMode
        self.timeoutSeconds = timeoutSeconds
    }

    var chatEndpoint: URL? {
        guard let backendBaseURL else { return nil }
        return Self.endpoint(baseURL: backendBaseURL, path: chatPath)
    }

    var isConfigured: Bool {
        mockMode || chatEndpoint != nil
    }

    func missingConfigurationKeys() -> [String] {
        guard !mockMode else { return [] }
        return chatEndpoint == nil ? ["OrionBackendBaseURL"] : []
    }

    static func load(bundle: Bundle = .main, defaults: UserDefaults = .standard) -> OrionConfiguration {
        OrionConfiguration(
            backendBaseURL: urlValue(named: "OrionBackendBaseURL", bundle: bundle),
            chatPath: stringValue(named: "OrionChatPath", bundle: bundle) ?? "/orion/chat",
            mockMode: defaults.bool(forKey: OrionDefaultsKeys.mockMode) || boolValue(named: "OrionMockMode", bundle: bundle)
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

    private static func endpoint(baseURL: URL, path: String) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
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

enum OrionDefaultsKeys {
    static let mockMode = "pulsar.orion.mockMode.v1"
}
