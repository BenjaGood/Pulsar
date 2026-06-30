//
//  MealScannerTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

@Suite(.serialized)
struct MealScannerTests {
    @Test func ingredientGramEditsRecalculateTotalsProportionally() throws {
        let ingredient = MealIngredient(
            name: "Rice",
            grams: 100,
            nutrition: MealNutritionTotals(
                calories: 130,
                proteinGrams: 2.5,
                carbohydrateGrams: 28,
                fatGrams: 0.3,
                fiberGrams: 1.8
            ),
            confidence: 0.72
        )
        var result = MealScanResult(
            title: "Bowl",
            ingredients: [ingredient],
            quality: MealScanQuality(level: .good, confidence: 0.72)
        )

        result.updateIngredient(id: ingredient.id, estimatedGrams: 150)

        #expect(result.totalEstimatedGrams == 150)
        #expect(result.totalCalories == 195)
        #expect(result.totalCarbs == 42)
        #expect(result.ingredients.first?.protein == 3.75)
    }

    @Test func userFacingAIJSONAliasesDecodeIntoMealResult() throws {
        let json = """
        {
          "title": "Chicken rice plate",
          "totalCalories": 420,
          "totalCarbs": 39,
          "totalProtein": 38,
          "totalFat": 12,
          "totalFiber": 5,
          "confidence": 0.71,
          "ingredients": [
            {
              "name": "Grilled chicken",
              "estimatedGrams": 120,
              "calories": 198,
              "protein": 37,
              "carbs": 0,
              "fat": 4,
              "fiber": 0,
              "confidence": 0.76,
              "reasoning": "Lean protein region in the center of the plate."
            }
          ],
          "micronutrients": [
            { "name": "Iron", "amount": 1.1, "unit": "mg", "percentDailyValue": 6 }
          ],
          "accuracyDisclaimer": "Estimated using image + depth analysis."
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(MealScanResult.self, from: try #require(json.data(using: .utf8)))

        #expect(result.title == "Chicken rice plate")
        #expect(result.totalCalories == 420)
        #expect(result.totalProtein == 38)
        #expect(result.ingredients.first?.estimatedGrams == 120)
        #expect(result.ingredients.first?.reasoning?.contains("Lean protein") == true)
        #expect(result.micronutrients.first?.unit == "mg")
    }

    @Test func mealScannerConfigurationBuildsBackendEndpointWithoutSecrets() throws {
        let baseURL = try #require(URL(string: "https://www.aetherial.tech"))
        let configuration = MealScannerConfiguration(
            backendBaseURL: baseURL,
            analysisPath: "/api/orion/meal-scan"
        )

        #expect(configuration.analysisEndpoint?.absoluteString == "https://www.aetherial.tech/api/orion/meal-scan")
        #expect(configuration.isConfigured)
        #expect(configuration.missingConfigurationKeys().isEmpty)
    }

    @Test func http404UsesUnverifiedFallbackInsteadOfInventingFood() async throws {
        let baseURL = try #require(URL(string: "https://meal.example.test"))
        let configuration = MealScannerConfiguration(
            backendBaseURL: baseURL,
            analysisPath: "/api/orion/meal-scan"
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MealScannerURLProtocol.self]
        let recorder = MealScannerRequestRecorder(
            statusCode: 404,
            body: Data(#"{"error":"Not found"}"#.utf8)
        )
        MealScannerURLProtocol.register(recorder)
        defer { MealScannerURLProtocol.unregister(recorder) }

        let service = MealNutritionAIService(
            configuration: configuration,
            session: URLSession(configuration: sessionConfiguration)
        )
        let payload = MealScanPayload(
            metadata: MealScanCaptureMetadata(mode: .depthAssisted, imageWidth: 1080, imageHeight: 1440, imageOrientation: "up"),
            quality: MealScanQuality(level: .usable, confidence: 0.62, hasLiDAR: true)
        )

        let result = try await service.analyzeMeal(imageBase64: "image", payload: payload)

        #expect(recorder.paths == ["/api/orion/meal-scan"])
        #expect(result.metadata.backendVersion == "fallback")
        #expect(result.title.localizedCaseInsensitiveContains("chicken") == false)
        #expect(result.title.localizedCaseInsensitiveContains("rice") == false)
        #expect(result.ingredients.isEmpty)
        #expect(result.quality.confidence <= 0.2)
        #expect(result.metadata.needsUserReview)
        #expect(result.quality.warnings.contains { $0.contains("HTTP 404") })
        #expect(result.quality.warnings.contains { $0.contains("No backend visual analysis") })
    }

    @Test func analysisRequestRequiresVisibleEvidenceAndIncludesScanFlowHints() async throws {
        let baseURL = try #require(URL(string: "https://meal.example.test"))
        let configuration = MealScannerConfiguration(
            backendBaseURL: baseURL,
            analysisPath: "/api/orion/meal-scan"
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MealScannerURLProtocol.self]
        let recorder = MealScannerRequestRecorder(
            statusCode: 200,
            body: Data("""
            {
              "result": {
                "title": "Visible salad",
                "summary": "Backend visual result.",
                "ingredients": [],
                "quality": { "level": "usable", "confidence": 0.5 }
              }
            }
            """.utf8)
        )
        MealScannerURLProtocol.register(recorder)
        defer { MealScannerURLProtocol.unregister(recorder) }

        let service = MealNutritionAIService(
            configuration: configuration,
            session: URLSession(configuration: sessionConfiguration)
        )
        let payload = MealScanPayload(
            metadata: MealScanCaptureMetadata(mode: .depthAssisted, imageWidth: 1080, imageHeight: 1440, imageOrientation: "up"),
            quality: MealScanQuality(level: .usable, confidence: 0.62, hasLiDAR: true),
            clientHints: [
                "scannerFlow": "photo_then_lidar_v2",
                "photoPhaseCaptured": "true",
                "lidarCoverageRatio": "0.74",
                "lidarCoveredCellRatio": "0.68"
            ]
        )

        _ = try await service.analyzeMeal(imageBase64: "image", payload: payload)

        let requestBody = try #require(recorder.requestBodies.first)
        let object = try JSONSerialization.jsonObject(with: requestBody) as? [String: Any]
        let prompt = try #require(object?["prompt"] as? String)
        let instructions = try #require(object?["instructions"] as? String)

        #expect(prompt.contains("Scanner flow: photo_then_lidar_v2"))
        #expect(prompt.contains("LiDAR coverage ratio: 0.74"))
        #expect(instructions.contains("Only identify foods supported by visible image evidence"))
        #expect(instructions.contains("First identify visible regions"))
        #expect(instructions.contains("Do not infer common meal templates"))
        #expect(instructions.contains("unknown protein"))
        #expect(instructions.contains("ground meat/protein, type uncertain"))
        #expect(instructions.contains("Do not invent ingredients"))
    }
}

private final class MealScannerRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var paths: [String] = []
    private(set) var requestBodies: [Data] = []
    let statusCode: Int
    let body: Data

    init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }

    func append(path: String, body: Data?) {
        lock.lock()
        paths.append(path)
        if let body {
            requestBodies.append(body)
        }
        lock.unlock()
    }
}

private final class MealScannerURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var recorder: MealScannerRequestRecorder?

    static func register(_ recorder: MealScannerRequestRecorder) {
        lock.lock()
        self.recorder = recorder
        lock.unlock()
    }

    static func unregister(_ recorder: MealScannerRequestRecorder) {
        lock.lock()
        if self.recorder === recorder {
            self.recorder = nil
        }
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "meal.example.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let recorder = Self.recorder
        Self.lock.unlock()

        if let path = request.url?.path {
            recorder?.append(path: path, body: request.httpBody ?? Self.data(from: request.httpBodyStream))
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://meal.example.test")!,
            statusCode: recorder?.statusCode ?? 404,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: recorder?.body ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func data(from stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }
        return data.isEmpty ? nil : data
    }
}
