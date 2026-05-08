//
//  WgerExerciseService.swift
//  Pulsar
//

import Foundation

enum WgerExerciseServiceError: LocalizedError {
    case invalidResponse
    case invalidStatusCode(Int)
    case emptyCatalog

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The exercise catalog returned an unreadable response."
        case .invalidStatusCode(let statusCode):
            "The exercise catalog is temporarily unavailable. Status \(statusCode)."
        case .emptyCatalog:
            "No exercises were returned by the catalog."
        }
    }
}

struct WgerExerciseService {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: URL = URL(string: "https://wger.de/api/v2/")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = JSONDecoder()
    }

    func fetchAllExercises() async throws -> [PulsarExercise] {
        var nextURL: URL? = endpointURL(path: "exerciseinfo/", queryItems: [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "language", value: "2"),
            URLQueryItem(name: "limit", value: "100")
        ])
        var pageCount = 0
        var exercises: [PulsarExercise] = []

        while let url = nextURL {
            try Task.checkCancellation()
            pageCount += 1

            let page: WgerPaginatedResponse<WgerExerciseInfoDTO> = try await fetch(url)
            exercises.append(contentsOf: page.results.compactMap(WgerExerciseNormalizer.normalize))

            if let next = page.next, !next.isEmpty, pageCount < 80 {
                nextURL = URL(string: next)
            } else {
                nextURL = nil
            }
        }

        let normalized = exercises
            .uniqued(by: \.id)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        guard !normalized.isEmpty else { throw WgerExerciseServiceError.emptyCatalog }
        return normalized
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WgerExerciseServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw WgerExerciseServiceError.invalidStatusCode(httpResponse.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }

    private func endpointURL(path: String, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        return components.url!
    }
}

private struct WgerPaginatedResponse<Result: Decodable>: Decodable {
    var count: Int?
    var next: String?
    var previous: String?
    var results: [Result]
}

private struct WgerExerciseInfoDTO: Decodable {
    var id: Int?
    var idText: String?
    var uuid: String?
    var name: String?
    var description: String?
    var category: WgerNamedDTO?
    var muscles: [WgerMuscleDTO]
    var musclesSecondary: [WgerMuscleDTO]
    var equipment: [WgerNamedDTO]
    var images: [WgerExerciseImageDTO]
    var translations: [WgerTranslationDTO]
    var licenseAuthor: String?
    var licenseTitle: String?
    var licenseObjectURL: String?
    var licenseAuthorURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case name
        case description
        case category
        case muscles
        case musclesSecondary = "muscles_secondary"
        case equipment
        case images
        case translations
        case licenseAuthor = "license_author"
        case licenseTitle = "license_title"
        case licenseObjectURL = "license_object_url"
        case licenseAuthorURL = "license_author_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleInt(forKey: .id)
        idText = container.decodeFlexibleString(forKey: .id)
        uuid = container.decodeFlexibleString(forKey: .uuid)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        category = try? container.decodeIfPresent(WgerNamedDTO.self, forKey: .category)
        muscles = container.decodeLossyArray(WgerMuscleDTO.self, forKey: .muscles)
        musclesSecondary = container.decodeLossyArray(WgerMuscleDTO.self, forKey: .musclesSecondary)
        equipment = container.decodeLossyArray(WgerNamedDTO.self, forKey: .equipment)
        images = container.decodeLossyArray(WgerExerciseImageDTO.self, forKey: .images)
        translations = container.decodeLossyArray(WgerTranslationDTO.self, forKey: .translations)
        licenseAuthor = try? container.decodeIfPresent(String.self, forKey: .licenseAuthor)
        licenseTitle = try? container.decodeIfPresent(String.self, forKey: .licenseTitle)
        licenseObjectURL = try? container.decodeIfPresent(String.self, forKey: .licenseObjectURL)
        licenseAuthorURL = try? container.decodeIfPresent(String.self, forKey: .licenseAuthorURL)
    }
}

private struct WgerNamedDTO: Decodable {
    var id: Int?
    var name: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleInt(forKey: .id)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
    }
}

private struct WgerMuscleDTO: Decodable {
    var id: Int?
    var name: String
    var nameEn: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case nameEn = "name_en"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleInt(forKey: .id)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        nameEn = try? container.decodeIfPresent(String.self, forKey: .nameEn)
    }
}

private struct WgerExerciseImageDTO: Decodable {
    var image: String?
    var isMain: Bool
    var licenseTitle: String?
    var licenseObjectURL: String?
    var licenseAuthor: String?
    var licenseAuthorURL: String?

    enum CodingKeys: String, CodingKey {
        case image
        case isMain = "is_main"
        case licenseTitle = "license_title"
        case licenseObjectURL = "license_object_url"
        case licenseAuthor = "license_author"
        case licenseAuthorURL = "license_author_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        image = try? container.decodeIfPresent(String.self, forKey: .image)
        isMain = (try? container.decodeIfPresent(Bool.self, forKey: .isMain)) ?? false
        licenseTitle = try? container.decodeIfPresent(String.self, forKey: .licenseTitle)
        licenseObjectURL = try? container.decodeIfPresent(String.self, forKey: .licenseObjectURL)
        licenseAuthor = try? container.decodeIfPresent(String.self, forKey: .licenseAuthor)
        licenseAuthorURL = try? container.decodeIfPresent(String.self, forKey: .licenseAuthorURL)
    }
}

private struct WgerTranslationDTO: Decodable {
    var id: Int?
    var name: String?
    var description: String?
    var language: Int?
    var licenseTitle: String?
    var licenseObjectURL: String?
    var licenseAuthor: String?
    var licenseAuthorURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case language
        case licenseTitle = "license_title"
        case licenseObjectURL = "license_object_url"
        case licenseAuthor = "license_author"
        case licenseAuthorURL = "license_author_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleInt(forKey: .id)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        language = container.decodeFlexibleInt(forKey: .language)
        licenseTitle = try? container.decodeIfPresent(String.self, forKey: .licenseTitle)
        licenseObjectURL = try? container.decodeIfPresent(String.self, forKey: .licenseObjectURL)
        licenseAuthor = try? container.decodeIfPresent(String.self, forKey: .licenseAuthor)
        licenseAuthorURL = try? container.decodeIfPresent(String.self, forKey: .licenseAuthorURL)
    }
}

private enum WgerExerciseNormalizer {
    static func normalize(_ dto: WgerExerciseInfoDTO) -> PulsarExercise? {
        let preferredTranslation = dto.translations.first { translation in
            translation.language == 2 && !(translation.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? dto.translations.first { translation in
            !(translation.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let name = (preferredTranslation?.name ?? dto.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let primaryMuscles = dto.muscles.map { muscle in
            PulsarMuscle(
                wgerID: muscle.id,
                name: visibleMuscleName(muscle),
                englishName: muscle.nameEn,
                group: group(for: muscle, categoryName: dto.category?.name)
            )
        }
        let secondaryMuscles = dto.musclesSecondary.map { muscle in
            PulsarMuscle(
                wgerID: muscle.id,
                name: visibleMuscleName(muscle),
                englishName: muscle.nameEn,
                group: group(for: muscle, categoryName: dto.category?.name)
            )
        }
        let primaryGroup = primaryMuscles.first?.group ?? group(forCategoryName: dto.category?.name)
        let sortedImages = dto.images.sorted { lhs, rhs in
            if lhs.isMain != rhs.isMain { return lhs.isMain && !rhs.isMain }
            return (lhs.image ?? "") < (rhs.image ?? "")
        }
        let imageURLs = sortedImages.compactMap { absoluteWgerMediaURL($0.image) }
        let attributionImage = sortedImages.first
        let sourceID = dto.uuid ?? dto.idText ?? dto.id.map(String.init)

        // wger exercise data and images carry per-entry Creative Commons metadata.
        // Keep this attribution available wherever the catalog is exported or shown publicly.
        return PulsarExercise(
            id: sourceID.map { "wger-\($0)" } ?? name.normalizedPulsarIdentifier(prefix: "wger"),
            wgerID: dto.id,
            wgerUUID: dto.uuid,
            name: name,
            instructions: cleanHTML(preferredTranslation?.description ?? dto.description),
            primaryMuscles: primaryMuscles,
            secondaryMuscles: secondaryMuscles,
            primaryMuscleGroup: primaryGroup,
            equipment: dto.equipment
                .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { PulsarEquipment(wgerID: $0.id, name: $0.name) },
            imageURLs: imageURLs,
            thumbnailURL: imageURLs.first,
            attribution: .wger(
                sourceExerciseID: sourceID,
                licenseTitle: preferredTranslation?.licenseTitle ?? attributionImage?.licenseTitle ?? dto.licenseTitle,
                licenseObjectURL: preferredTranslation?.licenseObjectURL ?? attributionImage?.licenseObjectURL ?? dto.licenseObjectURL,
                licenseAuthor: preferredTranslation?.licenseAuthor ?? attributionImage?.licenseAuthor ?? dto.licenseAuthor,
                licenseAuthorURL: preferredTranslation?.licenseAuthorURL ?? attributionImage?.licenseAuthorURL ?? dto.licenseAuthorURL
            )
        )
    }

    private static func visibleMuscleName(_ muscle: WgerMuscleDTO) -> String {
        let english = muscle.nameEn?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let english, !english.isEmpty {
            return english
        }
        return muscle.name
    }

    private static func group(for muscle: WgerMuscleDTO, categoryName: String?) -> PulsarMuscleGroup {
        if let id = muscle.id {
            switch id {
            case 1, 13: return .biceps
            case 2: return .shoulders
            case 3, 4: return .chest
            case 5, 7: return .absCore
            case 6, 15: return .calves
            case 8: return .glutes
            case 9, 12: return .back
            case 10: return .quadriceps
            case 11: return .hamstrings
            case 14: return .triceps
            default: break
            }
        }

        let name = "\(muscle.name) \(muscle.nameEn ?? "")".lowercased()
        if name.contains("pector") || name.contains("chest") || name.contains("serratus") { return .chest }
        if name.contains("latissimus") || name.contains("trapezius") || name.contains("back") { return .back }
        if name.contains("deltoid") || name.contains("shoulder") { return .shoulders }
        if name.contains("biceps") || name.contains("brachialis") { return .biceps }
        if name.contains("triceps") { return .triceps }
        if name.contains("forearm") || name.contains("brachioradialis") { return .forearms }
        if name.contains("abdom") || name.contains("oblique") || name.contains("core") { return .absCore }
        if name.contains("glute") { return .glutes }
        if name.contains("quadriceps") { return .quadriceps }
        if name.contains("hamstring") || name.contains("femoris") { return .hamstrings }
        if name.contains("gastrocnemius") || name.contains("soleus") || name.contains("calf") { return .calves }
        if name.contains("adductor") { return .adductors }
        if name.contains("abductor") { return .abductors }
        return group(forCategoryName: categoryName)
    }

    private static func group(forCategoryName name: String?) -> PulsarMuscleGroup {
        let category = (name ?? "").lowercased()
        if category.contains("chest") { return .chest }
        if category.contains("back") { return .back }
        if category.contains("shoulder") { return .shoulders }
        if category.contains("abs") || category.contains("core") { return .absCore }
        if category.contains("calves") { return .calves }
        if category.contains("legs") { return .quadriceps }
        if category.contains("cardio") { return .cardioConditioning }
        if category.contains("arms") { return .fullBody }
        return .other
    }

    private static func absoluteWgerMediaURL(_ rawURL: String?) -> String? {
        guard let rawURL, !rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if rawURL.hasPrefix("http://") || rawURL.hasPrefix("https://") {
            return rawURL
        }
        if rawURL.hasPrefix("/") {
            return "https://wger.de\(rawURL)"
        }
        return "https://wger.de/\(rawURL)"
    }

    private static func cleanHTML(_ html: String?) -> String? {
        guard let html, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var text = html.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleInt(forKey key: Key) -> Int? {
        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return intValue
        }
        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return Int(stringValue)
        }
        return nil
    }

    func decodeFlexibleString(forKey key: Key) -> String? {
        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return stringValue
        }
        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        }
        return nil
    }

    func decodeLossyArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T] {
        (try? decodeIfPresent([T].self, forKey: key)) ?? []
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
