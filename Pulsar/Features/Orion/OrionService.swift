//
//  OrionService.swift
//  Pulsar
//

import Foundation

protocol OrionServicing {
    func sendMessage(
        _ content: String,
        history: [OrionMessage],
        context: OrionUserContext
    ) async throws -> OrionMessage
}

enum OrionServiceError: LocalizedError {
    case notConfigured([String])
    case invalidResponse
    case http(statusCode: Int, message: String)
    case emptyResponse
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let keys):
            "Orion is not configured. Set \(keys.joined(separator: ", ")) to the hosted Orion backend. The OpenAI API key belongs only in the backend environment."
        case .invalidResponse:
            "Orion returned an invalid response."
        case .http(_, let message):
            message
        case .emptyResponse:
            "Orion returned an empty response."
        case .transport(let message), .decoding(let message):
            message
        }
    }
}

final class OrionService: OrionServicing {
    private let configuration: OrionConfiguration
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        configuration: OrionConfiguration = .load(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func sendMessage(
        _ content: String,
        history: [OrionMessage],
        context: OrionUserContext
    ) async throws -> OrionMessage {
        if configuration.mockMode {
            return OrionMessage(
                role: .assistant,
                content: mockReply(for: content, context: context)
            )
        }

        guard let endpoint = configuration.chatEndpoint else {
            throw OrionServiceError.notConfigured(configuration.missingConfigurationKeys())
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = configuration.timeoutSeconds
        request.httpBody = try encoder.encode(
            OrionChatRequest(
                message: content,
                messages: Array(history.suffix(12)),
                context: context,
                capabilities: OrionCapabilityHints.default
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw OrionServiceError.transport(Self.transportMessage(endpoint: endpoint, error: error))
        } catch {
            throw OrionServiceError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OrionServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OrionServiceError.http(
                statusCode: httpResponse.statusCode,
                message: errorMessage(from: data) ?? "Orion backend returned HTTP \(httpResponse.statusCode)."
            )
        }

        do {
            let responseBody = try decoder.decode(OrionChatResponse.self, from: data)
            guard let text = responseBody.assistantText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                throw OrionServiceError.emptyResponse
            }
            return OrionMessage(
                id: responseBody.id.flatMap(UUID.init(uuidString:)) ?? UUID(),
                role: .assistant,
                content: text,
                createdAt: responseBody.createdAt ?? Date()
            )
        } catch let error as OrionServiceError {
            throw error
        } catch {
            throw OrionServiceError.decoding(error.localizedDescription)
        }
    }

    private func errorMessage(from data: Data) -> String? {
        guard !data.isEmpty,
              let response = try? decoder.decode(OrionChatResponse.self, from: data) else {
            return nil
        }
        return response.errorText
    }

    private func mockReply(for content: String, context: OrionUserContext) -> String {
        let focus = context.questionFocus.joined(separator: ", ")
        return "Orion mock mode is on. I would answer your \(focus) question using summarized Pulsar context, without sending raw HealthKit samples or local databases. You asked: “\(content)”"
    }

    private static func transportMessage(endpoint: URL, error: URLError) -> String {
        if error.code == .timedOut {
            return "Orion timed out. Try again in a moment."
        }
        #if targetEnvironment(simulator)
        return "Orion backend is not reachable. The iOS Simulator is calling \(endpoint.absoluteString)."
        #else
        if endpoint.host == "127.0.0.1" || endpoint.host == "localhost" {
            return "Orion backend is not reachable. On a physical iPhone, localhost points to the phone itself. Use https://www.aetherial.tech."
        }
        return "Orion backend is not reachable. Check your network connection and backend endpoint."
        #endif
    }
}

private struct OrionChatRequest: Encodable {
    var message: String
    var messages: [OrionMessage]
    var context: OrionUserContext
    var capabilities: [String]

    enum CodingKeys: String, CodingKey {
        case message
        case messages
        case context
        case capabilities
        case instructions
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encode(messages, forKey: .messages)
        try container.encode(context, forKey: .context)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encode(Self.instructions, forKey: .instructions)
    }

    private static let instructions = """
    You are Orion, Pulsar's intelligence assistant. Use only the summarized Pulsar context supplied in this request unless the backend explicitly gives you tools. Be concise, practical, and clear when data is missing. Do not provide medical diagnosis.
    """
}

private enum OrionCapabilityHints {
    static let `default` = [
        "summarized_pulsar_context",
        "future_tool_calling_ready",
        "future_web_search_backend"
    ]
}

private struct OrionChatResponse: Decodable {
    var id: String?
    var createdAt: Date?
    var reply: String?
    var content: String?
    var messageText: String?
    var errorDescription: String?
    var error: String?

    var assistantText: String? {
        reply ?? content ?? messageText
    }

    var errorText: String? {
        messageText ?? errorDescription ?? content ?? error
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case reply
        case content
        case message
        case error
        case errorDescription = "error_description"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        reply = try container.decodeIfPresent(String.self, forKey: .reply)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        errorDescription = try container.decodeIfPresent(String.self, forKey: .errorDescription)

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
