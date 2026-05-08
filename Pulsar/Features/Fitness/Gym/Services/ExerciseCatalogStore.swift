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

    private let service: WgerExerciseService
    private let cache: ExerciseCatalogCache
    private var hasLoaded = false

    init(service: WgerExerciseService? = nil, cache: ExerciseCatalogCache? = nil) {
        self.service = service ?? WgerExerciseService()
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
                sourceName: "wger",
                refreshedAt: .now,
                schemaVersion: 1
            )
            cache.save(snapshot)
            exercises = fetchedExercises
            lastRefreshDate = snapshot.refreshedAt
            isShowingCachedData = false
        } catch {
            if exercises.isEmpty {
                loadCachedCatalog()
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
}

final class ExerciseCatalogCache {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = supportURL.appendingPathComponent("Pulsar/ExerciseCatalog", isDirectory: true)
        self.fileURL = directoryURL.appendingPathComponent("wger-exercises-v1.json")
    }

    func loadSnapshot() -> PulsarExerciseCatalogSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(PulsarExerciseCatalogSnapshot.self, from: data),
              snapshot.schemaVersion == 1 else { return nil }
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
            assertionFailure("Unable to cache wger exercise catalog: \(error.localizedDescription)")
        }
    }
}
