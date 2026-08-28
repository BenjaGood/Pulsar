//
//  PulsarSyncPayloadFileCacheTests.swift
//  PulsarTests
//

import Foundation
import Testing
@testable import Pulsar

struct PulsarSyncPayloadFileCacheTests {
    @Test func cacheRoundTripsJSONOffPreferences() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PulsarSyncPayloadFileCache(directoryURL: directory)
        let payload = ["2026-08-18": ["recovery": 82, "strain": 11]]

        let didSave = await cache.save(payload, for: .dailyPayloads, revision: 1)
        let data = cache.loadData(for: .dailyPayloads) {
            (try? JSONDecoder().decode([String: [String: Int]].self, from: $0)) != nil
        }
        let restored = try JSONDecoder().decode([String: [String: Int]].self, from: #require(data))

        #expect(didSave)
        #expect(restored == payload)
    }

    @Test func staleAsynchronousWriteCannotReplaceNewerCache() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PulsarSyncPayloadFileCache(directoryURL: directory)

        #expect(await cache.save(["value": 2], for: .latestPayload, revision: 2))
        #expect(await cache.save(["value": 1], for: .latestPayload, revision: 1) == false)

        let data = try #require(
            cache.loadData(for: .latestPayload) {
                (try? JSONDecoder().decode([String: Int].self, from: $0)) != nil
            }
        )
        #expect(try JSONDecoder().decode([String: Int].self, from: data) == ["value": 2])
    }

    @Test func corruptFileIsRemovedAndTreatedAsEmpty() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PulsarSyncPayloadFileCache(directoryURL: directory)
        let fileURL = cache.fileURL(for: .sourceDailyPayloads)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: fileURL)

        let restored = cache.loadData(for: .sourceDailyPayloads) {
            (try? JSONSerialization.jsonObject(with: $0)) != nil
        }

        #expect(restored == nil)
        #expect(FileManager.default.fileExists(atPath: fileURL.path()) == false)
    }

    @Test func migrationMovesAllLargeLegacyKeysOutOfUserDefaults() throws {
        let suiteName = "pulsar.sync-file-cache.migration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PulsarSyncPayloadFileCache(directoryURL: directory)
        let data = try JSONEncoder().encode(["payload": String(repeating: "x", count: 150_000)])
        let migrations: [(String, PulsarSyncPayloadFileCache.Entry)] = [
            ("pulsar.sync.cachedDailyMetricsPayload.v1", .latestPayload),
            ("pulsar.sync.cachedDailyMetricPayloadsByDateKey.v1", .dailyPayloads),
            ("pulsar.sync.cachedSleepPayloadsByDateKey.v1", .sleepPayloads),
            ("pulsar.sync.cachedDailyMetricPayloadsByDateKeyAndSource.v1", .sourceDailyPayloads),
            ("pulsar.sync.cachedSleepPayloadsByDateKeyAndSource.v1", .sourceSleepPayloads),
            ("pulsar.sync.savedGymRoutines.v1", .savedGymRoutines),
            ("pulsar.calendar.dailyHealthRecords.v1", .dailyHealthHistory),
            ("pulsar.dashboard.cache.v1", .dashboard)
        ]

        for (key, entry) in migrations {
            defaults.set(data, forKey: key)
            let migrated = cache.migrateLegacyData(
                from: defaults,
                key: key,
                to: entry,
                validating: { $0 == data }
            )

            #expect(migrated == data)
            #expect(defaults.data(forKey: key) == nil)
            #expect(try Data(contentsOf: cache.fileURL(for: entry)) == data)
        }
    }

    @Test func corruptLegacyValueIsDeletedWithoutCreatingAFile() throws {
        let suiteName = "pulsar.sync-file-cache.corrupt-migration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = PulsarSyncPayloadFileCache(directoryURL: directory)
        let key = "pulsar.sync.cachedDailyMetricPayloadsByDateKey.v1"
        defaults.set(Data("corrupt".utf8), forKey: key)

        let migrated = cache.migrateLegacyData(
            from: defaults,
            key: key,
            to: .dailyPayloads,
            validating: { _ in false }
        )

        #expect(migrated == nil)
        #expect(defaults.data(forKey: key) == nil)
        #expect(FileManager.default.fileExists(atPath: cache.fileURL(for: .dailyPayloads).path()) == false)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PulsarSyncPayloadFileCacheTests-\(UUID().uuidString)", isDirectory: true)
    }
}
