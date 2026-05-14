//
//  LabBiologicalAgeEngine.swift
//  Pulsar
//

import Foundation

struct LabBiologicalAgeEngine {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func calculate(input: LabBiologicalAgeInput) -> BiologicalAgeResult? {
        guard let chronologicalAge = input.chronologicalAge, chronologicalAge > 0 else {
            return nil
        }

        let physiologicalScore = physiologicalScore(from: input.physiological)
        let lifestyleScore = lifestyleScore(from: input.lifestyle)
        let biomarkerScore = biomarkerScore(from: input.biomarkers, now: input.now)
        let availableScores: [(LabPillarKind, Double)] = [
            physiologicalScore.map { (.physiological, $0) },
            lifestyleScore.map { (.lifestyle, $0) },
            biomarkerScore.map { (.biomarkers, $0) }
        ].compactMap { $0 }

        guard !availableScores.isEmpty else { return nil }

        let weights = redistributedWeights(forAvailableKinds: Set(availableScores.map(\.0)))
        let physiologicalContributionRaw = contributionYears(
            score: physiologicalScore,
            kind: .physiological,
            weight: weights[.physiological] ?? 0
        )
        let lifestyleContributionRaw = contributionYears(
            score: lifestyleScore,
            kind: .lifestyle,
            weight: weights[.lifestyle] ?? 0
        )
        let biomarkerContributionRaw = contributionYears(
            score: biomarkerScore,
            kind: .biomarkers,
            weight: weights[.biomarkers] ?? 0
        )
        let recentBiomarkerCount = recentBiomarkers(input.biomarkers, now: input.now).count
        let lifestyleSurveyCompleted = input.lifestyle?.hasAnyData == true
        let confidenceLevel = confidence(
            wearableDataDays: input.physiological.wearableDataDays,
            recentBiomarkerCount: recentBiomarkerCount,
            lifestyleSurveyCompleted: lifestyleSurveyCompleted
        )
        let moderatedDelta = moderatedDelta(
            rawDelta: physiologicalContributionRaw + lifestyleContributionRaw + biomarkerContributionRaw,
            chronologicalAge: chronologicalAge,
            confidence: confidenceLevel,
            hasRecentBiomarkers: biomarkerScore != nil,
            biomarkersComplete: recentBiomarkerCount >= LabBiomarkerDefinition.required.count
        )
        let biologicalAge = max(0, (chronologicalAge + moderatedDelta).labRoundedToTenth)
        let ageDelta = biologicalAge - chronologicalAge
        let adjustedContributions = adjustedContributions(
            physiological: physiologicalContributionRaw,
            lifestyle: lifestyleContributionRaw,
            biomarker: biomarkerContributionRaw,
            finalDelta: ageDelta
        )

        return BiologicalAgeResult(
            biologicalAge: biologicalAge,
            chronologicalAge: chronologicalAge,
            ageDelta: ageDelta,
            paceOfAging: nil,
            confidence: confidenceLevel,
            updatedAt: input.now,
            nextUpdateAt: nextMonday(after: input.now),
            physiologicalScore: physiologicalScore,
            lifestyleScore: lifestyleScore,
            biomarkerScore: biomarkerScore,
            physiologicalContributionYears: adjustedContributions.physiological,
            lifestyleContributionYears: adjustedContributions.lifestyle,
            biomarkerContributionYears: adjustedContributions.biomarker,
            missingDataMessages: missingDataMessages(
                input: input,
                physiologicalScore: physiologicalScore,
                lifestyleScore: lifestyleScore,
                biomarkerScore: biomarkerScore,
                recentBiomarkerCount: recentBiomarkerCount
            ),
            wearableDataDays: input.physiological.wearableDataDays,
            recentBiomarkerCount: recentBiomarkerCount,
            lifestyleSurveyCompleted: lifestyleSurveyCompleted
        )
    }

    private func physiologicalScore(from input: LabPhysiologicalFitnessInput) -> Double? {
        var scores: [Double] = []

        if let averageSleepDurationHours = input.averageSleepDurationHours {
            scores.append(bandScore(value: averageSleepDurationHours, optimalLow: 7.0, optimalHigh: 8.6, referenceLow: 5.5, referenceHigh: 10.0))
        }

        if let sleepConsistency = input.sleepConsistency {
            scores.append(min(max(sleepConsistency, 0), 1) * 100)
        }

        if let minutes = input.activityMinutesZone2to3PerWeek {
            scores.append(progressScore(value: minutes, target: 180, floor: 45))
        }

        if let minutes = input.activityMinutesZone4to5PerWeek {
            scores.append(bandScore(value: minutes, optimalLow: 25, optimalHigh: 75, referenceLow: 0, referenceHigh: 150))
        }

        if let sessions = input.strengthTrainingSessionsPerWeek {
            scores.append(progressScore(value: sessions, target: 2.2, floor: 35))
        }

        if let dailyStepAverage = input.dailyStepAverage {
            let target = stepTarget(age: input.chronologicalAge)
            scores.append(progressScore(value: dailyStepAverage, target: target, floor: 38))
        }

        if let vo2Max = input.vo2Max {
            let target = vo2Benchmark(age: input.chronologicalAge, sex: input.biologicalSex)
            scores.append(progressScore(value: vo2Max, target: target, floor: 42))
        }

        if let restingHeartRate = input.restingHeartRate {
            scores.append(restingHeartRateScore(restingHeartRate))
        }

        if let leanBodyMassKilograms = input.leanBodyMassKilograms, leanBodyMassKilograms > 0 {
            scores.append(72)
        }

        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private func lifestyleScore(from input: LabLifestyleInput?) -> Double? {
        guard let input, input.hasAnyData else { return nil }
        var scores: [Double] = []

        if let nutritionScore = input.nutritionScore {
            scores.append(min(max(nutritionScore, 0), 100))
        }

        if let alcoholFrequencyPerWeek = input.alcoholFrequencyPerWeek {
            switch alcoholFrequencyPerWeek {
            case ...0.5: scores.append(96)
            case ...2: scores.append(90)
            case ...5: scores.append(76)
            case ...10: scores.append(56)
            default: scores.append(36)
            }
        }

        if let smokingStatus = input.smokingStatus {
            switch smokingStatus {
            case .never: scores.append(96)
            case .former: scores.append(82)
            case .occasional: scores.append(58)
            case .current: scores.append(30)
            }
        }

        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private func biomarkerScore(from biomarkers: [LabBiomarker], now: Date) -> Double? {
        let latest = latestBiomarkersByDefinition(biomarkers, now: now, recentOnly: true)
        let scores = LabBiomarkerDefinition.required.compactMap { definition -> Double? in
            definition.score(for: latest[definition.id]?.value)
        }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private func recentBiomarkers(_ biomarkers: [LabBiomarker], now: Date) -> [LabBiomarker] {
        Array(latestBiomarkersByDefinition(biomarkers, now: now, recentOnly: true).values)
    }

    private func latestBiomarkersByDefinition(
        _ biomarkers: [LabBiomarker],
        now: Date,
        recentOnly: Bool
    ) -> [String: LabBiomarker] {
        let cutoff = calendar.date(byAdding: .month, value: -6, to: now) ?? now.addingTimeInterval(-180 * 86_400)
        var latest: [String: LabBiomarker] = [:]

        for biomarker in biomarkers {
            guard let definition = LabBiomarkerDefinition.definition(for: biomarker.name),
                  biomarker.value != nil else { continue }
            if recentOnly,
               let collectedAt = biomarker.collectedAt,
               collectedAt < cutoff {
                continue
            }
            if recentOnly, biomarker.collectedAt == nil {
                continue
            }
            let current = latest[definition.id]
            if current == nil || (biomarker.collectedAt ?? .distantPast) > (current?.collectedAt ?? .distantPast) {
                latest[definition.id] = biomarker
            }
        }

        return latest
    }

    private func confidence(
        wearableDataDays: Int,
        recentBiomarkerCount: Int,
        lifestyleSurveyCompleted: Bool
    ) -> LabConfidenceLevel {
        if wearableDataDays >= 20,
           recentBiomarkerCount >= LabBiomarkerDefinition.required.count,
           lifestyleSurveyCompleted {
            return .high
        }

        if wearableDataDays >= 14,
           (recentBiomarkerCount > 0 || lifestyleSurveyCompleted) {
            return .medium
        }

        if recentBiomarkerCount >= 5, wearableDataDays >= 7 {
            return .medium
        }

        return .low
    }

    private func missingDataMessages(
        input: LabBiologicalAgeInput,
        physiologicalScore: Double?,
        lifestyleScore: Double?,
        biomarkerScore: Double?,
        recentBiomarkerCount: Int
    ) -> [String] {
        var messages: [String] = []

        if input.physiological.wearableDataDays < 20 {
            messages.append("Wear your device for at least 20 days in the last 4 weeks to raise confidence.")
        }

        if physiologicalScore == nil {
            messages.append("Connect wearable data to activate sleep, steps, activity, and heart-rate signals.")
        }

        if lifestyleScore == nil {
            messages.append("Complete lifestyle check-ins for nutrition, alcohol, and smoking exposure.")
        }

        if biomarkerScore == nil {
            messages.append("Add recent lab results for Albumin, Creatinine, Glucose, ALP, hs-CRP, Lymphocytes, WBC Count, MCV, and RDW.")
        } else if recentBiomarkerCount < LabBiomarkerDefinition.required.count {
            messages.append("Add the remaining required biomarkers to improve the blood-marker pillar.")
        }

        return messages
    }

    private func redistributedWeights(forAvailableKinds kinds: Set<LabPillarKind>) -> [LabPillarKind: Double] {
        let total = kinds.reduce(0) { $0 + (Self.baseWeights[$1] ?? 0) }
        guard total > 0 else { return [:] }
        return Dictionary(uniqueKeysWithValues: kinds.map { kind in
            (kind, (Self.baseWeights[kind] ?? 0) / total)
        })
    }

    private func contributionYears(score: Double?, kind: LabPillarKind, weight: Double) -> Double {
        guard let score, weight > 0 else { return 0 }
        let boundedScore: Double = Swift.min(Swift.max(score, 0), 100)
        let center = 75.0
        let impact = Self.pillarImpactYears[kind] ?? (improvement: 0.5, penalty: 0.8)
        let baseWeight = Self.baseWeights[kind] ?? weight
        let redistributionFactor = baseWeight > 0
            ? min(max(weight / baseWeight, 0), 1.18)
            : 1

        if boundedScore >= center {
            let progress: Double = Swift.min(Swift.max((boundedScore - center) / (100 - center), 0), 1)
            return -progress * impact.improvement * redistributionFactor
        }

        let progress: Double = Swift.min(Swift.max((center - boundedScore) / center, 0), 1)
        return progress * impact.penalty * redistributionFactor
    }

    private func adjustedContributions(
        physiological: Double,
        lifestyle: Double,
        biomarker: Double,
        finalDelta: Double
    ) -> (physiological: Double, lifestyle: Double, biomarker: Double) {
        let rawTotal = physiological + lifestyle + biomarker
        guard abs(rawTotal) > 0.0001 else {
            return (0, 0, 0)
        }

        let scale = finalDelta / rawTotal
        return (
            physiological * scale,
            lifestyle * scale,
            biomarker * scale
        )
    }

    private func moderatedDelta(
        rawDelta: Double,
        chronologicalAge: Double,
        confidence: LabConfidenceLevel,
        hasRecentBiomarkers: Bool,
        biomarkersComplete: Bool
    ) -> Double {
        let regressionFactor: Double
        switch confidence {
        case .low:
            regressionFactor = 0.12
        case .medium:
            regressionFactor = 0.48
        case .high:
            regressionFactor = 0.78
        }

        let caps = deltaCaps(for: confidence)
        var delta = rawDelta * regressionFactor
        delta = min(max(delta, caps.maxImprovement), caps.maxPenalty)

        if !hasRecentBiomarkers {
            delta = max(delta, -1.25)
        } else if !biomarkersComplete {
            delta = max(delta, -2.0)
        }

        if chronologicalAge < 30 {
            let youngImprovementCap: Double
            switch confidence {
            case .low:
                youngImprovementCap = -0.5
            case .medium:
                youngImprovementCap = -1.25
            case .high:
                youngImprovementCap = biomarkersComplete ? -2.0 : -1.25
            }

            delta = max(delta, youngImprovementCap)
            delta = max(delta, 18 - chronologicalAge)
        }

        return min(max(delta, caps.maxImprovement), caps.maxPenalty).labRoundedToTenth
    }

    private func deltaCaps(for confidence: LabConfidenceLevel) -> (maxImprovement: Double, maxPenalty: Double) {
        switch confidence {
        case .low:
            return (-0.75, 1.0)
        case .medium:
            return (-1.75, 2.25)
        case .high:
            return (-3.5, 4.0)
        }
    }

    private func progressScore(value: Double, target: Double, floor: Double) -> Double {
        guard target > 0 else { return floor }
        let progress = min(max(value / target, 0), 1)
        return floor + (100 - floor) * progress
    }

    private func bandScore(
        value: Double,
        optimalLow: Double,
        optimalHigh: Double,
        referenceLow: Double,
        referenceHigh: Double
    ) -> Double {
        if (optimalLow...optimalHigh).contains(value) {
            return 100
        }
        if value < optimalLow {
            return progressScore(value: value - referenceLow, target: optimalLow - referenceLow, floor: 35)
        }
        if value > optimalHigh {
            let span = max(referenceHigh - optimalHigh, 0.1)
            let excess = min(max((value - optimalHigh) / span, 0), 1)
            return 100 - excess * 55
        }
        return 76
    }

    private func restingHeartRateScore(_ value: Double) -> Double {
        switch value {
        case ...54: return 100
        case ...62: return 94 - (value - 54) * 1.5
        case ...72: return 82 - (value - 62) * 2.1
        case ...86: return 61 - (value - 72) * 2.0
        default: return 32
        }
    }

    private func stepTarget(age: Double?) -> Double {
        guard let age else { return 8_000 }
        switch age {
        case ..<50: return 8_500
        case ..<65: return 7_500
        default: return 6_500
        }
    }

    private func vo2Benchmark(age: Double?, sex: BiologicalSex?) -> Double {
        let age = age ?? 40
        let maleOffset = sex == .male ? 4.0 : 0.0
        switch age {
        case ..<30: return 42 + maleOffset
        case ..<40: return 39 + maleOffset
        case ..<50: return 36 + maleOffset
        case ..<60: return 33 + maleOffset
        default: return 30 + maleOffset
        }
    }

    private func nextMonday(after date: Date) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let monday = 2
        let daysUntilMonday = (monday - weekday + 7) % 7
        let offset = daysUntilMonday == 0 ? 7 : daysUntilMonday
        return calendar.date(byAdding: .day, value: offset, to: startOfDay) ?? date.addingTimeInterval(7 * 86_400)
    }

    private static let baseWeights: [LabPillarKind: Double] = [
        .physiological: 0.45,
        .lifestyle: 0.20,
        .biomarkers: 0.35
    ]

    private static let pillarImpactYears: [LabPillarKind: (improvement: Double, penalty: Double)] = [
        .physiological: (improvement: 1.5, penalty: 2.0),
        .lifestyle: (improvement: 0.75, penalty: 1.5),
        .biomarkers: (improvement: 2.0, penalty: 2.5)
    ]
}

private extension Double {
    var labRoundedToTenth: Double {
        (self * 10).rounded() / 10
    }
}
