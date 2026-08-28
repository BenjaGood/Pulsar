import Foundation
import OSLog

nonisolated struct FoodCommunityConfiguration: Sendable {
    var supabaseURL: URL?
    var supabaseAnonKey: String?

    var isConfigured: Bool {
        validationIssue == nil
    }

    var validationIssue: ValidationIssue? {
        guard let supabaseURL else { return .missingURL }
        guard Self.isAllowedSupabaseURL(supabaseURL) else { return .invalidURL }
        guard let supabaseAnonKey, !supabaseAnonKey.isEmpty else { return .missingAnonKey }
        guard !Self.isPlaceholder(supabaseAnonKey), supabaseAnonKey.count >= 20 else { return .invalidAnonKey }
        return nil
    }

    static func current(bundle: Bundle = .main) -> Self {
        let rawURL = cleaned(bundle.object(forInfoDictionaryKey: "FoodCommunitySupabaseURL") as? String)
        let key = cleaned(bundle.object(forInfoDictionaryKey: "FoodCommunitySupabaseAnonKey") as? String)
        let configuration = Self(
            supabaseURL: rawURL.flatMap(URL.init(string:)),
            supabaseAnonKey: key
        )
#if DEBUG
        if let issue = configuration.validationIssue {
            Logger.foodDatabase.fault(
                "Food database configuration invalid: \(issue.rawValue, privacy: .public). URL/key presence only: url=\(rawURL != nil, privacy: .public) anon_key=\(key != nil, privacy: .public)"
            )
        }
#endif
        return configuration
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$("), !isPlaceholder(trimmed) else { return nil }
        return trimmed
    }

    private static func isAllowedSupabaseURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return false }
        if scheme == "https" { return !isPlaceholder(host) }
#if DEBUG
        return scheme == "http" && (host == "localhost" || host == "127.0.0.1")
#else
        return false
#endif
    }

    private static func isPlaceholder(_ value: String) -> Bool {
        let lowercase = value.lowercased()
        return lowercase.contains("your_project")
            || lowercase.contains("your-project")
            || lowercase.contains("your_public")
            || lowercase.contains("placeholder")
            || lowercase.contains("server_only_secret")
    }

    enum ValidationIssue: String, Sendable {
        case missingURL = "missing_supabase_url"
        case invalidURL = "invalid_supabase_url"
        case missingAnonKey = "missing_supabase_anon_key"
        case invalidAnonKey = "invalid_supabase_anon_key"
    }
}

extension Logger {
    nonisolated static let foodDatabase = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "aetherial.Pulsar",
        category: "FoodDatabase"
    )
}
