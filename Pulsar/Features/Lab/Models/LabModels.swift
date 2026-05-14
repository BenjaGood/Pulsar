//
//  LabModels.swift
//  Pulsar
//

import Foundation

enum LabBiomarkerStatus: String, CaseIterable, Identifiable, Codable, Hashable {
    case optimal = "Optimal"
    case normal = "Normal"
    case high = "High"
    case low = "Low"
    case missing = "Missing"

    var id: String { rawValue }
}

enum LabBiomarkerSource: String, CaseIterable, Identifiable, Codable, Hashable {
    case manual
    case pdf
    case healthKit
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual: "Manual"
        case .pdf: "PDF"
        case .healthKit: "Health"
        case .other: "Other"
        }
    }
}

struct LabBiomarker: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var value: Double?
    var unit: String
    var referenceLow: Double?
    var referenceHigh: Double?
    var status: LabBiomarkerStatus
    var collectedAt: Date?
    var source: LabBiomarkerSource
    var notes: String?

    init(
        id: UUID = UUID(),
        name: String,
        value: Double?,
        unit: String,
        referenceLow: Double? = nil,
        referenceHigh: Double? = nil,
        status: LabBiomarkerStatus,
        collectedAt: Date? = nil,
        source: LabBiomarkerSource,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.value = value
        self.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        self.referenceLow = referenceLow
        self.referenceHigh = referenceHigh
        self.status = status
        self.collectedAt = collectedAt
        self.source = source
        self.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    var displayValue: String {
        guard let value else { return "--" }
        if abs(value) >= 100 {
            return "\(Int(value.rounded()))"
        }
        if abs(value) >= 10 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value).trimmedTrailingZeros
    }

    var displayReferenceRange: String {
        guard let referenceLow, let referenceHigh else { return "Reference unavailable" }
        return "\(referenceLow.formattedLabValue)-\(referenceHigh.formattedLabValue) \(unit)"
    }
}

struct LabBiomarkerDefinition: Identifiable, Hashable {
    let id: String
    let name: String
    let unit: String
    let referenceLow: Double?
    let referenceHigh: Double?
    let optimalLow: Double?
    let optimalHigh: Double?
    let explanation: String
    let aliases: [String]

    init(
        name: String,
        unit: String,
        referenceLow: Double?,
        referenceHigh: Double?,
        optimalLow: Double?,
        optimalHigh: Double?,
        explanation: String,
        aliases: [String] = []
    ) {
        self.id = name.normalizedBiomarkerKey
        self.name = name
        self.unit = unit
        self.referenceLow = referenceLow
        self.referenceHigh = referenceHigh
        self.optimalLow = optimalLow
        self.optimalHigh = optimalHigh
        self.explanation = explanation
        self.aliases = aliases
    }

    func matches(_ candidate: String) -> Bool {
        let key = candidate.normalizedBiomarkerKey
        return key == id || aliases.map(\.normalizedBiomarkerKey).contains(key)
    }

    func status(for value: Double?) -> LabBiomarkerStatus {
        guard let value, value.isFinite else { return .missing }
        if let optimalLow, let optimalHigh, (optimalLow...optimalHigh).contains(value) {
            return .optimal
        }
        if let referenceLow, value < referenceLow {
            return .low
        }
        if let referenceHigh, value > referenceHigh {
            return .high
        }
        return .normal
    }

    func score(for value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }

        if let optimalLow, let optimalHigh, (optimalLow...optimalHigh).contains(value) {
            return 100
        }

        if let referenceLow, let referenceHigh, (referenceLow...referenceHigh).contains(value) {
            if let optimalLow, value < optimalLow {
                return interpolate(value: value, from: referenceLow, to: optimalLow, lowScore: 72, highScore: 96)
            }
            if let optimalHigh, value > optimalHigh {
                return interpolate(value: value, from: optimalHigh, to: referenceHigh, lowScore: 96, highScore: 72)
            }
            return 82
        }

        if let referenceLow, value < referenceLow {
            let span = max(abs(referenceLow) * 0.35, 1)
            let deficit = min((referenceLow - value) / span, 1)
            return 68 - deficit * 38
        }

        if let referenceHigh, value > referenceHigh {
            let span = max(abs(referenceHigh) * 0.35, 1)
            let excess = min((value - referenceHigh) / span, 1)
            return 68 - excess * 38
        }

        return 72
    }

    private func interpolate(value: Double, from: Double, to: Double, lowScore: Double, highScore: Double) -> Double {
        guard from != to else { return highScore }
        let progress = min(max((value - from) / (to - from), 0), 1)
        return lowScore + (highScore - lowScore) * progress
    }

    static let required: [LabBiomarkerDefinition] = [
        LabBiomarkerDefinition(
            name: "Albumin",
            unit: "g/dL",
            referenceLow: 3.5,
            referenceHigh: 5.0,
            optimalLow: 4.2,
            optimalHigh: 4.8,
            explanation: "A protein marker that can reflect nutrition status, inflammation load, and liver synthesis.",
            aliases: ["serum albumin"]
        ),
        LabBiomarkerDefinition(
            name: "Creatinine",
            unit: "mg/dL",
            referenceLow: 0.6,
            referenceHigh: 1.3,
            optimalLow: 0.7,
            optimalHigh: 1.1,
            explanation: "A kidney filtration and muscle-mass related marker interpreted alongside context and trends.",
            aliases: ["serum creatinine"]
        ),
        LabBiomarkerDefinition(
            name: "Glucose",
            unit: "mg/dL",
            referenceLow: 70,
            referenceHigh: 99,
            optimalLow: 75,
            optimalHigh: 90,
            explanation: "A metabolic marker that helps estimate glucose regulation when interpreted with fasting state.",
            aliases: ["fasting glucose", "blood glucose"]
        ),
        LabBiomarkerDefinition(
            name: "ALP",
            unit: "U/L",
            referenceLow: 44,
            referenceHigh: 147,
            optimalLow: 50,
            optimalHigh: 100,
            explanation: "Alkaline phosphatase is commonly included in metabolic panels and may reflect liver or bone turnover.",
            aliases: ["alkaline phosphatase"]
        ),
        LabBiomarkerDefinition(
            name: "hs-CRP",
            unit: "mg/L",
            referenceLow: 0,
            referenceHigh: 3,
            optimalLow: 0,
            optimalHigh: 1,
            explanation: "A high-sensitivity inflammation marker; lower values generally suggest lower systemic inflammatory load.",
            aliases: ["crp", "high sensitivity crp", "c-reactive protein"]
        ),
        LabBiomarkerDefinition(
            name: "Lymphocytes",
            unit: "%",
            referenceLow: 20,
            referenceHigh: 40,
            optimalLow: 25,
            optimalHigh: 35,
            explanation: "A white blood cell subset that gives context on immune distribution and recovery balance.",
            aliases: ["lymphocyte percent", "lymphs"]
        ),
        LabBiomarkerDefinition(
            name: "WBC Count",
            unit: "10^3/uL",
            referenceLow: 4.0,
            referenceHigh: 11.0,
            optimalLow: 4.5,
            optimalHigh: 8.0,
            explanation: "White blood cell count is a broad immune and inflammation signal best read with symptoms and trends.",
            aliases: ["wbc", "white blood cells", "white blood cell count"]
        ),
        LabBiomarkerDefinition(
            name: "MCV",
            unit: "fL",
            referenceLow: 80,
            referenceHigh: 100,
            optimalLow: 84,
            optimalHigh: 94,
            explanation: "Mean corpuscular volume describes red blood cell size and can add context for nutrient and blood-health patterns.",
            aliases: ["mean corpuscular volume"]
        ),
        LabBiomarkerDefinition(
            name: "RDW",
            unit: "%",
            referenceLow: 11.5,
            referenceHigh: 14.5,
            optimalLow: 11.5,
            optimalHigh: 13.2,
            explanation: "Red cell distribution width captures variation in red blood cell size and is useful as a trend marker.",
            aliases: ["red cell distribution width"]
        )
    ]

    static func definition(for name: String) -> LabBiomarkerDefinition? {
        required.first { $0.matches(name) }
    }
}

enum LabConfidenceLevel: String, Codable, CaseIterable, Identifiable, Hashable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var id: String { rawValue }
}

enum LabPillarKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case physiological
    case lifestyle
    case biomarkers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .physiological: "Physiological & Fitness"
        case .lifestyle: "Lifestyle Habits"
        case .biomarkers: "Blood Biomarkers"
        }
    }

    var shortTitle: String {
        switch self {
        case .physiological: "Fitness"
        case .lifestyle: "Lifestyle"
        case .biomarkers: "Biomarkers"
        }
    }
}

struct LabPillarResult: Identifiable, Codable, Equatable, Hashable {
    var id: LabPillarKind { kind }
    var kind: LabPillarKind
    var score: Double?
    var statusLabel: String
    var explanation: String
    var contributionYears: Double
}

struct BiologicalAgeResult: Codable, Equatable {
    var biologicalAge: Double
    var chronologicalAge: Double
    var ageDelta: Double
    var paceOfAging: Double?
    var confidence: LabConfidenceLevel
    var updatedAt: Date
    var nextUpdateAt: Date
    var physiologicalScore: Double?
    var lifestyleScore: Double?
    var biomarkerScore: Double?
    var physiologicalContributionYears: Double
    var lifestyleContributionYears: Double
    var biomarkerContributionYears: Double
    var missingDataMessages: [String]
    var wearableDataDays: Int
    var recentBiomarkerCount: Int
    var lifestyleSurveyCompleted: Bool

    var pillarResults: [LabPillarResult] {
        [
            LabPillarResult(
                kind: .physiological,
                score: physiologicalScore,
                statusLabel: Self.statusLabel(for: physiologicalScore),
                explanation: physiologicalScore == nil
                    ? "Wearable trends from the last four weeks are not available yet."
                    : "Sleep, steps, training minutes, resting heart rate, and available fitness signals.",
                contributionYears: physiologicalContributionYears
            ),
            LabPillarResult(
                kind: .lifestyle,
                score: lifestyleScore,
                statusLabel: Self.statusLabel(for: lifestyleScore),
                explanation: lifestyleScore == nil
                    ? "Complete nutrition, alcohol, and smoking check-ins to activate this pillar."
                    : "Nutrition consistency, alcohol frequency, and smoking exposure from in-app surveys.",
                contributionYears: lifestyleContributionYears
            ),
            LabPillarResult(
                kind: .biomarkers,
                score: biomarkerScore,
                statusLabel: Self.statusLabel(for: biomarkerScore),
                explanation: biomarkerScore == nil
                    ? "Import or manually enter recent blood results to strengthen the estimate."
                    : "Recent lab markers weighted for inflammation, metabolic, immune, kidney, and blood-health context.",
                contributionYears: biomarkerContributionYears
            )
        ]
    }

    static func statusLabel(for score: Double?) -> String {
        guard let score else { return "Insufficient data" }
        switch score {
        case 86...100: return "Excellent"
        case 72..<86: return "Good"
        case 0..<72: return "Needs attention"
        default: return "Insufficient data"
        }
    }
}

struct LabPhysiologicalFitnessInput: Equatable {
    var wearableDataDays: Int
    var averageSleepDurationHours: Double?
    var sleepConsistency: Double?
    var activityMinutesZone2to3PerWeek: Double?
    var activityMinutesZone4to5PerWeek: Double?
    var strengthTrainingSessionsPerWeek: Double?
    var dailyStepAverage: Double?
    var vo2Max: Double?
    var restingHeartRate: Double?
    var leanBodyMassKilograms: Double?
    var chronologicalAge: Double?
    var biologicalSex: BiologicalSex?
}

enum LabSmokingStatus: String, Codable, Hashable {
    case never
    case former
    case occasional
    case current
}

struct LabLifestyleInput: Equatable {
    var nutritionScore: Double?
    var alcoholFrequencyPerWeek: Double?
    var smokingStatus: LabSmokingStatus?

    var hasAnyData: Bool {
        nutritionScore != nil || alcoholFrequencyPerWeek != nil || smokingStatus != nil
    }
}

struct LabBiologicalAgeInput: Equatable {
    var chronologicalAge: Double?
    var biologicalSex: BiologicalSex?
    var physiological: LabPhysiologicalFitnessInput
    var lifestyle: LabLifestyleInput?
    var biomarkers: [LabBiomarker]
    var now: Date
}

enum LabImportStatus: Equatable {
    case idle
    case importing(progress: Double)
    case review(extracted: [LabBiomarker])
    case comingSoon(message: String)
    case failed(message: String)
}

struct ManualBiomarkerEntryState: Equatable {
    var name = ""
    var value = ""
    var unit = ""
    var collectedAt = Date()
    var referenceLow = ""
    var referenceHigh = ""
    var notes = ""
}

struct LabModuleState: Equatable {
    var latestBiologicalAgeResult: BiologicalAgeResult?
    var biomarkers: [LabBiomarker]
    var importStatus: LabImportStatus
    var manualEntryState: ManualBiomarkerEntryState

    static let empty = LabModuleState(
        latestBiologicalAgeResult: nil,
        biomarkers: [],
        importStatus: .idle,
        manualEntryState: ManualBiomarkerEntryState()
    )
}

extension String {
    var normalizedBiomarkerKey: String {
        lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension String {
    var trimmedTrailingZeros: String {
        var copy = self
        while copy.contains(".") && copy.last == "0" {
            copy.removeLast()
        }
        if copy.last == "." {
            copy.removeLast()
        }
        return copy
    }
}

extension Double {
    var formattedLabValue: String {
        if abs(self) >= 100 {
            return "\(Int(rounded()))"
        }
        if abs(self) >= 10 {
            return String(format: "%.1f", self).trimmedTrailingZeros
        }
        return String(format: "%.2f", self).trimmedTrailingZeros
    }
}
