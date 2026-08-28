//
//  PulsarSyncPayloadFileCache.swift
//  Pulsar
//

import Foundation

/// Durable storage for WatchConnectivity payload caches that are too large for
/// a preferences domain. Startup reads and legacy migration stay synchronous so
/// the sync store is fully hydrated before its public API can be used.
actor PulsarSyncPayloadFileCache {
    enum Entry: String, CaseIterable, Sendable {
        case latestPayload = "latestPayload.json"
        case dailyPayloads = "dailyPayloads.json"
        case sleepPayloads = "sleepPayloads.json"
        case sourceDailyPayloads = "sourceDailyPayloads.json"
        case sourceSleepPayloads = "sourceSleepPayloads.json"
        case savedGymRoutines = "savedGymRoutines.json"
        case dailyHealthHistory = "dailyHealthHistory.json"
        case dashboard = "dashboard.json"
    }

    static let shared = PulsarSyncPayloadFileCache()

    nonisolated let directoryURL: URL
    private var latestRevisionByEntry: [Entry: UInt64] = [:]

    init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            self.directoryURL = URL.applicationSupportDirectory
                .appending(path: "PulsarSyncCache", directoryHint: .isDirectory)
        }
    }

    @discardableResult
    func save<Value: Encodable & Sendable>(
        _ value: Value,
        for entry: Entry,
        revision: UInt64
    ) -> Bool {
        do {
            let data = try JSONEncoder().encode(value)
            return saveEncodedData(data, for: entry, revision: revision)
        } catch {
            PulsarSyncDebugLogger.log(
                "Sync file cache encode failed entry=\(entry.rawValue) error=\(error.localizedDescription)"
            )
            return false
        }
    }

    @discardableResult
    func saveEncodedData(
        _ data: Data,
        for entry: Entry,
        revision: UInt64
    ) -> Bool {
        guard revision >= (latestRevisionByEntry[entry] ?? 0) else { return false }
        do {
            try Self.write(data, to: fileURL(for: entry))
            latestRevisionByEntry[entry] = revision
            return true
        } catch {
            PulsarSyncDebugLogger.log(
                "Sync file cache write failed entry=\(entry.rawValue) bytes=\(data.count) error=\(error.localizedDescription)"
            )
            return false
        }
    }

    func remove(_ entry: Entry, revision: UInt64) {
        guard revision >= (latestRevisionByEntry[entry] ?? 0) else { return }
        do {
            try Self.removeFileIfPresent(at: fileURL(for: entry))
            latestRevisionByEntry[entry] = revision
        } catch {
            PulsarSyncDebugLogger.log(
                "Sync file cache remove failed entry=\(entry.rawValue) error=\(error.localizedDescription)"
            )
        }
    }

    /// Loads and validates an existing cache file. Invalid files are removed so
    /// a future sync can rebuild the re-syncable cache.
    nonisolated func loadData(
        for entry: Entry,
        validating isValid: (Data) -> Bool
    ) -> Data? {
        let url = fileURL(for: entry)
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard isValid(data) else {
            try? Self.removeFileIfPresent(at: url)
            PulsarSyncDebugLogger.log("Removed corrupt sync file cache entry=\(entry.rawValue)")
            return nil
        }
        return data
    }

    /// Moves a legacy preferences value to disk. The preferences key is only
    /// removed after an atomic file write succeeds.
    @discardableResult
    nonisolated func migrateLegacyData(
        from defaults: UserDefaults,
        key: String,
        to entry: Entry,
        validating isValid: (Data) -> Bool
    ) -> Data? {
        guard let legacyData = defaults.data(forKey: key) else {
            return loadData(for: entry, validating: isValid)
        }

        guard isValid(legacyData) else {
            defaults.removeObject(forKey: key)
            PulsarSyncDebugLogger.log("Removed corrupt legacy sync cache key=\(key)")
            return loadData(for: entry, validating: isValid)
        }

        do {
            try Self.write(legacyData, to: fileURL(for: entry))
            defaults.removeObject(forKey: key)
            PulsarSyncDebugLogger.log(
                "Migrated legacy sync cache key=\(key) entry=\(entry.rawValue) bytes=\(legacyData.count)"
            )
            return legacyData
        } catch {
            PulsarSyncDebugLogger.log(
                "Legacy sync cache migration failed key=\(key) error=\(error.localizedDescription)"
            )
            return legacyData
        }
    }

    nonisolated func fileURL(for entry: Entry) -> URL {
        directoryURL.appending(path: entry.rawValue)
    }

    private nonisolated static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private nonisolated static func removeFileIfPresent(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path()) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
