//
//  OrionChatViewModel.swift
//  Pulsar
//

import Combine
import Foundation

@MainActor
final class OrionChatViewModel: ObservableObject {
    @Published var messages: [OrionMessage]
    @Published var draft = ""
    @Published private(set) var conversations: [OrionConversation]
    @Published private(set) var activeConversation: OrionConversation
    @Published private(set) var generationLifecycle: OrionGenerationLifecycle = .idle
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?

    private var service: any OrionServicing
    private var contextProvider: any OrionContextProviding
    private let conversationStore: any OrionConversationPersisting
    private var sendTask: Task<Void, Never>?
    private var activeGenerationID: UUID?

    init(
        service: (any OrionServicing)? = nil,
        contextProvider: (any OrionContextProviding)? = nil,
        conversationStore: (any OrionConversationPersisting)? = nil
    ) {
        self.service = service ?? OrionService()
        self.contextProvider = contextProvider ?? OrionContextProvider()
        self.conversationStore = conversationStore ?? OrionConversationFileStore()
        let loadedConversations = self.conversationStore.loadConversations()
        let initialConversation = OrionConversation()
        self.conversations = loadedConversations
        self.activeConversation = initialConversation
        self.messages = initialConversation.messages
    }

    deinit {
        sendTask?.cancel()
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    func configure(
        service: (any OrionServicing)? = nil,
        contextProvider: (any OrionContextProviding)? = nil
    ) {
        if let service {
            self.service = service
        }
        if let contextProvider {
            self.contextProvider = contextProvider
        }
    }

    func sendCurrentMessage() {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSending else { return }

        let history = messages
        let generationID = UUID()
        draft = ""
        errorMessage = nil
        isSending = true
        activeGenerationID = generationID
        generationLifecycle = .generating(generationID)
        appendMessage(OrionMessage(role: .user, content: content))

        sendTask?.cancel()
        sendTask = Task { [weak self] in
            guard let self else { return }
            await self.send(content, history: history, generationID: generationID)
        }
    }

    func startNewConversation() {
        sendTask?.cancel()
        cancelActiveGenerationIfNeeded()
        draft = ""
        errorMessage = nil

        let conversation = OrionConversation()
        activeConversation = conversation
        messages = conversation.messages
    }

    func selectConversation(_ conversation: OrionConversation) {
        sendTask?.cancel()
        cancelActiveGenerationIfNeeded()
        draft = ""
        errorMessage = nil
        activeConversation = conversation
        messages = conversation.messages
    }

    func conversations(matching query: String) -> [OrionConversation] {
        let historyConversations = conversations.filter(\.hasUserMessages)
        let normalizedQuery = query.orionCondensedWhitespace().localizedLowercase
        guard !normalizedQuery.isEmpty else {
            return historyConversations
        }

        return historyConversations.filter { conversation in
            let searchableText = [
                conversation.displayTitle,
                conversation.previewSummary ?? "",
                conversation.previewText,
                conversation.messages.map(\.content).joined(separator: " ")
            ]
            .joined(separator: " ")
            .localizedLowercase
            return searchableText.contains(normalizedQuery)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func send(_ content: String, history: [OrionMessage], generationID: UUID) async {
        do {
            let context = await contextProvider.makeContext(for: content)
            let response = try await service.sendMessage(
                content,
                history: history,
                context: context
            )
            guard shouldFinishGeneration(generationID) else { return }
            appendMessage(response)
            await Task.yield()
            guard shouldFinishGeneration(generationID) else { return }
            finishGeneration(.completed(generationID))
        } catch is CancellationError {
            guard shouldFinishGeneration(generationID) else { return }
            finishGeneration(.cancelled(generationID))
        } catch {
            guard shouldFinishGeneration(generationID) else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            finishGeneration(.failed(generationID))
        }
    }

    private func shouldFinishGeneration(_ generationID: UUID) -> Bool {
        !Task.isCancelled && activeGenerationID == generationID
    }

    private func finishGeneration(_ lifecycle: OrionGenerationLifecycle) {
        activeGenerationID = nil
        isSending = false
        generationLifecycle = lifecycle
    }

    private func cancelActiveGenerationIfNeeded() {
        guard let generationID = activeGenerationID else {
            isSending = false
            return
        }
        activeGenerationID = nil
        isSending = false
        generationLifecycle = .cancelled(generationID)
    }

    private func appendMessage(_ message: OrionMessage) {
        messages.append(message)
        activeConversation.messages = messages
        activeConversation.updatedAt = message.createdAt
        activeConversation.title = generatedTitle(for: activeConversation)
        activeConversation.previewSummary = generatedPreview(for: activeConversation)
        activeConversation.thumbnailSystemName = generatedThumbnailSymbol(for: activeConversation)
        upsertConversation(activeConversation)
    }

    private func upsertConversation(_ conversation: OrionConversation) {
        var conversationsByID: [UUID: OrionConversation] = [:]
        for existingConversation in conversations {
            conversationsByID[existingConversation.id] = existingConversation
        }
        conversationsByID[conversation.id] = conversation
        conversations = conversationsByID.values.sorted { $0.updatedAt > $1.updatedAt }
        persistConversations()
    }

    private func persistConversations() {
        do {
            try conversationStore.saveConversations(conversations)
        } catch {
            errorMessage = "Orion could not save this chat locally: \(error.localizedDescription)"
        }
    }

    private func generatedTitle(for conversation: OrionConversation) -> String {
        if conversation.title != OrionConversation.defaultTitle,
           !conversation.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return conversation.title
        }

        guard let firstUserMessage = conversation.messages.first(where: { $0.role == .user })?.content else {
            return OrionConversation.defaultTitle
        }

        let words = firstUserMessage
            .orionCondensedWhitespace()
            .split(separator: " ")
            .prefix(6)
        let title = words.joined(separator: " ")
        return title.isEmpty ? OrionConversation.defaultTitle : title
    }

    private func generatedPreview(for conversation: OrionConversation) -> String? {
        conversation.messages
            .reversed()
            .first { $0.role != .system }?
            .content
            .orionCondensedWhitespace()
            .orionTruncated(to: 150)
    }

    private func generatedThumbnailSymbol(for conversation: OrionConversation) -> String? {
        let searchable = [
            conversation.displayTitle,
            conversation.previewSummary ?? "",
            conversation.previewText
        ]
        .joined(separator: " ")
        .localizedLowercase

        if searchable.contains("sleep") { return "moon.zzz.fill" }
        if searchable.contains("nutrition") || searchable.contains("protein") || searchable.contains("calorie") { return "fork.knife" }
        if searchable.contains("run") || searchable.contains("workout") || searchable.contains("training") { return "figure.run" }
        if searchable.contains("recovery") || searchable.contains("hrv") { return "heart.text.square.fill" }
        return nil
    }
}

#if DEBUG
extension OrionChatViewModel {
    static var preview: OrionChatViewModel {
        let now = Date(timeIntervalSinceReferenceDate: 802_000_000)
        let fixtureConversation = OrionConversation(
            createdAt: now.addingTimeInterval(-3_600),
            updatedAt: now.addingTimeInterval(-1_000),
            title: "Training plan today",
            messages: [
                OrionMessage(role: .assistant, content: "Ask me about your training, recovery, sleep, or nutrition.", createdAt: now.addingTimeInterval(-3_600)),
                OrionMessage(role: .user, content: "How should I train today?", createdAt: now.addingTimeInterval(-3_000)),
                OrionMessage(role: .assistant, content: "Your recovery is trending steady, so make today feel productive without forcing intensity. Start with a controlled warmup, then keep the main work conversational unless your legs feel unusually fresh.", createdAt: now.addingTimeInterval(-1_000))
            ],
            previewSummary: "Your recovery is steady. Keep the main work conversational unless your legs feel fresh.",
            thumbnailSystemName: "figure.run"
        )
        let nutritionConversation = OrionConversation(
            createdAt: now.addingTimeInterval(-18_000),
            updatedAt: now.addingTimeInterval(-16_000),
            title: "Protein target",
            messages: [
                OrionMessage(role: .user, content: "How much protein do I need tonight?", createdAt: now.addingTimeInterval(-18_000)),
                OrionMessage(role: .assistant, content: "You are close to target. A simple dinner with 35 to 45 grams of protein keeps the day balanced.", createdAt: now.addingTimeInterval(-16_000))
            ],
            previewSummary: "A 35 to 45 gram protein dinner keeps the day balanced.",
            thumbnailSystemName: "fork.knife"
        )
        let viewModel = OrionChatViewModel(
            service: OrionPreviewService(),
            contextProvider: OrionContextProvider(),
            conversationStore: OrionPreviewConversationStore(conversations: [fixtureConversation, nutritionConversation])
        )
        viewModel.selectConversation(fixtureConversation)
        return viewModel
    }
}

private struct OrionPreviewConversationStore: OrionConversationPersisting {
    var conversations: [OrionConversation]

    func loadConversations() -> [OrionConversation] {
        conversations
    }

    func saveConversations(_ conversations: [OrionConversation]) throws {
        _ = conversations
    }
}

private struct OrionPreviewService: OrionServicing {
    func sendMessage(
        _ content: String,
        history: [OrionMessage],
        context: OrionUserContext
    ) async throws -> OrionMessage {
        _ = history
        _ = context
        return OrionMessage(role: .assistant, content: "Preview response for: \(content)")
    }
}
#endif
