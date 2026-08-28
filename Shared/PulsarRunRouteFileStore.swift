//
//  PulsarRunRouteFileStore.swift
//  Pulsar
//

import Foundation

/// Durable on-disk sidecar for GPS route points so history does not depend solely
/// on in-memory arrays or oversized UserDefaults JSON blobs.
actor PulsarRunRouteFileStore {
    static let shared = PulsarRunRouteFileStore()

    private let fileManager: FileManager
    private let directoryURL: URL

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.directoryURL = base.appendingPathComponent("PulsarRunRoutes", isDirectory: true)
        }
    }

    func save(
        route: [PulsarRunCoordinate],
        sessionId: UUID?,
        workoutUUID: UUID?
    ) {
        guard route.count > 1 else { return }
        ensureDirectory()
        let payload = RouteFilePayload(
            sessionId: sessionId,
            workoutUUID: workoutUUID,
            route: route,
            savedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(payload) else {
            PulsarSyncDebugLogger.log("Run route file encode failed session=\(sessionId?.uuidString ?? "none")")
            return
        }
        for key in storageKeys(sessionId: sessionId, workoutUUID: workoutUUID) {
            let url = directoryURL.appendingPathComponent("\(key).json")
            do {
                try data.write(to: url, options: [.atomic])
            } catch {
                PulsarSyncDebugLogger.log(
                    "Run route file write failed key=\(key) error=\(error.localizedDescription)"
                )
            }
        }
    }

    func load(sessionId: UUID?, workoutUUID: UUID?) -> [PulsarRunCoordinate] {
        for key in storageKeys(sessionId: sessionId, workoutUUID: workoutUUID) {
            let url = directoryURL.appendingPathComponent("\(key).json")
            guard let data = try? Data(contentsOf: url),
                  let payload = try? JSONDecoder().decode(RouteFilePayload.self, from: data),
                  payload.route.count > 1 else {
                continue
            }
            return payload.route
        }
        return []
    }

    func hydrate(_ summary: PulsarRunSummary) -> PulsarRunSummary {
        let diskRoute = load(sessionId: summary.pulsarWorkoutSessionId, workoutUUID: summary.workoutUUID)
        guard diskRoute.count > summary.route.count else { return summary }
        var hydrated = summary
        hydrated.route = diskRoute
        return hydrated
    }

    private func storageKeys(sessionId: UUID?, workoutUUID: UUID?) -> [String] {
        var keys: [String] = []
        if let sessionId {
            keys.append("session-\(sessionId.uuidString)")
        }
        if let workoutUUID {
            keys.append("workout-\(workoutUUID.uuidString)")
        }
        return keys
    }

    private func ensureDirectory() {
        guard !fileManager.fileExists(atPath: directoryURL.path) else { return }
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}

private nonisolated struct RouteFilePayload: Codable, Sendable {
    var sessionId: UUID?
    var workoutUUID: UUID?
    var route: [PulsarRunCoordinate]
    var savedAt: Date
}
