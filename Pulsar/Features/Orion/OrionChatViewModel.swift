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
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?

    private var service: any OrionServicing
    private var contextProvider: any OrionContextProviding
    private var sendTask: Task<Void, Never>?

    init(
        service: (any OrionServicing)? = nil,
        contextProvider: (any OrionContextProviding)? = nil
    ) {
        self.service = service ?? OrionService()
        self.contextProvider = contextProvider ?? OrionContextProvider()
        self.messages = [
            OrionMessage(
                role: .assistant,
                content: "Ask me about your training, recovery, sleep, or nutrition."
            )
        ]
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
        draft = ""
        errorMessage = nil
        messages.append(OrionMessage(role: .user, content: content))

        sendTask?.cancel()
        sendTask = Task { [weak self] in
            guard let self else { return }
            await self.send(content, history: history)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func send(_ content: String, history: [OrionMessage]) async {
        isSending = true
        defer { isSending = false }

        do {
            let context = await contextProvider.makeContext(for: content)
            let response = try await service.sendMessage(
                content,
                history: history,
                context: context
            )
            guard !Task.isCancelled else { return }
            messages.append(response)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#if DEBUG
extension OrionChatViewModel {
    static var preview: OrionChatViewModel {
        let viewModel = OrionChatViewModel(
            service: OrionPreviewService(),
            contextProvider: OrionContextProvider()
        )
        viewModel.messages = [
            OrionMessage(role: .assistant, content: "Ask me about your training, recovery, sleep, or nutrition."),
            OrionMessage(role: .user, content: "How should I train today?"),
            OrionMessage(role: .assistant, content: "Your recovery context is still being wired in, so I would start with an easy recommendation and adjust once the live dashboard summary is available.")
        ]
        return viewModel
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
