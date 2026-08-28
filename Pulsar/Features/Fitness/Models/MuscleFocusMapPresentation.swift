//
//  MuscleFocusMapPresentation.swift
//  Pulsar
//

import Foundation
import OSLog

/// A lightweight, deterministic presentation model for the Fitness muscle map.
/// It adapts the existing weekly matrix analytics instead of introducing a second
/// workout aggregation path for the visualisation.
struct MuscleFocusMapPresentation: Hashable {
    struct Entry: Identifiable, Hashable {
        var muscleGroup: MuscleMatrixGroup
        var intensity: MuscleIntensity
        var score: Int

        var id: String { muscleGroup.rawValue }

        var displayName: String { muscleGroup.displayName }

        var compactName: String { muscleGroup.compactName }

        var isActive: Bool { intensity != .none }

        /// Lets real training volume control the opacity of the baked-color,
        /// anatomically aligned muscle-region pass.
        var glowOpacity: Double {
            switch intensity {
            case .none: 0
            case .light: 0.38
            case .medium: 0.68
            case .high: 0.94
            }
        }
    }

    var entries: [Entry]
    var primaryFocus: [Entry]
    var balanceScore: Int
    var balanceLabel: String
    var insight: String
    var insightTitle: String
    var overallIntensity: MuscleIntensity
    var hasTrainingData: Bool

    init(viewModel: MuscleMatrixViewModel) {
        let signpostState = PulsarPerformanceSignposts.muscle.beginInterval(
            "map_prepare",
            "stage=presentation"
        )
        defer {
            PulsarPerformanceSignposts.muscle.endInterval("map_prepare", signpostState)
        }
        let mappedEntries = viewModel.rows.map { row in
            let score = row.muscleGroup == .cardio ? row.weeklyMinutes : row.weeklyCompletedSets
            let intensity = row.muscleGroup == .cardio
                ? MuscleIntensity(cardioMinutes: score)
                : MuscleIntensity(sets: score)
            return Entry(muscleGroup: row.muscleGroup, intensity: intensity, score: score)
        }

        entries = mappedEntries
        primaryFocus = mappedEntries
            .filter(\.isActive)
            .sorted { lhs, rhs in
                if lhs.intensity.rank == rhs.intensity.rank {
                    if lhs.score == rhs.score {
                        return lhs.displayName < rhs.displayName
                    }
                    return lhs.score > rhs.score
                }
                return lhs.intensity.rank > rhs.intensity.rank
            }
            .prefix(4)
            .map { $0 }
        balanceScore = viewModel.weeklySummary.balanceScore
        balanceLabel = Self.balanceLabel(
            score: viewModel.weeklySummary.balanceScore,
            hasTrainingData: viewModel.weeklySummary.totalSets > 0 || viewModel.weeklySummary.totalCardioMinutes > 0
        )
        insight = viewModel.weeklySummary.insight
        insightTitle = viewModel.weeklySummary.insightTitle
        overallIntensity = mappedEntries.map(\.intensity).max(by: { $0.rank < $1.rank }) ?? .none
        hasTrainingData = viewModel.weeklySummary.totalSets > 0 || viewModel.weeklySummary.totalCardioMinutes > 0
    }

    func entry(for muscleGroup: MuscleMatrixGroup) -> Entry {
        entries.first(where: { $0.muscleGroup == muscleGroup })
            ?? Entry(muscleGroup: muscleGroup, intensity: .none, score: 0)
    }

    nonisolated private static func balanceLabel(score: Int, hasTrainingData: Bool) -> String {
        guard hasTrainingData else { return "Ready" }
        return switch score {
        case 70...:
            "Balanced"
        case 45...:
            "Building"
        default:
            "Needs balance"
        }
    }
}
