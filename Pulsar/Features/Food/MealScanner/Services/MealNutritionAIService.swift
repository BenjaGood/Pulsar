//
//  MealNutritionAIService.swift
//  Pulsar
//

import Foundation
import OSLog

protocol MealNutritionAIServicing {
    func analyzeMeal(imageBase64: String, payload: MealScanPayload) async throws -> MealScanResult
    func resolveIngredient(_ request: MealIngredientResolveRequest) async throws -> MealIngredientResolveResponse
}

struct MealScannerConfiguration: Equatable, Sendable {
    var backendBaseURL: URL?
    var analysisPath: String
    var resolvePath: String
    var mockMode: Bool
    var timeoutSeconds: TimeInterval

    static let notConfigured = MealScannerConfiguration()
    static let mock = MealScannerConfiguration(mockMode: true)

    init(
        backendBaseURL: URL? = nil,
        analysisPath: String = "/api/orion/meal-scan",
        resolvePath: String = "/api/orion/meal-scan/resolve-ingredient",
        mockMode: Bool = false,
        timeoutSeconds: TimeInterval = 45
    ) {
        self.backendBaseURL = backendBaseURL
        self.analysisPath = analysisPath.isEmpty ? "/api/orion/meal-scan" : analysisPath
        self.resolvePath = resolvePath.isEmpty ? "/api/orion/meal-scan/resolve-ingredient" : resolvePath
        self.mockMode = mockMode
        self.timeoutSeconds = timeoutSeconds
    }

    var analysisEndpoint: URL? {
        guard let backendBaseURL else { return nil }
        return Self.endpoint(baseURL: backendBaseURL, path: analysisPath)
    }

    var resolveEndpoint: URL? {
        guard let backendBaseURL else { return nil }
        return Self.endpoint(baseURL: backendBaseURL, path: resolvePath)
    }

    var isConfigured: Bool {
        mockMode || analysisEndpoint != nil
    }

    func missingConfigurationKeys() -> [String] {
        guard !mockMode else { return [] }
        return analysisEndpoint == nil ? ["MealScannerBackendBaseURL", "OrionBackendBaseURL"] : []
    }

    static func load(bundle: Bundle = .main, defaults: UserDefaults = .standard) -> MealScannerConfiguration {
        MealScannerConfiguration(
            backendBaseURL: urlValue(named: "MealScannerBackendBaseURL", bundle: bundle)
                ?? urlValue(named: "OrionBackendBaseURL", bundle: bundle),
            analysisPath: stringValue(named: "MealScannerAnalyzePath", bundle: bundle) ?? "/api/orion/meal-scan",
            resolvePath: stringValue(named: "MealScannerResolvePath", bundle: bundle) ?? "/api/orion/meal-scan/resolve-ingredient",
            mockMode: defaults.bool(forKey: MealScannerDefaultsKeys.mockMode)
                || defaults.bool(forKey: MealScannerDefaultsKeys.orionMockMode)
                || boolValue(named: "MealScannerMockMode", bundle: bundle)
                || boolValue(named: "OrionMockMode", bundle: bundle)
        )
    }

    private static func stringValue(named key: String, bundle: Bundle) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private static func urlValue(named key: String, bundle: Bundle) -> URL? {
        stringValue(named: key, bundle: bundle).flatMap(URL.init(string:))
    }

    private static func boolValue(named key: String, bundle: Bundle) -> Bool {
        if let value = bundle.object(forInfoDictionaryKey: key) as? Bool {
            return value
        }
        if let value = bundle.object(forInfoDictionaryKey: key) as? String {
            return ["1", "true", "yes"].contains(value.lowercased())
        }
        return false
    }

    private static func endpoint(baseURL: URL, path: String) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, endpointPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

enum MealScannerDefaultsKeys {
    static let mockMode = "pulsar.mealScanner.mockMode.v1"
    static let orionMockMode = "pulsar.orion.mockMode.v1"
}

enum MealNutritionAIServiceError: LocalizedError {
    case notConfigured([String])
    case invalidResponse
    case http(statusCode: Int, message: String)
    case emptyResponse
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let keys):
            "Meal Scanner is not configured. Set \(keys.joined(separator: " or ")) to the hosted backend. The OpenAI API key belongs only in the backend environment."
        case .invalidResponse:
            "Meal Scanner returned an invalid response."
        case .http(_, let message):
            message
        case .emptyResponse:
            "Meal Scanner returned an empty response."
        case .transport(let message), .decoding(let message):
            message
        }
    }
}

final class MealNutritionAIService: MealNutritionAIServicing {
    private let configuration: MealScannerConfiguration
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private static let logger = Logger(subsystem: "tech.aetherial.pulsar", category: "MealScanner")

    init(
        configuration: MealScannerConfiguration = .load(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func analyzeMeal(imageBase64: String, payload: MealScanPayload) async throws -> MealScanResult {
        Self.logger.debug("Meal scan AI analyze requested mockMode=\(self.configuration.mockMode, privacy: .public) endpoint=\(self.configuration.analysisEndpoint?.absoluteString ?? "nil", privacy: .public) missingConfiguration=\(self.configuration.missingConfigurationKeys().joined(separator: ","), privacy: .public)")
        if configuration.mockMode {
            Self.logger.debug("Meal scan AI returning mock result")
            return Self.mockResult(payload: payload)
        }

        guard let endpoint = configuration.analysisEndpoint else {
            Self.logger.error("Meal scan AI is not configured missingConfiguration=\(self.configuration.missingConfigurationKeys().joined(separator: ","), privacy: .public)")
            throw MealNutritionAIServiceError.notConfigured(configuration.missingConfigurationKeys())
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = configuration.timeoutSeconds
        request.httpBody = try encoder.encode(
            MealScanAnalysisRequest(
                prompt: Self.prompt(for: payload),
                instructions: Self.instructions,
                imageBase64: imageBase64,
                payload: payload
            )
        )
        Self.logger.debug("Meal scan AI request encoded bodyBytes=\(request.httpBody?.count ?? 0, privacy: .public)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            Self.logger.error("Meal scan AI transport failed code=\(error.code.rawValue, privacy: .public) endpoint=\(endpoint.absoluteString, privacy: .public)")
            throw MealNutritionAIServiceError.transport(Self.transportMessage(endpoint: endpoint, error: error))
        } catch {
            Self.logger.error("Meal scan AI transport failed error=\(error.localizedDescription, privacy: .public)")
            throw MealNutritionAIServiceError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            Self.logger.error("Meal scan AI returned non-HTTP response")
            throw MealNutritionAIServiceError.invalidResponse
        }
        Self.logger.debug("Meal scan AI HTTP status=\(httpResponse.statusCode, privacy: .public) responseBytes=\(data.count, privacy: .public)")
        guard (200..<300).contains(httpResponse.statusCode) else {
            if Self.shouldUseLocalFallback(for: httpResponse.statusCode) {
                Self.logger.error("Meal scan AI backend unavailable status=\(httpResponse.statusCode, privacy: .public) responseBytes=\(data.count, privacy: .public)")
                throw MealNutritionAIServiceError.http(
                    statusCode: httpResponse.statusCode,
                    message: Self.unavailableBackendMessage(statusCode: httpResponse.statusCode)
                )
            }
            Self.logger.error("Meal scan AI HTTP failure status=\(httpResponse.statusCode, privacy: .public) responseBytes=\(data.count, privacy: .public)")
            throw MealNutritionAIServiceError.http(
                statusCode: httpResponse.statusCode,
                message: errorMessage(from: data) ?? "Meal Scanner backend returned HTTP \(httpResponse.statusCode)."
            )
        }
        guard !data.isEmpty else {
            Self.logger.error("Meal scan AI returned empty 2xx response")
            throw MealNutritionAIServiceError.emptyResponse
        }

        do {
            let result = Self.normalizedResult(try decodeResult(from: data), for: payload)
            guard !result.isEmptyNutritionEstimate else {
                Self.logger.warning("Meal scan AI decoded empty nutrition result ingredients=0 totalsZero=true")
                throw MealNutritionAIServiceError.emptyResponse
            }
            return result
        } catch let error as MealNutritionAIServiceError {
            Self.logger.error("Meal scan AI decode failed error=\(error.errorDescription ?? String(describing: error), privacy: .public) responseBytes=\(data.count, privacy: .public)")
            throw error
        } catch {
            Self.logger.error("Meal scan AI decode failed error=\(error.localizedDescription, privacy: .public) responseBytes=\(data.count, privacy: .public)")
            throw MealNutritionAIServiceError.decoding(error.localizedDescription)
        }
    }

    /// Phase 3: recalculates honest nutrition for a single ingredient the user just
    /// identified. Throws on any failure so callers can apply the Phase 1 fallback
    /// (rename + keep grams + nutritionNeedsRecalculation = true) rather than faking data.
    func resolveIngredient(_ request: MealIngredientResolveRequest) async throws -> MealIngredientResolveResponse {
        Self.logger.debug("Meal scan ingredient resolve requested mockMode=\(self.configuration.mockMode, privacy: .public) endpoint=\(self.configuration.resolveEndpoint?.absoluteString ?? "nil", privacy: .public)")
        if configuration.mockMode {
            Self.logger.debug("Meal scan ingredient resolve returning mock result")
            return Self.mockResolveResponse(for: request)
        }

        guard let endpoint = configuration.resolveEndpoint else {
            Self.logger.error("Meal scan ingredient resolve is not configured")
            throw MealNutritionAIServiceError.notConfigured(configuration.missingConfigurationKeys())
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = configuration.timeoutSeconds
        urlRequest.httpBody = try encoder.encode(request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            Self.logger.error("Meal scan ingredient resolve transport failed code=\(error.code.rawValue, privacy: .public)")
            throw MealNutritionAIServiceError.transport(Self.transportMessage(endpoint: endpoint, error: error))
        } catch {
            Self.logger.error("Meal scan ingredient resolve transport failed error=\(error.localizedDescription, privacy: .public)")
            throw MealNutritionAIServiceError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            Self.logger.error("Meal scan ingredient resolve returned non-HTTP response")
            throw MealNutritionAIServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            Self.logger.error("Meal scan ingredient resolve HTTP failure status=\(httpResponse.statusCode, privacy: .public)")
            throw MealNutritionAIServiceError.http(
                statusCode: httpResponse.statusCode,
                message: errorMessage(from: data) ?? "Ingredient recalculation failed (HTTP \(httpResponse.statusCode))."
            )
        }
        guard !data.isEmpty else {
            Self.logger.error("Meal scan ingredient resolve returned empty 2xx response")
            throw MealNutritionAIServiceError.emptyResponse
        }

        do {
            return try decoder.decode(MealIngredientResolveResponse.self, from: data)
        } catch {
            Self.logger.error("Meal scan ingredient resolve decode failed error=\(error.localizedDescription, privacy: .public)")
            throw MealNutritionAIServiceError.decoding(error.localizedDescription)
        }
    }

    private func decodeResult(from data: Data) throws -> MealScanResult {
        if let envelopeResult = decodeEnvelopeResult(from: data, branchPrefix: "response-envelope", remainingTextDepth: 2) {
            return envelopeResult
        }
        if let response = try? decoder.decode(MealScanAnalysisResponse.self, from: data) {
            Self.logger.debug("Meal scan AI decode branch=analysis-response")
            return response.result
        }
        if let direct = try? decoder.decode(MealScanResult.self, from: data) {
            Self.logger.debug("Meal scan AI decode branch=direct")
            return direct
        }

        throw MealNutritionAIServiceError.emptyResponse
    }

    private func decodeEnvelopeResult(
        from data: Data,
        branchPrefix: String,
        remainingTextDepth: Int
    ) -> MealScanResult? {
        guard let container = try? decoder.decode(MealScanResponseEnvelope.self, from: data) else {
            return nil
        }
        if let result = container.result {
            Self.logger.debug("Meal scan AI decode branch=\(branchPrefix, privacy: .public)-result")
            return result
        }
        guard remainingTextDepth > 0 else {
            return nil
        }

        for text in container.textCandidates where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let nestedData = trimmed.data(using: .utf8) else { continue }

            if let result = decodeEnvelopeResult(
                from: nestedData,
                branchPrefix: "\(branchPrefix)-text-envelope",
                remainingTextDepth: remainingTextDepth - 1
            ) {
                return result
            }
            if let response = try? decoder.decode(MealScanAnalysisResponse.self, from: nestedData) {
                Self.logger.debug("Meal scan AI decode branch=\(branchPrefix, privacy: .public)-text-analysis-response")
                return response.result
            }
            if let direct = try? decoder.decode(MealScanResult.self, from: nestedData) {
                Self.logger.debug("Meal scan AI decode branch=\(branchPrefix, privacy: .public)-text-direct")
                return direct
            }
        }

        return nil
    }

    private static func normalizedResult(_ result: MealScanResult, for payload: MealScanPayload) -> MealScanResult {
        guard payload.volumeEstimate == nil,
              result.quality.depthContributedToEstimate == true
        else { return result }

        var normalized = result
        normalized.quality.depthContributedToEstimate = false
        normalized.quality.confidenceBreakdown?.portionVolume = nil
        normalized.quality.confidenceBreakdown?.density = nil
        return normalized
    }

    private func errorMessage(from data: Data) -> String? {
        guard !data.isEmpty,
              let envelope = try? decoder.decode(MealScanErrorEnvelope.self, from: data) else {
            return nil
        }
        return envelope.errorText
    }

    static func mockResult(payload: MealScanPayload, fallbackReason: String? = nil) -> MealScanResult {
        if let fallbackReason {
            return unavailableFallbackResult(payload: payload, fallbackReason: fallbackReason)
        }

        let hasDepth = payload.depthStats != nil
        let protein = MealIngredient(
            name: "Demo protein portion",
            grams: hasDepth ? 120 : 110,
            nutrition: MealNutritionTotals(
                calories: hasDepth ? 198 : 182,
                proteinGrams: hasDepth ? 37 : 34,
                carbohydrateGrams: 0,
                fatGrams: hasDepth ? 4.3 : 3.9,
                sodiumMilligrams: 88
            ),
            micronutrients: [
                Micronutrient(name: "Iron", amount: 1.1, unit: .milligrams),
                Micronutrient(name: "Potassium", amount: 307, unit: .milligrams)
            ],
            confidence: hasDepth ? 0.56 : 0.42,
            notes: "Demo-only item; no visual analysis was performed."
        )
        let carbohydrate = MealIngredient(
            name: "Demo carbohydrate portion",
            grams: hasDepth ? 150 : 135,
            nutrition: MealNutritionTotals(
                calories: hasDepth ? 167 : 150,
                proteinGrams: hasDepth ? 3.9 : 3.5,
                carbohydrateGrams: hasDepth ? 34.5 : 31,
                fatGrams: 1.4,
                fiberGrams: 2.7,
                sugarGrams: 0.5,
                sodiumMilligrams: 5
            ),
            micronutrients: [
                Micronutrient(name: "Magnesium", amount: 65, unit: .milligrams)
            ],
            confidence: hasDepth ? 0.52 : 0.38,
            notes: "Demo-only item; no visual analysis was performed."
        )
        let produce = MealIngredient(
            name: "Demo produce portion",
            grams: hasDepth ? 90 : 80,
            nutrition: MealNutritionTotals(
                calories: hasDepth ? 45 : 40,
                proteinGrams: 2,
                carbohydrateGrams: hasDepth ? 9 : 8,
                fatGrams: 0.4,
                fiberGrams: hasDepth ? 3.6 : 3.2,
                sugarGrams: hasDepth ? 4.2 : 3.7,
                sodiumMilligrams: 42
            ),
            micronutrients: [
                Micronutrient(name: "Vitamin C", amount: 28, unit: .milligrams),
                Micronutrient(name: "Vitamin A", amount: 210, unit: .micrograms)
            ],
            confidence: hasDepth ? 0.50 : 0.36,
            notes: "Demo-only item; no visual analysis was performed."
        )

        return MealScanResult(
            mode: payload.metadata.mode,
            title: "Demo meal estimate",
            summary: "Mock estimate for local Meal Scanner development. This is not a visual food recognition result.",
            ingredients: [protein, carbohydrate, produce],
            quality: MealScanQuality(
                level: hasDepth ? .good : .usable,
                confidence: hasDepth ? 0.52 : 0.38,
                hasDepth: hasDepth,
                hasLiDAR: payload.quality.hasLiDAR,
                depthSource: payload.depthStats?.source ?? .none,
                lightingEstimate: payload.quality.lightingEstimate,
                occlusionRisk: payload.quality.occlusionRisk,
                warnings: payload.quality.warnings + ["Mock result; no backend visual analysis was performed."]
            ),
            plateEstimate: payload.plateEstimate,
            metadata: MealScanResultMetadata(
                modelName: "meal-scanner-mock",
                backendVersion: "local",
                needsUserReview: true
            )
        )
    }

    /// Local-development-only stand-in for the Phase 3 resolve endpoint. Clearly labeled
    /// as a demo value (matching `mockResult`'s existing convention) so it is never
    /// mistaken for a real recalculation; production builds never take this branch.
    static func mockResolveResponse(for request: MealIngredientResolveRequest) -> MealIngredientResolveResponse {
        let grams = max(0, request.grams)
        let caloriesPerGram = 1.8
        let updated = MealIngredient(
            name: request.replacementName,
            grams: grams,
            nutrition: MealNutritionTotals(
                calories: grams * caloriesPerGram,
                proteinGrams: grams * 0.18,
                carbohydrateGrams: grams * 0.05,
                fatGrams: grams * 0.07,
                sodiumMilligrams: grams * 0.6
            ),
            confidence: 0.6,
            notes: "Demo-only recalculation; no backend visual analysis was performed."
        )
        return MealIngredientResolveResponse(updatedIngredient: updated, updatedMealTotals: updated.nutrition)
    }

    static func unavailableFallbackResult(payload: MealScanPayload, fallbackReason: String) -> MealScanResult {
        MealScanResult(
            mode: payload.metadata.mode,
            title: "Meal scan unavailable",
            summary: "The backend did not analyze this image, so Pulsar will not guess foods from a local fallback.",
            ingredients: [],
            totals: .zero,
            notes: [
                "No visual food recognition was performed.",
                "Retry when the meal scanner backend is available."
            ],
            accuracyDisclaimer: "No nutrition estimate is available because the backend did not analyze the meal image.",
            quality: MealScanQuality(
                level: .insufficient,
                confidence: 0.05,
                hasDepth: payload.depthStats != nil,
                hasLiDAR: payload.quality.hasLiDAR,
                depthSource: payload.depthStats?.source ?? .none,
                lightingEstimate: payload.quality.lightingEstimate,
                occlusionRisk: payload.quality.occlusionRisk,
                warnings: payload.quality.warnings + [
                    fallbackReason,
                    "No backend visual analysis was performed; no foods were inferred locally."
                ]
            ),
            plateEstimate: payload.plateEstimate,
            metadata: MealScanResultMetadata(
                modelName: "meal-scanner-local-fallback",
                backendVersion: "fallback",
                needsUserReview: true
            )
        )
    }

    private static func prompt(for payload: MealScanPayload) -> String {
        """
        Analyze this meal scan for Pulsar. Return strict JSON matching MealScanResult. Estimate ingredients, grams, calories, macros, fiber, sugar, sodium, micronutrients when visible, scan quality, plate estimate, and food regions. Use conservative portion estimates, respect the compact scan payload, and never claim raw depth was provided.

        Scan mode: \(payload.metadata.mode.rawValue)
        Depth source: \(payload.depthStats?.source.rawValue ?? "none")
        Scanner flow: \(payload.clientHints["scannerFlow"] ?? "unknown")
        Photo captured: \(payload.clientHints["photoPhaseCaptured"] ?? "unknown")
        LiDAR coverage ratio: \(payload.clientHints["lidarCoverageRatio"] ?? "unknown")
        LiDAR covered cells: \(payload.clientHints["lidarCoveredCellRatio"] ?? "unknown")
        """
    }

    private static let instructions = """
    You are the backend nutrition analysis service for Pulsar's 3D Meal Scanner. The client sends a compressed image and compact capture metadata only. Do not require or expose an API key in the app. Return strict JSON only, with no Markdown fences.

    Only identify foods supported by visible image evidence. Do not infer common meal templates. Do not invent ingredients that are not visible.
    First identify visible regions, then estimate nutrition from those regions. Treat food identity as uncertain unless texture, shape, color, separation, label text, or another visible cue supports it.
    Never label a protein as chicken, beef, pork, fish, tofu, egg, cheese, etc. unless visual cues clearly support that exact protein. If meat identity is ambiguous, use "unknown protein" or "ground meat/protein, type uncertain" with low confidence.
    If a food looks like cooked ground meat but the exact animal is not visually provable, name it "ground meat/protein, type uncertain", not chicken or beef.
    If the compact payload includes a volumeEstimate, use it only as portion-size evidence; choose density from the visible food form and include uncertainty instead of implying scale-level precision.
    For salad/vegetables, identify only visible groups such as leafy greens, tomato, cucumber, dressing, etc.; do not add unseen toppings.
    For each ingredient, include reasoning that cites visible evidence such as color, texture, shape, separation on the plate, garnish, packaging text, or image region.
    If evidence is weak, lower confidence, add notes, and set metadata.needsUserReview = true. Nutrition is an estimate and should mark needsUserReview true when uncertain.
    """

    private static func transportMessage(endpoint: URL, error: URLError) -> String {
        if error.code == .timedOut {
            return "Meal Scanner timed out. Try another scan in a moment."
        }
        #if targetEnvironment(simulator)
        return "Meal Scanner backend is not reachable. The iOS Simulator is calling \(endpoint.absoluteString)."
        #else
        if endpoint.host == "127.0.0.1" || endpoint.host == "localhost" {
            return "Meal Scanner backend is not reachable. On a physical iPhone, localhost points to the phone itself. Use the hosted backend."
        }
        return "Meal Scanner backend is not reachable. Check your network connection and backend endpoint."
        #endif
    }

    private static func shouldUseLocalFallback(for statusCode: Int) -> Bool {
        statusCode == 404 || statusCode == 501 || statusCode == 503
    }

    private static func unavailableBackendMessage(statusCode: Int) -> String {
        "Meal Scanner backend is unavailable (HTTP \(statusCode)). No foods were inferred locally. Check the backend deployment and try again."
    }
}

private extension MealScanResult {
    var isEmptyNutritionEstimate: Bool {
        ingredients.isEmpty && totals.isZero
    }
}

private extension MealNutritionTotals {
    var isZero: Bool {
        calories == 0
            && proteinGrams == 0
            && carbohydrateGrams == 0
            && fatGrams == 0
            && fiberGrams == 0
            && sugarGrams == 0
            && sodiumMilligrams == 0
    }
}

private struct MealScanResponseEnvelope: Decodable {
    var result: MealScanResult?
    var textCandidates: [String]

    enum CodingKeys: String, CodingKey {
        case result
        case content
        case reply
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        result = nil
        textCandidates = []

        for key in [CodingKeys.result, .content, .reply, .message] {
            if result == nil {
                result = try? container.decode(MealScanResult.self, forKey: key)
            }
            if result == nil,
               let response = try? container.decode(MealScanAnalysisResponse.self, forKey: key) {
                result = response.result
            }
            if let text = try? container.decode(String.self, forKey: key) {
                textCandidates.append(text)
            }
            if let message = try? container.decode(ResponseMessage.self, forKey: key) {
                textCandidates.append(message.content)
            }
        }
    }

    private struct ResponseMessage: Decodable {
        var content: String
    }
}

private struct MealScanErrorEnvelope: Decodable {
    var messageText: String?
    var errorDescription: String?
    var error: String?
    var content: String?

    var errorText: String? {
        messageText ?? errorDescription ?? content ?? error
    }

    enum CodingKeys: String, CodingKey {
        case message
        case error
        case errorDescription = "error_description"
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        error = try? container.decodeIfPresent(String.self, forKey: .error)
        errorDescription = try? container.decodeIfPresent(String.self, forKey: .errorDescription)
        content = try? container.decodeIfPresent(String.self, forKey: .content)

        if let message = try? container.decode(String.self, forKey: .message) {
            messageText = message
        } else if let message = try? container.decode(ResponseMessage.self, forKey: .message) {
            messageText = message.content
        } else {
            messageText = nil
        }
    }

    private struct ResponseMessage: Decodable {
        var content: String
    }
}
