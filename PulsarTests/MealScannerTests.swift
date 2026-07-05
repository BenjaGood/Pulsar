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

    @Test func measuredDepthContributionRequiresExplicitFlag() throws {
        let ingredient = MealIngredient(
            name: "Rice",
            grams: 100,
            nutrition: MealNutritionTotals(calories: 130, proteinGrams: 2.5, carbohydrateGrams: 28),
            confidence: 0.72
        )
        let depthContextOnly = MealScanResult(
            title: "Depth context result",
            ingredients: [ingredient],
            quality: MealScanQuality(
                level: .good,
                confidence: 0.72,
                hasDepth: true,
                hasLiDAR: true,
                depthSource: .sceneDepth
            )
        )
        let measuredDepth = MealScanResult(
            title: "Measured depth result",
            ingredients: [ingredient],
            quality: MealScanQuality(
                level: .good,
                confidence: 0.82,
                hasDepth: true,
                hasLiDAR: true,
                depthContributedToEstimate: true,
                depthSource: .smoothedSceneDepth
            )
        )

        #expect(depthContextOnly.usesMeasuredDepthForPortionEstimate == false)
        #expect(measuredDepth.usesMeasuredDepthForPortionEstimate)
    }

    @Test func phase2MealScanPayloadEncodesOptionalGeometryContract() throws {
        let payload = MealScanPayload(
            metadata: MealScanCaptureMetadata(mode: .depthAssisted, imageWidth: 1080, imageHeight: 1440, imageOrientation: "up"),
            quality: MealScanQuality(level: .good, confidence: 0.82, hasDepth: true, hasLiDAR: true, depthSource: .smoothedSceneDepth),
            depthStats: MealScanDepthStats(
                source: .smoothedSceneDepth,
                width: 256,
                height: 192,
                validSampleCount: 320,
                sampledPixelCount: 400,
                minMeters: 0.32,
                maxMeters: 0.84,
                meanMeters: 0.51,
                percentile10Meters: 0.38,
                percentile50Meters: 0.49,
                percentile90Meters: 0.72,
                highConfidenceRatio: 0.78
            ),
            camera: MealScanCameraMetadata(
                trackingState: "normal",
                cameraIntrinsics: [1, 0, 0, 0, 1, 0, 540, 720, 1],
                cameraTransform: [
                    1, 0, 0, 0,
                    0, 1, 0, 0,
                    0, 0, 1, 0,
                    0.1, 0.2, -0.4, 1
                ],
                imageResolutionWidth: 1080,
                imageResolutionHeight: 1440
            ),
            volumeEstimate: MealVolumeEstimate(
                volumeMilliliters: 180,
                method: "single_frame_placeholder",
                supportPlaneConfidence: 0.74,
                coverage: 0.68,
                uncertaintyMlLow: 140,
                uncertaintyMlHigh: 230
            ),
            foodRegions: [
                MealFoodRegion(
                    label: "Cooked rice",
                    normalizedBoundingBox: MealScanNormalizedRect(x: 0.2, y: 0.25, width: 0.48, height: 0.42),
                    estimatedGrams: nil,
                    estimatedVolumeMilliliters: 180,
                    confidence: 0.68
                )
            ],
            clientHints: ["depthRawIncluded": "false"]
        )

        let data = try JSONEncoder().encode(payload)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let camera = try #require(object?["camera"] as? [String: Any])
        let transform = try #require(camera["cameraTransform"] as? [Any])
        let volumeEstimate = try #require(object?["volumeEstimate"] as? [String: Any])
        let foodRegions = try #require(object?["foodRegions"] as? [[String: Any]])
        let requestText = String(decoding: data, as: UTF8.self)

        #expect(transform.count == 16)
        #expect(volumeEstimate["volumeMilliliters"] as? Double == 180)
        #expect(volumeEstimate["method"] as? String == "single_frame_placeholder")
        #expect(foodRegions.first?["estimatedVolumeMilliliters"] as? Double == 180)
        #expect(requestText.contains("depthMap") == false)
        #expect(requestText.contains("rawDepth") == false)
        #expect(requestText.contains("imageBase64") == false)
    }

    @Test func phase2MealScanResultDecodesOptionalConfidenceAndDensityFields() throws {
        let json = """
        {
          "title": "Measured rice bowl",
          "ingredients": [
            {
              "name": "Cooked rice",
              "grams": 168,
              "estimatedVolumeMilliliters": 210,
              "densityUsed": 0.8,
              "gramsLow": 140,
              "gramsHigh": 190,
              "nutrition": {
                "calories": 218,
                "proteinGrams": 4.5,
                "carbohydrateGrams": 48,
                "fatGrams": 0.5,
                "fiberGrams": 1.4,
                "sugarGrams": 0.2,
                "sodiumMilligrams": 2
              },
              "micronutrients": [],
              "confidence": 0.76
            }
          ],
          "totals": {
            "calories": 218,
            "proteinGrams": 4.5,
            "carbohydrateGrams": 48,
            "fatGrams": 0.5,
            "fiberGrams": 1.4,
            "sugarGrams": 0.2,
            "sodiumMilligrams": 2
          },
          "quality": {
            "level": "good",
            "confidence": 0.78,
            "hasDepth": true,
            "hasLiDAR": true,
            "depthContributedToEstimate": true,
            "confidenceBreakdown": {
              "foodRecognition": 0.72,
              "depthCoverage": 0.82,
              "portionVolume": 0.74,
              "density": 0.64,
              "overall": 0.70
            },
            "depthSource": "smoothedSceneDepth",
            "occlusionRisk": 0.2,
            "warnings": ["Review density range."]
          }
        }
        """

        let result = try JSONDecoder().decode(MealScanResult.self, from: try #require(json.data(using: .utf8)))

        #expect(result.usesMeasuredDepthForPortionEstimate)
        #expect(result.quality.confidenceBreakdown?.portionVolume == 0.74)
        #expect(result.ingredients.first?.estimatedVolumeMilliliters == 210)
        #expect(result.ingredients.first?.densityUsed == 0.8)
        #expect(result.ingredients.first?.gramsLow == 140)
        #expect(result.ingredients.first?.gramsHigh == 190)
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

    @Test func successEnvelopeDecodesInnerMealResult() async throws {
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
              "id": "resp_meal_123",
              "created_at": "2026-07-03T12:00:00Z",
              "model": "gpt-4.1-mini",
              "result": {
                "id": "00000000-0000-0000-0000-000000000123",
                "created_at": "2026-07-03T12:00:01Z",
                "title": "Chicken rice bowl",
                "summary": "Visible chicken and rice with greens.",
                "ingredients": [
                  {
                    "name": "Grilled chicken",
                    "estimatedGrams": 125,
                    "nutrition": {
                      "calories": 210,
                      "proteinGrams": 39,
                      "carbohydrateGrams": 0,
                      "fatGrams": 5,
                      "fiberGrams": 0,
                      "sugarGrams": 0,
                      "sodiumMilligrams": 92
                    },
                    "confidence": 0.84
                  },
                  {
                    "name": "Rice",
                    "estimatedGrams": 155,
                    "nutrition": {
                      "calories": 202,
                      "proteinGrams": 4,
                      "carbohydrateGrams": 44,
                      "fatGrams": 0.4,
                      "fiberGrams": 1.2,
                      "sugarGrams": 0.1,
                      "sodiumMilligrams": 2
                    },
                    "confidence": 0.78
                  }
                ],
                "totals": {
                  "calories": 412,
                  "proteinGrams": 43,
                  "carbohydrateGrams": 44,
                  "fatGrams": 5.4,
                  "fiberGrams": 1.2,
                  "sugarGrams": 0.1,
                  "sodiumMilligrams": 94
                },
                "quality": {
                  "level": "good",
                  "confidence": 0.82,
                  "hasDepth": true,
                  "hasLiDAR": true,
                  "depthSource": "sceneDepth",
                  "occlusionRisk": 0.18,
                  "warnings": []
                }
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
            quality: MealScanQuality(level: .usable, confidence: 0.62, hasLiDAR: true)
        )

        let result = try await service.analyzeMeal(imageBase64: "image", payload: payload)

        #expect(recorder.paths == ["/api/orion/meal-scan"])
        #expect(result.id.uuidString == "00000000-0000-0000-0000-000000000123")
        #expect(result.title == "Chicken rice bowl")
        #expect(result.ingredients.count == 2)
        #expect(result.ingredients.first?.estimatedGrams == 125)
        #expect(result.totalCalories == 412)
        #expect(result.totalProtein == 43)
        #expect(result.totalCarbs == 44)
        #expect(result.quality.confidence == 0.82)
        #expect(result.quality.confidence != 0.5)
        #expect(result.usesMeasuredDepthForPortionEstimate == false)
    }

    @Test func backendCannotClaimMeasuredDepthWithoutClientVolumeEstimate() async throws {
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
                "title": "Rice bowl",
                "ingredients": [
                  {
                    "name": "Rice",
                    "estimatedGrams": 170,
                    "nutrition": {
                      "calories": 221,
                      "proteinGrams": 4,
                      "carbohydrateGrams": 48,
                      "fatGrams": 0.5,
                      "fiberGrams": 1.4,
                      "sugarGrams": 0.1,
                      "sodiumMilligrams": 2
                    },
                    "confidence": 0.78
                  }
                ],
                "totals": {
                  "calories": 221,
                  "proteinGrams": 4,
                  "carbohydrateGrams": 48,
                  "fatGrams": 0.5,
                  "fiberGrams": 1.4,
                  "sugarGrams": 0.1,
                  "sodiumMilligrams": 2
                },
                "quality": {
                  "level": "good",
                  "confidence": 0.82,
                  "hasDepth": true,
                  "hasLiDAR": true,
                  "depthContributedToEstimate": true,
                  "confidenceBreakdown": {
                    "foodRecognition": 0.78,
                    "depthCoverage": 0.7,
                    "portionVolume": 0.8,
                    "density": 0.66,
                    "overall": 0.75
                  },
                  "depthSource": "sceneDepth",
                  "occlusionRisk": 0.18,
                  "warnings": []
                }
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
            quality: MealScanQuality(level: .usable, confidence: 0.62, hasDepth: true, hasLiDAR: true),
            depthStats: MealScanDepthStats(
                source: .sceneDepth,
                width: 256,
                height: 192,
                validSampleCount: 200,
                sampledPixelCount: 320,
                minMeters: 0.32,
                maxMeters: 0.75,
                meanMeters: 0.48,
                percentile10Meters: 0.36,
                percentile50Meters: 0.46,
                percentile90Meters: 0.62
            )
        )

        let result = try await service.analyzeMeal(imageBase64: "image", payload: payload)

        #expect(result.quality.hasDepth)
        #expect(result.usesMeasuredDepthForPortionEstimate == false)
        #expect(result.quality.confidenceBreakdown?.portionVolume == nil)
        #expect(result.quality.confidenceBreakdown?.density == nil)
    }

    @Test func bareMealScanResultBodyStillDecodes() async throws {
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
              "id": "00000000-0000-0000-0000-000000000456",
              "created_at": "2026-07-03T12:05:00Z",
              "title": "Turkey sandwich",
              "ingredients": [
                {
                  "name": "Turkey sandwich",
                  "estimatedGrams": 230,
                  "calories": 390,
                  "protein": 31,
                  "carbs": 43,
                  "fat": 11,
                  "fiber": 5,
                  "confidence": 0.77
                }
              ],
              "totalCalories": 390,
              "totalProtein": 31,
              "totalCarbs": 43,
              "totalFat": 11,
              "totalFiber": 5,
              "quality": {
                "level": "usable",
                "confidence": 0.74,
                "hasDepth": false,
                "hasLiDAR": false,
                "depthSource": "none",
                "occlusionRisk": 0.34,
                "warnings": []
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
            metadata: MealScanCaptureMetadata(mode: .photoOnly, imageWidth: 1080, imageHeight: 1440, imageOrientation: "up"),
            quality: MealScanQuality(level: .usable, confidence: 0.62)
        )

        let result = try await service.analyzeMeal(imageBase64: "image", payload: payload)

        #expect(recorder.paths == ["/api/orion/meal-scan"])
        #expect(result.id.uuidString == "00000000-0000-0000-0000-000000000456")
        #expect(result.title == "Turkey sandwich")
        #expect(result.ingredients.count == 1)
        #expect(result.totalCalories == 390)
        #expect(result.quality.confidence == 0.74)
    }

    @Test func zeroResultEnvelopeThrowsEmptyResponseInsteadOfEmptySuccess() async throws {
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
              "id": "resp_empty",
              "created_at": "2026-07-03T12:10:00Z",
              "model": "gpt-4.1-mini",
              "result": {
                "title": "No visible food",
                "ingredients": [],
                "totals": {
                  "calories": 0,
                  "proteinGrams": 0,
                  "carbohydrateGrams": 0,
                  "fatGrams": 0,
                  "fiberGrams": 0,
                  "sugarGrams": 0,
                  "sodiumMilligrams": 0
                },
                "quality": {
                  "level": "insufficient",
                  "confidence": 0.5,
                  "hasDepth": false,
                  "hasLiDAR": false,
                  "depthSource": "none",
                  "occlusionRisk": 0.8,
                  "warnings": ["No visible foods found."]
                }
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
            metadata: MealScanCaptureMetadata(mode: .photoOnly, imageWidth: 1080, imageHeight: 1440, imageOrientation: "up"),
            quality: MealScanQuality(level: .usable, confidence: 0.62)
        )

        do {
            _ = try await service.analyzeMeal(imageBase64: "image", payload: payload)
            Issue.record("Expected zero-result 200 response to throw instead of returning an empty success.")
        } catch let error as MealNutritionAIServiceError {
            guard case .emptyResponse = error else {
                Issue.record("Expected emptyResponse for zero-result 200 response, got \(error).")
                return
            }
        } catch {
            Issue.record("Expected MealNutritionAIServiceError.emptyResponse, got \(error).")
        }

        #expect(recorder.paths == ["/api/orion/meal-scan"])
    }

    @Test func nonJSONSuccessResponseThrowsDecodingOrEmptyResponse() async throws {
        let baseURL = try #require(URL(string: "https://meal.example.test"))
        let configuration = MealScannerConfiguration(
            backendBaseURL: baseURL,
            analysisPath: "/api/orion/meal-scan"
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MealScannerURLProtocol.self]
        let recorder = MealScannerRequestRecorder(
            statusCode: 200,
            body: Data("this is not json".utf8)
        )
        MealScannerURLProtocol.register(recorder)
        defer { MealScannerURLProtocol.unregister(recorder) }

        let service = MealNutritionAIService(
            configuration: configuration,
            session: URLSession(configuration: sessionConfiguration)
        )
        let payload = MealScanPayload(
            metadata: MealScanCaptureMetadata(mode: .photoOnly, imageWidth: 1080, imageHeight: 1440, imageOrientation: "up"),
            quality: MealScanQuality(level: .usable, confidence: 0.62)
        )

        do {
            _ = try await service.analyzeMeal(imageBase64: "image", payload: payload)
            Issue.record("Expected malformed 200 response to throw instead of returning a default meal result.")
        } catch let error as MealNutritionAIServiceError {
            switch error {
            case .decoding, .emptyResponse:
                break
            default:
                Issue.record("Expected decoding or emptyResponse, got \(error).")
            }
        } catch {
            Issue.record("Expected MealNutritionAIServiceError.decoding or emptyResponse, got \(error).")
        }

        #expect(recorder.paths == ["/api/orion/meal-scan"])
    }

    @Test func http404And503ThrowRetryableErrorInsteadOfInventingFood() async throws {
        for statusCode in [404, 503] {
            try await assertHTTPStatusThrowsRetryableBackendError(statusCode)
        }
    }

    @Test func saveToNutritionEligibilityRequiresPositiveIngredientGrams() throws {
        let emptyResult = MealScanResult(
            title: "Empty result",
            ingredients: [],
            quality: MealScanQuality(level: .insufficient, confidence: 0.2)
        )
        let zeroGramResult = MealScanResult(
            title: "Zero gram result",
            ingredients: [
                MealIngredient(
                    name: "Unknown food",
                    grams: 0,
                    nutrition: .zero,
                    confidence: 0.1
                )
            ],
            quality: MealScanQuality(level: .insufficient, confidence: 0.2)
        )
        let validResult = MealScanResult(
            title: "Valid result",
            ingredients: [
                MealIngredient(
                    name: "Greek yogurt",
                    grams: 170,
                    nutrition: MealNutritionTotals(
                        calories: 100,
                        proteinGrams: 17,
                        carbohydrateGrams: 6,
                        fatGrams: 0,
                        fiberGrams: 0
                    ),
                    confidence: 0.82
                )
            ],
            quality: MealScanQuality(level: .good, confidence: 0.82)
        )

        #expect(Self.saveToNutritionButtonIsEnabled(for: emptyResult) == false)
        #expect(Self.saveToNutritionButtonIsEnabled(for: zeroGramResult) == false)
        #expect(Self.saveToNutritionButtonIsEnabled(for: validResult))
        #expect(Self.saveToNutritionButtonIsEnabled(for: validResult, hasSaved: true) == false)
    }

    @Test func phase1AmbiguityDetectionCoversBackendAndPromptExamples() {
        let ambiguousExamples: [(String, MealIngredientAmbiguityType)] = [
            ("unknown protein, chopped", .protein),
            ("ground meat/protein, type uncertain", .protein),
            ("Detected food, type uncertain", .ingredient),
            ("unknown sauce", .sauce),
            ("unknown topping", .topping),
            ("poultry or protein, type uncertain", .protein),
            ("pork or processed meat, type uncertain", .protein),
            ("seafood/protein, type uncertain", .protein),
            ("protein/dairy item, type uncertain", .protein)
        ]

        for (name, type) in ambiguousExamples {
            let ingredient = MealIngredient(name: name, grams: 40, nutrition: .zero, confidence: 0.4)
            #expect(ingredient.resolvedIsAmbiguous, "\(name) should require clarification")
            #expect(ingredient.resolvedAmbiguityType == type)
        }

        for name in ["chicken", "corn tortilla", "chopped onion"] {
            let ingredient = MealIngredient(name: name, grams: 40, nutrition: .zero, confidence: 0.8)
            #expect(ingredient.resolvedIsAmbiguous == false, "\(name) should not require clarification")
        }
    }

    @Test func phase1AmbiguityFieldsDecodeBackwardCompatiblyAndUseBackendPreference() throws {
        let json = """
        {
          "name": "poultry or protein, type uncertain",
          "grams": 120.5,
          "nutrition": {
            "calories": 220.25,
            "proteinGrams": 31.5,
            "carbohydrateGrams": 0,
            "fatGrams": 9.25
          },
          "confidence": 0.56,
          "is_ambiguous": true,
          "ambiguity_type": "protein",
          "clarification_question": "What type of protein is this?",
          "suggestions": ["Chicken", "Turkey"],
          "visual_evidence": "Browned chopped protein pieces.",
          "requires_user_confirmation": true
        }
        """

        let ingredient = try JSONDecoder().decode(MealIngredient.self, from: try #require(json.data(using: .utf8)))

        #expect(ingredient.estimatedGrams == 120.5)
        #expect(ingredient.resolvedIsAmbiguous)
        #expect(ingredient.resolvedAmbiguityType == .protein)
        #expect(ingredient.clarificationQuestion == "What type of protein is this?")
        #expect(ingredient.ambiguitySuggestions == ["Chicken", "Turkey"])
        #expect(ingredient.ambiguityEvidenceText == "Browned chopped protein pieces.")
        #expect(ingredient.requiresUserConfirmation == true)
    }

    @Test func phase1ResultTracksMultipleUnresolvedAmbiguousIngredients() {
        let result = MealScanResult(
            title: "Tacos",
            ingredients: [
                MealIngredient(name: "corn tortilla", grams: 120, nutrition: .zero, confidence: 0.8),
                MealIngredient(name: "unknown protein, chopped", grams: 90, nutrition: .zero, confidence: 0.42),
                MealIngredient(name: "unknown sauce", grams: 20, nutrition: .zero, confidence: 0.35)
            ],
            quality: MealScanQuality(level: .usable, confidence: 0.6)
        )

        #expect(result.hasUnresolvedAmbiguousIngredients)
        #expect(result.ambiguousIngredients.count == 2)
        #expect(result.hasSavableMealScannerIngredients)
    }

    @Test func phase1ConfirmingAmbiguousIngredientRenamesAndMarksNutritionPending() throws {
        let ingredient = MealIngredient(
            name: "unknown protein, chopped",
            grams: 90.75,
            nutrition: MealNutritionTotals(calories: 180, proteinGrams: 20, fatGrams: 10),
            confidence: 0.42
        )

        let resolved = ingredient.resolvingAmbiguity(as: "grilled chicken")

        #expect(resolved.name == "grilled chicken")
        #expect(resolved.originalName == "unknown protein, chopped")
        #expect(resolved.userResolvedName == "grilled chicken")
        #expect(resolved.wasUserCorrected)
        #expect(resolved.wasKeptAsUnknown == false)
        #expect(resolved.nutritionNeedsRecalculation)
        #expect(resolved.needsUserClarification == false)
        #expect(resolved.estimatedGrams == 90.75)
        #expect(resolved.calories == 180, "Phase 1 must not fake recalculated macros")
    }

    @Test func phase1KeepingUnknownRequiresReviewWithoutRenaming() {
        let ingredient = MealIngredient(
            name: "Detected food, type uncertain",
            grams: 33.3,
            nutrition: MealNutritionTotals(calories: 42),
            confidence: 0.74
        )

        let kept = ingredient.keepingAsUnknown()

        #expect(kept.name == "Detected food, type uncertain")
        #expect(kept.originalName == "Detected food, type uncertain")
        #expect(kept.wasKeptAsUnknown)
        #expect(kept.wasUserCorrected == false)
        #expect(kept.needsUserClarification == false)
        #expect(kept.confidence <= 0.35)
        #expect(kept.mealScannerCanSave)
        #expect(kept.mealScannerSaveDetail.contains("needs review"))
    }

    @Test func phase1GramsAdjustmentPreservesCorrectedNameAndResolutionState() {
        let ingredient = MealIngredient(
            name: "unknown protein, chopped",
            grams: 100,
            nutrition: MealNutritionTotals(calories: 200, proteinGrams: 30, fatGrams: 8),
            confidence: 0.4
        )
        .resolvingAmbiguity(as: "tofu")

        let adjusted = ingredient.scaled(toGrams: 125.5)

        #expect(adjusted.name == "tofu")
        #expect(adjusted.originalName == "unknown protein, chopped")
        #expect(adjusted.wasUserCorrected)
        #expect(adjusted.nutritionNeedsRecalculation)
        #expect(adjusted.estimatedGrams == 125.5)
        #expect(abs(adjusted.calories - 251) < 0.001)
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
                "ingredients": [
                  {
                    "name": "Leafy greens",
                    "estimatedGrams": 85,
                    "calories": 18,
                    "protein": 1.5,
                    "carbs": 3.2,
                    "fat": 0.2,
                    "fiber": 2.1,
                    "confidence": 0.72
                  }
                ],
                "totals": {
                  "calories": 18,
                  "proteinGrams": 1.5,
                  "carbohydrateGrams": 3.2,
                  "fatGrams": 0.2,
                  "fiberGrams": 2.1,
                  "sugarGrams": 0.6,
                  "sodiumMilligrams": 28
                },
                "quality": {
                  "level": "usable",
                  "confidence": 0.72,
                  "hasDepth": false,
                  "hasLiDAR": false,
                  "depthSource": "none",
                  "occlusionRisk": 0.3,
                  "warnings": []
                }
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
        let requestText = String(decoding: requestBody, as: UTF8.self)
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
        #expect(requestText.contains("depthContributedToEstimate") == false)
    }

    // MARK: - Phase 3: Volume estimator (synthetic depth grids, no ARKit objects)

    @Test func phase3VolumeEstimatorFlatCuboidProducesExpectedMilliliters() throws {
        // 64×64 grid. Support region: rows 0-15 and 48-63 (maskValue=0, depth=0.50m).
        // Food region: rows 16-47 (maskValue=255, depth=0.45m → 5 cm above support).
        // Camera: fx=fy=200, cx=cy=32, identity transform → unprojects to camera space.
        // Expected: each food pixel contributes height=0.05m, pixelArea=0.45²/(200×200)=5.0625e-6 m².
        // Food pixels: 32 rows × 64 cols = 2048. Volume ≈ 2048 × 0.05 × 5.0625e-6 = 518.4 mL.
        let width = 64
        let height = 64
        var depths = [Float](repeating: 0, count: width * height)
        var mask = [UInt8](repeating: 0, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                if y >= 16 && y < 48 {
                    depths[index] = 0.45
                    mask[index] = 255
                } else {
                    depths[index] = 0.50
                    mask[index] = 0
                }
            }
        }

        let grid = MealVolumeEstimator.DepthGrid(
            width: width,
            height: height,
            depthsMeters: depths,
            maskValues: mask
        )
        let calibration = MealVolumeEstimator.CameraCalibration(
            fx: 200, fy: 200, cx: 32, cy: 32,
            imageWidth: width,
            imageHeight: height
        )

        let result = MealVolumeEstimator.estimate(grid: grid, calibration: calibration)

        let estimate = try #require(result, "Expected a volume estimate for a well-defined cuboid synthetic shape")
        let expectedML = 518.4
        let tolerance = 0.05
        #expect(estimate.volumeMilliliters > expectedML * (1 - tolerance))
        #expect(estimate.volumeMilliliters < expectedML * (1 + tolerance))
        #expect(estimate.method == "single_frame_depth_mask_v1")
        #expect(estimate.supportPlaneConfidence > 0.5)
        #expect(estimate.coverage > 0)
        #expect(estimate.uncertaintyMlLow < estimate.volumeMilliliters)
        #expect(estimate.uncertaintyMlHigh > estimate.volumeMilliliters)
    }

    @Test func phase3VolumeEstimatorUsesOnlyHighConfidenceFoodSamples() throws {
        let width = 64
        let height = 64
        var depths = [Float](repeating: 0.50, count: width * height)
        var mask = [UInt8](repeating: 0, count: width * height)
        var confidence = [UInt8](repeating: 2, count: width * height)

        for y in 16..<48 {
            for x in 0..<width {
                let index = y * width + x
                depths[index] = 0.45
                mask[index] = 255
                confidence[index] = y < 32 ? 2 : 1
            }
        }

        let grid = MealVolumeEstimator.DepthGrid(
            width: width,
            height: height,
            depthsMeters: depths,
            maskValues: mask,
            confidenceValues: confidence
        )
        let calibration = MealVolumeEstimator.CameraCalibration(
            fx: 200, fy: 200, cx: 32, cy: 32,
            imageWidth: width,
            imageHeight: height
        )

        let result = MealVolumeEstimator.estimate(grid: grid, calibration: calibration)

        let estimate = try #require(result, "Expected high-confidence food samples to produce an estimate")
        let expectedML = 259.2
        let tolerance = 0.08
        #expect(estimate.volumeMilliliters > expectedML * (1 - tolerance))
        #expect(estimate.volumeMilliliters < expectedML * (1 + tolerance))
    }

    @Test func phase3VolumeEstimatorRejectsMediumConfidenceFoodSamples() {
        let width = 64
        let height = 64
        var depths = [Float](repeating: 0.50, count: width * height)
        var mask = [UInt8](repeating: 0, count: width * height)
        var confidence = [UInt8](repeating: 2, count: width * height)

        for y in 16..<48 {
            for x in 0..<width {
                let index = y * width + x
                depths[index] = 0.45
                mask[index] = 255
                confidence[index] = 1
            }
        }

        let grid = MealVolumeEstimator.DepthGrid(
            width: width,
            height: height,
            depthsMeters: depths,
            maskValues: mask,
            confidenceValues: confidence
        )
        let calibration = MealVolumeEstimator.CameraCalibration(
            fx: 200, fy: 200, cx: 32, cy: 32,
            imageWidth: width,
            imageHeight: height
        )

        let result = MealVolumeEstimator.estimate(grid: grid, calibration: calibration)
        #expect(result == nil, "Medium-confidence food depth should not produce a measured volume")
    }

    @Test func phase3VolumeEstimatorReturnsNilForEmptyMask() {
        let width = 64
        let height = 64
        let depths = [Float](repeating: 0.50, count: width * height)
        let mask = [UInt8](repeating: 0, count: width * height)

        let grid = MealVolumeEstimator.DepthGrid(
            width: width,
            height: height,
            depthsMeters: depths,
            maskValues: mask
        )
        let calibration = MealVolumeEstimator.CameraCalibration(
            fx: 200, fy: 200, cx: 32, cy: 32,
            imageWidth: width,
            imageHeight: height
        )

        let result = MealVolumeEstimator.estimate(grid: grid, calibration: calibration)
        #expect(result == nil, "Empty mask should produce no estimate")
    }

    @Test func phase3VolumeEstimatorReturnsNilForInsufficientFoodSamples() {
        // Only 4 food pixels — below the 24-sample minimum.
        let width = 64
        let height = 64
        var depths = [Float](repeating: 0.50, count: width * height)
        var mask = [UInt8](repeating: 0, count: width * height)

        for i in 0..<4 {
            depths[width * 30 + 30 + i] = 0.45
            mask[width * 30 + 30 + i] = 255
        }

        let grid = MealVolumeEstimator.DepthGrid(
            width: width,
            height: height,
            depthsMeters: depths,
            maskValues: mask
        )
        let calibration = MealVolumeEstimator.CameraCalibration(
            fx: 200, fy: 200, cx: 32, cy: 32,
            imageWidth: width,
            imageHeight: height
        )

        let result = MealVolumeEstimator.estimate(grid: grid, calibration: calibration)
        #expect(result == nil, "Too few food samples should produce no estimate")
    }

    @Test func phase3MaskResamplingIdentityPreservesAllValues() {
        let values: [UInt8] = [0, 128, 255, 64, 192, 32, 0, 255, 100]
        let resampled = MealVolumeEstimator.resampledMaskValues(
            from: values,
            maskWidth: 3,
            maskHeight: 3,
            depthWidth: 3,
            depthHeight: 3
        )
        #expect(resampled == values)
    }

    @Test func phase3MaskResamplingDownscalesWithNearestNeighbour() {
        // 4×4 mask where top-left quadrant is 255, rest is 0. Resample to 2×2.
        var values = [UInt8](repeating: 0, count: 16)
        values[0] = 255
        values[1] = 255
        values[4] = 255
        values[5] = 255

        let resampled = MealVolumeEstimator.resampledMaskValues(
            from: values,
            maskWidth: 4,
            maskHeight: 4,
            depthWidth: 2,
            depthHeight: 2
        )

        #expect(resampled.count == 4)
        #expect(resampled[0] == 255)
        #expect(resampled[1] == 0)
        #expect(resampled[2] == 0)
        #expect(resampled[3] == 0)
    }

    @Test func phase3VolumeEstimateRoundTripCodable() throws {
        let original = MealVolumeEstimate(
            volumeMilliliters: 312.5,
            method: "single_frame_depth_mask_v1",
            supportPlaneConfidence: 0.81,
            coverage: 0.72,
            uncertaintyMlLow: 250,
            uncertaintyMlHigh: 385
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MealVolumeEstimate.self, from: data)

        #expect(decoded.volumeMilliliters == original.volumeMilliliters)
        #expect(decoded.method == original.method)
        #expect(decoded.supportPlaneConfidence == original.supportPlaneConfidence)
        #expect(decoded.coverage == original.coverage)
        #expect(decoded.uncertaintyMlLow == original.uncertaintyMlLow)
        #expect(decoded.uncertaintyMlHigh == original.uncertaintyMlHigh)
    }

    @Test func phase3PayloadIncludesVolumeEstimateWhenDepthContributes() throws {
        // Verify that a payload built with a volume estimate sets depthContributedToEstimate.
        let volumeEstimate = MealVolumeEstimate(
            volumeMilliliters: 200,
            method: "single_frame_depth_mask_v1",
            supportPlaneConfidence: 0.78,
            coverage: 0.65,
            uncertaintyMlLow: 160,
            uncertaintyMlHigh: 250
        )
        let quality = MealScanQuality(
            level: .good,
            confidence: 0.82,
            hasDepth: true,
            hasLiDAR: true,
            depthContributedToEstimate: true,
            depthSource: .smoothedSceneDepth
        )
        let payload = MealScanPayload(
            metadata: MealScanCaptureMetadata(mode: .depthAssisted, imageWidth: 1080, imageHeight: 1440, imageOrientation: "up"),
            quality: quality,
            volumeEstimate: volumeEstimate
        )

        let data = try JSONEncoder().encode(payload)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let volObj = try #require(object["volumeEstimate"] as? [String: Any])
        let qualityObj = try #require(object["quality"] as? [String: Any])

        #expect(volObj["volumeMilliliters"] as? Double == 200)
        #expect(volObj["method"] as? String == "single_frame_depth_mask_v1")
        #expect(qualityObj["depthContributedToEstimate"] as? Bool == true)
        let encoded = String(decoding: data, as: UTF8.self)
        #expect(encoded.contains("rawDepth") == false)
        #expect(encoded.contains("depthMap") == false)
    }

    // MARK: - Phase 4: Multi-frame fusion (pure-Swift, no ARKit objects)

    @Test func phase4FusionMedianIsRobustToOutlier() {
        // Five estimates: 100, 200, 210, 220, 500 mL — median should be 210.
        let estimates = [100.0, 200.0, 210.0, 220.0, 500.0].map { ml in
            MealVolumeEstimate(
                volumeMilliliters: ml,
                method: "single_frame_depth_mask_v1",
                supportPlaneConfidence: 0.75,
                coverage: 0.65,
                uncertaintyMlLow: ml * 0.8,
                uncertaintyMlHigh: ml * 1.2
            )
        }

        let result = MealScanFrameAccumulator.fusedResult(from: estimates)

        let estimate = result.estimate
        #expect(estimate != nil)
        #expect(estimate?.volumeMilliliters == 210.0)
        #expect(estimate?.method == "multi_frame_depth_mask_v1")
        #expect(estimate?.frameCount == 5)
        #expect(result.relativeStdDev > 0)
    }

    @Test func phase4FusionUncertaintyExpandsWithHighVariance() {
        // Two estimates far apart: 100 mL and 400 mL — relative stdDev should be high.
        let estimates = [
            MealVolumeEstimate(
                volumeMilliliters: 100,
                method: "single_frame_depth_mask_v1",
                supportPlaneConfidence: 0.7,
                coverage: 0.6,
                uncertaintyMlLow: 80,
                uncertaintyMlHigh: 125
            ),
            MealVolumeEstimate(
                volumeMilliliters: 400,
                method: "single_frame_depth_mask_v1",
                supportPlaneConfidence: 0.7,
                coverage: 0.6,
                uncertaintyMlLow: 320,
                uncertaintyMlHigh: 500
            )
        ]

        let result = MealScanFrameAccumulator.fusedResult(from: estimates)

        let estimate = result.estimate
        #expect(estimate != nil)
        #expect(estimate?.volumeMilliliters == 250)
        #expect(result.relativeStdDev > 0.35, "High inter-frame variance should produce relativeStdDev > 0.35")
        // Uncertainty range should be wider than a typical single-frame estimate.
        if let e = estimate {
            let relRange = (e.uncertaintyMlHigh - e.uncertaintyMlLow) / e.volumeMilliliters
            #expect(relRange > 0.30, "Fused uncertainty range should be wider when frames diverge")
        }
    }

    @Test func phase4FusionUsesTrueMedianForEvenFrameCounts() {
        let estimates = [100.0, 200.0, 300.0, 400.0].map { ml in
            MealVolumeEstimate(
                volumeMilliliters: ml,
                method: "single_frame_depth_mask_v1",
                supportPlaneConfidence: 0.85,
                coverage: 0.82,
                uncertaintyMlLow: ml * 0.85,
                uncertaintyMlHigh: ml * 1.15
            )
        }

        let result = MealScanFrameAccumulator.fusedResult(from: estimates)

        #expect(result.estimate?.volumeMilliliters == 250)
        #expect(result.estimate?.frameCount == 4)
    }

    @Test func phase4FusionReturnsNilForEmptyInput() {
        let result = MealScanFrameAccumulator.fusedResult(from: [])
        #expect(result.estimate == nil)
        #expect(result.relativeStdDev == 0)
    }

    @Test func phase4FusionPassesThroughSingleEstimate() {
        let single = MealVolumeEstimate(
            volumeMilliliters: 250,
            method: "single_frame_depth_mask_v1",
            supportPlaneConfidence: 0.82,
            coverage: 0.71,
            uncertaintyMlLow: 195,
            uncertaintyMlHigh: 310
        )
        let result = MealScanFrameAccumulator.fusedResult(from: [single])

        let estimate = result.estimate
        #expect(estimate != nil)
        #expect(estimate?.volumeMilliliters == 250)
        #expect(estimate?.frameCount == 1)
        #expect(result.relativeStdDev == 0)
    }

    @Test func phase4FusionIgnoresZeroVolumeEstimates() {
        let estimates = [
            MealVolumeEstimate(
                volumeMilliliters: 0,    // invalid — should be filtered
                method: "single_frame_depth_mask_v1",
                supportPlaneConfidence: 0.5,
                coverage: 0.3,
                uncertaintyMlLow: 0,
                uncertaintyMlHigh: 0
            ),
            MealVolumeEstimate(
                volumeMilliliters: 175,
                method: "single_frame_depth_mask_v1",
                supportPlaneConfidence: 0.78,
                coverage: 0.68,
                uncertaintyMlLow: 135,
                uncertaintyMlHigh: 215
            )
        ]

        let result = MealScanFrameAccumulator.fusedResult(from: estimates)
        #expect(result.estimate?.volumeMilliliters == 175)
        #expect(result.estimate?.frameCount == 1)
    }

    @Test func phase4FusionLowCoverageExpandsUncertainty() throws {
        let highQualityEstimates = [198.0, 200.0, 202.0].map { ml in
            MealVolumeEstimate(
                volumeMilliliters: ml,
                method: "single_frame_depth_mask_v1",
                supportPlaneConfidence: 0.90,
                coverage: 0.88,
                uncertaintyMlLow: ml * 0.86,
                uncertaintyMlHigh: ml * 1.14
            )
        }
        let lowQualityEstimates = [198.0, 200.0, 202.0].map { ml in
            MealVolumeEstimate(
                volumeMilliliters: ml,
                method: "single_frame_depth_mask_v1",
                supportPlaneConfidence: 0.45,
                coverage: 0.22,
                uncertaintyMlLow: ml * 0.86,
                uncertaintyMlHigh: ml * 1.14
            )
        }

        let highQuality = try #require(MealScanFrameAccumulator.fusedResult(from: highQualityEstimates).estimate)
        let lowQuality = try #require(MealScanFrameAccumulator.fusedResult(from: lowQualityEstimates).estimate)
        let highRelativeRange = (highQuality.uncertaintyMlHigh - highQuality.uncertaintyMlLow) / highQuality.volumeMilliliters
        let lowRelativeRange = (lowQuality.uncertaintyMlHigh - lowQuality.uncertaintyMlLow) / lowQuality.volumeMilliliters

        #expect(lowQuality.coverage < highQuality.coverage)
        #expect(lowRelativeRange > highRelativeRange + 0.20)
    }

    @Test func phase4ScanQualityWarningsCoverUnstableLowLightLowCoverage() {
        var warnings: [String] = []
        let depthStats = MealScanDepthStats(
            source: .smoothedSceneDepth,
            width: 256,
            height: 192,
            validSampleCount: 140,
            sampledPixelCount: 400,
            minMeters: 0.28,
            maxMeters: 0.96,
            meanMeters: 0.52,
            percentile10Meters: 0.34,
            percentile50Meters: 0.50,
            percentile90Meters: 0.78,
            highConfidenceRatio: 0.18
        )
        let volumeEstimate = MealVolumeEstimate(
            volumeMilliliters: 210,
            method: "multi_frame_depth_mask_v1",
            supportPlaneConfidence: 0.42,
            coverage: 0.31,
            uncertaintyMlLow: 130,
            uncertaintyMlHigh: 315,
            frameCount: 3
        )
        let scanSession = MealScanSessionSummary(
            photoCaptured: true,
            depthScanCompleted: true,
            coverageRatio: 0.28,
            coveredCellRatio: 0.20,
            depthFrameCount: 3,
            stableFrameCount: 2,
            coverageGridColumns: 7,
            coverageGridRows: 5
        )

        MealScanProcessingService.appendVolumeWarnings(
            to: &warnings,
            frame: nil,
            scanMode: .depthAssisted,
            depthStats: depthStats,
            volumeEstimate: volumeEstimate,
            volumeRelativeStdDev: 0.42,
            lightingEstimate: 0.18,
            scanSession: scanSession
        )

        #expect(warnings.contains { $0.contains("varied significantly") })
        #expect(warnings.contains { $0.contains("coverage was limited") })
        #expect(warnings.contains { $0.contains("Lighting was low") })
        #expect(warnings.contains { $0.contains("Too few LiDAR viewpoints") })
        #expect(warnings.contains { $0.contains("transparent or reflective") })
    }

    @Test func phase4FusionStableEstimatesProduceLowRelativeStdDev() {
        // Three estimates very close together → low variance → tight uncertainty.
        let estimates = [198.0, 200.0, 202.0].map { ml in
            MealVolumeEstimate(
                volumeMilliliters: ml,
                method: "single_frame_depth_mask_v1",
                supportPlaneConfidence: 0.80,
                coverage: 0.70,
                uncertaintyMlLow: ml * 0.82,
                uncertaintyMlHigh: ml * 1.18
            )
        }

        let result = MealScanFrameAccumulator.fusedResult(from: estimates)

        let estimate = result.estimate
        #expect(estimate != nil)
        #expect(result.relativeStdDev < 0.05, "Stable estimates should produce relativeStdDev < 5%")
        #expect(estimate?.frameCount == 3)
        #expect(estimate?.method == "multi_frame_depth_mask_v1")
    }

    @Test func phase4VolumeEstimateFrameCountEncodesDecode() throws {
        let original = MealVolumeEstimate(
            volumeMilliliters: 220,
            method: "multi_frame_depth_mask_v1",
            supportPlaneConfidence: 0.79,
            coverage: 0.68,
            uncertaintyMlLow: 170,
            uncertaintyMlHigh: 280,
            frameCount: 5
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MealVolumeEstimate.self, from: data)

        #expect(decoded.frameCount == 5)
        #expect(decoded.method == "multi_frame_depth_mask_v1")
    }

    @Test func phase4VolumeEstimateFrameCountNilDecodesFromOldPayload() throws {
        // Old payload without frameCount field — should decode to nil frameCount.
        let json = """
        {
          "volumeMilliliters": 185.0,
          "method": "single_frame_depth_mask_v1",
          "supportPlaneConfidence": 0.72,
          "coverage": 0.61,
          "uncertaintyMlLow": 145.0,
          "uncertaintyMlHigh": 235.0
        }
        """
        let decoded = try JSONDecoder().decode(
            MealVolumeEstimate.self,
            from: try #require(json.data(using: .utf8))
        )
        #expect(decoded.frameCount == nil, "Old payloads without frameCount should decode to nil")
        #expect(decoded.volumeMilliliters == 185.0)
    }

    // MARK: - Phase 5: Food density & calibration

    @Test func phase5FoodFormClassifiesRiceAsLooseGrains() {
        #expect(MealScanFoodForm.classify(from: "Cooked white rice") == .looseGrains)
        #expect(MealScanFoodForm.classify(from: "Quinoa bowl") == .looseGrains)
    }

    @Test func phase5FoodFormClassifiesChickenAsSolidProtein() {
        #expect(MealScanFoodForm.classify(from: "Grilled chicken breast") == .solidProtein)
        #expect(MealScanFoodForm.classify(from: "Scrambled egg") == .solidProtein)
        #expect(MealScanFoodForm.classify(from: "Salmon fillet") == .solidProtein)
    }

    @Test func phase5FoodFormClassifiesMixedForUnknown() {
        #expect(MealScanFoodForm.classify(from: "Unknown mystery food") == .mixed)
        #expect(MealScanFoodForm.classify(from: "Appetizer platter") == .mixed)
    }

    @Test func phase5FoodFormClassifiesLeafyGreenAsChoppedVeg() {
        #expect(MealScanFoodForm.classify(from: "Mixed salad greens") == .choppedVeg)
        #expect(MealScanFoodForm.classify(from: "Baby spinach") == .choppedVeg)
    }

    @Test func phase5CalibrationFactorBoundsAreClamped() {
        let store = MealScanCalibrationStore()
        store.reset()

        // A ratio of 3.0 (300% of estimated) should be clamped to factorMax = 1.7.
        store.record(estimatedGrams: 100, measuredGrams: 300, foodForm: .looseGrains)
        let factor = store.factors[MealScanFoodForm.looseGrains.rawValue]
        #expect(factor != nil)
        #expect((factor ?? 0) <= MealScanCalibrationStore.factorMax + 0.001,
                "Factor must not exceed factorMax even for extreme measurements")

        // A ratio of 0.1 (10% of estimated) should be clamped to factorMin = 0.6.
        store.reset()
        store.record(estimatedGrams: 100, measuredGrams: 10, foodForm: .looseGrains)
        let factorLow = store.factors[MealScanFoodForm.looseGrains.rawValue]
        #expect((factorLow ?? 1) >= MealScanCalibrationStore.factorMin - 0.001,
                "Factor must not go below factorMin even for extreme measurements")
    }

    @Test func phase5CalibrationEMAConvergesOverMultipleScans() {
        let store = MealScanCalibrationStore()
        store.reset()

        // Record a consistent 1.2x ratio several times; EMA should approach 1.2.
        for _ in 0..<8 {
            store.record(estimatedGrams: 100, measuredGrams: 120, foodForm: .pasta)
        }
        let factor = store.factors[MealScanFoodForm.pasta.rawValue] ?? 1.0
        #expect(factor > 1.15, "EMA should converge toward the measured ratio after several scans")
        #expect(factor < 1.25, "EMA should stay near the true ratio without overshooting")
    }

    @Test func phase5CalibrationIgnoresZeroOrNegativeGrams() {
        let store = MealScanCalibrationStore()
        store.reset()
        store.record(estimatedGrams: 0, measuredGrams: 120, foodForm: .pasta)
        store.record(estimatedGrams: 100, measuredGrams: 0, foodForm: .pasta)
        store.record(estimatedGrams: -5, measuredGrams: 80, foodForm: .pasta)
        #expect(store.factors[MealScanFoodForm.pasta.rawValue] == nil,
                "Zero or negative gram inputs must be silently ignored")
    }

    @Test func phase5NonNeutralFactorsExcludesNearUnityValues() {
        let store = MealScanCalibrationStore()
        store.reset()
        // Record very close to 1.0 — should not appear in nonNeutralFactors.
        store.record(estimatedGrams: 100, measuredGrams: 101, foodForm: .denseVeg)
        // After EMA with alpha=0.65: factor = 0.65*1.0 + 0.35*1.01 = 1.0035, within neutralThreshold.
        let nonNeutral = store.nonNeutralFactors
        // The factor may or may not appear depending on EMA convergence; what matters is that
        // truly neutral factors (ratio ≈ 1.0) eventually converge out of nonNeutralFactors.
        for (_, value) in nonNeutral {
            #expect(abs(value - 1.0) > MealScanCalibrationStore.neutralThreshold,
                    "nonNeutralFactors must only contain factors meaningfully different from 1.0")
        }
    }

    @Test func phase5CalibrationFactorsRoundTripCodable() throws {
        let factors: [String: Double] = ["loose_grains": 1.15, "solid_protein": 0.88]
        let payload = MealScanCapturePayload(
            metadata: MealScanCaptureMetadata(
                mode: .depthAssisted,
                imageWidth: 1920,
                imageHeight: 1440,
                imageOrientation: "up"
            ),
            quality: MealScanQuality(level: .good, confidence: 0.72),
            calibrationFactors: factors
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(payload)
        let decoded = try decoder.decode(MealScanCapturePayload.self, from: data)
        #expect(decoded.calibrationFactors?["loose_grains"] != nil,
                "calibrationFactors should survive encode/decode round-trip")
        #expect(abs((decoded.calibrationFactors?["loose_grains"] ?? 0) - 1.15) < 0.001)
        #expect(abs((decoded.calibrationFactors?["solid_protein"] ?? 0) - 0.88) < 0.001)
    }

    @Test func phase5CalibrationFactorsNilWhenEmpty() throws {
        let payload = MealScanCapturePayload(
            metadata: MealScanCaptureMetadata(
                mode: .depthAssisted,
                imageWidth: 1920,
                imageHeight: 1440,
                imageOrientation: "up"
            ),
            quality: MealScanQuality(level: .good, confidence: 0.72),
            calibrationFactors: [:]
        )
        #expect(payload.calibrationFactors == nil,
                "Empty calibrationFactors dict must be normalized to nil to keep payload compact")
    }

    @Test func phase5CalibrationFactorsNeutralValuesStrippedFromPayload() throws {
        // A factor of 1.01 is within the 0.03 neutral threshold — should be stripped.
        let payload = MealScanCapturePayload(
            metadata: MealScanCaptureMetadata(
                mode: .depthAssisted,
                imageWidth: 1920,
                imageHeight: 1440,
                imageOrientation: "up"
            ),
            quality: MealScanQuality(level: .good, confidence: 0.72),
            calibrationFactors: ["loose_grains": 1.01, "solid_protein": 1.30]
        )
        // Only solid_protein (1.30) is beyond the threshold; loose_grains (1.01) should be stripped.
        #expect(payload.calibrationFactors?["loose_grains"] == nil,
                "Near-unity factors must be stripped from the payload")
        #expect(payload.calibrationFactors?["solid_protein"] != nil,
                "Non-neutral factors must be preserved in the payload")
    }

    private func assertHTTPStatusThrowsRetryableBackendError(_ statusCode: Int) async throws {
        let baseURL = try #require(URL(string: "https://meal.example.test"))
        let configuration = MealScannerConfiguration(
            backendBaseURL: baseURL,
            analysisPath: "/api/orion/meal-scan"
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MealScannerURLProtocol.self]
        let recorder = MealScannerRequestRecorder(
            statusCode: statusCode,
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

        do {
            _ = try await service.analyzeMeal(imageBase64: "image", payload: payload)
            Issue.record("Expected HTTP \(statusCode) to surface as a retryable backend error.")
        } catch let error as MealNutritionAIServiceError {
            guard case .http(let receivedStatusCode, let message) = error else {
                Issue.record("Expected HTTP error for status \(statusCode), got \(error).")
                return
            }
            #expect(receivedStatusCode == statusCode)
            #expect(message.contains("backend is unavailable"))
            #expect(message.contains("No foods were inferred locally"))
        } catch {
            Issue.record("Expected MealNutritionAIServiceError.http for status \(statusCode), got \(error).")
        }

        #expect(recorder.paths == ["/api/orion/meal-scan"])
    }

    private static func saveToNutritionButtonIsEnabled(for result: MealScanResult, hasSaved: Bool = false) -> Bool {
        !hasSaved && result.hasSavableMealScannerIngredients
    }

    // MARK: - Phase 3: resolve-ingredient client

    @Test func mealScannerConfigurationBuildsResolveEndpointAlongsideAnalysisEndpoint() throws {
        let baseURL = try #require(URL(string: "https://www.aetherial.tech"))
        let configuration = MealScannerConfiguration(backendBaseURL: baseURL)

        #expect(configuration.resolveEndpoint?.absoluteString == "https://www.aetherial.tech/api/orion/meal-scan/resolve-ingredient")
    }

    @Test func resolveIngredientPostsToResolveEndpointAndDecodesRecalculatedNutrition() async throws {
        let baseURL = try #require(URL(string: "https://meal.example.test"))
        let configuration = MealScannerConfiguration(backendBaseURL: baseURL)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MealScannerURLProtocol.self]
        let recorder = MealScannerRequestRecorder(
            statusCode: 200,
            body: Data("""
            {
              "id": "resp_resolve_1",
              "updatedIngredient": {
                "name": "Grilled chicken",
                "grams": 120,
                "densityUsed": 1.0,
                "gramsLow": 102,
                "gramsHigh": 138,
                "nutrition": {
                  "calories": 198,
                  "proteinGrams": 37,
                  "carbohydrateGrams": 0,
                  "fatGrams": 4.3,
                  "fiberGrams": 0,
                  "sugarGrams": 0,
                  "sodiumMilligrams": 88
                },
                "micronutrients": [],
                "confidence": 0.81
              },
              "updatedMealTotals": {
                "calories": 198,
                "proteinGrams": 37,
                "carbohydrateGrams": 0,
                "fatGrams": 4.3,
                "fiberGrams": 0,
                "sugarGrams": 0,
                "sodiumMilligrams": 88
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
        let request = MealIngredientResolveRequest(
            ingredientId: UUID().uuidString,
            originalName: "unknown protein, chopped",
            replacementName: "Grilled chicken",
            grams: 120,
            ambiguityType: MealIngredientAmbiguityType.protein.rawValue
        )

        let response = try await service.resolveIngredient(request)

        #expect(recorder.paths == ["/api/orion/meal-scan/resolve-ingredient"])
        #expect(response.updatedIngredient.name == "Grilled chicken")
        #expect(response.updatedIngredient.calories == 198)
        #expect(response.updatedIngredient.protein == 37)
        #expect(response.updatedMealTotals?.calories == 198)
    }

    @Test func resolveIngredientHTTPFailureThrowsRetryableError() async throws {
        let baseURL = try #require(URL(string: "https://meal.example.test"))
        let configuration = MealScannerConfiguration(backendBaseURL: baseURL)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [MealScannerURLProtocol.self]
        let recorder = MealScannerRequestRecorder(
            statusCode: 502,
            body: Data(#"{"message":"OpenAI request failed."}"#.utf8)
        )
        MealScannerURLProtocol.register(recorder)
        defer { MealScannerURLProtocol.unregister(recorder) }

        let service = MealNutritionAIService(
            configuration: configuration,
            session: URLSession(configuration: sessionConfiguration)
        )
        let request = MealIngredientResolveRequest(
            ingredientId: UUID().uuidString,
            originalName: "unknown protein, chopped",
            replacementName: "Tofu",
            grams: 90,
            ambiguityType: MealIngredientAmbiguityType.protein.rawValue
        )

        do {
            _ = try await service.resolveIngredient(request)
            Issue.record("Expected an HTTP failure to throw.")
        } catch let error as MealNutritionAIServiceError {
            guard case .http(let statusCode, let message) = error else {
                Issue.record("Expected .http error, got \(error).")
                return
            }
            #expect(statusCode == 502)
            #expect(message.contains("OpenAI request failed."))
        }
    }

    @Test func resolveIngredientNotConfiguredThrowsWhenBackendBaseURLMissing() async throws {
        let configuration = MealScannerConfiguration()
        let service = MealNutritionAIService(configuration: configuration)
        let request = MealIngredientResolveRequest(
            ingredientId: UUID().uuidString,
            originalName: "unknown protein, chopped",
            replacementName: "Tofu",
            grams: 90,
            ambiguityType: MealIngredientAmbiguityType.protein.rawValue
        )

        do {
            _ = try await service.resolveIngredient(request)
            Issue.record("Expected notConfigured to throw when no backend base URL is set.")
        } catch let error as MealNutritionAIServiceError {
            guard case .notConfigured = error else {
                Issue.record("Expected .notConfigured error, got \(error).")
                return
            }
        }
    }

    @Test func mergingRecalculatedNutritionScalesToActualGramsAndClearsPendingFlag() {
        let ingredient = MealIngredient(
            name: "unknown protein, chopped",
            grams: 90,
            nutrition: MealNutritionTotals(calories: 150, proteinGrams: 20, fatGrams: 8),
            confidence: 0.4
        )
        .resolvingAmbiguity(as: "Grilled chicken")

        let backendResolved = MealIngredient(
            name: "Grilled chicken",
            grams: 120,
            nutrition: MealNutritionTotals(calories: 198, proteinGrams: 37, fatGrams: 4.3),
            confidence: 0.81
        )

        let merged = ingredient.mergingRecalculatedNutrition(from: backendResolved)

        #expect(merged.name == "Grilled chicken")
        #expect(merged.originalName == "unknown protein, chopped")
        #expect(merged.estimatedGrams == 90, "Backend nutrition must scale to the scan's actual grams, not overwrite them")
        #expect(abs(merged.calories - 148.5) < 0.001)
        #expect(abs(merged.protein - 27.75) < 0.001)
        #expect(merged.nutritionNeedsRecalculation == false)
        #expect(merged.confidence == 0.81)
    }

    @Test func mockResolveResponseIsClearlyLabeledAndMatchesRequestedGrams() {
        let request = MealIngredientResolveRequest(
            ingredientId: UUID().uuidString,
            originalName: "unknown protein, chopped",
            replacementName: "Tofu",
            grams: 100,
            ambiguityType: MealIngredientAmbiguityType.protein.rawValue
        )

        let response = MealNutritionAIService.mockResolveResponse(for: request)

        #expect(response.updatedIngredient.name == "Tofu")
        #expect(response.updatedIngredient.grams == 100)
        #expect(response.updatedIngredient.notes?.contains("Demo-only") == true)
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
