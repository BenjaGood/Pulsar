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

    @Test func conversationFileStorePersistsLocalHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("orion-history-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let createdAt = Date(timeIntervalSinceReferenceDate: 10_000)
        let updatedAt = Date(timeIntervalSinceReferenceDate: 11_000)
        let conversation = OrionConversation(
            createdAt: createdAt,
            updatedAt: updatedAt,
            title: "Recovery check",
            messages: [
                OrionMessage(role: .user, content: "How recovered am I?", createdAt: createdAt),
                OrionMessage(role: .assistant, content: "You look ready for controlled aerobic work.", createdAt: updatedAt)
            ],
            previewSummary: "Ready for controlled aerobic work.",
            thumbnailSystemName: "heart.text.square.fill"
        )

        let writer = OrionConversationFileStore(directoryURL: directory)
        try writer.saveConversations([conversation])

        let reader = OrionConversationFileStore(directoryURL: directory)
        let loaded = reader.loadConversations()

        #expect(loaded.count == 1)
        #expect(loaded.first?.id == conversation.id)
        #expect(loaded.first?.title == "Recovery check")
        #expect(loaded.first?.messages.count == 2)
    }

    @Test func conversationFileStoreFallsBackToFirstMessageDateWhenCreationDateIsMissing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("orion-history-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let startedAt = Date(timeIntervalSinceReferenceDate: 30_000)
        let updatedAt = Date(timeIntervalSinceReferenceDate: 31_000)
        let dateFormatter = ISO8601DateFormatter()
        let conversationID = UUID()
        let promptID = UUID()
        let replyID = UUID()
        let legacyJSON = """
        {
          "version": 1,
          "conversations": [
            {
              "id": "\(conversationID.uuidString)",
              "updatedAt": "\(dateFormatter.string(from: updatedAt))",
              "title": "Legacy recovery check",
              "messages": [
                {
                  "id": "\(promptID.uuidString)",
                  "role": "user",
                  "content": "How did I sleep?",
                  "createdAt": "\(dateFormatter.string(from: startedAt))"
                },
                {
                  "id": "\(replyID.uuidString)",
                  "role": "assistant",
                  "content": "Your sleep looked steady.",
                  "createdAt": "\(dateFormatter.string(from: updatedAt))"
                }
              ],
              "previewSummary": "Your sleep looked steady.",
              "thumbnailSystemName": "moon.zzz.fill"
            }
          ]
        }
        """
        let fileURL = directory.appendingPathComponent("orion-conversations-v1.json")
        try #require(legacyJSON.data(using: .utf8)).write(to: fileURL)

        let loaded = OrionConversationFileStore(directoryURL: directory).loadConversations()
        let conversation = try #require(loaded.first)

        #expect(conversation.id == conversationID)
        #expect(conversation.createdAt == startedAt)
        #expect(conversation.startedAt == startedAt)
        #expect(conversation.updatedAt == updatedAt)
        #expect(conversation.messages.count == 2)
    }

    @Test func viewModelStartsFreshWithoutReopeningLoadedHistory() throws {
        let createdAt = Date(timeIntervalSinceReferenceDate: 20_000)
        let updatedAt = Date(timeIntervalSinceReferenceDate: 21_000)
        let previousConversation = OrionConversation(
            createdAt: createdAt,
            updatedAt: updatedAt,
            title: "Recovery check",
            messages: [
                OrionMessage(role: .user, content: "How is recovery today?", createdAt: createdAt),
                OrionMessage(role: .assistant, content: "Recovery looks balanced.", createdAt: updatedAt)
            ],
            previewSummary: "Recovery looks balanced.",
            thumbnailSystemName: "heart.text.square.fill"
        )
        let store = OrionMemoryConversationStore(loadedConversations: [previousConversation])
        let viewModel = OrionChatViewModel(
            service: OrionImmediateReplyService(),
            contextProvider: OrionStaticContextProvider(),
            conversationStore: store
        )

        #expect(viewModel.conversations.map(\.id) == [previousConversation.id])
        #expect(viewModel.conversations(matching: "").map(\.id) == [previousConversation.id])
        #expect(viewModel.activeConversation.id != previousConversation.id)
        #expect(!viewModel.activeConversation.hasUserMessages)
        #expect(viewModel.messages.count == 1)
        #expect(store.savedConversations.isEmpty)

        viewModel.selectConversation(previousConversation)

        #expect(viewModel.activeConversation.id == previousConversation.id)
        #expect(viewModel.messages == previousConversation.messages)
        #expect(store.savedConversations.isEmpty)

        viewModel.startNewConversation()

        #expect(viewModel.activeConversation.id != previousConversation.id)
        #expect(!viewModel.activeConversation.hasUserMessages)
        #expect(viewModel.messages.count == 1)
        #expect(viewModel.conversations.map(\.id) == [previousConversation.id])
        #expect(store.savedConversations.isEmpty)
    }

    @Test func viewModelSavesMessagesAndKeepsPreviousChatsSearchable() async throws {
        let store = OrionMemoryConversationStore()
        let viewModel = OrionChatViewModel(
            service: OrionImmediateReplyService(),
            contextProvider: OrionStaticContextProvider(),
            conversationStore: store
        )

        viewModel.draft = "How is recovery today?"
        viewModel.sendCurrentMessage()
        try await waitFor {
            !viewModel.isSending && viewModel.messages.count == 3
        }

        #expect(store.savedConversations.count == 1)
        #expect(store.savedConversations.first?.messages.count == 3)
        #expect(viewModel.conversations(matching: "recovery").count == 1)

        let firstConversationID = viewModel.activeConversation.id
        viewModel.startNewConversation()

        #expect(viewModel.activeConversation.id != firstConversationID)
        #expect(viewModel.conversations.count == 1)
        #expect(store.savedConversations.count == 1)
        #expect(viewModel.messages.count == 1)
        #expect(viewModel.conversations(matching: "balanced").count == 1)
    }

    @Test func openAIHistoryIsIsolatedToTheActiveConversation() async throws {
        let service = OrionRecordingReplyService()
        let store = OrionMemoryConversationStore()
        let viewModel = OrionChatViewModel(
            service: service,
            contextProvider: OrionStaticContextProvider(),
            conversationStore: store
        )

        viewModel.draft = "How is recovery today?"
        viewModel.sendCurrentMessage()
        try await waitFor {
            !viewModel.isSending && viewModel.messages.count == 3
        }

        let firstConversationID = viewModel.activeConversation.id
        let firstConversation = try #require(viewModel.conversations.first { $0.id == firstConversationID })

        viewModel.startNewConversation()
        viewModel.draft = "How much protein tonight?"
        viewModel.sendCurrentMessage()
        try await waitFor {
            !viewModel.isSending && viewModel.messages.count == 3
        }

        let secondConversationID = viewModel.activeConversation.id
        #expect(secondConversationID != firstConversationID)

        viewModel.selectConversation(firstConversation)
        viewModel.draft = "What about tomorrow?"
        viewModel.sendCurrentMessage()
        try await waitFor {
            !viewModel.isSending && viewModel.messages.count == 5
        }

        let requests = service.recordedRequests()
        #expect(requests.count == 3)

        let freshSecondHistory = requests[1].history.map(\.content).joined(separator: " ")
        #expect(!freshSecondHistory.contains("How is recovery today?"))
        #expect(!freshSecondHistory.contains("Recovery looks balanced"))

        let selectedHistory = requests[2].history.map(\.content).joined(separator: " ")
        #expect(selectedHistory.contains("How is recovery today?"))
        #expect(!selectedHistory.contains("How much protein tonight?"))
        #expect(viewModel.conversations.count == 2)
    }

    @Test func audioManagerTransitionsFromStartToLoopThenCompletion() async throws {
        let playback = OrionRecordingAudioPlayback(
            thinkingStartDuration: 0.03,
            responseCompleteDuration: 5
        )
        let audioManager = OrionAudioManager(
            playback: playback,
            notificationCenter: NotificationCenter()
        )
        let viewModel = OrionChatViewModel(
            service: OrionDelayedReplyService(delayNanoseconds: 120_000_000),
            contextProvider: OrionStaticContextProvider(),
            conversationStore: OrionMemoryConversationStore()
        )
        audioManager.bind(to: viewModel)

        viewModel.draft = "How should I train today?"
        viewModel.sendCurrentMessage()

        try await waitFor {
            playback.events.contains(.thinkingStartSchedulingLoop)
        }
        #expect(viewModel.generationLifecycle.isGenerating)
        #expect(audioManager.state == .thinkingStart)

        try await waitFor {
            audioManager.state == .thinkingLoop
        }
        #expect(!playback.events.contains(.responseComplete))

        try await waitFor {
            !viewModel.isSending && playback.events.contains(.responseComplete)
        }

        #expect(audioManager.state == .responseComplete)
        #expect(playback.events.filter { $0 == .thinkingStartSchedulingLoop }.count == 1)
        #expect(playback.events.filter { $0 == .responseComplete }.count == 1)
    }

    @Test func audioManagerStopsOnCancellation() async throws {
        let playback = OrionRecordingAudioPlayback(
            thinkingStartDuration: 0.03,
            responseCompleteDuration: 5
        )
        let audioManager = OrionAudioManager(
            playback: playback,
            notificationCenter: NotificationCenter()
        )
        let viewModel = OrionChatViewModel(
            service: OrionDelayedReplyService(delayNanoseconds: 500_000_000),
            contextProvider: OrionStaticContextProvider(),
            conversationStore: OrionMemoryConversationStore()
        )
        audioManager.bind(to: viewModel)

        viewModel.draft = "Build a recovery plan."
        viewModel.sendCurrentMessage()
        try await waitFor {
            playback.events.contains(.thinkingStartSchedulingLoop)
        }

        viewModel.startNewConversation()

        try await waitFor {
            audioManager.state == .idle && playback.events.contains(.stopAll)
        }

        try await Task.sleep(nanoseconds: 80_000_000)
        #expect(!playback.events.contains(.responseComplete))
    }

    @Test func audioManagerStopsOnFailureWithoutCompletionSound() async throws {
        let playback = OrionRecordingAudioPlayback(
            thinkingStartDuration: 0.03,
            responseCompleteDuration: 5
        )
        let audioManager = OrionAudioManager(
            playback: playback,
            notificationCenter: NotificationCenter()
        )
        let viewModel = OrionChatViewModel(
            service: OrionFailingReplyService(),
            contextProvider: OrionStaticContextProvider(),
            conversationStore: OrionMemoryConversationStore()
        )
        audioManager.bind(to: viewModel)

        viewModel.draft = "What is my readiness?"
        viewModel.sendCurrentMessage()

        try await waitFor {
            !viewModel.isSending && viewModel.errorMessage != nil
        }

        #expect(audioManager.state == .idle)
        #expect(playback.events.contains(.stopAll))
        #expect(!playback.events.contains(.responseComplete))
    }

    @Test func audioManagerResumesLoopOnlyWhileGenerationRemainsActiveAfterForegrounding() async throws {
        let playback = OrionRecordingAudioPlayback(
            thinkingStartDuration: 0.03,
            responseCompleteDuration: 5
        )
        let audioManager = OrionAudioManager(
            playback: playback,
            notificationCenter: NotificationCenter()
        )
        let viewModel = OrionChatViewModel(
            service: OrionDelayedReplyService(delayNanoseconds: 400_000_000),
            contextProvider: OrionStaticContextProvider(),
            conversationStore: OrionMemoryConversationStore()
        )
        audioManager.bind(to: viewModel)

        viewModel.draft = "Keep working while I switch apps."
        viewModel.sendCurrentMessage()
        try await waitFor {
            playback.events.contains(.thinkingStartSchedulingLoop)
        }

        audioManager.setAppIsActive(false)
        #expect(audioManager.state == .idle)
        #expect(playback.events.contains(.stopAll))

        audioManager.setAppIsActive(true)
        try await waitFor {
            audioManager.state == .thinkingLoop && playback.events.contains(.thinkingLoop)
        }

        viewModel.startNewConversation()
    }

    @Test func rapidPromptAttemptsDoNotStartDuplicateAudio() async throws {
        let playback = OrionRecordingAudioPlayback(
            thinkingStartDuration: 0.03,
            responseCompleteDuration: 5
        )
        let audioManager = OrionAudioManager(
            playback: playback,
            notificationCenter: NotificationCenter()
        )
        let viewModel = OrionChatViewModel(
            service: OrionDelayedReplyService(delayNanoseconds: 120_000_000),
            contextProvider: OrionStaticContextProvider(),
            conversationStore: OrionMemoryConversationStore()
        )
        audioManager.bind(to: viewModel)

        viewModel.draft = "First prompt"
        viewModel.sendCurrentMessage()
        viewModel.draft = "Second prompt"
        viewModel.sendCurrentMessage()

        try await waitFor {
            playback.events.contains(.thinkingStartSchedulingLoop)
        }

        #expect(viewModel.messages.filter { $0.role == .user }.map(\.content) == ["First prompt"])
        #expect(playback.events.filter { $0 == .thinkingStartSchedulingLoop }.count == 1)
    }

    private func waitFor(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutNanoseconds) / 1_000_000_000)
        while !condition() {
            try await Task.sleep(nanoseconds: 20_000_000)
            if Date() >= deadline {
                Issue.record("Timed out waiting for condition")
                return
            }
        }
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

private final class OrionMemoryConversationStore: OrionConversationPersisting {
    var loadedConversations: [OrionConversation]
    private(set) var savedConversations: [OrionConversation] = []

    init(loadedConversations: [OrionConversation] = []) {
        self.loadedConversations = loadedConversations
    }

    func loadConversations() -> [OrionConversation] {
        loadedConversations
    }

    func saveConversations(_ conversations: [OrionConversation]) throws {
        savedConversations = conversations
    }
}

private struct OrionStaticContextProvider: OrionContextProviding {
    func makeContext(for question: String) async -> OrionUserContext {
        _ = question
        return .testFixture
    }
}

private struct OrionImmediateReplyService: OrionServicing {
    func sendMessage(
        _ content: String,
        history: [OrionMessage],
        context: OrionUserContext
    ) async throws -> OrionMessage {
        _ = content
        _ = history
        _ = context
        return await MainActor.run {
            OrionMessage(role: .assistant, content: "Recovery looks balanced. Keep the next session controlled and smooth.")
        }
    }
}

@MainActor
private final class OrionRecordingReplyService: OrionServicing {
    struct Request: Sendable {
        var content: String
        var history: [OrionMessage]
        var context: OrionUserContext
    }

    private var requests: [Request] = []

    func sendMessage(
        _ content: String,
        history: [OrionMessage],
        context: OrionUserContext
    ) async throws -> OrionMessage {
        requests.append(Request(content: content, history: history, context: context))
        return await MainActor.run {
            OrionMessage(role: .assistant, content: "Reply for \(content)")
        }
    }

    func recordedRequests() -> [Request] {
        requests
    }
}

private struct OrionDelayedReplyService: OrionServicing {
    var delayNanoseconds: UInt64

    func sendMessage(
        _ content: String,
        history: [OrionMessage],
        context: OrionUserContext
    ) async throws -> OrionMessage {
        _ = history
        _ = context
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return await MainActor.run {
            OrionMessage(role: .assistant, content: "Reply for \(content)")
        }
    }
}

private struct OrionFailingReplyService: OrionServicing {
    func sendMessage(
        _ content: String,
        history: [OrionMessage],
        context: OrionUserContext
    ) async throws -> OrionMessage {
        _ = content
        _ = history
        _ = context
        throw OrionServiceError.transport("Fixture failure.")
    }
}

@MainActor
private final class OrionRecordingAudioPlayback: OrionAudioPlaybackManaging {
    enum Event: Equatable {
        case thinkingStartSchedulingLoop
        case thinkingLoop
        case responseComplete
        case stopAll
        case deactivate
    }

    let thinkingStartDuration: TimeInterval
    let responseCompleteDuration: TimeInterval
    private(set) var events: [Event] = []

    init(thinkingStartDuration: TimeInterval, responseCompleteDuration: TimeInterval) {
        self.thinkingStartDuration = thinkingStartDuration
        self.responseCompleteDuration = responseCompleteDuration
    }

    func playThinkingStartSchedulingLoop() {
        events.append(.thinkingStartSchedulingLoop)
    }

    func playThinkingLoop() {
        events.append(.thinkingLoop)
    }

    func playResponseComplete() {
        events.append(.responseComplete)
    }

    func stopAll() {
        events.append(.stopAll)
    }

    func deactivate() {
        events.append(.deactivate)
    }
}
