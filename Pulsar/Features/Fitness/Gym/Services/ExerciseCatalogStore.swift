//
//  ExerciseCatalogStore.swift
//  Pulsar
//

import Combine
import Foundation
import OSLog

@MainActor
final class ExerciseCatalogStore: ObservableObject {
    @Published private(set) var exercises: [PulsarExercise] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var isShowingCachedData = false

    private let service: ExercisesDatasetService
    private let cache: ExerciseCatalogCache
    private let customStore: CustomExerciseCatalogStore
    private var hasLoaded = false
    private var catalogExercises: [PulsarExercise] = []
    private var customExercises: [PulsarExercise] = []

    init(
        service: ExercisesDatasetService? = nil,
        cache: ExerciseCatalogCache? = nil,
        customStore: CustomExerciseCatalogStore? = nil
    ) {
        self.service = service ?? ExercisesDatasetService()
        self.cache = cache ?? ExerciseCatalogCache()
        self.customStore = customStore ?? CustomExerciseCatalogStore()
        self.customExercises = self.customStore.loadExercises()
        publishExercises()
    }

    var hasExercises: Bool {
        !exercises.isEmpty
    }

    var availableMuscleGroups: [PulsarMuscleGroup] {
        let groups = Set(exercises.map(\.primaryMuscleGroup))
        return PulsarMuscleGroup.allCases.filter { groups.contains($0) }
    }

    func exercise(id: String) -> PulsarExercise? {
        exercises.first { $0.id == id }
    }

    func loadCatalogIfNeeded() async {
        guard !hasLoaded else { return }
        let signpostState = PulsarPerformanceSignposts.catalog.beginInterval("load")
        defer {
            PulsarPerformanceSignposts.catalog.endInterval("load", signpostState)
        }
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
                sourceName: ExercisesDatasetService.sourceName,
                refreshedAt: .now,
                schemaVersion: ExerciseCatalogCache.schemaVersion
            )
            cache.save(snapshot)
            catalogExercises = fetchedExercises
            publishExercises()
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

    @discardableResult
    func addCustomExercise(
        name: String,
        primaryMuscleGroup: PulsarMuscleGroup,
        imageData: Data?
    ) throws -> PulsarExercise {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw CustomExerciseCatalogError.missingName
        }

        let exerciseID = Self.customExerciseID(for: trimmedName)
        let thumbnailURL = try customStore.saveImageData(imageData, exerciseID: exerciseID)
        let exercise = PulsarExercise.custom(
            id: exerciseID,
            name: trimmedName,
            primaryMuscleGroup: primaryMuscleGroup,
            thumbnailURL: thumbnailURL
        )

        customExercises.insert(exercise, at: 0)
        customStore.saveExercises(customExercises)
        publishExercises()
        return exercise
    }

    private func loadCachedCatalog() {
        guard let snapshot = cache.loadSnapshot() else { return }
        catalogExercises = snapshot.exercises.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        publishExercises()
        lastRefreshDate = snapshot.refreshedAt
        isShowingCachedData = true
    }

    private func loadBundledCatalog() {
        guard let bundledExercises = try? service.loadBundledExercises() else { return }
        catalogExercises = bundledExercises
        publishExercises()
        lastRefreshDate = nil
        isShowingCachedData = false
    }

    private func publishExercises() {
        let catalogIds = Set(catalogExercises.map(\.id))
        let uniqueCustomExercises = customExercises.filter { !catalogIds.contains($0.id) }
        exercises = (uniqueCustomExercises + catalogExercises).sorted { first, second in
            if first.attribution.sourceName == "Pulsar Custom",
               second.attribution.sourceName != "Pulsar Custom" {
                return true
            }
            if second.attribution.sourceName == "Pulsar Custom",
               first.attribution.sourceName != "Pulsar Custom" {
                return false
            }
            return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }
    }

    private static func customExerciseID(for name: String) -> String {
        "\(name.normalizedPulsarIdentifier(prefix: "custom-exercise"))-\(UUID().uuidString.lowercased())"
    }
}

final class ExerciseCatalogCache {
    static let schemaVersion = 3

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = supportURL.appendingPathComponent("Pulsar/ExerciseCatalog", isDirectory: true)
        self.fileURL = directoryURL.appendingPathComponent("exercises-dataset-v1.json")
    }

    func loadSnapshot() -> PulsarExerciseCatalogSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(PulsarExerciseCatalogSnapshot.self, from: data),
              snapshot.schemaVersion == Self.schemaVersion,
              snapshot.sourceName == ExercisesDatasetService.sourceName else { return nil }
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

enum CustomExerciseCatalogError: LocalizedError {
    case missingName

    var errorDescription: String? {
        switch self {
        case .missingName:
            return "Add a name for your custom exercise."
        }
    }
}

final class CustomExerciseCatalogStore {
    private struct Snapshot: Codable {
        var schemaVersion: Int
        var exercises: [PulsarExercise]
    }

    private static let schemaVersion = 1

    private let fileURL: URL
    private let imageDirectoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = supportURL.appendingPathComponent("Pulsar/ExerciseCatalog", isDirectory: true)
        self.fileURL = directoryURL.appendingPathComponent("custom-exercises-v1.json")
        self.imageDirectoryURL = directoryURL.appendingPathComponent("CustomExerciseImages", isDirectory: true)
    }

    func loadExercises() -> [PulsarExercise] {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(Snapshot.self, from: data),
              snapshot.schemaVersion == Self.schemaVersion else {
            return []
        }
        return snapshot.exercises
    }

    func saveExercises(_ exercises: [PulsarExercise]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let snapshot = Snapshot(schemaVersion: Self.schemaVersion, exercises: exercises)
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Unable to save custom exercises: \(error.localizedDescription)")
        }
    }

    func saveImageData(_ imageData: Data?, exerciseID: String) throws -> String? {
        guard let imageData else { return nil }
        try FileManager.default.createDirectory(
            at: imageDirectoryURL,
            withIntermediateDirectories: true
        )
        let imageURL = imageDirectoryURL.appendingPathComponent("\(exerciseID).jpg")
        try imageData.write(to: imageURL, options: [.atomic])
        return imageURL.absoluteString
    }
}
