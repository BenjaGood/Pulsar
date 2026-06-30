//
//  FreeExerciseDBService.swift
//  Pulsar
//

import Foundation

enum ExercisesDatasetServiceError: LocalizedError {
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

struct ExercisesDatasetService {
    // Catalog source: hasaneyldrm/exercises-dataset.
    // License: educational and non-commercial use only; media remains owned by
    // its respective copyright holders. Attribution is preserved per exercise.
    static let sourceName = "hasaneyldrm/exercises-dataset"
    static let sourceURL = "https://github.com/hasaneyldrm/exercises-dataset"
    static let license = "Educational / non-commercial only"
    static let defaultCatalogURL = URL(string: "https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/data/exercises.json")!

    private let catalogURL: URL
    private let bundledCatalogURL: URL?
    private let session: URLSession
    private let decoder: JSONDecoder

    init(
        catalogURL: URL = Self.defaultCatalogURL,
        bundledCatalogURL: URL? = nil,
        session: URLSession = .shared
    ) {
        self.catalogURL = catalogURL
        self.bundledCatalogURL = bundledCatalogURL
        self.session = session
        self.decoder = JSONDecoder()
    }

    func fetchAllExercises() async throws -> [PulsarExercise] {
        var request = URLRequest(url: catalogURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExercisesDatasetServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ExercisesDatasetServiceError.invalidStatusCode(httpResponse.statusCode)
        }

        return try Self.decodeCatalog(from: data, decoder: decoder)
    }

    func loadBundledExercises() throws -> [PulsarExercise] {
        let data = try Data(contentsOf: bundledCatalogFileURL())
        return try Self.decodeCatalog(from: data, decoder: decoder)
    }

    static func decodeCatalog(
        from data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> [PulsarExercise] {
        let exercises = try decoder.decode([ExercisesDatasetExerciseDTO].self, from: data)
            .compactMap(ExercisesDatasetExerciseNormalizer.normalize)
            .uniqued(by: \.id)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard !exercises.isEmpty else { throw ExercisesDatasetServiceError.emptyCatalog }
        return exercises
    }

    private func bundledCatalogFileURL() throws -> URL {
        if let bundledCatalogURL {
            return bundledCatalogURL
        }

        let resourceName = "exercises"
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "json") {
            return url
        }

        let subdirectories = [
            "Features/Fitness/Gym/Resources/ExerciseDataset/data",
            "Pulsar/Features/Fitness/Gym/Resources/ExerciseDataset/data",
            "ExerciseDataset/data",
            "data"
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
                if url.path.contains("ExerciseDataset") {
                    return url
                }
            }
        }

        throw ExercisesDatasetServiceError.bundledCatalogUnavailable
    }
}

enum ExerciseDatasetMediaResolver {
    nonisolated private static let remoteMediaBaseURL = URL(string: "https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/")!
    nonisolated private static let bundledRootSubdirectories = [
        "Features/Fitness/Gym/Resources/ExerciseDataset",
        "Pulsar/Features/Fitness/Gym/Resources/ExerciseDataset",
        "ExerciseDataset",
        ""
    ]

    nonisolated static func url(for reference: String?) -> URL? {
        guard let reference = reference.cleanedCatalogValue else { return nil }
        if reference.hasPrefix("http://") || reference.hasPrefix("https://") || reference.hasPrefix("file://") {
            return URL(string: reference)
        }

        if let bundledURL = bundledURL(for: reference) {
            return bundledURL
        }

        return remoteURL(for: reference)
    }

    private nonisolated static func bundledURL(for reference: String) -> URL? {
        let pathComponents = reference
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard let fileComponent = pathComponents.last else { return nil }

        let fileURL = URL(fileURLWithPath: fileComponent)
        let filename = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = fileURL.pathExtension
        guard !filename.isEmpty, !fileExtension.isEmpty else { return nil }

        if let url = Bundle.main.url(forResource: filename, withExtension: fileExtension) {
            return url
        }

        let relativeDirectory = pathComponents.dropLast().joined(separator: "/")
        for root in bundledRootSubdirectories {
            let subdirectory = [root, relativeDirectory]
                .filter { !$0.isEmpty && $0 != "." }
                .joined(separator: "/")
            if let url = Bundle.main.url(forResource: filename, withExtension: fileExtension, subdirectory: subdirectory) {
                return url
            }
        }

        return nil
    }

    private nonisolated static func remoteURL(for reference: String) -> URL? {
        let encodedPath = reference
            .split(separator: "/", omittingEmptySubsequences: true)
            .compactMap { pathComponent in
                String(pathComponent).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            }
            .joined(separator: "/")
        guard !encodedPath.isEmpty else { return nil }

        return URL(string: remoteMediaBaseURL.absoluteString + encodedPath)
    }
}

private struct ExercisesDatasetExerciseDTO: Decodable {
    var id: String?
    var name: String?
    var category: String?
    var bodyPart: String?
    var equipment: String?
    var instructions: [String: String]
    var instructionSteps: [String: [String]]
    var muscleGroup: String?
    var secondaryMuscles: [String]
    var target: String?
    var image: String?
    var gifURL: String?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case bodyPart = "body_part"
        case equipment
        case instructions
        case instructionSteps = "instruction_steps"
        case muscleGroup = "muscle_group"
        case secondaryMuscles = "secondary_muscles"
        case target
        case image
        case gifURL = "gif_url"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        category = try? container.decodeIfPresent(String.self, forKey: .category)
        bodyPart = try? container.decodeIfPresent(String.self, forKey: .bodyPart)
        equipment = try? container.decodeIfPresent(String.self, forKey: .equipment)
        instructions = (try? container.decodeIfPresent([String: String].self, forKey: .instructions)) ?? [:]
        instructionSteps = (try? container.decodeIfPresent([String: [String]].self, forKey: .instructionSteps)) ?? [:]
        muscleGroup = try? container.decodeIfPresent(String.self, forKey: .muscleGroup)
        secondaryMuscles = container.decodeLossyStringArray(forKey: .secondaryMuscles)
        target = try? container.decodeIfPresent(String.self, forKey: .target)
        image = try? container.decodeIfPresent(String.self, forKey: .image)
        gifURL = try? container.decodeIfPresent(String.self, forKey: .gifURL)
        createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

private enum ExercisesDatasetExerciseNormalizer {
    nonisolated static func normalize(_ dto: ExercisesDatasetExerciseDTO) -> PulsarExercise? {
        let name = displayName(dto.name)
        guard let name else { return nil }

        let sourceID = dto.id.cleanedCatalogValue ?? name.normalizedPulsarIdentifier(prefix: "exercises-dataset-source")
        let bodyPart = dto.bodyPart.cleanedCatalogValue ?? dto.category.cleanedCatalogValue
        let target = dto.target.cleanedCatalogValue
        let primaryGroup = group(forBodyPart: bodyPart, target: target, muscleGroup: dto.muscleGroup)
        let primaryMuscles = primaryMuscles(target: target, muscleGroup: dto.muscleGroup, fallbackGroup: primaryGroup)
        let secondaryMuscles = secondaryMuscles(
            target: target,
            muscleGroup: dto.muscleGroup,
            secondaryMuscles: dto.secondaryMuscles,
            primaryGroup: primaryGroup
        )
        let imageURL = dto.image.cleanedCatalogValue
        let imageURLs = imageURL.map { [$0] } ?? []
        let category = displayValue(bodyPart)

        return PulsarExercise(
            id: "exercises-dataset-\(sourceID)",
            wgerID: nil,
            wgerUUID: nil,
            name: name,
            instructions: instructions(from: dto),
            primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles,
            primaryMuscleGroup: primaryMuscles.first?.group ?? primaryGroup,
            equipment: equipment(from: dto.equipment),
            imageURLs: imageURLs,
            thumbnailURL: imageURL,
            animationURL: dto.gifURL.cleanedCatalogValue,
            attribution: .exercisesDataset(sourceExerciseID: sourceID),
            category: category,
            level: nil,
            force: nil,
            mechanic: nil
        )
    }

    private nonisolated static func primaryMuscles(
        target: String?,
        muscleGroup: String?,
        fallbackGroup: PulsarMuscleGroup
    ) -> [PulsarMuscle] {
        if let target {
            return [makeMuscle(target, fallbackGroup: fallbackGroup)]
        }
        if let muscleGroup = muscleGroup.cleanedCatalogValue {
            return [makeMuscle(muscleGroup, fallbackGroup: fallbackGroup)]
        }
        return [
            PulsarMuscle(
                name: fallbackGroup.displayName,
                englishName: fallbackGroup.displayName,
                group: fallbackGroup
            )
        ]
    }

    private nonisolated static func secondaryMuscles(
        target: String?,
        muscleGroup: String?,
        secondaryMuscles: [String],
        primaryGroup: PulsarMuscleGroup
    ) -> [PulsarMuscle] {
        let targetKey = target?.normalizedCatalogKey
        var candidates = secondaryMuscles.normalizedCatalogValues
        if let muscleGroup = muscleGroup.cleanedCatalogValue {
            candidates.insert(muscleGroup, at: 0)
        }

        var seen = Set<String>()
        return candidates.compactMap { rawName in
            let key = rawName.normalizedCatalogKey
            guard key != targetKey, seen.insert(key).inserted else { return nil }
            let muscle = makeMuscle(rawName, fallbackGroup: group(forMuscleName: rawName))
            return muscle.group == primaryGroup ? nil : muscle
        }
    }

    private nonisolated static func makeMuscle(
        _ rawName: String,
        fallbackGroup: PulsarMuscleGroup
    ) -> PulsarMuscle {
        let group = group(forMuscleName: rawName)
        return PulsarMuscle(
            name: displayValue(rawName),
            englishName: rawName,
            group: group == .other ? fallbackGroup : group
        )
    }

    private nonisolated static func equipment(from rawEquipment: String?) -> [PulsarEquipment] {
        let displayName: String
        switch rawEquipment.cleanedCatalogValue?.normalizedCatalogKey {
        case .some("body weight"):
            displayName = "Bodyweight"
        case .some("ez barbell"):
            displayName = "EZ Barbell"
        case .some("bosu ball"):
            displayName = "BOSU Ball"
        case .some("skierg machine"):
            displayName = "SkiErg Machine"
        case .some(let value):
            displayName = value.catalogTitleCased()
        case .none:
            displayName = "Bodyweight"
        }
        return [PulsarEquipment(name: displayName)]
    }

    private nonisolated static func instructions(from dto: ExercisesDatasetExerciseDTO) -> String? {
        let steps = dto.instructionSteps["en"]?.normalizedCatalogValues ?? []
        if !steps.isEmpty {
            return steps.joined(separator: "\n\n")
        }

        return dto.instructions["en"].cleanedCatalogValue
    }

    private nonisolated static func group(
        forBodyPart bodyPart: String?,
        target: String?,
        muscleGroup: String?
    ) -> PulsarMuscleGroup {
        let targetGroup = [target, muscleGroup]
            .compactMap { $0 }
            .map(group(forMuscleName:))
            .first { $0 != .other }
        if let targetGroup {
            return targetGroup
        }

        switch bodyPart?.normalizedCatalogKey {
        case .some("back"):
            return .back
        case .some("cardio"):
            return .cardioConditioning
        case .some("chest"):
            return .chest
        case .some("lower arms"):
            return .forearms
        case .some("lower legs"):
            return .calves
        case .some("neck"):
            return .neckTraps
        case .some("shoulders"):
            return .shoulders
        case .some("upper arms"):
            return .biceps
        case .some("upper legs"):
            return .quadriceps
        case .some("waist"):
            return .absCore
        default:
            return .other
        }
    }

    private nonisolated static func group(forMuscleName rawName: String) -> PulsarMuscleGroup {
        let name = rawName.normalizedCatalogKey

        if name.contains("abductor") { return .abductors }
        if name.contains("adductor") || name.contains("groin") || name.contains("inner thigh") { return .adductors }
        if name.contains("abs") || name.contains("abdominal") || name.contains("oblique") || name.contains("core") || name.contains("hip flexor") { return .absCore }
        if name.contains("biceps") || name.contains("brachialis") { return .biceps }
        if name.contains("calves") || name.contains("soleus") { return .calves }
        if name.contains("chest") || name.contains("pectoral") || name.contains("serratus") { return .chest }
        if name.contains("deltoid") || name.contains("delt") || name.contains("shoulder") || name.contains("rotator cuff") { return .shoulders }
        if name.contains("forearm") || name.contains("wrist") || name.contains("hand") || name.contains("grip") || name.contains("lower arm") { return .forearms }
        if name.contains("glute") { return .glutes }
        if name.contains("hamstring") { return .hamstrings }
        if name.contains("latissimus") || name == "lats" { return .lats }
        if name.contains("lower back") || name.contains("spine") { return .lowerBack }
        if name.contains("quadriceps") || name.contains("quads") { return .quadriceps }
        if name.contains("rhomboid") || name.contains("upper back") { return .upperMiddleBack }
        if name.contains("trapezius") || name == "traps" { return .traps }
        if name.contains("triceps") { return .triceps }
        if name.contains("cardio") || name.contains("cardiovascular") { return .cardioConditioning }
        if name.contains("neck") || name.contains("levator scapulae") || name.contains("sternocleidomastoid") { return .neckTraps }
        return .other
    }

    private nonisolated static func displayName(_ value: String?) -> String? {
        displayValue(value)
    }

    private nonisolated static func displayValue(_ value: String?) -> String? {
        value.cleanedCatalogValue.map(displayValue)
    }

    private nonisolated static func displayValue(_ value: String) -> String {
        switch value.normalizedCatalogKey {
        case "abs":
            return "Abs"
        case "body weight":
            return "Bodyweight"
        case "cardiovascular system":
            return "Cardiovascular System"
        case "delts":
            return "Delts"
        case "ez barbell":
            return "EZ Barbell"
        case "lats":
            return "Lats"
        case "quads":
            return "Quads"
        case "skierg machine":
            return "SkiErg Machine"
        default:
            return value.catalogTitleCased()
        }
    }
}

typealias FreeExerciseDBService = ExercisesDatasetService
typealias FreeExerciseDBServiceError = ExercisesDatasetServiceError

private extension KeyedDecodingContainer {
    func decodeLossyStringArray(forKey key: Key) -> [String] {
        (try? decodeIfPresent([String].self, forKey: key)) ?? []
    }
}

private extension Optional where Wrapped == String {
    nonisolated var cleanedCatalogValue: String? {
        guard let self else { return nil }
        let cleaned = self
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

private extension Array where Element == String {
    nonisolated var normalizedCatalogValues: [String] {
        var seen = Set<String>()
        return compactMap { Optional($0).cleanedCatalogValue }
            .filter { value in
                seen.insert(value.normalizedCatalogKey).inserted
            }
    }
}

private extension String {
    nonisolated var normalizedCatalogKey: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[_\\-]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated func catalogTitleCased() -> String {
        let uppercaseWords: Set<String> = ["ai", "bmi", "ez", "hiit", "it", "tr"]
        return normalizedCatalogKey
            .split(separator: " ")
            .map { word in
                let rawWord = String(word)
                if uppercaseWords.contains(rawWord) {
                    return rawWord.uppercased()
                }
                return rawWord.prefix(1).uppercased() + rawWord.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}

private extension Array {
    nonisolated func uniqued<ID: Hashable>(by keyPath: KeyPath<Element, ID>) -> [Element] {
        var seen = Set<ID>()
        var result: [Element] = []
        for item in self where seen.insert(item[keyPath: keyPath]).inserted {
            result.append(item)
        }
        return result
    }
}
