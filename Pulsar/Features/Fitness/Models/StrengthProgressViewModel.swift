//
//  StrengthProgressViewModel.swift
//  Pulsar
//

import Combine
import Foundation

@MainActor
final class StrengthProgressViewModel: ObservableObject {
    @Published private(set) var dashboard: StrengthProgressDashboard
    @Published private(set) var selectedTimeRange: StrengthProgressTimeRange
    @Published private(set) var isLoading = false

    private let historyStore: PulsarGymWorkoutHistoryStore
    private let calendar: Calendar
    private var cache: [StrengthProgressCacheKey: StrengthProgressDashboard] = [:]
    private var lastHistorySignature: String = ""

    init(
        historyStore: PulsarGymWorkoutHistoryStore? = nil,
        calendar: Calendar = .autoupdatingCurrent,
        initialTimeRange: StrengthProgressTimeRange = .threeMonths,
        displayUnit: PulsarWeightUnit = .kilograms
    ) {
        self.historyStore = historyStore ?? .shared
        self.calendar = calendar
        self.selectedTimeRange = initialTimeRange
        self.dashboard = .empty(timeRange: initialTimeRange, displayUnit: displayUnit)
    }

    func load(displayUnit: PulsarWeightUnit) async {
        await refresh(displayUnit: displayUnit, force: false)
    }

    func refresh(displayUnit: PulsarWeightUnit, force: Bool = false) async {
        historyStore.reload()
        let signature = historySignature(for: historyStore.sessions)
        if signature != lastHistorySignature {
            cache.removeAll()
            lastHistorySignature = signature
        }

        let key = StrengthProgressCacheKey(
            signature: signature,
            timeRange: selectedTimeRange,
            displayUnit: displayUnit
        )

        if !force, let cached = cache[key] {
            dashboard = cached
            return
        }

        isLoading = true
        await Task.yield()
        let nextDashboard = StrengthProgressAnalyticsService.dashboard(
            sessions: historyStore.sessions,
            timeRange: selectedTimeRange,
            displayUnit: displayUnit,
            now: Date(),
            calendar: calendar
        )
        cache[key] = nextDashboard
        dashboard = nextDashboard
        isLoading = false
    }

    func selectTimeRange(_ timeRange: StrengthProgressTimeRange, displayUnit: PulsarWeightUnit) async {
        guard timeRange != selectedTimeRange else { return }
        selectedTimeRange = timeRange
        await refresh(displayUnit: displayUnit, force: false)
    }

    private func historySignature(for sessions: [PulsarGymWorkoutSession]) -> String {
        let completed = sessions.filter { $0.finishedAt != nil }
        let first = completed.first
        let last = completed.last
        let firstPart = first.map { "\($0.id.uuidString)-\(Int($0.startedAt.timeIntervalSince1970))-\($0.exercises.count)" } ?? "none"
        let lastPart = last.map { "\($0.id.uuidString)-\(Int(($0.finishedAt ?? $0.startedAt).timeIntervalSince1970))-\($0.exercises.count)" } ?? "none"
        return "\(completed.count)-\(firstPart)-\(lastPart)"
    }
}

private struct StrengthProgressCacheKey: Hashable {
    var signature: String
    var timeRange: StrengthProgressTimeRange
    var displayUnit: PulsarWeightUnit
}
