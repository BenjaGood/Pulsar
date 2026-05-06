//
//  SleepAnalysis.swift
//  Pulsar
//

import Foundation

enum SleepAnalysisStage: String, CaseIterable, Codable, Equatable {
    case awake
    case asleepCore
    case asleepDeep
    case asleepREM
    case asleepUnspecified
    case inBed

    nonisolated var isAsleep: Bool {
        switch self {
        case .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified: true
        case .awake, .inBed: false
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .awake: "awake"
        case .asleepCore: "asleepCore"
        case .asleepDeep: "asleepDeep"
        case .asleepREM: "asleepREM"
        case .asleepUnspecified: "asleepUnspecified"
        case .inBed: "inBed"
        }
    }

    fileprivate var overlapPriority: Int {
        switch self {
        case .awake: 50
        case .asleepDeep, .asleepREM, .asleepCore: 40
        case .asleepUnspecified: 30
        case .inBed: 10
        }
    }
}

struct SleepAnalysisSample: Codable, Equatable {
    var id: String
    var stage: SleepAnalysisStage
    var start: Date
    var end: Date
    var sourceName: String
    var sourceBundleIdentifier: String?
    var deviceName: String?

    var sourceKey: String {
        [sourceBundleIdentifier, sourceName, deviceName].compactMap { $0 }.joined(separator: "|")
    }
}

struct SleepAnalysisInterval: Codable, Equatable {
    var stage: SleepAnalysisStage
    var start: Date
    var end: Date
    var sourceNames: [String]

    nonisolated var durationMinutes: Double { max(0, end.timeIntervalSince(start) / 60) }
}

struct SleepAnalysisSummary: Codable, Equatable {
    var wakeUpDate: Date
    var queryStart: Date
    var queryEnd: Date
    var rawSampleCount: Int
    var usedSampleCount: Int
    var totalSleepMinutes: Double
    var timeInBedMinutes: Double
    var awakeMinutes: Double
    var wasoMinutes: Double
    var remMinutes: Double
    var coreMinutes: Double
    var deepMinutes: Double
    var asleepUnspecifiedMinutes: Double
    var awakenings: Int
    var mergedIntervals: [SleepAnalysisInterval]
    var sourceNames: [String]

    nonisolated var hasSamples: Bool { usedSampleCount > 0 }
    nonisolated var sleepEfficiency: Double { timeInBedMinutes > 0 ? totalSleepMinutes / timeInBedMinutes : 0 }
}

enum SleepWindowResolver {
    nonisolated static func window(forWakeUpDate wakeUpDate: Date, calendar: Calendar) -> DateInterval {
        let wakeDay = calendar.startOfDay(for: wakeUpDate)
        let previousDay = calendar.date(byAdding: .day, value: -1, to: wakeDay) ?? wakeDay.addingTimeInterval(-86_400)
        let start = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: previousDay) ?? previousDay.addingTimeInterval(18 * 3_600)
        let end = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: wakeDay) ?? wakeDay.addingTimeInterval(12 * 3_600)
        return DateInterval(start: start, end: end)
    }

    nonisolated static func sleepDateKey(forWakeUpDate wakeUpDate: Date, calendar: Calendar) -> String {
        let wakeDay = calendar.startOfDay(for: wakeUpDate)
        let components = calendar.dateComponents([.year, .month, .day], from: wakeDay)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

struct SleepAnalyzer {
    private let sessionGapLimit: TimeInterval = 90 * 60

    func analyze(samples: [SleepAnalysisSample], wakeUpDate: Date, calendar: Calendar) -> SleepAnalysisSummary {
        let wakeDay = calendar.startOfDay(for: wakeUpDate)
        let window = SleepWindowResolver.window(forWakeUpDate: wakeDay, calendar: calendar)
        let clipped = normalizedSamples(samples, in: window)
        let dominantIntervals = mergedDominantIntervals(from: clipped)
        let sessionRange = primarySessionRange(in: dominantIntervals)
        let sessionIntervals = sessionRange.map { range in
            clipIntervals(dominantIntervals, to: range)
        } ?? []
        let bedMinutes = sessionRange.map { range in
            unionDurationMinutes(for: clipped.filter { isBedOccupancyStage($0.stage) }, clippedTo: range)
        } ?? 0
        let timeInBed = max(bedMinutes, minutes(in: sessionIntervals, where: { $0.stage.isAsleep || $0.stage == .awake }))
        let sleepMinutes = minutes(in: sessionIntervals, where: \.stage.isAsleep)
        let awakeMinutes = minutes(in: sessionIntervals, where: { $0.stage == .awake })

        let summary = SleepAnalysisSummary(
            wakeUpDate: wakeDay,
            queryStart: window.start,
            queryEnd: window.end,
            rawSampleCount: samples.count,
            usedSampleCount: clipped.count,
            totalSleepMinutes: sleepMinutes,
            timeInBedMinutes: timeInBed,
            awakeMinutes: awakeMinutes,
            wasoMinutes: wakeAfterSleepOnsetMinutes(sessionIntervals),
            remMinutes: minutes(in: sessionIntervals, where: { $0.stage == .asleepREM }),
            coreMinutes: minutes(in: sessionIntervals, where: { $0.stage == .asleepCore }),
            deepMinutes: minutes(in: sessionIntervals, where: { $0.stage == .asleepDeep }),
            asleepUnspecifiedMinutes: minutes(in: sessionIntervals, where: { $0.stage == .asleepUnspecified }),
            awakenings: awakeningCount(in: sessionIntervals),
            mergedIntervals: sessionIntervals,
            sourceNames: Array(Set(clipped.map(\.sourceName))).sorted()
        )

        SleepDebugLogger.logAnalysis(summary)
        return summary
    }

    private func normalizedSamples(_ samples: [SleepAnalysisSample], in window: DateInterval) -> [SleepAnalysisSample] {
        var seen = Set<String>()
        return samples
            .sorted { lhs, rhs in
                if lhs.start == rhs.start { return lhs.id < rhs.id }
                return lhs.start < rhs.start
            }
            .compactMap { sample in
                let start = max(sample.start, window.start)
                let end = min(sample.end, window.end)
                guard start < end else { return nil }
                let key = dedupeKey(for: sample)
                guard seen.insert(key).inserted else { return nil }
                var clipped = sample
                clipped.start = start
                clipped.end = end
                return clipped
            }
    }

    private func dedupeKey(for sample: SleepAnalysisSample) -> String {
        if !sample.id.isEmpty { return "id:\(sample.id)" }
        return [
            sample.sourceKey,
            sample.stage.rawValue,
            String(sample.start.timeIntervalSinceReferenceDate),
            String(sample.end.timeIntervalSinceReferenceDate)
        ].joined(separator: "|")
    }

    private func mergedDominantIntervals(from samples: [SleepAnalysisSample]) -> [SleepAnalysisInterval] {
        let boundaries = Array(Set(samples.flatMap { [$0.start, $0.end] })).sorted()
        guard boundaries.count >= 2 else { return [] }

        var intervals: [SleepAnalysisInterval] = []
        for index in 0..<(boundaries.count - 1) {
            let start = boundaries[index]
            let end = boundaries[index + 1]
            guard start < end else { continue }
            let active = samples.filter { $0.start < end && $0.end > start }
            guard let stage = dominantStage(in: active) else { continue }
            let sourceNames = Array(Set(active.map(\.sourceName))).sorted()
            appendMerged(SleepAnalysisInterval(stage: stage, start: start, end: end, sourceNames: sourceNames), to: &intervals)
        }
        return intervals
    }

    private func dominantStage(in samples: [SleepAnalysisSample]) -> SleepAnalysisStage? {
        samples
            .map(\.stage)
            .sorted { lhs, rhs in
                if lhs.overlapPriority == rhs.overlapPriority { return lhs.rawValue < rhs.rawValue }
                return lhs.overlapPriority > rhs.overlapPriority
            }
            .first
    }

    private func appendMerged(_ interval: SleepAnalysisInterval, to intervals: inout [SleepAnalysisInterval]) {
        guard let last = intervals.last,
              last.stage == interval.stage,
              last.end == interval.start,
              last.sourceNames == interval.sourceNames else {
            intervals.append(interval)
            return
        }
        intervals[intervals.count - 1].end = interval.end
    }

    private func primarySessionRange(in intervals: [SleepAnalysisInterval]) -> DateInterval? {
        let occupied = intervals.filter { isBedOccupancyStage($0.stage) }
        guard !occupied.isEmpty else { return nil }

        var sessions: [[SleepAnalysisInterval]] = []
        for interval in occupied.sorted(by: { $0.start < $1.start }) {
            guard var current = sessions.popLast() else {
                sessions.append([interval])
                continue
            }
            let previousEnd = current.map(\.end).max() ?? interval.start
            if interval.start.timeIntervalSince(previousEnd) <= sessionGapLimit {
                current.append(interval)
                sessions.append(current)
            } else {
                sessions.append(current)
                sessions.append([interval])
            }
        }

        let best = sessions.max { lhs, rhs in
            let lhsSleep = minutes(in: lhs, where: \.stage.isAsleep)
            let rhsSleep = minutes(in: rhs, where: \.stage.isAsleep)
            if lhsSleep != rhsSleep { return lhsSleep < rhsSleep }
            let lhsDuration = (lhs.map(\.end).max() ?? .distantPast).timeIntervalSince(lhs.map(\.start).min() ?? .distantPast)
            let rhsDuration = (rhs.map(\.end).max() ?? .distantPast).timeIntervalSince(rhs.map(\.start).min() ?? .distantPast)
            if lhsDuration != rhsDuration { return lhsDuration < rhsDuration }
            return (lhs.map(\.end).max() ?? .distantPast) < (rhs.map(\.end).max() ?? .distantPast)
        }

        guard let start = best?.map(\.start).min(), let end = best?.map(\.end).max(), start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    private func clipIntervals(_ intervals: [SleepAnalysisInterval], to range: DateInterval) -> [SleepAnalysisInterval] {
        var clipped: [SleepAnalysisInterval] = []
        for interval in intervals {
            let start = max(interval.start, range.start)
            let end = min(interval.end, range.end)
            guard start < end else { continue }
            appendMerged(SleepAnalysisInterval(stage: interval.stage, start: start, end: end, sourceNames: interval.sourceNames), to: &clipped)
        }
        return clipped
    }

    private func unionDurationMinutes(for samples: [SleepAnalysisSample], clippedTo range: DateInterval) -> Double {
        let intervals = samples.compactMap { sample -> DateInterval? in
            let start = max(sample.start, range.start)
            let end = min(sample.end, range.end)
            guard start < end else { return nil }
            return DateInterval(start: start, end: end)
        }.sorted { $0.start < $1.start }

        var merged: [DateInterval] = []
        for interval in intervals {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }
            if interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged.reduce(0) { $0 + $1.duration / 60 }
    }

    private func wakeAfterSleepOnsetMinutes(_ intervals: [SleepAnalysisInterval]) -> Double {
        guard let firstSleepStart = intervals.first(where: { $0.stage.isAsleep })?.start,
              let lastSleepEnd = intervals.last(where: { $0.stage.isAsleep })?.end else { return 0 }
        return minutes(in: intervals) { interval in
            interval.stage == .awake && interval.start >= firstSleepStart && interval.end <= lastSleepEnd
        }
    }

    private func awakeningCount(in intervals: [SleepAnalysisInterval]) -> Int {
        guard let firstSleepStart = intervals.first(where: { $0.stage.isAsleep })?.start,
              let lastSleepEnd = intervals.last(where: { $0.stage.isAsleep })?.end else { return 0 }
        return intervals.filter { interval in
            interval.stage == .awake &&
                interval.start >= firstSleepStart &&
                interval.end <= lastSleepEnd &&
                interval.durationMinutes >= 1
        }.count
    }

    private func isBedOccupancyStage(_ stage: SleepAnalysisStage) -> Bool {
        stage == .inBed || stage == .awake || stage.isAsleep
    }

    private func minutes<T>(in values: [T], where predicate: (T) -> Bool) -> Double where T: SleepIntervalDuration {
        values.filter(predicate).reduce(0) { $0 + $1.durationMinutes }
    }
}

private protocol SleepIntervalDuration {
    var durationMinutes: Double { get }
}

extension SleepAnalysisInterval: SleepIntervalDuration {}

enum SleepDebugLogger {
    nonisolated static func logQuery(platform: String, start: Date, end: Date, samples: [SleepAnalysisSample]) {
        #if DEBUG
        print("[PulsarSleep][\(platform)] query start=\(start) end=\(end) samples=\(samples.count)")
        for sample in samples {
            print("[PulsarSleep][\(platform)] sample uuid=\(sample.id) source=\(sample.sourceName) device=\(sample.deviceName ?? "-") start=\(sample.start) end=\(sample.end) value=\(sample.stage.displayName)")
        }
        #endif
    }

    nonisolated static func logAnalysis(_ summary: SleepAnalysisSummary) {
        #if DEBUG
        print("[PulsarSleep] analysis wakeUpDate=\(summary.wakeUpDate) queryStart=\(summary.queryStart) queryEnd=\(summary.queryEnd) raw=\(summary.rawSampleCount) used=\(summary.usedSampleCount)")
        for interval in summary.mergedIntervals {
            print("[PulsarSleep] merged stage=\(interval.stage.displayName) start=\(interval.start) end=\(interval.end) minutes=\(interval.durationMinutes) sources=\(interval.sourceNames.joined(separator: ","))")
        }
        print("[PulsarSleep] totals sleep=\(summary.totalSleepMinutes) deep=\(summary.deepMinutes) rem=\(summary.remMinutes) core=\(summary.coreMinutes) unspecified=\(summary.asleepUnspecifiedMinutes) awake=\(summary.awakeMinutes) awakenings=\(summary.awakenings) inBed=\(summary.timeInBedMinutes) waso=\(summary.wasoMinutes) efficiency=\(summary.sleepEfficiency)")
        #endif
    }
}
