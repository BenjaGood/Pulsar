//
//  OrionIntegrationTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

@MainActor
struct OrionIntegrationTests {
    @Test func configurationBuildsBackendChatEndpointWithoutSecrets() throws {
        let baseURL = try #require(URL(string: "http://127.0.0.1:8788/api"))
        let configuration = OrionConfiguration(
            backendBaseURL: baseURL,
            chatPath: "/orion/chat"
        )

        #expect(configuration.chatEndpoint?.absoluteString == "http://127.0.0.1:8788/api/orion/chat")
        #expect(configuration.isConfigured)
        #expect(configuration.missingConfigurationKeys().isEmpty)
    }

    @Test func hostedConfigurationUsesAetherialOrionAPI() throws {
        let baseURL = try #require(URL(string: "https://www.aetherial.tech"))
        let configuration = OrionConfiguration(
            backendBaseURL: baseURL,
            chatPath: "/api/orion/chat"
        )

        #expect(configuration.chatEndpoint?.absoluteString == "https://www.aetherial.tech/api/orion/chat")
        #expect(configuration.isConfigured)
        #expect(configuration.missingConfigurationKeys().isEmpty)
    }

    @Test func unconfiguredServiceFailsBeforeNetworkRequest() async throws {
        let service = OrionService(configuration: .notConfigured)

        do {
            _ = try await service.sendMessage(
                "How recovered am I?",
                history: [],
                context: .testFixture
            )
            Issue.record("Expected Orion to require a backend endpoint")
        } catch let error as OrionServiceError {
            if case .notConfigured(let keys) = error {
                #expect(keys == ["OrionBackendBaseURL"])
            } else {
                Issue.record("Expected notConfigured, received \(error)")
            }
        }
    }

    @Test func mockModeReturnsAssistantMessageWithoutBackend() async throws {
        let service = OrionService(configuration: OrionConfiguration(mockMode: true))

        let response = try await service.sendMessage(
            "What should I focus on today?",
            history: [],
            context: .testFixture
        )

        #expect(response.role == .assistant)
        #expect(response.content.contains("Orion mock mode is on"))
    }
}

private extension OrionUserContext {
    static let testFixture = OrionUserContext(
        generatedAt: Date(timeIntervalSinceReferenceDate: 42_000),
        questionFocus: ["recovery"],
        todayWorkoutSummary: OrionWorkoutDayContext(
            date: Date(timeIntervalSinceReferenceDate: 42_000),
            strainScore: 42,
            steps: 7_200,
            stepGoal: 10_000,
            activeEnergyKilocalories: 520,
            exerciseMinutes: 38,
            workoutMinutes: 32,
            workoutCount: 1,
            summary: "Fixture activity summary."
        ),
        recentWorkouts: [],
        nutritionSummary: OrionNutritionSummary(
            date: Date(timeIntervalSinceReferenceDate: 42_000),
            calories: 1_200,
            calorieGoal: 2_400,
            proteinGrams: 92,
            proteinGoalGrams: 130,
            carbohydratesGrams: 140,
            fatGrams: 42,
            fiberGrams: 18,
            hydrationMilliliters: 1_600,
            hydrationGoalMilliliters: 2_800,
            insightCount: 2,
            summary: "Fixture nutrition summary."
        ),
        recoverySummary: OrionRecoveryContext(
            date: Date(timeIntervalSinceReferenceDate: 42_000),
            score: 78,
            status: "Balanced recovery",
            confidence: "High",
            hrvMilliseconds: 58,
            restingHeartRateBPM: 51,
            respiratoryRate: 14.2,
            explanation: "Fixture recovery summary."
        ),
        sleepSummary: OrionSleepContext(
            wakeUpDate: Date(timeIntervalSinceReferenceDate: 42_000),
            score: 84,
            confidence: "High",
            totalSleepMinutes: 455,
            sleepEfficiencyPercent: 91,
            awakenings: 2,
            sleepStart: nil,
            wakeTime: nil,
            summary: "Fixture sleep summary."
        ),
        userGoals: OrionUserGoals(
            trainingLevel: "Intermediate",
            preferredUnits: "Metric",
            sleepGoalMinutes: 480,
            sleepGoalDays: "Every day",
            preferredDataSource: "Auto",
            primarySleepSource: "Auto",
            nutritionCalorieRange: "2200-2600 kcal",
            nutritionProteinRange: "130-160 g"
        ),
        notes: ["Fixture context is summarized."]
    )
}
