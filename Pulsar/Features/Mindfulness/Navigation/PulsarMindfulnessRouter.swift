//
//  PulsarMindfulnessRouter.swift
//  Pulsar
//

import Combine
import Foundation

struct PulsarMindfulnessPresentation: Equatable, Identifiable {
    enum Source: String, Equatable {
        case inApp
        case notification
        case deepLink
    }

    let id = UUID()
    var dateKey: String?
    var source: Source
}

@MainActor
final class PulsarMindfulnessRouter: ObservableObject {
    @Published private(set) var pendingPresentation: PulsarMindfulnessPresentation?

    func presentDailyRewind(
        dateKey: String? = nil,
        source: PulsarMindfulnessPresentation.Source = .inApp
    ) {
        pendingPresentation = PulsarMindfulnessPresentation(dateKey: dateKey, source: source)
    }

    func consume(_ presentation: PulsarMindfulnessPresentation) {
        guard pendingPresentation == presentation else { return }
        pendingPresentation = nil
    }
}
