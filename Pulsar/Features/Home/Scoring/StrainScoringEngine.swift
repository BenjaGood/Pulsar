//
//  StrainScoringEngine.swift
//  Pulsar
//

import Foundation

struct StrainScoringEngine {
    func score(input: DailyStrainInput, dayHeartRateSamples: [HeartRateSample] = [], restingHeartRate: Double? = nil) -> StrainSummary {
        let maxHeartRate = input.maxHeartRate
        let workoutEntries = input.workouts.map { workout in
            ledgerEntry(for: workout, maxHeartRate: maxHeartRate)
        }
        let heartContext = PulsarSharedMetricCalculator.heartRateContext(
            samples: dayHeartRateSamples.map {
                PulsarSharedHeartRateSample(start: $0.start, end: $0.end, bpm: $0.bpm)
            },
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate
        )
        let sharedMetric = PulsarSharedMetricCalculator.makeStrainMetric(
            activity: PulsarSharedActivityInput(
                steps: input.activity.steps,
                activeEnergyKilocalories: input.activity.activeEnergyKilocalories,
                basalEnergyKilocalories: input.activity.basalEnergyKilocalories,
                distanceMeters: input.activity.distanceMeters,
                exerciseMinutes: input.activity.exerciseMinutes,
                elevatedHeartRateMinutes: heartContext.elevatedMinutes,
                moderateHeartRateMinutes: heartContext.moderateMinutes,
                vigorousHeartRateMinutes: heartContext.vigorousMinutes,
                zone1Minutes: heartContext.zone1Minutes,
                zone2Minutes: heartContext.zone2Minutes,
                zone3Minutes: heartContext.zone3Minutes,
                zone4Minutes: heartContext.zone4Minutes,
                zone5Minutes: heartContext.zone5Minutes,
                averageElevatedHeartRate: heartContext.averageElevatedHeartRate,
                peakHeartRate: heartContext.peakHeartRate,
                restingHeartRate: restingHeartRate,
                maxHeartRate: maxHeartRate
            ),
            workouts: input.workouts.map { workout in
                let heartRates = workout.heartRateSamples.map(\.bpm).filter { $0 > 0 }
                return PulsarSharedWorkoutInput(
                    type: workout.type,
                    durationMinutes: workout.durationMinutes,
                    activeEnergyKilocalories: workout.activeEnergyKilocalories,
                    distanceMeters: workout.distanceMeters,
                    averageHeartRate: heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count),
                    peakHeartRate: heartRates.max(),
                    sourceName: workout.provenance.displayName
                )
            },
            recentRawLoads: input.recentRawLoads,
            computedAt: input.date
        )
        let workoutLoad = sharedMetric?.workoutLoad ?? workoutEntries.reduce(0) { $0 + $1.load }
        let movementLoad = sharedMetric?.movementLoad ?? 0
        let rawLoad = sharedMetric?.rawLoad ?? workoutLoad
        let twentyEightDailyAverage = input.twentyEightDayRawLoad / 28
        let expectedSevenDayLoad = max(1, twentyEightDailyAverage * 7)
        let sevenVsTwentyEightRatio = input.sevenDayRawLoad / expectedSevenDayLoad
        let sourceBadges = SourceResolver.uniqueSourceBadges(
            input.workouts.map(\.provenance) + input.activity.provenance
        )
        let confidence = sharedMetric?.confidence.appConfidence ?? confidenceGrade(maxHeartRate: maxHeartRate, workouts: input.workouts, activity: input.activity)

        return StrainSummary(
            date: input.date,
            score: sharedMetric?.score ?? 0,
            confidence: confidence,
            rawLoad: rawLoad,
            workoutLoad: workoutLoad,
            movementLoad: movementLoad,
            sevenDayLoad: input.sevenDayRawLoad,
            twentyEightDayAverageLoad: twentyEightDailyAverage,
            sevenVsTwentyEightRatio: sevenVsTwentyEightRatio,
            steps: Int(input.activity.steps.rounded()),
            stepGoal: 10_000,
            activeEnergyKilocalories: input.activity.activeEnergyKilocalories,
            basalEnergyKilocalories: input.activity.basalEnergyKilocalories,
            exerciseMinutes: input.activity.exerciseMinutes,
            averageActiveHeartRate: sharedMetric?.averageActiveHeartRate,
            peakHeartRate: sharedMetric?.peakHeartRate ?? input.workouts.flatMap(\.heartRateSamples).map(\.bpm).max(),
            restingHeartRate: restingHeartRate,
            hrvSDNNMilliseconds: nil,
            workoutMinutes: input.workouts.reduce(0) { $0 + $1.durationMinutes },
            workouts: input.workouts.map { workout in
                let heartRates = workout.heartRateSamples.map(\.bpm).filter { $0 > 0 }
                return StrainWorkoutSummary(
                    id: workout.id,
                    workoutType: workout.type,
                    startDate: workout.start,
                    endDate: workout.end,
                    activeEnergyKilocalories: workout.activeEnergyKilocalories,
                    averageHeartRate: heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count),
                    peakHeartRate: heartRates.max(),
                    sourceName: workout.provenance.displayName
                )
            }.sorted { $0.startDate > $1.startDate },
            timeline: [],
            heartRatePoints: [],
            workoutBands: [],
            analyzedSampleCount: input.workouts.count + Int(input.activity.steps > 0 ? 1 : 0),
            queryStart: nil,
            queryEnd: nil,
            lastUpdated: nil,
            timeInZones: combineZones(workoutEntries.flatMap(\.timeInZones)),
            ledger: workoutEntries.sorted { $0.start > $1.start },
            sourceBadges: sourceBadges,
            notes: notes(maxHeartRate: maxHeartRate, confidence: confidence, workoutLoad: workoutLoad)
        )
    }

    func ledgerEntry(for workout: WorkoutLoadInput, maxHeartRate: Double?) -> WorkoutLedgerEntry {
        let zones = timeInZones(for: workout.heartRateSamples, maxHeartRate: maxHeartRate)
        let load = zones.reduce(0.0) { partial, zone in
            partial + zone.minutes * Double(zone.zone)
        }
        let fallbackLoad = workout.heartRateSamples.isEmpty ? min(workout.durationMinutes * 1.2, (workout.activeEnergyKilocalories ?? 0) / 8) : load
        return WorkoutLedgerEntry(
            title: workout.type,
            start: workout.start,
            durationMinutes: workout.durationMinutes,
            load: max(load, fallbackLoad),
            timeInZones: zones,
            provenance: workout.provenance
        )
    }

    func timeInZones(for samples: [HeartRateSample], maxHeartRate: Double?) -> [TimeInZone] {
        guard let maxHeartRate, maxHeartRate > 100 else { return [] }
        var minutesByZone: [Int: Double] = [:]
        for sample in samples where sample.bpm > 0 {
            guard let zone = zone(for: sample.bpm, maxHeartRate: maxHeartRate) else { continue }
            minutesByZone[zone, default: 0] += max(0, sample.end.timeIntervalSince(sample.start) / 60)
        }
        return (1...5).map { TimeInZone(zone: $0, minutes: minutesByZone[$0, default: 0]) }
    }

    private func zone(for bpm: Double, maxHeartRate: Double) -> Int? {
        let percent = bpm / maxHeartRate
        switch percent {
        case ..<0.50: return nil
        case ..<0.60: return 1
        case ..<0.70: return 2
        case ..<0.80: return 3
        case ..<0.90: return 4
        default: return 5
        }
    }

    private func combineZones(_ zones: [TimeInZone]) -> [TimeInZone] {
        (1...5).map { zone in
            TimeInZone(zone: zone, minutes: zones.filter { $0.zone == zone }.reduce(0) { $0 + $1.minutes })
        }
    }

    private func confidenceGrade(maxHeartRate: Double?, workouts: [WorkoutLoadInput], activity: DailyActivityInput) -> ConfidenceGrade {
        let hasWorkoutHR = workouts.contains { !$0.heartRateSamples.isEmpty }
        if maxHeartRate != nil && hasWorkoutHR { return .high }
        if hasWorkoutHR || activity.steps > 0 || activity.exerciseMinutes > 0 { return .moderate }
        return .low
    }

    private func notes(maxHeartRate: Double?, confidence: ConfidenceGrade, workoutLoad: Double) -> [String] {
        var notes = ["Strain uses Edwards TRIMP-style heart-rate zone load first, with a smaller background movement contribution."]
        if maxHeartRate == nil {
            notes.append("Max heart rate is missing; add a manual value or date of birth so zone load can be estimated.")
        }
        if confidence != .high {
            notes.append("Heart-rate and time-in-zone signals are preferred over calorie estimates when sources disagree.")
        }
        if workoutLoad == 0 {
            notes.append("No workout heart-rate load was available today.")
        }
        return notes
    }
}
