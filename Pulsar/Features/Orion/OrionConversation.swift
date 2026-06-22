//
//  OrionConversation.swift
//  Pulsar
//

import Foundation

struct OrionConversation: Identifiable, Codable, Equatable, Sendable {
    static let defaultTitle = "New Orion chat"

    let id: UUID
    var createdAt: Date
    var updatedAt: Date
    var title: String
    var messages: [OrionMessage]
    var previewSummary: String?
    var thumbnailSystemName: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case title
        case messages
        case previewSummary
        case thumbnailSystemName
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        title: String = OrionConversation.defaultTitle,
        messages: [OrionMessage] = OrionConversation.welcomeMessages(),
        previewSummary: String? = nil,
        thumbnailSystemName: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.messages = messages
        self.previewSummary = previewSummary
        self.thumbnailSystemName = thumbnailSystemName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedMessages = try container.decodeIfPresent([OrionMessage].self, forKey: .messages)
        let messages = decodedMessages ?? Self.welcomeMessages()
        let decodedUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        let firstMessageDate = decodedMessages?.map(\.createdAt).min()
        let lastMessageDate = decodedMessages?.map(\.createdAt).max()
        let fallbackCreatedAt = firstMessageDate ?? decodedUpdatedAt ?? Date()
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? fallbackCreatedAt

        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.createdAt = createdAt
        self.updatedAt = decodedUpdatedAt ?? lastMessageDate ?? createdAt
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? Self.defaultTitle
        self.messages = messages
        self.previewSummary = try container.decodeIfPresent(String.self, forKey: .previewSummary)
        self.thumbnailSystemName = try container.decodeIfPresent(String.self, forKey: .thumbnailSystemName)
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultTitle : trimmed
    }

    var startedAt: Date { createdAt }

    var previewText: String {
        if let previewSummary,
           !previewSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return previewSummary
        }

        return messages
            .reversed()
            .first { $0.role != .system }?
            .content
            .orionCondensedWhitespace()
            .orionTruncated(to: 138)
            ?? "Ask me about your training, recovery, sleep, or nutrition."
    }

    var hasUserMessages: Bool {
        messages.contains { $0.role == .user }
    }

    static func welcomeMessages(date: Date = Date()) -> [OrionMessage] {
        [
            OrionMessage(
                role: .assistant,
                content: "Ask me about your training, recovery, sleep, or nutrition.",
                createdAt: date
            )
        ]
    }
}

struct OrionConversationPersistedState: Codable, Equatable {
    var version: Int
    var conversations: [OrionConversation]

    static let currentVersion = 1
    static let empty = OrionConversationPersistedState(version: currentVersion, conversations: [])
}

protocol OrionConversationPersisting {
    func loadConversations() -> [OrionConversation]
    func saveConversations(_ conversations: [OrionConversation]) throws
}

struct OrionConversationFileStore: OrionConversationPersisting {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let fileName = "orion-conversations-v1.json"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.directoryURL = applicationSupport
                .appendingPathComponent("Pulsar", isDirectory: true)
                .appendingPathComponent("Orion", isDirectory: true)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadConversations() -> [OrionConversation] {
        let url = directoryURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let persisted = try? decoder.decode(OrionConversationPersistedState.self, from: data) else {
            return []
        }
        return normalized(persisted.conversations)
    }

    func saveConversations(_ conversations: [OrionConversation]) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let persisted = OrionConversationPersistedState(
            version: OrionConversationPersistedState.currentVersion,
            conversations: normalized(conversations)
        )
        let data = try encoder.encode(persisted)
        try data.write(to: directoryURL.appendingPathComponent(fileName), options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    private func normalized(_ conversations: [OrionConversation]) -> [OrionConversation] {
        var conversationsByID: [UUID: OrionConversation] = [:]
        for conversation in conversations {
            conversationsByID[conversation.id] = Self.normalized(conversation)
        }
        return conversationsByID.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private static func normalized(_ conversation: OrionConversation) -> OrionConversation {
        var normalized = conversation
        normalized.messages = normalized.messages.sorted { $0.createdAt < $1.createdAt }
        normalized.title = normalized.displayTitle
        if normalized.previewSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            normalized.previewSummary = nil
        }
        return normalized
    }
}

extension String {
    func orionCondensedWhitespace() -> String {
        components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func orionTruncated(to limit: Int) -> String {
        guard count > limit else { return self }
        let index = self.index(startIndex, offsetBy: max(0, limit - 1))
        return String(self[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
