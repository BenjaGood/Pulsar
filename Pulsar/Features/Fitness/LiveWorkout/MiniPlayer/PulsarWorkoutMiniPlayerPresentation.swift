import SwiftUI

struct PulsarWorkoutMiniPlayerMetric: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case heartRate
        case distance
        case pace
        case calories
        case exercise
        case set
        case steps
        case cadence
        case source
    }

    let kind: Kind
    let label: String
    let value: String

    var id: Kind { kind }
}

struct PulsarWorkoutMiniPlayerState: Equatable, Identifiable {
    enum Kind: Equatable {
        case run(PulsarOutdoorWorkoutKind)
        case gym
        case watchGym
    }

    enum LiveStatus: Equatable {
        case live
        case paused
        case preparing
        case saving
        case disconnected

        var label: String {
            switch self {
            case .live: "Live"
            case .paused: "Paused"
            case .preparing: "Connecting"
            case .saving: "Finishing"
            case .disconnected: "Connection lost"
            }
        }

        var color: Color {
            switch self {
            case .live: .green
            case .paused: .orange
            case .preparing: .yellow
            case .saving: .blue
            case .disconnected: .gray
            }
        }
    }

    let id: String
    let sessionID: UUID
    let kind: Kind
    let title: String
    let symbol: String
    let status: LiveStatus
    let elapsedText: String
    let secondaryMetrics: [PulsarWorkoutMiniPlayerMetric]

    var compactMetric: PulsarWorkoutMiniPlayerMetric? {
        secondaryMetrics.first
    }

    var accentColor: Color {
        switch kind {
        case .run(let workoutKind): workoutKind.accentColor
        case .gym: Color(red: 0.72, green: 0.66, blue: 1.0)
        case .watchGym: Color(red: 0.48, green: 0.84, blue: 1.0)
        }
    }

    var accessibilitySummary: String {
        let metricSummary = secondaryMetrics
            .map { "\($0.label) \($0.value)" }
            .joined(separator: ", ")
        return [status.label, title, elapsedText, metricSummary]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

