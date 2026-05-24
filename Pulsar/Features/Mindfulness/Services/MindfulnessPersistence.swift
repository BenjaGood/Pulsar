//
//  MindfulnessPersistence.swift
//  Pulsar
//

import Foundation

struct PulsarMindfulnessPersistedState: Codable, Equatable {
    var version: Int
    var entries: [PulsarDailyJournalEntry]
    var sessions: [PulsarMindfulnessSessionSummary]

    static let empty = PulsarMindfulnessPersistedState(version: 1, entries: [], sessions: [])
}

struct PulsarMindfulnessFileStore {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let fileName = "mindfulness-state-v1.json"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.directoryURL = applicationSupport
                .appendingPathComponent("Pulsar", isDirectory: true)
                .appendingPathComponent("Mindfulness", isDirectory: true)
        }
    }

    func load() -> PulsarMindfulnessPersistedState {
        let url = directoryURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let state = try? decoder.decode(PulsarMindfulnessPersistedState.self, from: data) else {
            return .empty
        }
        return normalized(state)
    }

    func save(_ state: PulsarMindfulnessPersistedState) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(normalized(state))
        try data.write(to: directoryURL.appendingPathComponent(fileName), options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    private func normalized(_ state: PulsarMindfulnessPersistedState) -> PulsarMindfulnessPersistedState {
        var entriesByID: [UUID: PulsarDailyJournalEntry] = [:]
        for entry in state.entries {
            entriesByID[entry.id] = entry
        }

        var sessionsByID: [UUID: PulsarMindfulnessSessionSummary] = [:]
        for session in state.sessions {
            sessionsByID[session.id] = session
        }

        return PulsarMindfulnessPersistedState(
            version: 1,
            entries: entriesByID.values.sorted { $0.date > $1.date },
            sessions: sessionsByID.values.sorted { $0.startedAt > $1.startedAt }
        )
    }
}
