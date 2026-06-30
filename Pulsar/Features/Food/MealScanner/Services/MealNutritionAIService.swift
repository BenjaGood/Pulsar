//
//  MealNutritionAIService.swift
//  Pulsar
//

import Foundation

protocol MealNutritionAIServicing {
    func analyzeMeal(imageBase64: String, payload: MealScanPayload) async throws -> MealScanResult
}

struct MealScannerConfiguration: Equatable, Sendable {
    var backendBaseURL: URL?
    var analysisPath: String
    var mockMode: Bool
    var timeoutSeconds: TimeInterval

    static let notConfigured = MealScannerConfiguration()
    static let mock = MealScannerConfiguration(mockMode: true)

    init(
        backendBaseURL: URL? = nil,
        analysisPath: String = "/api/orion/meal-scan",
        mockMode: Bool = false,
        timeoutSeconds: TimeInterval = 45
    ) {
        self.backendBaseURL = backendBaseURL
        self.analysisPath = analysisPath.isEmpty ? "/api/orion/meal-scan" : analysisPath
        self.mockMode = mockMode
        self.timeoutSeconds = timeoutSeconds
    }

    var analysisEndpoint: URL? {
        guard let backendBaseURL else { return nil }
        return Self.endpoint(baseURL: backendBaseURL, path: analysisPath)
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
        if configuration.mockMode {
            return Self.mockResult(payload: payload)
        }

        guard let endpoint = configuration.analysisEndpoint else {
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw MealNutritionAIServiceError.transport(Self.transportMessage(endpoint: endpoint, error: error))
        } catch {
            throw MealNutritionAIServiceError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MealNutritionAIServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            if Self.shouldUseLocalFallback(for: httpResponse.statusCode) {
                return Self.unavailableFallbackResult(
                    payload: payload,
                    fallbackReason: Self.backendFallbackWarning(statusCode: httpResponse.statusCode)
                )
            }
            throw MealNutritionAIServiceError.http(
                statusCode: httpResponse.statusCode,
                message: errorMessage(from: data) ?? "Meal Scanner backend returned HTTP \(httpResponse.statusCode)."
            )
        }
        guard !data.isEmpty else {
            throw MealNutritionAIServiceError.emptyResponse
        }

        do {
            return try decodeResult(from: data)
        } catch let error as MealNutritionAIServiceError {
            throw error
        } catch {
            throw MealNutritionAIServiceError.decoding(error.localizedDescription)
        }
    }

    private func decodeResult(from data: Data) throws -> MealScanResult {
        if let direct = try? decoder.decode(MealScanResult.self, from: data) {
            return direct
        }
        if let response = try? decoder.decode(MealScanAnalysisResponse.self, from: data) {
            return response.result
        }

        let container = try decoder.decode(MealScanResponseEnvelope.self, from: data)
        if let result = container.result {
            return result
        }

        for text in container.textCandidates where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let nestedData = trimmed.data(using: .utf8) else { continue }

            if let direct = try? decoder.decode(MealScanResult.self, from: nestedData) {
                return direct
            }
            if let response = try? decoder.decode(MealScanAnalysisResponse.self, from: nestedData) {
                return response.result
            }
        }

        throw MealNutritionAIServiceError.emptyResponse
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

    private static func backendFallbackWarning(statusCode: Int) -> String {
        "Backend meal-scan endpoint unavailable (HTTP \(statusCode)); no local food estimate was produced."
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
