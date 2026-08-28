//
//  PulsarPerformanceTests.swift
//  PulsarTests
//

import XCTest
@testable import Pulsar

@MainActor
final class PulsarPerformanceTests: XCTestCase {
    private static let historyStorageKey = "pulsar.gym.workoutSessions.v1"

    func testGymHistoryDecodeEmpty() throws {
        try measureGymHistoryDecode(sessionCount: 0)
    }

    func testGymHistoryDecode20Sessions() throws {
        try measureGymHistoryDecode(sessionCount: 20)
    }

    func testGymHistoryDecode80Sessions() throws {
        try measureGymHistoryDecode(sessionCount: 80)
    }

    func testActiveGymStateEncode() {
        let state = PulsarPerformanceFixtures.activeGymState()
        var encodedPayloads: [Data] = []

        measure(
            metrics: [
                XCTClockMetric(),
                XCTMemoryMetric(),
                XCTOSSignpostMetric(
                    subsystem: PulsarPerformanceSignposts.subsystem,
                    category: PulsarPerformanceSignposts.Category.watchConnectivity,
                    name: PulsarPerformanceSignposts.Name.encode
                )
            ],
            options: measureOptions()
        ) {
            encodedPayloads.append(ActiveGymWorkoutCodec.encodeState(state)!)
        }

        XCTAssertFalse(encodedPayloads.isEmpty)
        XCTAssertTrue(encodedPayloads.allSatisfy { !$0.isEmpty })
    }

    func testExerciseCatalogDecode1324Exercises() throws {
        let data = try PulsarPerformanceFixtures.exerciseCatalogData()
        XCTAssertEqual(try ExercisesDatasetService.decodeCatalog(from: data).count, 1_324)
        var decodedCatalogs: [[PulsarExercise]] = []

        measure(
            metrics: [XCTClockMetric(), XCTMemoryMetric()],
            options: measureOptions()
        ) {
            decodedCatalogs.append(try! ExercisesDatasetService.decodeCatalog(from: data))
        }

        XCTAssertFalse(decodedCatalogs.isEmpty)
        XCTAssertTrue(decodedCatalogs.allSatisfy { $0.count == 1_324 })
    }

    private func measureGymHistoryDecode(sessionCount: Int) throws {
        let suiteName = "PulsarTests.Performance.History.\(sessionCount).\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fixture = PulsarPerformanceFixtures.completedGymSessions(count: sessionCount)
        defaults.set(try JSONEncoder().encode(fixture), forKey: Self.historyStorageKey)
        var retainedStores: [PulsarGymWorkoutHistoryStore] = []

        measure(
            metrics: [
                XCTClockMetric(),
                XCTMemoryMetric(),
                XCTOSSignpostMetric(
                    subsystem: PulsarPerformanceSignposts.subsystem,
                    category: PulsarPerformanceSignposts.Category.fitness,
                    name: PulsarPerformanceSignposts.Name.historyInit
                )
            ],
            options: measureOptions()
        ) {
            retainedStores.append(PulsarGymWorkoutHistoryStore(defaults: defaults))
        }

        XCTAssertFalse(retainedStores.isEmpty)
        XCTAssertTrue(retainedStores.allSatisfy { $0.sessions.count == sessionCount })
    }

    private func measureOptions() -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        return options
    }
}
