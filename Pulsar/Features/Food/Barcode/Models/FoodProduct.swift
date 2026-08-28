import Foundation

nonisolated struct FoodProduct: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var barcode: String?
    var originalBarcode: String?
    var name: String
    var genericName: String?
    var brand: String?
    var countryCode: String?
    var packageQuantity: Double?
    var packageUnit: String?
    var serving: FoodServing?
    var servingsPerContainer: Double?
    var servingIsEstimated: Bool
    var frontImageURL: URL?
    var nutritionImageURL: URL?
    var ingredientsImageURL: URL?
    var ingredients: String?
    var allergens: [String]
    var source: FoodProductSource
    var sourceProductID: String?
    var sourceDatasetVersion: String?
    var sourceURL: URL?
    var sourceReferences: [FoodSourceReference]
    var provenanceClass: FoodProvenanceClass?
    var sourceConfidence: Double?
    var isAIEstimated: Bool?
    var foodType: OpenNutritionFoodType?
    var alternateNames: [String]
    var sourceUpdatedAt: Date?
    var verificationStatus: FoodVerificationStatus
    var verificationCount: Int
    var verifiedAt: Date?
    var nutrients: [FoodNutrient]
    var sourcePayload: Data?
    var createdAt: Date?
    var updatedAt: Date?

    init(
        id: UUID = UUID(),
        barcode: String? = nil,
        originalBarcode: String? = nil,
        name: String,
        genericName: String? = nil,
        brand: String? = nil,
        countryCode: String? = nil,
        packageQuantity: Double? = nil,
        packageUnit: String? = nil,
        serving: FoodServing? = nil,
        servingsPerContainer: Double? = nil,
        servingIsEstimated: Bool = false,
        frontImageURL: URL? = nil,
        nutritionImageURL: URL? = nil,
        ingredientsImageURL: URL? = nil,
        ingredients: String? = nil,
        allergens: [String] = [],
        source: FoodProductSource,
        sourceProductID: String? = nil,
        sourceDatasetVersion: String? = nil,
        sourceURL: URL? = nil,
        sourceReferences: [FoodSourceReference] = [],
        provenanceClass: FoodProvenanceClass? = nil,
        sourceConfidence: Double? = nil,
        isAIEstimated: Bool? = nil,
        foodType: OpenNutritionFoodType? = nil,
        alternateNames: [String] = [],
        sourceUpdatedAt: Date? = nil,
        verificationStatus: FoodVerificationStatus,
        verificationCount: Int = 0,
        verifiedAt: Date? = nil,
        nutrients: [FoodNutrient],
        sourcePayload: Data? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.barcode = barcode
        self.originalBarcode = originalBarcode
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.genericName = genericName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.brand = brand?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.countryCode = countryCode
        self.packageQuantity = packageQuantity
        self.packageUnit = packageUnit
        self.serving = serving
        self.servingsPerContainer = servingsPerContainer.map { max($0, 0) }
        self.servingIsEstimated = servingIsEstimated
        self.frontImageURL = frontImageURL
        self.nutritionImageURL = nutritionImageURL
        self.ingredientsImageURL = ingredientsImageURL
        self.ingredients = ingredients?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.allergens = allergens
        self.source = source
        self.sourceProductID = sourceProductID
        self.sourceDatasetVersion = sourceDatasetVersion
        self.sourceURL = sourceURL
        self.sourceReferences = sourceReferences
        self.provenanceClass = provenanceClass
        self.sourceConfidence = sourceConfidence
        self.isAIEstimated = isAIEstimated
        self.foodType = foodType
        self.alternateNames = alternateNames
        self.sourceUpdatedAt = sourceUpdatedAt
        self.verificationStatus = verificationStatus
        self.verificationCount = max(verificationCount, 0)
        self.verifiedAt = verifiedAt
        self.nutrients = nutrients
        self.sourcePayload = sourcePayload
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isComplete: Bool {
        !name.isEmpty && FoodNutrientKey.essentials.allSatisfy { nutrient(for: $0) != nil }
    }

    var missingEssentialNutrients: [FoodNutrientKey] {
        FoodNutrientKey.essentials.filter { nutrient(for: $0) == nil }.sorted { $0.rawValue < $1.rawValue }
    }

    var requiresOpenNutritionAttribution: Bool { source == .openNutrition }

    var requiresOpenFoodFactsAttribution: Bool {
        source == .openFoodFacts || sourceReferences.contains(where: \.isOpenFoodFacts)
    }

    var estimationDisclosure: String? {
        if isAIEstimated == true { return "OpenNutrition marks this record as estimated." }
        if isAIEstimated == nil, source == .openNutrition {
            return "This dataset release does not provide a record-level AI-estimation flag or confidence score."
        }
        return nil
    }

    func nutrient(for key: FoodNutrientKey, preferredBasis: FoodNutrientBasis? = nil) -> FoodNutrient? {
        let matches = nutrients.filter { $0.key == key }
        if let preferredBasis, let exact = matches.first(where: { $0.basis == preferredBasis }) {
            return exact
        }
        return matches.first(where: { $0.basis == .perServing })
            ?? matches.first(where: { $0.basis == .per100Grams })
            ?? matches.first(where: { $0.basis == .per100Milliliters })
            ?? matches.first
    }

    func nutrientAmount(_ key: FoodNutrientKey, servingMultiplier: Double) -> Double? {
        guard servingMultiplier.isFinite, servingMultiplier > 0,
              let servingOptions = ProductServingOptions(product: self) else { return nil }
        return ProductNutritionCalculator(product: self)
            .calculate(option: servingOptions.defaultOption, quantity: servingMultiplier)?
            .amount(for: key)
    }

    @MainActor
    func pulsarFoodItem() -> PulsarFoodItem? {
        guard let servingOptions = ProductServingOptions(product: self),
              let calculation = ProductNutritionCalculator(product: self)
                .calculate(option: servingOptions.defaultOption, quantity: 1) else { return nil }
        return calculation.foodItem(for: self)
    }
}

nonisolated enum OpenNutritionFoodType: String, Codable, Hashable, Sendable {
    case everyday, grocery, prepared, restaurant
}

nonisolated enum FoodProvenanceClass: String, Codable, Hashable, Sendable {
    case authoritativeDatabase = "authoritative_database"
    case unknownProvenance = "unknown_provenance"
}

nonisolated struct FoodSourceReference: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var reference: String?
    var database: String?
    var name: String?
    var url: URL?

    var isOpenFoodFacts: Bool {
        [database, name].compactMap { $0?.lowercased() }.contains { $0.contains("open food facts") }
    }

    private enum CodingKeys: String, CodingKey { case id, reference, database, name, url }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stringID = try? container.decode(String.self, forKey: .id) {
            id = stringID
        } else if let integerID = try? container.decode(Int.self, forKey: .id) {
            id = String(integerID)
        } else {
            id = UUID().uuidString
        }
        reference = try container.decodeIfPresent(String.self, forKey: .reference)
        database = try container.decodeIfPresent(String.self, forKey: .database)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        url = try container.decodeIfPresent(URL.self, forKey: .url)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(reference, forKey: .reference)
        try container.encodeIfPresent(database, forKey: .database)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(url, forKey: .url)
    }
}
