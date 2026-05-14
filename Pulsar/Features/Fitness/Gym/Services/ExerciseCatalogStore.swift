//
//  ExerciseCatalogStore.swift
//  Pulsar
//

import Combine
import Foundation

@MainActor
final class ExerciseCatalogStore: ObservableObject {
    @Published private(set) var exercises: [PulsarExercise] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var isShowingCachedData = false

    private let service: FreeExerciseDBService
    private let cache: ExerciseCatalogCache
    private var hasLoaded = false

    init(service: FreeExerciseDBService? = nil, cache: ExerciseCatalogCache? = nil) {
        self.service = service ?? FreeExerciseDBService()
        self.cache = cache ?? ExerciseCatalogCache()
    }

    var hasExercises: Bool {
        !exercises.isEmpty
    }

    var availableMuscleGroups: [PulsarMuscleGroup] {
        let groups = Set(exercises.map(\.primaryMuscleGroup))
        return PulsarMuscleGroup.allCases.filter { groups.contains($0) }
    }

    func loadCatalogIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        loadCachedCatalog()

        if exercises.isEmpty {
            loadBundledCatalog()
        }

        if exercises.isEmpty {
            await refreshCatalog()
        }
    }

    func refreshCatalog() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let fetchedExercises = try await service.fetchAllExercises()
            let snapshot = PulsarExerciseCatalogSnapshot(
                exercises: fetchedExercises,
                sourceName: FreeExerciseDBService.sourceName,
                refreshedAt: .now,
                schemaVersion: ExerciseCatalogCache.schemaVersion
            )
            cache.save(snapshot)
            exercises = fetchedExercises
            lastRefreshDate = snapshot.refreshedAt
            isShowingCachedData = false
        } catch {
            if exercises.isEmpty {
                loadCachedCatalog()
            }
            if exercises.isEmpty {
                loadBundledCatalog()
            }
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func loadCachedCatalog() {
        guard let snapshot = cache.loadSnapshot() else { return }
        exercises = snapshot.exercises.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        lastRefreshDate = snapshot.refreshedAt
        isShowingCachedData = true
    }

    private func loadBundledCatalog() {
        guard let bundledExercises = try? service.loadBundledExercises() else { return }
        let snapshot = PulsarExerciseCatalogSnapshot(
            exercises: bundledExercises,
            sourceName: FreeExerciseDBService.sourceName,
            refreshedAt: .now,
            schemaVersion: ExerciseCatalogCache.schemaVersion
        )
        cache.save(snapshot)
        exercises = bundledExercises
        lastRefreshDate = nil
        isShowingCachedData = false
    }
}

final class ExerciseCatalogCache {
    static let schemaVersion = 2

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = supportURL.appendingPathComponent("Pulsar/ExerciseCatalog", isDirectory: true)
        self.fileURL = directoryURL.appendingPathComponent("free-exercise-db-exercises-v1.json")
    }

    func loadSnapshot() -> PulsarExerciseCatalogSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(PulsarExerciseCatalogSnapshot.self, from: data),
              snapshot.schemaVersion == Self.schemaVersion,
              snapshot.sourceName == FreeExerciseDBService.sourceName else { return nil }
        return snapshot
    }

    func save(_ snapshot: PulsarExerciseCatalogSnapshot) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Unable to cache exercise catalog: \(error.localizedDescription)")
        }
    }
}
