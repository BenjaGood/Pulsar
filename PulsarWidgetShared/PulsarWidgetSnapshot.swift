import Foundation

enum PulsarWidgetKind {
    static let mainMetrics = "PulsarMainMetricsWidget"
    static let stress = "PulsarStressWidget"
}

enum PulsarWidgetMetricKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case sleep
    case recovery
    case strain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep:
            return "Sleep"
        case .recovery:
            return "Recovery"
        case .strain:
            return "Strain"
        }
    }

    var systemImageName: String {
        switch self {
        case .sleep:
            return "moon.zzz.fill"
        case .recovery:
            return "heart.text.square.fill"
        case .strain:
            return "figure.run.circle.fill"
        }
    }
}

enum PulsarWidgetStressState: String, Codable, Sendable {
    case ready
    case buildingBaseline
    case paused
    case noData
}

struct PulsarWidgetMetricSnapshot: Codable, Equatable, Identifiable, Sendable {
    var id: PulsarWidgetMetricKind { kind }
    var kind: PulsarWidgetMetricKind
    var score: Int?
    var detailText: String
    var secondaryText: String?
    var updatedAt: Date?

    var isAvailable: Bool {
        score != nil
    }
}

struct PulsarWidgetStressSnapshot: Codable, Equatable, Sendable {
    var state: PulsarWidgetStressState
    var score: Int?
    var statusText: String
    var insightText: String?
    var updatedAt: Date?

    var isAvailable: Bool {
        score != nil
    }
}

struct PulsarWidgetSnapshot: Codable, Equatable, Sendable {
    var generatedAt: Date
    var lastUpdated: Date?
    var metrics: [PulsarWidgetMetricSnapshot]
    var stress: PulsarWidgetStressSnapshot
    var emptyMessage: String

    static let emptyMessageText = "Open Pulsar to update your metrics."

    var hasMetricData: Bool {
        metrics.contains(where: \.isAvailable)
    }

    var hasStressData: Bool {
        stress.isAvailable || stress.state != .noData
    }

    func metric(_ kind: PulsarWidgetMetricKind) -> PulsarWidgetMetricSnapshot {
        metrics.first(where: { $0.kind == kind }) ??
            PulsarWidgetMetricSnapshot(kind: kind, score: nil, detailText: emptyMessage, secondaryText: nil, updatedAt: nil)
    }

    static let empty = PulsarWidgetSnapshot(
        generatedAt: .distantPast,
        lastUpdated: nil,
        metrics: PulsarWidgetMetricKind.allCases.map {
            PulsarWidgetMetricSnapshot(kind: $0, score: nil, detailText: emptyMessageText, secondaryText: nil, updatedAt: nil)
        },
        stress: PulsarWidgetStressSnapshot(
            state: .noData,
            score: nil,
            statusText: "No data",
            insightText: emptyMessageText,
            updatedAt: nil
        ),
        emptyMessage: emptyMessageText
    )

    static var preview: PulsarWidgetSnapshot {
        let now = Date()
        return PulsarWidgetSnapshot(
            generatedAt: now,
            lastUpdated: now,
            metrics: [
                PulsarWidgetMetricSnapshot(
                    kind: .sleep,
                    score: 84,
                    detailText: "7h 42m sleep",
                    secondaryText: "91% efficiency",
                    updatedAt: now
                ),
                PulsarWidgetMetricSnapshot(
                    kind: .recovery,
                    score: 73,
                    detailText: "Balanced recovery",
                    secondaryText: "HRV 63 ms",
                    updatedAt: now
                ),
                PulsarWidgetMetricSnapshot(
                    kind: .strain,
                    score: 58,
                    detailText: "42m training",
                    secondaryText: "Target 52-74",
                    updatedAt: now
                )
            ],
            stress: PulsarWidgetStressSnapshot(
                state: .ready,
                score: 36,
                statusText: "Medium",
                insightText: "Your physiology is close to baseline today.",
                updatedAt: now
            ),
            emptyMessage: emptyMessageText
        )
    }
}
