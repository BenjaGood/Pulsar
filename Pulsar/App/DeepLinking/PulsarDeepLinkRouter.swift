//
//  PulsarDeepLinkRouter.swift
//  Pulsar
//

import Combine
import Foundation

enum PulsarDeepLinkRoute: Equatable, Identifiable, Sendable {
    case mindfulnessDailyRewind(dateKey: String?)

    var id: String {
        switch self {
        case .mindfulnessDailyRewind(let dateKey):
            "mindfulness.dailyRewind.\(dateKey ?? "today")"
        }
    }

    init?(url: URL) {
        guard url.scheme == "aetherial-pulsar" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let dateKey = components?.queryItems?.first(where: { $0.name == "date" })?.value
        let host = url.host?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if host == "daily-rewind" || path == "daily-rewind" || (host == "mindfulness" && path == "daily-rewind") {
            self = .mindfulnessDailyRewind(dateKey: dateKey)
            return
        }

        return nil
    }

    init?(notificationUserInfo userInfo: [AnyHashable: Any]) {
        if let deepLink = userInfo["pulsar.deepLinkURL"] as? String,
           let url = URL(string: deepLink),
           let route = PulsarDeepLinkRoute(url: url) {
            self = route
            return
        }

        let kind = userInfo["pulsar.notification.kind"] as? String
        let destination = userInfo["pulsar.destination"] as? String
        let presentation = userInfo["pulsar.presentation"] as? String
        guard kind == "dailyRewind" || destination == "mindfulness.dailyRewind" || presentation == "dailyRewind" else {
            return nil
        }

        self = .mindfulnessDailyRewind(dateKey: userInfo["pulsar.dateKey"] as? String)
    }
}

@MainActor
final class PulsarDeepLinkRouter: ObservableObject {
    static let shared = PulsarDeepLinkRouter()

    @Published private(set) var pendingRoute: PulsarDeepLinkRoute?

    private init() {}

    func open(_ url: URL) {
        guard let route = PulsarDeepLinkRoute(url: url) else { return }
        open(route)
    }

    func open(_ route: PulsarDeepLinkRoute) {
        pendingRoute = route
    }

    func consume(_ route: PulsarDeepLinkRoute) {
        guard pendingRoute == route else { return }
        pendingRoute = nil
    }
}
