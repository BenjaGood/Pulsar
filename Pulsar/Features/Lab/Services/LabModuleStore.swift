//
//  LabModuleStore.swift
//  Pulsar
//

import Combine
import Foundation
import UIKit

@MainActor
final class LabModuleStore: ObservableObject {
    @Published private(set) var state: LabModuleState

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let historyStore: DailyHealthHistoryStore
    private let engine: LabBiologicalAgeEngine
    private let importService: LabResultsImportService
    private let biomarkerStorageKey = "pulsar.lab.biomarkers.v1"
    private let resultHistoryStorageKey = "pulsar.lab.biologicalAgeHistory.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        historyStore: DailyHealthHistoryStore? = nil,
        engine: LabBiologicalAgeEngine? = nil,
        importService: LabResultsImportService? = nil
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.historyStore = historyStore ?? DailyHealthHistoryStore(defaults: defaults)
        self.engine = engine ?? LabBiologicalAgeEngine(calendar: calendar)
        self.importService = importService ?? LabResultsImportService()
        self.state = LabModuleState(
            latestBiologicalAgeResult: Self.loadResultHistory(defaults: defaults, key: resultHistoryStorageKey, decoder: decoder).last,
            biomarkers: Self.loadBiomarkers(defaults: defaults, key: biomarkerStorageKey, decoder: decoder),
            importStatus: .idle,
            manualEntryState: ManualBiomarkerEntryState()
        )
    }

    var displayedBiomarkers: [LabBiomarker] {
        let latest = latestBiomarkersByDefinition(state.biomarkers)
        let requiredRows = LabBiomarkerDefinition.required.enumerated().map { index, definition -> LabBiomarker in
            if var biomarker = latest[definition.id] {
                biomarker.status = definition.status(for: biomarker.value)
                if biomarker.unit.isEmpty {
                    biomarker.unit = definition.unit
                }
                biomarker.referenceLow = biomarker.referenceLow ?? definition.referenceLow
                biomarker.referenceHigh = biomarker.referenceHigh ?? definition.referenceHigh
                return biomarker
            }

            return LabBiomarker(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1)) ?? UUID(),
                name: definition.name,
                value: nil,
                unit: definition.unit,
                referenceLow: definition.referenceLow,
                referenceHigh: definition.referenceHigh,
                status: .missing,
                collectedAt: nil,
                source: .other,
                notes: definition.explanation
            )
        }

        let requiredKeys = Set(LabBiomarkerDefinition.required.map(\.id))
        let customRows = state.biomarkers
            .filter { biomarker in
                guard let definition = LabBiomarkerDefinition.definition(for: biomarker.name) else { return true }
                return !requiredKeys.contains(definition.id)
            }
            .sorted { ($0.collectedAt ?? .distantPast) > ($1.collectedAt ?? .distantPast) }

        return requiredRows + customRows
    }

    var missingBiomarkerNames: [String] {
        displayedBiomarkers
            .filter { $0.status == .missing }
            .map(\.name)
    }

    var biologicalAgeTrendResults: [BiologicalAgeResult] {
        Array(weeklyTrendResults().suffix(4))
    }

    func refresh(profile: UserProfile, now: Date = Date()) {
        var result = engine.calculate(input: makeBiologicalAgeInput(profile: profile, now: now))
        if var calculated = result {
            calculated = applyingPace(to: calculated, previousResults: previousDistinctResults(before: calculated.updatedAt))
            persist(result: calculated)
            result = calculated
        }
        state.latestBiologicalAgeResult = result ?? state.latestBiologicalAgeResult ?? loadResultHistory().last
    }

    @discardableResult
    func addManualBiomarker(
        name: String,
        value: Double,
        unit: String,
        collectedAt: Date,
        referenceLow: Double?,
        referenceHigh: Double?,
        notes: String?,
        profile: UserProfile
    ) -> LabBiomarker {
        let definition = LabBiomarkerDefinition.definition(for: name)
        let resolvedName = definition?.name ?? name
        let resolvedUnit = unit.nilIfBlank ?? definition?.unit ?? ""
        let resolvedLow = referenceLow ?? definition?.referenceLow
        let resolvedHigh = referenceHigh ?? definition?.referenceHigh
        let status = definition?.status(for: value) ?? status(value: value, referenceLow: resolvedLow, referenceHigh: resolvedHigh)
        let biomarker = LabBiomarker(
            name: resolvedName,
            value: value,
            unit: resolvedUnit,
            referenceLow: resolvedLow,
            referenceHigh: resolvedHigh,
            status: status,
            collectedAt: collectedAt,
            source: .manual,
            notes: notes
        )
        state.biomarkers.removeAll { existing in
            existing.name.normalizedBiomarkerKey == biomarker.name.normalizedBiomarkerKey &&
                calendar.isDate(existing.collectedAt ?? .distantPast, inSameDayAs: collectedAt)
        }
        state.biomarkers.insert(biomarker, at: 0)
        persistBiomarkers()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        refresh(profile: profile)
        return biomarker
    }

    func deleteBiomarker(_ biomarker: LabBiomarker, profile: UserProfile) {
        guard biomarker.value != nil else { return }
        state.biomarkers.removeAll { $0.id == biomarker.id }
        persistBiomarkers()
        refresh(profile: profile)
    }

    func importPDF(from url: URL, profile: UserProfile) async {
        state.importStatus = .importing(progress: 0.08)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        for progress in [0.22, 0.38, 0.56, 0.74] {
            try? await Task.sleep(nanoseconds: 160_000_000)
            state.importStatus = .importing(progress: progress)
        }

        do {
            let extracted = try await importService.extractBiomarkers(from: url)
            state.importStatus = extracted.isEmpty
                ? .comingSoon(message: "PDF import is coming soon. You can manually enter biomarkers for now.")
                : .review(extracted: extracted)
        } catch LabResultsImportError.notImplemented {
            state.importStatus = .comingSoon(message: "PDF import is coming soon. You can manually enter biomarkers for now.")
        } catch {
            state.importStatus = .failed(message: "We could not import this PDF yet. You can manually enter biomarkers for now.")
        }

        refresh(profile: profile)
    }

    func confirmImportedBiomarkers(_ biomarkers: [LabBiomarker], profile: UserProfile) {
        guard !biomarkers.isEmpty else {
            state.importStatus = .idle
            return
        }
        state.biomarkers.insert(contentsOf: biomarkers, at: 0)
        persistBiomarkers()
        state.importStatus = .idle
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        refresh(profile: profile)
    }

    func resetImportStatus() {
        state.importStatus = .idle
    }

    private func makeBiologicalAgeInput(profile: UserProfile, now: Date) -> LabBiologicalAgeInput {
        let recentRecords = recentWearableRecords(now: now)
        let physiological = LabPhysiologicalFitnessInput(
            wearableDataDays: recentRecords.count,
            averageSleepDurationHours: average(recentRecords.compactMap { $0.sleepMinutes.map { Double($0) / 60 } }),
            sleepConsistency: sleepConsistency(from: recentRecords),
            activityMinutesZone2to3PerWeek: estimatedWeeklyZoneMinutes(records: recentRecords, multiplier: 0.65),
            activityMinutesZone4to5PerWeek: estimatedWeeklyZoneMinutes(records: recentRecords, multiplier: 0.20),
            strengthTrainingSessionsPerWeek: nil,
            dailyStepAverage: average(recentRecords.map(\.steps).filter { $0 > 0 }.map(Double.init)),
            vo2Max: nil,
            restingHeartRate: average(recentRecords.compactMap(\.restingHeartRate)),
            leanBodyMassKilograms: nil,
            chronologicalAge: profile.age(on: now, calendar: calendar).map(Double.init),
            biologicalSex: profile.resolvedBiologicalSex
        )

        return LabBiologicalAgeInput(
            chronologicalAge: profile.age(on: now, calendar: calendar).map(Double.init),
            biologicalSex: profile.resolvedBiologicalSex,
            physiological: physiological,
            lifestyle: nil,
            biomarkers: state.biomarkers,
            now: now
        )
    }

    private func recentWearableRecords(now: Date) -> [DailyStrainRecord] {
        let start = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(-28 * 86_400)
        return historyStore.loadRecords(calendar: calendar)
            .filter { record in
                record.date >= start && record.date <= now && record.hasRecordedData
            }
            .sorted { $0.date < $1.date }
    }

    private func sleepConsistency(from records: [DailyStrainRecord]) -> Double? {
        let sleepMinutes = records.compactMap(\.sleepMinutes).map(Double.init)
        guard sleepMinutes.count >= 2 else { return nil }
        let mean = average(sleepMinutes) ?? 0
        let variance = sleepMinutes.reduce(0) { $0 + pow($1 - mean, 2) } / Double(sleepMinutes.count)
        let standardDeviation = sqrt(variance)
        return min(max(1 - standardDeviation / 120, 0), 1)
    }

    private func estimatedWeeklyZoneMinutes(records: [DailyStrainRecord], multiplier: Double) -> Double? {
        let workoutMinutes = records.map(\.workoutMinutes).filter { $0 > 0 }
        guard !workoutMinutes.isEmpty else { return nil }
        let total = workoutMinutes.reduce(0, +)
        return Double(total) / 4.0 * multiplier
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func latestBiomarkersByDefinition(_ biomarkers: [LabBiomarker]) -> [String: LabBiomarker] {
        var latest: [String: LabBiomarker] = [:]
        for biomarker in biomarkers {
            guard let definition = LabBiomarkerDefinition.definition(for: biomarker.name) else { continue }
            let current = latest[definition.id]
            if current == nil || (biomarker.collectedAt ?? .distantPast) > (current?.collectedAt ?? .distantPast) {
                latest[definition.id] = biomarker
            }
        }
        return latest
    }

    private func status(value: Double, referenceLow: Double?, referenceHigh: Double?) -> LabBiomarkerStatus {
        if let referenceLow, value < referenceLow { return .low }
        if let referenceHigh, value > referenceHigh { return .high }
        return .normal
    }

    private func applyingPace(to result: BiologicalAgeResult, previousResults: [BiologicalAgeResult]) -> BiologicalAgeResult {
        guard previousResults.count >= 2,
              let previous = previousResults.last,
              result.updatedAt.timeIntervalSince(previous.updatedAt) >= 6 * 86_400 else {
            return result
        }

        var copy = result
        let elapsedWeeks = max(result.updatedAt.timeIntervalSince(previous.updatedAt) / (7 * 86_400), 1)
        let deltaChangePerWeek = (result.ageDelta - previous.ageDelta) / elapsedWeeks
        copy.paceOfAging = min(max(1 + deltaChangePerWeek * 0.10, 0.6), 1.4)
        return copy
    }

    private func previousDistinctResults(before date: Date) -> [BiologicalAgeResult] {
        loadResultHistory()
            .filter { !calendar.isDate($0.updatedAt, inSameDayAs: date) && $0.updatedAt < date }
    }

    private func weeklyTrendResults() -> [BiologicalAgeResult] {
        let history = loadResultHistory()
        var latestByWeek: [DateComponents: BiologicalAgeResult] = [:]

        for result in history {
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: result.updatedAt)
            guard components.yearForWeekOfYear != nil, components.weekOfYear != nil else { continue }
            if let existing = latestByWeek[components],
               existing.updatedAt >= result.updatedAt {
                continue
            }
            latestByWeek[components] = result
        }

        return latestByWeek.values.sorted { $0.updatedAt < $1.updatedAt }
    }

    private func persist(result: BiologicalAgeResult) {
        var history = loadResultHistory()
        if let lastIndex = history.indices.last,
           calendar.isDate(history[lastIndex].updatedAt, inSameDayAs: result.updatedAt) {
            history[lastIndex] = result
        } else {
            history.append(result)
        }
        history = Array(history.suffix(24))
        guard let data = try? encoder.encode(history) else { return }
        defaults.set(data, forKey: resultHistoryStorageKey)
    }

    private func persistBiomarkers() {
        let sorted = state.biomarkers.sorted { ($0.collectedAt ?? .distantPast) > ($1.collectedAt ?? .distantPast) }
        state.biomarkers = sorted
        guard let data = try? encoder.encode(sorted) else { return }
        defaults.set(data, forKey: biomarkerStorageKey)
    }

    private func loadResultHistory() -> [BiologicalAgeResult] {
        Self.loadResultHistory(defaults: defaults, key: resultHistoryStorageKey, decoder: decoder)
    }

    private static func loadBiomarkers(defaults: UserDefaults, key: String, decoder: JSONDecoder) -> [LabBiomarker] {
        guard let data = defaults.data(forKey: key),
              let biomarkers = try? decoder.decode([LabBiomarker].self, from: data) else { return [] }
        return biomarkers.sorted { ($0.collectedAt ?? .distantPast) > ($1.collectedAt ?? .distantPast) }
    }

    private static func loadResultHistory(defaults: UserDefaults, key: String, decoder: JSONDecoder) -> [BiologicalAgeResult] {
        guard let data = defaults.data(forKey: key),
              let history = try? decoder.decode([BiologicalAgeResult].self, from: data) else { return [] }
        return history.sorted { $0.updatedAt < $1.updatedAt }
    }
}

enum LabResultsImportError: Error {
    case notImplemented
}

struct LabResultsImportService {
    func extractBiomarkers(from url: URL) async throws -> [LabBiomarker] {
        _ = url
        try await Task.sleep(nanoseconds: 220_000_000)
        throw LabResultsImportError.notImplemented
    }
}
