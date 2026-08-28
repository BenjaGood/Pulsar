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
    nonisolated var appConfidence: ConfidenceGrade {
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
        let day = calendar.startOfDay(for: sleep.wakeUpDate ?? strain.date ?? recovery.date ?? healthMonitor.date ?? generatedAt)
        let sleepMetric = sleep.syncMetric(targetSleepHours: profile.sleepSchedule.targetSleepHours, calendar: calendar)
        let strainMetric = strain.syncMetric()
        let recoveryMetric = recovery.syncMetric()
        let stressMetric = stress.syncMetric()
        let healthMonitorMetric = healthMonitor.syncMetric()
        let validStrainMetric = strainMetric?.isValid == true ? strainMetric : nil
        let validRecoveryMetric = recoveryMetric?.isValid == true ? recoveryMetric : nil
        if strainMetric != nil && validStrainMetric == nil {
            PulsarSyncDebugLogger.log("invalid Strain payload ignored before build dateKey=\(PulsarDailyMetricsDateKey.dateKey(for: day, calendar: calendar))")
        }
        if recoveryMetric != nil && validRecoveryMetric == nil {
            PulsarSyncDebugLogger.log("invalid Recovery payload ignored before build dateKey=\(PulsarDailyMetricsDateKey.dateKey(for: day, calendar: calendar))")
        }
        let syncedAt = max(
            max(
                max(max(strain.lastUpdated ?? generatedAt, recovery.lastUpdated ?? generatedAt), stress.lastUpdated ?? generatedAt),
                healthMonitor.lastUpdated ?? generatedAt
            ),
            max(sleep.lastUpdated ?? generatedAt, generatedAt)
        )
        let payload = PulsarDailyMetricsSyncPayload(
            date: day,
            dateKey: PulsarDailyMetricsDateKey.dateKey(for: day, calendar: calendar),
            syncedAt: syncedAt,
            sourceDevice: sourceDevice,
            strain: validStrainMetric,
            recovery: validRecoveryMetric,
            sleep: sleepMetric,
            stress: stressMetric,
            healthMonitor: healthMonitorMetric,
            syncSessionID: syncSessionID,
            validityFlag: true
        )
        return payload.isValidPayload ? payload : nil
    }

    func applying(payload: PulsarDailyMetricsSyncPayload, calendar: Calendar = .current) -> HomeDashboard {
        guard payload.isValidPayload,
              payload.applies(to: sleep.wakeUpDate ?? strain.date ?? recovery.date ?? healthMonitor.date ?? generatedAt, calendar: calendar) else { return self }
        var copy = self
        if let strain = payload.strain, strain.isValid {
            let currentStrainUpdatedAt = copy.strain.lastUpdated ?? .distantPast
            if strain.computedAt >= currentStrainUpdatedAt || copy.strain.score == 0 {
                copy.strain = copy.strain.applying(syncMetric: strain, sourceDevice: payload.sourceDevice)
            } else {
                PulsarSyncDebugLogger.log("skipped Strain UI update because incoming metric was older dateKey=\(payload.resolvedDateKey) incoming=\(strain.computedAt) current=\(currentStrainUpdatedAt) session=\(payload.syncSessionID?.uuidString ?? "none")")
            }
        }
        if let recovery = payload.recovery, recovery.isValid {
            let currentRecoveryUpdatedAt = copy.recovery.lastUpdated ?? .distantPast
            if recovery.computedAt >= currentRecoveryUpdatedAt || copy.recovery.score == 0 {
                copy.recovery = copy.recovery.applying(syncMetric: recovery, sourceDevice: payload.sourceDevice)
            } else {
                PulsarSyncDebugLogger.log("skipped Recovery UI update because incoming metric was older dateKey=\(payload.resolvedDateKey) incoming=\(recovery.computedAt) current=\(currentRecoveryUpdatedAt) session=\(payload.syncSessionID?.uuidString ?? "none")")
            }
        }
        if let sleep = payload.sleep, sleep.isValid {
            copy.sleep = copy.sleep.applying(syncMetric: sleep, sourceDevice: payload.sourceDevice)
        }
        if let stress = payload.stress, stress.isValid {
            if payload.sourceDevice == .appleWatch, copy.stress.score != nil {
                PulsarSyncDebugLogger.log("skipped Watch Stress UI update because iPhone Stress remains canonical dateKey=\(payload.resolvedDateKey) incoming=\(stress.computedAt) current=\(copy.stress.lastUpdated ?? .distantPast) session=\(payload.syncSessionID?.uuidString ?? "none")")
            } else {
                copy.stress = copy.stress.applying(syncMetric: stress, sourceDevice: payload.sourceDevice)
            }
        }
        if let healthMonitor = payload.healthMonitor, healthMonitor.isValid {
            copy.healthMonitor = copy.healthMonitor.applying(syncMetric: healthMonitor, sourceDevice: payload.sourceDevice)
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
            computedAt: lastUpdated ?? Date(),
            stageIntervals: intervals.map {
                PulsarSleepStageSyncInterval(
                    stage: $0.stage.rawValue,
                    start: $0.startDate,
                    end: $0.endDate
                )
            }
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
        copy.intervals = stageIntervals(from: syncMetric)
        copy.sleepStart = syncMetric.sleepStart
        copy.wakeTime = syncMetric.sleepEnd
        copy.awakenings = syncMetric.awakenings
        copy.analyzedSampleCount = syncMetric.analyzedSampleCount
        copy.queryStart = syncMetric.queryStart
        copy.queryEnd = syncMetric.queryEnd
        copy.lastUpdated = syncMetric.computedAt
        copy.sourceBadges = mergeSources(existing: copy.sourceBadges, names: syncMetric.sourceNames, sourceDevice: sourceDevice)
        copy.notes = mergeNotes(copy.notes, sourceDevice: sourceDevice, title: "Synced sleep from \(sourceDevice.displayName) while local HealthKit data refreshes.")
        return copy
    }

    func stageIntervals(from metric: PulsarSleepSyncMetric) -> [SleepStageInterval] {
        let syncedIntervals = metric.stageIntervals?
            .compactMap { interval -> SleepStageInterval? in
                guard let stage = SleepStage(rawValue: interval.stage),
                      interval.start < interval.end else { return nil }
                return SleepStageInterval(stage: stage, startDate: interval.start, endDate: interval.end)
            }
            .sorted { $0.startDate < $1.startDate } ?? []

        if !syncedIntervals.isEmpty {
            return syncedIntervals
        }

        return synthesizedStageIntervals(from: metric)
    }

    func synthesizedStageIntervals(from metric: PulsarSleepSyncMetric) -> [SleepStageInterval] {
        let sleepDuration = max(0, metric.totalSleepMinutes)
        let stageMinutes: [(SleepStage, Double)] = [
            (.awake, max(0, metric.awakeMinutes * 0.35)),
            (.core, max(0, metric.coreMinutes * 0.45)),
            (.deep, max(0, metric.deepMinutes)),
            (.core, max(0, metric.coreMinutes * 0.55)),
            (.rem, max(0, metric.remMinutes * 0.55)),
            (.asleepUnspecified, max(0, metric.asleepUnspecifiedMinutes)),
            (.rem, max(0, metric.remMinutes * 0.45)),
            (.awake, max(0, metric.awakeMinutes * 0.65))
        ]
        let positiveStages = stageMinutes.filter { $0.1 > 0 }
        let fallbackStages: [(SleepStage, Double)] = positiveStages.isEmpty && sleepDuration > 0
            ? [(.asleepUnspecified, sleepDuration)]
            : positiveStages

        let totalMinutes = fallbackStages.reduce(0) { $0 + $1.1 }
        let availableSeconds = max(60, metric.sleepEnd.timeIntervalSince(metric.sleepStart))
        let scale = totalMinutes > 0 ? availableSeconds / (totalMinutes * 60) : 1
        var cursor = metric.sleepStart
        var intervals: [SleepStageInterval] = []

        for (stage, minutes) in fallbackStages {
            let duration = max(30, minutes * 60 * scale)
            let end = min(metric.sleepEnd, cursor.addingTimeInterval(duration))
            guard end > cursor else { continue }
            intervals.append(SleepStageInterval(stage: stage, startDate: cursor, endDate: end))
            cursor = end
        }

        if intervals.isEmpty, metric.sleepStart < metric.sleepEnd {
            intervals.append(SleepStageInterval(stage: .asleepUnspecified, startDate: metric.sleepStart, endDate: metric.sleepEnd))
        }

        return intervals
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
        if let analyzedSampleCount = syncMetric.analyzedSampleCount {
            copy.analyzedSampleCount = max(copy.analyzedSampleCount, analyzedSampleCount)
        }
        copy.lastUpdated = syncMetric.computedAt
        if copy.queryEnd == nil { copy.queryEnd = syncMetric.computedAt }
        copy.sourceBadges = mergeSources(existing: copy.sourceBadges, names: syncMetric.sourceNames, sourceDevice: sourceDevice)
        copy.notes = mergeNotes(copy.notes, sourceDevice: sourceDevice, title: "Synced strain from \(sourceDevice.displayName) while local HealthKit data refreshes.")
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
        copy.notes = mergeNotes(copy.notes, sourceDevice: sourceDevice, title: "Synced recovery from \(sourceDevice.displayName) while local HealthKit data refreshes.")
        if copy.explanation.isEmpty || copy.explanation == RecoverySummary.missing.explanation {
            copy.explanation = syncMetric.statusText
        }
        return copy
    }
}

private extension StressSummary {
    func syncMetric() -> PulsarStressSyncMetric? {
        let isPaused = state == .workoutPaused || state == .cooldown
        guard let score = score ?? (isPaused ? 0 : nil) else { return nil }
        let metric = PulsarStressSyncMetric(
            score: score,
            confidence: confidence.syncConfidence,
            levelText: isPaused ? (stressStatusText ?? syncCalculationStateRawValue) : PulsarSharedMetricCalculator.stressLevelText(score: score),
            driverInsights: Array(driverInsights.prefix(2)),
            hrvSDNN: lastHRV ?? signalValue(id: "hrv"),
            hrvTimestamp: lastHRVTimestamp,
            hrvBaseline: nil,
            restingHeartRate: signalValue(id: "resting-heart-rate"),
            restingHeartRateBaseline: nil,
            respiratoryRate: signalValue(id: "respiratory-rate"),
            recentHeartRate: lastHeartRate ?? signalValue(id: "heart-rate"),
            heartRateTimestamp: lastHeartRateTimestamp,
            daytimeHeartRateBaseline: nil,
            nonActivityStress: nonActivityStress.map(Double.init),
            activityAdjustedStress: activityAdjustedStress.map(Double.init),
            movementState: movementStateText,
            calculationState: syncCalculationStateRawValue,
            sleepDurationMinutes: nil,
            strainScore: signalValue(id: "recent-load"),
            availableSignalCount: availableSignalCount,
            baselineWindowDays: baselineWindowDays,
            timelineSamples: dailySamples.prefix(36).map {
                PulsarStressSyncSample(timestamp: $0.timestamp, score: $0.score, context: $0.context?.rawValue)
            },
            sourceNames: sourceBadges.map(\.displayName),
            computedAt: lastUpdated ?? queryEnd ?? date ?? .distantPast
        )
        return metric.isValid ? metric : nil
    }

    func applying(syncMetric: PulsarStressSyncMetric, sourceDevice: PulsarSyncSourceDevice) -> StressSummary {
        var copy = self
        copy.date = copy.date ?? syncMetric.computedAt
        copy.score = syncMetric.score
        copy.level = StressLevel.legacyLevel(named: syncMetric.levelText) ?? StressLevel.level(for: syncMetric.score)
        copy.confidence = syncMetric.confidence.appConfidence
        if syncMetric.isPaused {
            copy.score = nil
            copy.level = nil
            copy.state = syncMetric.sharedCalculationState == .workoutPaused ? .workoutPaused : .cooldown
        } else {
            copy.state = syncMetric.confidence == .low ? .lowConfidence : .ready
        }
        copy.driverInsights = syncMetric.driverInsights.isEmpty ? copy.driverInsights : syncMetric.driverInsights
        copy.drivers = syncMetric.driverInsights.enumerated().map { index, insight in
            StressDriver(
                id: "synced-stress-driver-\(index)",
                title: insight,
                detail: "Synced from \(sourceDevice.displayName) while local HealthKit data refreshes.",
                severity: syncMetric.score >= Int(PulsarStressScale.highLowerBound) ? .elevated : .neutral,
                relatedMetric: nil
            )
        }
        copy.signals = stressSignals(from: syncMetric)
        copy.lastHeartRate = syncMetric.recentHeartRate
        copy.lastHeartRateTimestamp = syncMetric.heartRateTimestamp
        copy.lastHRV = syncMetric.hrvSDNN
        copy.lastHRVTimestamp = syncMetric.hrvTimestamp
        copy.nonActivityStress = syncMetric.nonActivityStress.map(PulsarStressScale.roundedScore)
        copy.activityAdjustedStress = syncMetric.activityAdjustedStress.map(PulsarStressScale.roundedScore)
        copy.movementStateText = syncMetric.movementState.flatMap(PulsarSharedStressMovementState.init(rawValue:))?.displayText ?? syncMetric.movementState
        copy.stressStatusText = syncMetric.sharedCalculationState.displayText
        copy.dailySamples = syncMetric.timelineSamples.map {
            StressSample(
                timestamp: $0.timestamp,
                score: $0.score,
                confidence: syncMetric.confidence.appConfidence,
                context: $0.context.flatMap(StressContext.init(rawValue:))
            )
        }
        copy.dailyAverageScore = PulsarStressTimelineDistribution.weightedAverage(
            samples: copy.dailySamples.map { PulsarStressTimelineSample(timestamp: $0.timestamp, score: $0.score) }
        ).map(PulsarStressScale.roundedScore)
        copy.analyzedSampleCount = max(copy.analyzedSampleCount, syncMetric.availableSignalCount)
        copy.baselineWindowDays = max(copy.baselineWindowDays, syncMetric.baselineWindowDays)
        copy.availableSignalCount = max(copy.availableSignalCount, syncMetric.availableSignalCount)
        copy.lastUpdated = syncMetric.computedAt
        if copy.queryEnd == nil { copy.queryEnd = syncMetric.computedAt }
        copy.sourceBadges = mergeSources(existing: copy.sourceBadges, names: syncMetric.sourceNames, sourceDevice: sourceDevice)
        copy.explanation = syncMetric.isPaused ? (syncMetric.driverInsights.first ?? syncMetric.sharedCalculationState.displayText) : "Current stress compares recent HR and HRV with your baseline, while filtering movement and workout effects."
        copy.subtext = StressSummary.estimateSubtext
        return copy
    }

    private func signalValue(id: String) -> Double? {
        signals.first(where: { $0.id == id })?.value.extractFirstNumber()
    }

    private var syncCalculationStateRawValue: String {
        switch state {
        case .workoutPaused:
            return PulsarSharedStressCalculationState.workoutPaused.rawValue
        case .cooldown:
            return PulsarSharedStressCalculationState.cooldownPaused.rawValue
        case .lowConfidence:
            return PulsarSharedStressCalculationState.lowConfidence.rawValue
        case .ready, .noData, .buildingBaseline:
            return PulsarSharedStressCalculationState.measuring.rawValue
        }
    }

    private func stressSignals(from metric: PulsarStressSyncMetric) -> [StressSignal] {
        [
            StressSignal(id: "hrv", title: "HRV", value: metric.hrvSDNN.map { "\(Int($0.rounded())) ms" } ?? "Not available", baseline: nil, availability: metric.hrvSDNN == nil ? .unavailable : .limited),
            StressSignal(id: "heart-rate", title: "Heart rate", value: metric.recentHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "Not available", baseline: nil, availability: metric.recentHeartRate == nil ? .unavailable : .limited),
            StressSignal(id: "resting-heart-rate", title: "Resting heart rate", value: metric.restingHeartRate.map { "\(Int($0.rounded())) bpm" } ?? "Not available", baseline: nil, availability: metric.restingHeartRate == nil ? .unavailable : .limited),
            StressSignal(id: "respiratory-rate", title: "Respiratory rate", value: metric.respiratoryRate.map { String(format: "%.1f br/min", $0) } ?? "Not available", baseline: nil, availability: metric.respiratoryRate == nil ? .unavailable : .limited),
            StressSignal(id: "non-activity-stress", title: "Non-activity stress", value: metric.nonActivityStress.map { "\(PulsarStressScale.roundedScore($0))" } ?? "Paused", baseline: "Inactive-only estimate", availability: metric.nonActivityStress == nil ? .limited : .available),
            StressSignal(id: "activity-adjusted-stress", title: "Activity-adjusted stress", value: metric.activityAdjustedStress.map { "\(PulsarStressScale.roundedScore($0))" } ?? "Paused", baseline: metric.movementState, availability: metric.activityAdjustedStress == nil ? .limited : .available),
            StressSignal(id: "recent-load", title: "Recent strain/load", value: metric.strainScore.map { "\(Int($0.rounded()))" } ?? "Not available", baseline: nil, availability: metric.strainScore == nil ? .unavailable : .limited)
        ]
    }
}

private extension HealthMonitorSummary {
    func syncMetric() -> PulsarHealthMonitorSyncMetric? {
        let metrics = HealthMetricKind.allCases.map { metric($0).syncMetric() }
        let syncMetric = PulsarHealthMonitorSyncMetric(
            metrics: metrics,
            baselineWindowDays: baselineWindowDays,
            sourceNames: sourceBadges.map(\.displayName),
            computedAt: lastUpdated ?? date ?? Date()
        )
        return syncMetric.isValid ? syncMetric : nil
    }

    func applying(syncMetric: PulsarHealthMonitorSyncMetric, sourceDevice: PulsarSyncSourceDevice) -> HealthMonitorSummary {
        let existingByKind = Dictionary(uniqueKeysWithValues: metrics.map { ($0.kind, $0) })
        let incomingByKind = Dictionary(uniqueKeysWithValues: syncMetric.metrics.map { ($0.kind.appKind, $0) })
        let mergedMetrics = HealthMetricKind.allCases.map { kind -> HealthMetricModel in
            if let incoming = incomingByKind[kind] {
                return HealthMetricModel(
                    kind: kind,
                    value: incoming.value,
                    status: incoming.status.appStatus,
                    baselineValue: incoming.baselineValue,
                    comparisonText: incoming.comparisonText,
                    sourceBadges: mergeSources(existing: existingByKind[kind]?.sourceBadges ?? [], names: incoming.sourceNames, sourceDevice: sourceDevice),
                    lastUpdated: syncMetric.computedAt
                )
            }
            return existingByKind[kind] ?? .noData(kind: kind, lastUpdated: lastUpdated)
        }

        return HealthMonitorSummary(
            date: date,
            metrics: mergedMetrics,
            lastUpdated: syncMetric.computedAt,
            baselineWindowDays: max(baselineWindowDays, syncMetric.baselineWindowDays),
            sourceBadges: mergeSources(existing: sourceBadges, names: syncMetric.sourceNames, sourceDevice: sourceDevice)
        )
    }
}

private extension HealthMetricModel {
    func syncMetric() -> PulsarHealthMetricSyncValue {
        PulsarHealthMetricSyncValue(
            kind: kind.syncKind,
            value: value,
            status: status.syncStatus,
            baselineValue: baselineValue,
            comparisonText: comparisonText,
            sourceNames: sourceBadges.map(\.displayName)
        )
    }
}

private func mergeSources(existing: [SourceProvenance], names: [String], sourceDevice: PulsarSyncSourceDevice) -> [SourceProvenance] {
    let syncedSources = names.map {
        SourceProvenance(
            sourceName: $0,
            sourceBundleIdentifier: nil,
            sourceVersion: nil,
            operatingSystemVersion: nil,
            productType: sourceDevice.productType,
            deviceName: $0,
            deviceManufacturer: sourceDevice.manufacturer,
            deviceModel: sourceDevice.displayName
        )
    }
    return SourceResolver.uniqueSourceBadges(existing + syncedSources)
}

private func mergeNotes(_ existing: [String], sourceDevice: PulsarSyncSourceDevice, title: String) -> [String] {
    let combined = existing + [title]
    var seen = Set<String>()
    return combined.filter { seen.insert($0).inserted }
}

private extension PulsarSyncSourceDevice {
    var displayName: String {
        switch self {
        case .iPhone:
            return "iPhone"
        case .appleWatch:
            return "Apple Watch"
        case .ouraRing:
            return "Oura Ring"
        }
    }

    var productType: String {
        switch self {
        case .iPhone:
            return "iPhoneSync"
        case .appleWatch:
            return "AppleWatchSync"
        case .ouraRing:
            return "OuraCloudSync"
        }
    }

    var manufacturer: String {
        switch self {
        case .iPhone, .appleWatch:
            return "Apple"
        case .ouraRing:
            return "Oura"
        }
    }
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

private extension String {
    func extractFirstNumber() -> Double? {
        let allowed = Set("0123456789.-")
        let token = split(separator: " ").first { part in
            part.contains { allowed.contains($0) }
        }
        return token.flatMap { Double($0.filter { allowed.contains($0) }) }
    }
}

private extension HealthMetricKind {
    var syncKind: PulsarHealthMetricSyncKind {
        switch self {
        case .respiratoryRate:
            .respiratoryRate
        case .restingHeartRate:
            .restingHeartRate
        case .hrv:
            .hrv
        case .oxygenSaturation:
            .oxygenSaturation
        case .wristTemperature:
            .wristTemperature
        case .sleep:
            .sleep
        }
    }
}

extension PulsarHealthMetricSyncKind {
    nonisolated var appKind: HealthMetricKind {
        switch self {
        case .respiratoryRate:
            .respiratoryRate
        case .restingHeartRate:
            .restingHeartRate
        case .hrv:
            .hrv
        case .oxygenSaturation:
            .oxygenSaturation
        case .wristTemperature:
            .wristTemperature
        case .sleep:
            .sleep
        }
    }
}

private extension HealthMetricStatus {
    var syncStatus: PulsarHealthMetricSyncStatus {
        switch self {
        case .normal:
            .normal
        case .higher:
            .higher
        case .lower:
            .lower
        case .noData:
            .noData
        }
    }
}

extension PulsarHealthMetricSyncStatus {
    nonisolated var appStatus: HealthMetricStatus {
        switch self {
        case .normal:
            .normal
        case .higher:
            .higher
        case .lower:
            .lower
        case .noData:
            .noData
        }
    }
}
