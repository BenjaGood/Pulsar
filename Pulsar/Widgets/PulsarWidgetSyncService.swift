import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

struct PulsarWidgetSyncService {
    private let store: PulsarWidgetStore
    private let calendar: Calendar

    init(store: PulsarWidgetStore = PulsarWidgetStore(), calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    func persist(dashboard: HomeDashboard) {
        let snapshot = dashboard.widgetSnapshot(calendar: calendar)
        guard store.save(snapshot) else { return }
        reloadTimelines()
    }

    private func reloadTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: PulsarWidgetKind.mainMetrics)
        WidgetCenter.shared.reloadTimelines(ofKind: PulsarWidgetKind.stress)
        #endif
    }
}

private extension HomeDashboard {
    func widgetSnapshot(calendar: Calendar) -> PulsarWidgetSnapshot {
        let recoveryScore = recovery.score > 0 ? recovery.score : nil
        let strainTargetRange = PulsarSharedMetricCalculator.recommendedStrainTargetRange(forRecoveryScore: recoveryScore)
        let metrics: [PulsarWidgetMetricSnapshot] = [
            sleepWidgetSnapshot,
            recoveryWidgetSnapshot,
            strainWidgetSnapshot(targetRange: strainTargetRange)
        ]
        let stress = stressWidgetSnapshot
        let lastUpdated = ([sleep.lastUpdated, recovery.lastUpdated, strain.lastUpdated, stress.updatedAt, generatedAt] as [Date?])
            .compactMap { $0 }
            .max()

        return PulsarWidgetSnapshot(
            generatedAt: generatedAt,
            lastUpdated: lastUpdated,
            metrics: metrics,
            stress: stress,
            emptyMessage: PulsarWidgetSnapshot.emptyMessageText
        )
    }

    var sleepWidgetSnapshot: PulsarWidgetMetricSnapshot {
        let score = sleep.score > 0 ? sleep.score : nil
        let secondary: String?
        if sleep.sleepEfficiency > 0 {
            secondary = "\(Int((sleep.sleepEfficiency * 100).rounded()))% efficiency"
        } else if sleep.awakenings > 0 {
            secondary = "\(sleep.awakenings) awakenings"
        } else {
            secondary = nil
        }

        return PulsarWidgetMetricSnapshot(
            kind: .sleep,
            score: score,
            detailText: sleepDetailText,
            secondaryText: secondary,
            updatedAt: sleep.lastUpdated
        )
    }

    var recoveryWidgetSnapshot: PulsarWidgetMetricSnapshot {
        let score = recovery.score > 0 ? recovery.score : nil
        let secondary: String?
        if let hrvSDNN = recovery.hrvSDNN {
            secondary = "HRV \(Int(hrvSDNN.rounded())) ms"
        } else if let sleepDuration = recovery.sleepDuration {
            secondary = durationText(minutes: sleepDuration / 60)
        } else {
            secondary = nil
        }

        return PulsarWidgetMetricSnapshot(
            kind: .recovery,
            score: score,
            detailText: recoveryDetailText,
            secondaryText: secondary,
            updatedAt: recovery.lastUpdated
        )
    }

    func strainWidgetSnapshot(targetRange: PulsarSharedStrainTargetRange?) -> PulsarWidgetMetricSnapshot {
        let hasScore = hasCurrentStrainValue(strain)
        let secondary: String?
        if let targetRange {
            secondary = "Target \(targetRange.displayText)"
        } else if strain.steps > 0 {
            secondary = "\(strain.steps.formatted()) steps"
        } else {
            secondary = nil
        }

        return PulsarWidgetMetricSnapshot(
            kind: .strain,
            score: hasScore ? strain.score : nil,
            detailText: strainDetailText,
            secondaryText: secondary,
            updatedAt: strain.lastUpdated
        )
    }

    var stressWidgetSnapshot: PulsarWidgetStressSnapshot {
        let state: PulsarWidgetStressState
        switch stress.state {
        case .ready, .lowConfidence:
            state = .ready
        case .buildingBaseline:
            state = .buildingBaseline
        case .workoutPaused, .cooldown:
            state = .paused
        case .noData:
            state = .noData
        }

        return PulsarWidgetStressSnapshot(
            state: state,
            score: stress.score,
            statusText: stress.displayLevelText,
            insightText: stress.driverInsights.first ?? stress.explanation,
            updatedAt: stress.lastUpdated
        )
    }

    var sleepDetailText: String {
        guard sleep.score > 0 else {
            if sleep.confidenceExplanation == SleepSummary.permissionRequired.confidenceExplanation {
                return "Health access needed"
            }
            return "Awaiting sleep"
        }
        return "\(durationText(minutes: sleep.totalSleepMinutes)) sleep"
    }

    var recoveryDetailText: String {
        guard recovery.score > 0 else {
            return "Build baseline"
        }
        return recovery.status.label
    }

    var strainDetailText: String {
        guard hasCurrentStrainValue(strain) else {
            return "Awaiting load"
        }
        if strain.workoutMinutes > 0 {
            return "\(durationText(minutes: strain.workoutMinutes)) training"
        }
        if strain.steps > 0 {
            return "\(strain.steps.formatted()) steps"
        }
        return "Current \(strain.score)"
    }

    func hasCurrentStrainValue(_ summary: StrainSummary) -> Bool {
        summary.lastUpdated != nil ||
            summary.confidence != .missing ||
            summary.score > 0 ||
            summary.steps > 0 ||
            summary.workoutMinutes > 0 ||
            summary.exerciseMinutes > 0 ||
            (summary.activeEnergyKilocalories ?? 0) > 0
    }

    func durationText(minutes: Double) -> String {
        let roundedMinutes = max(0, Int(minutes.rounded()))
        let hours = roundedMinutes / 60
        let remainder = roundedMinutes % 60

        if hours > 0 && remainder > 0 {
            return "\(hours)h \(remainder)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(remainder)m"
    }
}
