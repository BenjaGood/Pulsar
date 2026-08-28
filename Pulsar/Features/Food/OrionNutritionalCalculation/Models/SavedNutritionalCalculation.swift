//
//  SavedNutritionalCalculation.swift
//  Pulsar
//

import Foundation

enum OrionNutritionAssessment: String, Codable, Equatable, Hashable {
    case plausible
    case needsReview
    case insufficientData
}

struct OrionNutritionExplanation: Codable, Equatable, Hashable {
    var summary: String
    var assessment: OrionNutritionAssessment
    var calorieTargetRationale: String
    var macroRationale: String
    var activityObservations: String
    var primaryDrivers: [String]
    var workoutPlanSummary: String
    var healthDataConsistency: String
    var questionsToImproveAccuracy: [String]
    var practicalRecommendations: [String]
    var reassessmentPlan: String
    var dataLimitations: String
    var suggestedReassessmentDate: String
    var safetyNote: String
    var limitations: String

    init(
        summary: String,
        assessment: OrionNutritionAssessment = .plausible,
        calorieTargetRationale: String,
        macroRationale: String,
        activityObservations: String,
        primaryDrivers: [String] = [],
        workoutPlanSummary: String = "",
        healthDataConsistency: String = "",
        questionsToImproveAccuracy: [String] = [],
        practicalRecommendations: [String],
        reassessmentPlan: String = "",
        dataLimitations: String,
        suggestedReassessmentDate: String,
        safetyNote: String,
        limitations: String = ""
    ) {
        self.summary = summary
        self.assessment = assessment
        self.calorieTargetRationale = calorieTargetRationale
        self.macroRationale = macroRationale
        self.activityObservations = activityObservations
        self.primaryDrivers = primaryDrivers
        self.workoutPlanSummary = workoutPlanSummary
        self.healthDataConsistency = healthDataConsistency
        self.questionsToImproveAccuracy = questionsToImproveAccuracy
        self.practicalRecommendations = practicalRecommendations
        self.reassessmentPlan = reassessmentPlan
        self.dataLimitations = dataLimitations
        self.suggestedReassessmentDate = suggestedReassessmentDate
        self.safetyNote = safetyNote
        self.limitations = limitations.isEmpty ? dataLimitations : limitations
    }

    func normalized() -> OrionNutritionExplanation {
        OrionNutritionExplanation(
            summary: summary.limited(to: 1_200),
            assessment: assessment,
            calorieTargetRationale: calorieTargetRationale.limited(to: 1_200),
            macroRationale: macroRationale.limited(to: 1_200),
            activityObservations: activityObservations.limited(to: 1_200),
            primaryDrivers: primaryDrivers.prefix(8).map { $0.limited(to: 240) },
            workoutPlanSummary: workoutPlanSummary.limited(to: 1_200),
            healthDataConsistency: healthDataConsistency.limited(to: 1_200),
            questionsToImproveAccuracy: questionsToImproveAccuracy.prefix(6).map { $0.limited(to: 240) },
            practicalRecommendations: practicalRecommendations.prefix(6).map { $0.limited(to: 360) },
            reassessmentPlan: reassessmentPlan.limited(to: 1_200),
            dataLimitations: dataLimitations.limited(to: 1_200),
            suggestedReassessmentDate: suggestedReassessmentDate.limited(to: 40),
            safetyNote: safetyNote.limited(to: 600),
            limitations: limitations.limited(to: 1_200)
        )
    }

    enum CodingKeys: String, CodingKey {
        case summary
        case assessment
        case calorieTargetRationale
        case macroRationale
        case activityObservations
        case primaryDrivers
        case workoutPlanSummary
        case healthDataConsistency
        case questionsToImproveAccuracy
        case practicalRecommendations
        case reassessmentPlan
        case dataLimitations
        case suggestedReassessmentDate
        case safetyNote
        case limitations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(String.self, forKey: .summary)
        assessment = try container.decodeIfPresent(OrionNutritionAssessment.self, forKey: .assessment) ?? .plausible
        calorieTargetRationale = try container.decode(String.self, forKey: .calorieTargetRationale)
        macroRationale = try container.decode(String.self, forKey: .macroRationale)
        activityObservations = try container.decode(String.self, forKey: .activityObservations)
        primaryDrivers = try container.decodeIfPresent([String].self, forKey: .primaryDrivers) ?? []
        workoutPlanSummary = try container.decodeIfPresent(String.self, forKey: .workoutPlanSummary) ?? ""
        healthDataConsistency = try container.decodeIfPresent(String.self, forKey: .healthDataConsistency) ?? ""
        questionsToImproveAccuracy = try container.decodeIfPresent([String].self, forKey: .questionsToImproveAccuracy) ?? []
        practicalRecommendations = try container.decode([String].self, forKey: .practicalRecommendations)
        reassessmentPlan = try container.decodeIfPresent(String.self, forKey: .reassessmentPlan) ?? ""
        dataLimitations = try container.decode(String.self, forKey: .dataLimitations)
        suggestedReassessmentDate = try container.decode(String.self, forKey: .suggestedReassessmentDate)
        safetyNote = try container.decode(String.self, forKey: .safetyNote)
        limitations = try container.decodeIfPresent(String.self, forKey: .limitations) ?? dataLimitations
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(summary, forKey: .summary)
        try container.encode(assessment, forKey: .assessment)
        try container.encode(calorieTargetRationale, forKey: .calorieTargetRationale)
        try container.encode(macroRationale, forKey: .macroRationale)
        try container.encode(activityObservations, forKey: .activityObservations)
        try container.encode(primaryDrivers, forKey: .primaryDrivers)
        try container.encode(workoutPlanSummary, forKey: .workoutPlanSummary)
        try container.encode(healthDataConsistency, forKey: .healthDataConsistency)
        try container.encode(questionsToImproveAccuracy, forKey: .questionsToImproveAccuracy)
        try container.encode(practicalRecommendations, forKey: .practicalRecommendations)
        try container.encode(reassessmentPlan, forKey: .reassessmentPlan)
        try container.encode(dataLimitations, forKey: .dataLimitations)
        try container.encode(suggestedReassessmentDate, forKey: .suggestedReassessmentDate)
        try container.encode(safetyNote, forKey: .safetyNote)
        try container.encode(limitations, forKey: .limitations)
    }
}

struct SavedNutritionalCalculation: Identifiable, Codable, Equatable {
    var id: UUID
    var input: NutritionCalculationInput
    var result: NutritionalCalculationResult
    var explanation: OrionNutritionExplanation?
    var savedAt: Date

    init(
        id: UUID? = nil,
        input: NutritionCalculationInput,
        result: NutritionalCalculationResult,
        explanation: OrionNutritionExplanation? = nil,
        savedAt: Date = .now
    ) {
        self.id = id ?? result.id
        self.input = input
        self.result = result
        self.explanation = explanation?.normalized()
        self.savedAt = savedAt
    }
}

private extension String {
    func limited(to maximumLength: Int) -> String {
        String(trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumLength))
    }
}
