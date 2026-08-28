//
//  OrionNutritionAIService.swift
//  Pulsar
//

import Foundation

protocol OrionNutritionAIServicing {
    func explain(input: NutritionCalculationInput, result: NutritionalCalculationResult) async throws -> OrionNutritionExplanation
}

enum OrionNutritionAIServiceError: LocalizedError {
    case notConfigured
    case invalidResponse
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Orion nutrition explanations are not configured. Your calculated targets still work offline."
        case .invalidResponse:
            "Orion returned an explanation that could not be validated."
        case .http(_, let message):
            message
        }
    }
}

final class OrionNutritionAIService: OrionNutritionAIServicing {
    private let configuration: OrionConfiguration
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(configuration: OrionConfiguration = .load(), session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func explain(input: NutritionCalculationInput, result: NutritionalCalculationResult) async throws -> OrionNutritionExplanation {
        if configuration.mockMode {
            return OrionNutritionExplanation(
                summary: "Your targets balance your selected goal with the activity data available to Pulsar.",
                assessment: result.confidence == .high ? .plausible : .needsReview,
                calorieTargetRationale: result.energy.rationale,
                macroRationale: "Protein is anchored first, fat keeps a minimum floor, and carbohydrates use the remaining energy.",
                activityObservations: "This mock explanation uses the same aggregated activity summary as the deterministic calculator.",
                primaryDrivers: result.energy.primaryDrivers,
                workoutPlanSummary: input.workoutPlan.workoutMixSummary,
                healthDataConsistency: input.healthActivity?.flags.first ?? "No HealthKit summary was attached.",
                questionsToImproveAccuracy: result.confidence == .low ? ["Can you confirm your typical workout durations and intensities?"] : [],
                practicalRecommendations: ["Use the target as a weekly average.", "Reassess after 2–4 weeks of consistent tracking."],
                reassessmentPlan: "Reassess after 14–28 days when weight trend and adherence are available.",
                dataLimitations: result.limitations.joined(separator: " "),
                suggestedReassessmentDate: ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(21 * 86_400)),
                safetyNote: "Informational only; seek qualified care for medical nutrition needs."
            ).normalized()
        }
        guard let endpoint = configuration.nutritionExplainEndpoint else {
            throw OrionNutritionAIServiceError.notConfigured
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = configuration.timeoutSeconds
        request.httpBody = try encoder.encode(OrionNutritionExplainRequest(input: input, result: result))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OrionNutritionAIServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let envelope = try? decoder.decode(OrionNutritionErrorEnvelope.self, from: data)
            throw OrionNutritionAIServiceError.http(
                httpResponse.statusCode,
                envelope?.message ?? "Orion nutrition backend returned HTTP \(httpResponse.statusCode)."
            )
        }
        if let envelope = try? decoder.decode(OrionNutritionExplainEnvelope.self, from: data) {
            return envelope.explanation.normalized()
        }
        if let explanation = try? decoder.decode(OrionNutritionExplanation.self, from: data) {
            return explanation.normalized()
        }
        throw OrionNutritionAIServiceError.invalidResponse
    }
}

private struct OrionNutritionExplainRequest: Encodable {
    var input: NutritionCalculationInput
    var result: NutritionalCalculationResult
}

private struct OrionNutritionExplainEnvelope: Decodable {
    var explanation: OrionNutritionExplanation
}

private struct OrionNutritionErrorEnvelope: Decodable {
    var message: String?
    var errorDescription: String?

    private enum CodingKeys: String, CodingKey {
        case message
        case errorDescription = "error_description"
    }
}
