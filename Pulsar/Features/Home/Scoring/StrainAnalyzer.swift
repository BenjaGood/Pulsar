//
//  StrainAnalyzer.swift
//  Pulsar
//

import Foundation

struct StrainAnalysisInput {
    var strainInput: DailyStrainInput
    var biometrics: DailyBiometrics
    var dayHeartRateSamples: [HeartRateSample]
    var queryInterval: DateInterval
    var refreshedAt: Date
    var stepGoal: Int = 10_000
}

struct StrainAnalyzer {
    func analyze(_ input: StrainAnalysisInput) -> StrainSummary {
        let workoutHeartSamples = input.strainInput.workouts.flatMap(\.heartRateSamples)
        let allHeartSamples = uniqueHeartSamples(input.dayHeartRateSamples + workoutHeartSamples).sorted { $0.start < $1.start }
        var summary = StrainScoringEngine().score(
            input: input.strainInput,
            dayHeartRateSamples: allHeartSamples,
            restingHeartRate: input.biometrics.restingHeartRateBPM
        )
        let activeHeartSamples = preferredActiveHeartSamples(workoutSamples: workoutHeartSamples, daySamples: input.dayHeartRateSamples, restingHeartRate: input.biometrics.restingHeartRateBPM)
        let peakHeartRate = allHeartSamples.map(\.bpm).filter { $0 > 0 }.max()

        summary.date = input.strainInput.date
        summary.stepGoal = input.stepGoal
        summary.activeEnergyKilocalories = input.strainInput.activity.activeEnergyKilocalories
        summary.basalEnergyKilocalories = input.strainInput.activity.basalEnergyKilocalories
        summary.exerciseMinutes = input.strainInput.activity.exerciseMinutes
        summary.averageActiveHeartRate = activeHeartSamples.isEmpty ? nil : activeHeartSamples.map(\.bpm).reduce(0, +) / Double(activeHeartSamples.count)
        summary.peakHeartRate = peakHeartRate
        summary.restingHeartRate = input.biometrics.restingHeartRateBPM
        summary.hrvSDNNMilliseconds = input.biometrics.hrvSDNNMilliseconds
        summary.workouts = workoutSummaries(from: input.strainInput.workouts)
        summary.timeline = timeline(from: input, allHeartSamples: allHeartSamples)
        summary.heartRatePoints = heartRatePoints(from: allHeartSamples, in: input.queryInterval)
        summary.workoutBands = workoutBands(from: input.strainInput.workouts, in: input.queryInterval)
        summary.analyzedSampleCount = input.strainInput.workouts.count + allHeartSamples.count + Int(input.strainInput.activity.steps > 0 ? 1 : 0) + Int(input.strainInput.activity.activeEnergyKilocalories > 0 ? 1 : 0)
        summary.queryStart = input.queryInterval.start
        summary.queryEnd = input.queryInterval.end
        summary.lastUpdated = input.refreshedAt
        return summary
    }

    func intensity(for bpm: Double, maxHeartRate: Double?) -> StrainIntensityZone {
        guard bpm > 0 else { return .rest }
        if let maxHeartRate, maxHeartRate > 100 {
            switch bpm / maxHeartRate {
            case ..<0.50: return .rest
            case ..<0.60: return .light
            case ..<0.75: return .moderate
            case ..<0.87: return .hard
            default: return .peak
            }
        }
        switch bpm {
        case ..<90: return .rest
        case ..<115: return .light
        case ..<140: return .moderate
        case ..<165: return .hard
        default: return .peak
        }
    }

    private func preferredActiveHeartSamples(workoutSamples: [HeartRateSample], daySamples: [HeartRateSample], restingHeartRate: Double?) -> [HeartRateSample] {
        let workout = workoutSamples.filter { $0.bpm > 0 }
        if !workout.isEmpty { return workout }
        let threshold = max(90, (restingHeartRate ?? 65) + 15)
        return daySamples.filter { $0.bpm >= threshold }
    }

    private func uniqueHeartSamples(_ samples: [HeartRateSample]) -> [HeartRateSample] {
        var seen = Set<String>()
        return samples.filter { sample in
            let key = sample.id.map { "uuid:\($0.uuidString)" }
                ?? "value:\(sample.start.timeIntervalSinceReferenceDate)-\(sample.end.timeIntervalSinceReferenceDate)-\(sample.bpm.rounded())-\(sample.provenance.id)"
            return seen.insert(key).inserted
        }
    }

    private func heartRatePoints(from samples: [HeartRateSample], in interval: DateInterval) -> [HeartRatePoint] {
        let validSamples = samples.compactMap { sample -> HeartRateSample? in
            let start = max(sample.start, interval.start)
            let end = min(sample.end, interval.end)
            guard start <= end, sample.bpm > 0 else { return nil }
            return HeartRateSample(start: start, end: end, bpm: sample.bpm, provenance: sample.provenance)
        }
        return downsample(validSamples.sorted { $0.start < $1.start }, maxPoints: 240).map { sample in
            let midpoint = sample.start.addingTimeInterval(max(0, sample.end.timeIntervalSince(sample.start)) / 2)
            return HeartRatePoint(date: midpoint, bpm: sample.bpm, source: sample.provenance.displayName)
        }
        .sorted { $0.date < $1.date }
    }

    private func workoutBands(from workouts: [WorkoutLoadInput], in interval: DateInterval) -> [WorkoutTimelineBand] {
        workouts.compactMap { workout -> WorkoutTimelineBand? in
            let start = max(workout.start, interval.start)
            let end = min(workout.end, interval.end)
            guard start < end else { return nil }
            let heartRates = workout.heartRateSamples.map(\.bpm).filter { $0 > 0 }
            return WorkoutTimelineBand(
                workoutType: workout.type,
                startDate: start,
                endDate: end,
                duration: end.timeIntervalSince(start),
                averageHeartRate: heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count),
                peakHeartRate: heartRates.max()
            )
        }
        .sorted { $0.startDate < $1.startDate }
    }

    private func downsample(_ samples: [HeartRateSample], maxPoints: Int) -> [HeartRateSample] {
        guard samples.count > maxPoints, maxPoints >= 8 else { return samples }
        let bucketCount = max(1, maxPoints / 2)
        let bucketSize = Int(ceil(Double(samples.count) / Double(bucketCount)))
        var reduced: [HeartRateSample] = []

        for startIndex in stride(from: 0, to: samples.count, by: bucketSize) {
            let endIndex = min(samples.count, startIndex + bucketSize)
            let bucket = Array(samples[startIndex..<endIndex])
            guard let minSample = bucket.min(by: { $0.bpm < $1.bpm }),
                  let maxSample = bucket.max(by: { $0.bpm < $1.bpm }) else { continue }
            let extremes = [minSample, maxSample].sorted { $0.start < $1.start }
            for sample in extremes where reduced.last != sample {
                reduced.append(sample)
            }
        }

        if let first = samples.first, reduced.first != first { reduced.insert(first, at: 0) }
        if let last = samples.last, reduced.last != last { reduced.append(last) }
        if reduced.count > maxPoints, let last = samples.last {
            reduced = Array(reduced.prefix(maxPoints - 1))
            if reduced.last != last { reduced.append(last) }
        }
        return reduced.sorted { $0.start < $1.start }
    }

    private func workoutSummaries(from workouts: [WorkoutLoadInput]) -> [StrainWorkoutSummary] {
        workouts.map { workout in
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
        }
        .sorted { $0.startDate > $1.startDate }
    }

    private func timeline(from input: StrainAnalysisInput, allHeartSamples: [HeartRateSample]) -> [StrainTimelineInterval] {
        let workouts = input.strainInput.workouts
        let heartIntervals = allHeartSamples.compactMap { sample -> StrainTimelineInterval? in
            let start = max(sample.start, input.queryInterval.start)
            let end = min(sample.end, input.queryInterval.end)
            guard start < end, sample.bpm > 0 else { return nil }
            let isWorkout = workouts.contains { workout in sample.start < workout.end && sample.end > workout.start }
            let intensity = intensity(for: sample.bpm, maxHeartRate: input.strainInput.maxHeartRate)
            return StrainTimelineInterval(
                startDate: start,
                endDate: end,
                intensity: intensity,
                value: value(for: intensity),
                source: sample.provenance.displayName,
                isWorkout: isWorkout
            )
        }

        if !heartIntervals.isEmpty {
            return mergeAdjacent(heartIntervals.sorted { $0.startDate < $1.startDate })
        }

        return workouts.map { workout in
            let load = StrainScoringEngine().ledgerEntry(for: workout, maxHeartRate: input.strainInput.maxHeartRate).load
            let intensity = fallbackWorkoutIntensity(load: load, durationMinutes: workout.durationMinutes)
            return StrainTimelineInterval(
                startDate: max(workout.start, input.queryInterval.start),
                endDate: min(workout.end, input.queryInterval.end),
                intensity: intensity,
                value: value(for: intensity),
                source: workout.provenance.displayName,
                isWorkout: true
            )
        }
        .filter { $0.startDate < $0.endDate }
        .sorted { $0.startDate < $1.startDate }
    }

    private func mergeAdjacent(_ intervals: [StrainTimelineInterval]) -> [StrainTimelineInterval] {
        var merged: [StrainTimelineInterval] = []
        for interval in intervals {
            guard let last = merged.last,
                  last.endDate == interval.startDate,
                  last.intensity == interval.intensity,
                  last.isWorkout == interval.isWorkout,
                  last.source == interval.source else {
                merged.append(interval)
                continue
            }
            merged[merged.count - 1].endDate = interval.endDate
        }
        return merged
    }

    private func fallbackWorkoutIntensity(load: Double, durationMinutes: Double) -> StrainIntensityZone {
        let density = durationMinutes > 0 ? load / durationMinutes : load
        switch density {
        case ..<1.2: return .light
        case ..<2.4: return .moderate
        case ..<3.8: return .hard
        default: return .peak
        }
    }

    private func value(for intensity: StrainIntensityZone) -> Double {
        switch intensity {
        case .rest: return 0.18
        case .light: return 0.34
        case .moderate: return 0.56
        case .hard: return 0.78
        case .peak: return 1.0
        }
    }
}
