import Foundation

extension ConfidenceGrade {
    var syncConfidence: PulsarSyncConfidence {
        switch self {
        case .high: .high
        case .moderate: .moderate
        case .low: .low
        case .missing: .missing
        }
    }
}

extension PulsarSyncConfidence {
    var appConfidence: ConfidenceGrade {
        switch self {
        case .high: .high
        case .moderate: .moderate
        case .low: .low
        case .missing: .missing
        }
    }
}

extension HomeDashboard {
    func syncPayload(sourceDevice: PulsarSyncSourceDevice, syncSessionID: UUID = UUID(), calendar: Calendar = .current) -> PulsarDailyMetricsSyncPayload? {
        let day = calendar.startOfDay(for: sleep.wakeUpDate ?? strain.date ?? recovery.date ?? generatedAt)
        let sleepMetric = sleep.syncMetric(targetSleepHours: profile.sleepSchedule.targetSleepHours, calendar: calendar)
        let strainMetric = strain.syncMetric()
        let recoveryMetric = recovery.syncMetric()
        let hasCompleteDailyMetrics = strainMetric?.isValid == true && recoveryMetric?.isValid == true
        if (strainMetric != nil || recoveryMetric != nil) && !hasCompleteDailyMetrics {
            PulsarSyncDebugLogger.log("invalid or partial Recovery/Strain payload ignored before build dateKey=\(PulsarDailyMetricsDateKey.dateKey(for: day, calendar: calendar)) strainValid=\(strainMetric?.isValid == true) recoveryValid=\(recoveryMetric?.isValid == true)")
        }
        let syncedAt = max(
            max(strain.lastUpdated ?? generatedAt, recovery.lastUpdated ?? generatedAt),
            max(sleep.lastUpdated ?? generatedAt, generatedAt)
        )
        let payload = PulsarDailyMetricsSyncPayload(
            date: day,
            dateKey: PulsarDailyMetricsDateKey.dateKey(for: day, calendar: calendar),
            syncedAt: syncedAt,
            sourceDevice: sourceDevice,
            strain: hasCompleteDailyMetrics ? strainMetric : nil,
            recovery: hasCompleteDailyMetrics ? recoveryMetric : nil,
            sleep: sleepMetric,
            syncSessionID: syncSessionID,
            validityFlag: true
        )
        return payload.isValidPayload ? payload : nil
    }

    func applying(payload: PulsarDailyMetricsSyncPayload, calendar: Calendar = .current) -> HomeDashboard {
        guard payload.isValidPayload,
              payload.applies(to: sleep.wakeUpDate ?? strain.date ?? recovery.date ?? generatedAt, calendar: calendar) else { return self }
        var copy = self
        if payload.hasCompleteDailyScores, let strain = payload.strain, let recovery = payload.recovery {
            let incomingDailyUpdatedAt = max(strain.computedAt, recovery.computedAt)
            let currentDailyUpdatedAt = max(copy.strain.lastUpdated ?? .distantPast, copy.recovery.lastUpdated ?? .distantPast)
            if incomingDailyUpdatedAt >= currentDailyUpdatedAt || copy.strain.score == 0 || copy.recovery.score == 0 {
                copy.strain = copy.strain.applying(syncMetric: strain, sourceDevice: payload.sourceDevice)
                copy.recovery = copy.recovery.applying(syncMetric: recovery, sourceDevice: payload.sourceDevice)
            } else {
                PulsarSyncDebugLogger.log("skipped Recovery/Strain UI update because daily metrics were older dateKey=\(payload.resolvedDateKey) incoming=\(incomingDailyUpdatedAt) current=\(currentDailyUpdatedAt) session=\(payload.syncSessionID?.uuidString ?? "none")")
            }
        }
        if let sleep = payload.sleep, sleep.isValid {
            copy.sleep = copy.sleep.applying(syncMetric: sleep, sourceDevice: payload.sourceDevice)
        }
        copy.generatedAt = max(copy.generatedAt, payload.syncedAt)
        return copy
    }
}

private extension SleepSummary {
    func syncMetric(targetSleepHours: Double, calendar: Calendar) -> PulsarSleepSyncMetric? {
        guard let wakeUpDate,
              let sleepStart,
              let wakeTime,
              let queryStart,
              let queryEnd else { return nil }
        let metric = PulsarSleepSyncMetric(
            score: score,
            confidence: confidence.syncConfidence,
            sleepDateKey: SleepWindowResolver.sleepDateKey(forWakeUpDate: wakeUpDate, calendar: calendar),
            wakeUpDate: calendar.startOfDay(for: wakeUpDate),
            sleepStart: sleepStart,
            sleepEnd: wakeTime,
            queryStart: queryStart,
            queryEnd: queryEnd,
            totalSleepMinutes: totalSleepMinutes,
            timeInBedMinutes: timeInBedMinutes,
            sleepEfficiency: sleepEfficiency,
            awakeMinutes: awakeMinutes,
            wasoMinutes: wasoMinutes,
            remMinutes: stageMinutes(.rem),
            coreMinutes: stageMinutes(.core),
            deepMinutes: stageMinutes(.deep),
            asleepUnspecifiedMinutes: stageMinutes(.asleepUnspecified),
            awakenings: awakenings,
            analyzedSampleCount: analyzedSampleCount,
            sleepConsistency: sleepConsistency,
            sleepPerformance: sleepPerformance,
            durationAdequacy: durationAdequacy,
            regularity: regularity,
            continuity: continuity,
            targetSleepHours: targetSleepHours,
            sourceNames: sourceBadges.map(\.displayName),
            computedAt: lastUpdated ?? Date()
        )
        return metric.isValid ? metric : nil
    }

    func applying(syncMetric: PulsarSleepSyncMetric, sourceDevice: PulsarSyncSourceDevice) -> SleepSummary {
        var copy = self
        copy.wakeUpDate = syncMetric.wakeUpDate
        copy.score = syncMetric.score
        copy.confidence = syncMetric.confidence.appConfidence
        copy.confidenceExplanation = sleepConfidenceExplanation(for: syncMetric)
        copy.timeInBedMinutes = syncMetric.timeInBedMinutes
        copy.totalSleepMinutes = syncMetric.totalSleepMinutes
        copy.sleepEfficiency = syncMetric.sleepEfficiency
        copy.awakeMinutes = syncMetric.awakeMinutes
        copy.wasoMinutes = syncMetric.wasoMinutes
        copy.sleepConsistency = syncMetric.sleepConsistency
        copy.sleepPerformance = syncMetric.sleepPerformance
        copy.durationAdequacy = syncMetric.durationAdequacy
        copy.regularity = syncMetric.regularity
        copy.continuity = syncMetric.continuity
        copy.stageBreakdown = stageBreakdown(from: syncMetric)
        copy.sleepStart = syncMetric.sleepStart
        copy.wakeTime = syncMetric.sleepEnd
        copy.awakenings = syncMetric.awakenings
        copy.analyzedSampleCount = syncMetric.analyzedSampleCount
        copy.queryStart = syncMetric.queryStart
        copy.queryEnd = syncMetric.queryEnd
        copy.lastUpdated = syncMetric.computedAt
        copy.sourceBadges = mergeSources(existing: copy.sourceBadges, names: syncMetric.sourceNames, sourceDevice: sourceDevice)
        copy.notes = mergeNotes(copy.notes, sourceDevice: sourceDevice, title: "Synced sleep from \(sourceDevice == .appleWatch ? "Apple Watch" : "iPhone") while local HealthKit data refreshes.")
        return copy
    }

    func stageMinutes(_ stage: SleepStage) -> Double {
        stageBreakdown.first(where: { $0.stage == stage })?.minutes ?? 0
    }

    func stageBreakdown(from metric: PulsarSleepSyncMetric) -> [StageMetric] {
        let total = max(1, metric.totalSleepMinutes)
        return [
            StageMetric(stage: .deep, minutes: metric.deepMinutes, percentOfSleep: metric.deepMinutes / total),
            StageMetric(stage: .rem, minutes: metric.remMinutes, percentOfSleep: metric.remMinutes / total),
            StageMetric(stage: .core, minutes: metric.coreMinutes, percentOfSleep: metric.coreMinutes / total),
            StageMetric(stage: .asleepUnspecified, minutes: metric.asleepUnspecifiedMinutes, percentOfSleep: metric.asleepUnspecifiedMinutes / total),
            StageMetric(stage: .awake, minutes: metric.awakeMinutes, percentOfSleep: 0)
        ].filter { $0.minutes > 0 }
    }

    func sleepConfidenceExplanation(for metric: PulsarSleepSyncMetric) -> String {
        switch metric.confidence {
        case .high: "Sleep/wake and Apple-style Core, Deep, and REM stages were available from the primary source."
        case .moderate: "Only binary asleep/awake sleep was available, so stage percentages are limited."
        case .low: "Sleep coverage was limited for this synced score."
        case .missing: SleepSummary.missing.confidenceExplanation
        }
    }
}

private extension StrainSummary {
    func syncMetric() -> PulsarStrainSyncMetric? {
        let metric = PulsarStrainSyncMetric(
            score: score,
            confidence: confidence.syncConfidence,
            rawLoad: rawLoad,
            workoutLoad: workoutLoad,
            movementLoad: movementLoad,
            steps: steps,
            activeEnergyKilocalories: activeEnergyKilocalories,
            exerciseMinutes: exerciseMinutes,
            workoutMinutes: workoutMinutes,
            averageActiveHeartRate: averageActiveHeartRate,
            peakHeartRate: peakHeartRate,
            sourceNames: sourceBadges.map(\.displayName),
            computedAt: lastUpdated ?? Date()
        )
        return metric.isValid ? metric : nil
    }

    func applying(syncMetric: PulsarStrainSyncMetric, sourceDevice: PulsarSyncSourceDevice) -> StrainSummary {
        var copy = self
        copy.date = copy.date ?? syncMetric.computedAt
        copy.score = syncMetric.score
        copy.confidence = syncMetric.confidence.appConfidence
        copy.rawLoad = syncMetric.rawLoad
        copy.workoutLoad = syncMetric.workoutLoad
        copy.movementLoad = syncMetric.movementLoad
        copy.steps = max(copy.steps, syncMetric.steps)
        copy.activeEnergyKilocalories = syncMetric.activeEnergyKilocalories ?? copy.activeEnergyKilocalories
        copy.exerciseMinutes = max(copy.exerciseMinutes, syncMetric.exerciseMinutes)
        copy.workoutMinutes = max(copy.workoutMinutes, syncMetric.workoutMinutes)
        copy.averageActiveHeartRate = syncMetric.averageActiveHeartRate ?? copy.averageActiveHeartRate
        copy.peakHeartRate = syncMetric.peakHeartRate ?? copy.peakHeartRate
        copy.lastUpdated = syncMetric.computedAt
        if copy.queryEnd == nil { copy.queryEnd = syncMetric.computedAt }
        copy.sourceBadges = mergeSources(existing: copy.sourceBadges, names: syncMetric.sourceNames, sourceDevice: sourceDevice)
        copy.notes = mergeNotes(copy.notes, sourceDevice: sourceDevice, title: "Synced strain from \(sourceDevice == .appleWatch ? "Apple Watch" : "iPhone") while local HealthKit data refreshes.")
        return copy
    }
}

private extension RecoverySummary {
    func syncMetric() -> PulsarRecoverySyncMetric? {
        let metric = PulsarRecoverySyncMetric(
            score: score,
            confidence: confidence.syncConfidence,
            statusText: status.label,
            hrvSDNN: hrvSDNN,
            hrvBaseline: hrvBaseline,
            restingHeartRate: restingHeartRate,
            restingHeartRateBaseline: restingHeartRateBaseline,
            sleepDuration: sleepDuration,
            sleepEfficiency: sleepEfficiency,
            strainScore: strainScore,
            respiratoryRate: respiratoryRate,
            oxygenSaturation: oxygenSaturation,
            wristTemperatureDeviation: wristTemperatureDeviation,
            hrvReadiness: hrvReadiness,
            restingHeartRateReadiness: restingHeartRateReadiness,
            respiratoryStability: respiratoryStability,
            sleepContribution: sleepContribution,
            strainPenalty: strainPenalty,
            sourceNames: sourceBadges.map(\.displayName),
            computedAt: lastUpdated ?? Date()
        )
        return metric.isValid ? metric : nil
    }

    func applying(syncMetric: PulsarRecoverySyncMetric, sourceDevice: PulsarSyncSourceDevice) -> RecoverySummary {
        var copy = self
        copy.date = copy.date ?? syncMetric.computedAt
        copy.score = syncMetric.score
        copy.confidence = syncMetric.confidence.appConfidence
        copy.status = statusFromLabel(syncMetric.statusText)
        copy.hrvSDNN = syncMetric.hrvSDNN ?? copy.hrvSDNN
        copy.hrvBaseline = syncMetric.hrvBaseline ?? copy.hrvBaseline
        copy.restingHeartRate = syncMetric.restingHeartRate ?? copy.restingHeartRate
        copy.restingHeartRateBaseline = syncMetric.restingHeartRateBaseline ?? copy.restingHeartRateBaseline
        copy.sleepDuration = syncMetric.sleepDuration ?? copy.sleepDuration
        copy.sleepEfficiency = syncMetric.sleepEfficiency ?? copy.sleepEfficiency
        copy.strainScore = syncMetric.strainScore ?? copy.strainScore
        copy.respiratoryRate = syncMetric.respiratoryRate ?? copy.respiratoryRate
        copy.oxygenSaturation = syncMetric.oxygenSaturation ?? copy.oxygenSaturation
        copy.wristTemperatureDeviation = syncMetric.wristTemperatureDeviation ?? copy.wristTemperatureDeviation
        copy.hrvReadiness = max(copy.hrvReadiness, syncMetric.hrvReadiness)
        copy.restingHeartRateReadiness = max(copy.restingHeartRateReadiness, syncMetric.restingHeartRateReadiness)
        copy.respiratoryStability = max(copy.respiratoryStability, syncMetric.respiratoryStability)
        copy.sleepContribution = max(copy.sleepContribution, syncMetric.sleepContribution)
        copy.strainPenalty = max(copy.strainPenalty, syncMetric.strainPenalty)
        copy.lastUpdated = syncMetric.computedAt
        if copy.queryEnd == nil { copy.queryEnd = syncMetric.computedAt }
        copy.sourceBadges = mergeSources(existing: copy.sourceBadges, names: syncMetric.sourceNames, sourceDevice: sourceDevice)
        copy.notes = mergeNotes(copy.notes, sourceDevice: sourceDevice, title: "Synced recovery from \(sourceDevice == .appleWatch ? "Apple Watch" : "iPhone") while local HealthKit data refreshes.")
        if copy.explanation.isEmpty || copy.explanation == RecoverySummary.missing.explanation {
            copy.explanation = syncMetric.statusText
        }
        return copy
    }
}

private func mergeSources(existing: [SourceProvenance], names: [String], sourceDevice: PulsarSyncSourceDevice) -> [SourceProvenance] {
    let syncedSources = names.map {
        SourceProvenance(
            sourceName: $0,
            sourceBundleIdentifier: nil,
            sourceVersion: nil,
            operatingSystemVersion: nil,
            productType: sourceDevice == .appleWatch ? "AppleWatchSync" : "iPhoneSync",
            deviceName: $0,
            deviceManufacturer: "Apple",
            deviceModel: sourceDevice == .appleWatch ? "Apple Watch" : "iPhone"
        )
    }
    return SourceResolver.uniqueSourceBadges(existing + syncedSources)
}

private func mergeNotes(_ existing: [String], sourceDevice: PulsarSyncSourceDevice, title: String) -> [String] {
    let combined = existing + [title]
    var seen = Set<String>()
    return combined.filter { seen.insert($0).inserted }
}

private func statusFromLabel(_ label: String) -> RecoveryStatus {
    switch label {
    case RecoveryStatus.excellent.label: .excellent
    case RecoveryStatus.balanced.label: .balanced
    case RecoveryStatus.moderate.label: .moderate
    case RecoveryStatus.low.label: .low
    case RecoveryStatus.needsAttention.label: .needsAttention
    default: .unknown
    }
}
