//
//  SleepDataService.swift
//  Pulsar
//

import Foundation

protocol SleepSummaryProviding {
    func sleepSummary(profile: UserProfile, wakeUpDate: Date, calendar: Calendar, refreshedAt: Date) async throws -> SleepSummary
}

struct SleepDataService: SleepSummaryProviding {
    var healthKit: HealthKitGateway

    init(healthKit: HealthKitGateway = HealthKitGateway()) {
        self.healthKit = healthKit
    }

    func sleepSummary(profile: UserProfile, wakeUpDate: Date, calendar: Calendar, refreshedAt: Date) async throws -> SleepSummary {
        let window = SleepWindowResolver.window(forWakeUpDate: wakeUpDate, calendar: calendar)
        let sleepDateKey = SleepWindowResolver.sleepDateKey(forWakeUpDate: wakeUpDate, calendar: calendar)
        PulsarSyncDebugLogger.log("Sleep sync selected canonical window sleepDateKey=\(sleepDateKey) start=\(window.start) end=\(window.end)")
        let segments = await healthKit.fetchSleepSegments(start: window.start, end: window.end)
        PulsarSyncDebugLogger.log("HealthKit sleep samples loaded count=\(segments.count) sleepDateKey=\(sleepDateKey)")
        guard !segments.isEmpty else { return .missing.withDetailsDate(wakeUpDate, calendar: calendar, refreshedAt: refreshedAt) }

        let night = NightlySleepInput(nightStart: window.start, nightEnd: window.end, segments: segments)
        var recent: [NightlySleepInput] = []
        for offset in 1...10 {
            guard let priorWakeDate = calendar.date(byAdding: .day, value: -offset, to: wakeUpDate) else { continue }
            let priorWindow = SleepWindowResolver.window(forWakeUpDate: priorWakeDate, calendar: calendar)
            let priorSegments = await healthKit.fetchSleepSegments(start: priorWindow.start, end: priorWindow.end)
            if !priorSegments.isEmpty {
                recent.append(NightlySleepInput(nightStart: priorWindow.start, nightEnd: priorWindow.end, segments: priorSegments))
            }
        }

        var summary = SleepScoringEngine(calendar: calendar).score(night: night, recentNights: recent, schedule: profile.sleepSchedule)
        summary.lastUpdated = refreshedAt
        return summary
    }
}

private extension SleepSummary {
    func withDetailsDate(_ wakeUpDate: Date, calendar: Calendar, refreshedAt: Date) -> SleepSummary {
        var copy = self
        copy.wakeUpDate = wakeUpDate
        copy.lastUpdated = refreshedAt
        let window = SleepWindowResolver.window(forWakeUpDate: wakeUpDate, calendar: calendar)
        copy.queryStart = window.start
        copy.queryEnd = window.end
        return copy
    }
}
