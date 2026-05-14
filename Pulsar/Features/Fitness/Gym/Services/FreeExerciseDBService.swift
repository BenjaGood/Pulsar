//
//  FreeExerciseDBService.swift
//  Pulsar
//

import Foundation

enum FreeExerciseDBServiceError: LocalizedError {
    case invalidResponse
    case invalidStatusCode(Int)
    case emptyCatalog
    case bundledCatalogUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The exercise catalog returned an unreadable response."
        case .invalidStatusCode(let statusCode):
            "The exercise catalog is temporarily unavailable. Status \(statusCode)."
        case .emptyCatalog:
            "No exercises were returned by the catalog."
        case .bundledCatalogUnavailable:
            "The bundled exercise catalog could not be loaded."
        }
    }
}

struct FreeExerciseDBService {
    // Catalog source: yuhonas/free-exercise-db. License: Unlicense.
    // The normalized PulsarExerciseAttribution preserves this source metadata.
    static let sourceName = "free-exercise-db"
    static let sourceURL = "https://github.com/yuhonas/free-exercise-db"
    static let license = "Unlicense"
    static let defaultCatalogURL = URL(string: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json")!
    static let defaultImageBaseURL = URL(string: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/")!

    private let catalogURL: URL
    private let imageBaseURL: URL
    private let bundledCatalogURL: URL?
    private let session: URLSession
    private let decoder: JSONDecoder

    init(
        catalogURL: URL = Self.defaultCatalogURL,
        imageBaseURL: URL = Self.defaultImageBaseURL,
        bundledCatalogURL: URL? = nil,
        session: URLSession = .shared
    ) {
        self.catalogURL = catalogURL
        self.imageBaseURL = imageBaseURL
        self.bundledCatalogURL = bundledCatalogURL
        self.session = session
        self.decoder = JSONDecoder()
    }

    func fetchAllExercises() async throws -> [PulsarExercise] {
        var request = URLRequest(url: catalogURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FreeExerciseDBServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw FreeExerciseDBServiceError.invalidStatusCode(httpResponse.statusCode)
        }

        return try Self.decodeCatalog(from: data, imageBaseURL: imageBaseURL, decoder: decoder)
    }

    func loadBundledExercises() throws -> [PulsarExercise] {
        let data = try Data(contentsOf: bundledCatalogFileURL())
        return try Self.decodeCatalog(from: data, imageBaseURL: imageBaseURL, decoder: decoder)
    }

    static func decodeCatalog(
        from data: Data,
        imageBaseURL: URL = Self.defaultImageBaseURL,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> [PulsarExercise] {
        let exercises = try decoder.decode([FreeExerciseDBExerciseDTO].self, from: data)
            .compactMap { FreeExerciseDBExerciseNormalizer.normalize($0, imageBaseURL: imageBaseURL) }
            .uniqued(by: \.id)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard !exercises.isEmpty else { throw FreeExerciseDBServiceError.emptyCatalog }
        return exercises
    }

    private func bundledCatalogFileURL() throws -> URL {
        if let bundledCatalogURL {
            return bundledCatalogURL
        }

        let resourceName = "free-exercise-db-exercises"
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "json") {
            return url
        }

        let subdirectories = [
            "Features/Fitness/Gym/Resources",
            "Pulsar/Features/Fitness/Gym/Resources"
        ]
        for subdirectory in subdirectories {
            if let url = Bundle.main.url(forResource: resourceName, withExtension: "json", subdirectory: subdirectory) {
                return url
            }
        }

        if let resourceURL = Bundle.main.resourceURL,
           let enumerator = FileManager.default.enumerator(
            at: resourceURL,
            includingPropertiesForKeys: nil
           ) {
            for case let url as URL in enumerator where url.lastPathComponent == "\(resourceName).json" {
                return url
            }
        }

        throw FreeExerciseDBServiceError.bundledCatalogUnavailable
    }
}

private struct FreeExerciseDBExerciseDTO: Decodable {
    var id: String?
    var name: String?
    var force: String?
    var level: String?
    var mechanic: String?
    var equipment: String?
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var instructions: [String]
    var category: String?
    var images: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case force
        case level
        case mechanic
        case equipment
        case primaryMuscles
        case secondaryMuscles
        case instructions
        case category
        case images
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        force = try? container.decodeIfPresent(String.self, forKey: .force)
        level = try? container.decodeIfPresent(String.self, forKey: .level)
        mechanic = try? container.decodeIfPresent(String.self, forKey: .mechanic)
        equipment = try? container.decodeIfPresent(String.self, forKey: .equipment)
        primaryMuscles = container.decodeLossyStringArray(forKey: .primaryMuscles)
        secondaryMuscles = container.decodeLossyStringArray(forKey: .secondaryMuscles)
        instructions = container.decodeLossyStringArray(forKey: .instructions)
        category = try? container.decodeIfPresent(String.self, forKey: .category)
        images = container.decodeLossyStringArray(forKey: .images)
    }
}

private enum FreeExerciseDBExerciseNormalizer {
    static func normalize(_ dto: FreeExerciseDBExerciseDTO, imageBaseURL: URL) -> PulsarExercise? {
        let name = dto.name.cleanedCatalogValue
        guard let name else { return nil }

        let sourceID = dto.id.cleanedCatalogValue ?? name.normalizedPulsarIdentifier(prefix: "free-exercise-db-source")
        let primaryMuscles = dto.primaryMuscles.normalizedCatalogValues.map(makeMuscle)
        let secondaryMuscles = dto.secondaryMuscles.normalizedCatalogValues.map(makeMuscle)
        let category = displayValue(dto.category)
        let imageURLs = dto.images.normalizedCatalogValues.compactMap {
            absoluteImageURL($0, imageBaseURL: imageBaseURL)
        }

        return PulsarExercise(
            id: "free-exercise-db-\(sourceID)",
            wgerID: nil,
            wgerUUID: nil,
            name: name,
            instructions: instructions(from: dto.instructions),
            primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles,
            primaryMuscleGroup: primaryMuscles.first?.group ?? group(forCategory: category),
            equipment: equipment(from: dto.equipment, category: category, exerciseName: name),
            imageURLs: imageURLs,
            thumbnailURL: imageURLs.first,
            attribution: .freeExerciseDB(sourceExerciseID: sourceID),
            category: category,
            level: displayValue(dto.level),
            force: displayValue(dto.force),
            mechanic: displayValue(dto.mechanic)
        )
    }

    private static func makeMuscle(_ rawName: String) -> PulsarMuscle {
        PulsarMuscle(
            name: displayValue(rawName) ?? rawName,
            englishName: rawName,
            group: group(forMuscleName: rawName)
        )
    }

    private static func equipment(
        from rawEquipment: String?,
        category: String?,
        exerciseName: String
    ) -> [PulsarEquipment] {
        let normalized = rawEquipment.cleanedCatalogValue?.lowercased()
        let displayName: String

        switch normalized {
        case .some("body only"):
            displayName = "Bodyweight"
        case .some("e-z curl bar"):
            displayName = "EZ Curl Bar"
        case .some("foam roll"):
            displayName = "Foam Roll"
        case .some("medicine ball"):
            displayName = "Medicine Ball"
        case .some("exercise ball"):
            displayName = "Exercise Ball"
        case .some("kettlebells"):
            displayName = "Kettlebells"
        case .some("other"):
            displayName = "Other"
        case .some(let value):
            displayName = value.catalogTitleCased()
        case .none:
            displayName = fallbackEquipmentName(category: category, exerciseName: exerciseName)
        }

        return [PulsarEquipment(name: displayName)]
    }

    private static func fallbackEquipmentName(category: String?, exerciseName: String) -> String {
        let categoryValue = category?.lowercased() ?? ""
        let name = exerciseName.lowercased()
        if categoryValue.contains("strength")
            || categoryValue.contains("stretch")
            || categoryValue.contains("plyometric")
            || categoryValue.contains("cardio")
            || name.contains("push-up")
            || name.contains("pull-up")
            || name.contains("sit-up")
            || name.contains("squat") {
            return "Bodyweight"
        }
        return "Unknown"
    }

    private static func instructions(from rawInstructions: [String]) -> String? {
        let instructions = rawInstructions.normalizedCatalogValues
        guard !instructions.isEmpty else { return nil }
        return instructions.joined(separator: "\n\n")
    }

    private static func absoluteImageURL(_ rawPath: String, imageBaseURL: URL) -> String? {
        if rawPath.hasPrefix("http://") || rawPath.hasPrefix("https://") {
            return rawPath
        }

        let encodedPath = rawPath
            .split(separator: "/", omittingEmptySubsequences: true)
            .compactMap { pathComponent in
                String(pathComponent).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            }
            .joined(separator: "/")

        guard !encodedPath.isEmpty else { return nil }
        let base = imageBaseURL.absoluteString
        let normalizedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        return "\(normalizedBase)/\(encodedPath)"
    }

    private static func group(forMuscleName rawName: String) -> PulsarMuscleGroup {
        let name = rawName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        switch name {
        case "abdominals":
            return .absCore
        case "abductors":
            return .abductors
        case "adductors":
            return .adductors
        case "biceps":
            return .biceps
        case "calves":
            return .calves
        case "chest":
            return .chest
        case "forearms":
            return .forearms
        case "glutes":
            return .glutes
        case "hamstrings":
            return .hamstrings
        case "lats":
            return .lats
        case "lower back":
            return .lowerBack
        case "middle back":
            return .upperMiddleBack
        case "neck":
            return .neckTraps
        case "quadriceps":
            return .quadriceps
        case "shoulders":
            return .shoulders
        case "traps":
            return .traps
        case "triceps":
            return .triceps
        default:
            return .other
        }
    }

    private static func group(forCategory category: String?) -> PulsarMuscleGroup {
        let category = category?.lowercased() ?? ""
        if category.contains("cardio") { return .cardioConditioning }
        if category.contains("plyometric") { return .fullBody }
        return .other
    }

    private static func displayValue(_ value: String?) -> String? {
        value.cleanedCatalogValue?.catalogTitleCased()
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyStringArray(forKey key: Key) -> [String] {
        (try? decodeIfPresent([String].self, forKey: key)) ?? []
    }
}

private extension Optional where Wrapped == String {
    var cleanedCatalogValue: String? {
        guard let self else { return nil }
        let cleaned = self
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

private extension Array where Element == String {
    var normalizedCatalogValues: [String] {
        var seen = Set<String>()
        return compactMap { Optional($0).cleanedCatalogValue }
            .filter { value in
                seen.insert(value.lowercased()).inserted
            }
    }
}

private extension String {
    func catalogTitleCased() -> String {
        split(separator: " ")
            .map { word in
                let rawWord = String(word)
                if rawWord.count <= 2 {
                    return rawWord.uppercased()
                }
                return rawWord.prefix(1).uppercased() + rawWord.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}

private extension Array {
    func uniqued<ID: Hashable>(by keyPath: KeyPath<Element, ID>) -> [Element] {
        var seen = Set<ID>()
        var result: [Element] = []
        for item in self where seen.insert(item[keyPath: keyPath]).inserted {
            result.append(item)
        }
        return result
    }
}
