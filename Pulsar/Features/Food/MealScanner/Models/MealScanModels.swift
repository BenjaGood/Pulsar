//
//  MealScanModels.swift
//  Pulsar
//

import Foundation

enum MealScanMode: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case depthAssisted
    case photoOnly
    case singlePlate
    case multiItem
    case packagedMeal
    case leftovers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .depthAssisted:
            "3D Meal Scan"
        case .photoOnly:
            "Photo Scan"
        case .singlePlate:
            "Single Plate"
        case .multiItem:
            "Multi Item"
        case .packagedMeal:
            "Packaged Meal"
        case .leftovers:
            "Leftovers"
        }
    }

    var subtitle: String {
        switch self {
        case .depthAssisted:
            "Uses LiDAR depth when available for more grounded portion estimates."
        case .photoOnly:
            "Uses a compressed image without depth samples."
        case .singlePlate:
            "Best for one visible plate or bowl."
        case .multiItem:
            "Best for separate meal components."
        case .packagedMeal:
            "Best when label context is visible."
        case .leftovers:
            "Best for partial servings and saved portions."
        }
    }

    var badgeTitle: String {
        switch self {
        case .depthAssisted:
            "Depth"
        case .photoOnly:
            "Photo"
        case .singlePlate:
            "Plate"
        case .multiItem:
            "Items"
        case .packagedMeal:
            "Label"
        case .leftovers:
            "Leftovers"
        }
    }
}

enum MealScanQualityLevel: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case excellent
    case good
    case usable
    case limited
    case insufficient

    var id: String { rawValue }
}

enum MealScanDepthSource: String, Codable, Hashable, Sendable {
    case none
    case sceneDepth
    case smoothedSceneDepth
}

enum MealScanMicronutrientUnit: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case milligrams
    case micrograms
    case grams
    case internationalUnits

    var id: String { rawValue }
}

enum MealIngredientAmbiguityType: String, Codable, Hashable, Sendable {
    case protein
    case sauce
    case topping
    case ingredient
    case unknown
}

struct Micronutrient: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var amount: Double
    var unit: String
    var percentDailyValue: Double?

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        unit: String,
        percentDailyValue: Double? = nil
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.amount = max(0, amount)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        self.unit = trimmedUnit.isEmpty ? "mg" : trimmedUnit
        self.percentDailyValue = percentDailyValue.map { max(0, $0) }
    }

    init(
        id: UUID = UUID(),
        name: String,
        amount: Double,
        unit: MealScanMicronutrientUnit,
        percentDailyValue: Double? = nil
    ) {
        self.init(
            id: id,
            name: name,
            amount: amount,
            unit: unit.displayUnit,
            percentDailyValue: percentDailyValue
        )
    }

    func scaled(by multiplier: Double) -> Micronutrient {
        Micronutrient(
            id: id,
            name: name,
            amount: amount * max(0, multiplier),
            unit: unit,
            percentDailyValue: percentDailyValue.map { $0 * max(0, multiplier) }
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case amount
        case unit
        case percentDailyValue
        case percent_daily_value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: (try? container.decode(UUID.self, forKey: .id)) ?? UUID(),
            name: (try? container.decode(String.self, forKey: .name)) ?? "Micronutrient",
            amount: try container.decodeFirstDouble(.amount) ?? 0,
            unit: (try? container.decode(String.self, forKey: .unit)) ?? "mg",
            percentDailyValue: try container.decodeFirstDouble(.percentDailyValue, .percent_daily_value)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(amount, forKey: .amount)
        try container.encode(unit, forKey: .unit)
        try container.encodeIfPresent(percentDailyValue, forKey: .percentDailyValue)
    }
}

extension MealScanMicronutrientUnit {
    var displayUnit: String {
        switch self {
        case .milligrams: "mg"
        case .micrograms: "mcg"
        case .grams: "g"
        case .internationalUnits: "IU"
        }
    }
}

struct MealNutritionTotals: Codable, Hashable, Sendable {
    var calories: Double
    var proteinGrams: Double
    var carbohydrateGrams: Double
    var fatGrams: Double
    var fiberGrams: Double
    var sugarGrams: Double
    var sodiumMilligrams: Double

    init(
        calories: Double = 0,
        proteinGrams: Double = 0,
        carbohydrateGrams: Double = 0,
        fatGrams: Double = 0,
        fiberGrams: Double = 0,
        sugarGrams: Double = 0,
        sodiumMilligrams: Double = 0
    ) {
        self.calories = max(0, calories)
        self.proteinGrams = max(0, proteinGrams)
        self.carbohydrateGrams = max(0, carbohydrateGrams)
        self.fatGrams = max(0, fatGrams)
        self.fiberGrams = max(0, fiberGrams)
        self.sugarGrams = max(0, sugarGrams)
        self.sodiumMilligrams = max(0, sodiumMilligrams)
    }

    static let zero = MealNutritionTotals()

    func scaled(by multiplier: Double) -> MealNutritionTotals {
        MealNutritionTotals(
            calories: calories * multiplier,
            proteinGrams: proteinGrams * multiplier,
            carbohydrateGrams: carbohydrateGrams * multiplier,
            fatGrams: fatGrams * multiplier,
            fiberGrams: fiberGrams * multiplier,
            sugarGrams: sugarGrams * multiplier,
            sodiumMilligrams: sodiumMilligrams * multiplier
        )
    }

    static func + (lhs: MealNutritionTotals, rhs: MealNutritionTotals) -> MealNutritionTotals {
        MealNutritionTotals(
            calories: lhs.calories + rhs.calories,
            proteinGrams: lhs.proteinGrams + rhs.proteinGrams,
            carbohydrateGrams: lhs.carbohydrateGrams + rhs.carbohydrateGrams,
            fatGrams: lhs.fatGrams + rhs.fatGrams,
            fiberGrams: lhs.fiberGrams + rhs.fiberGrams,
            sugarGrams: lhs.sugarGrams + rhs.sugarGrams,
            sodiumMilligrams: lhs.sodiumMilligrams + rhs.sodiumMilligrams
        )
    }

    enum CodingKeys: String, CodingKey {
        case calories
        case proteinGrams
        case protein
        case carbohydrateGrams
        case carbohydrates
        case carbs
        case fatGrams
        case fats
        case fat
        case fiberGrams
        case fiber
        case sugarGrams
        case sugar
        case sodiumMilligrams
        case sodium
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            calories: try container.decodeFirstDouble(.calories) ?? 0,
            proteinGrams: try container.decodeFirstDouble(.proteinGrams, .protein) ?? 0,
            carbohydrateGrams: try container.decodeFirstDouble(.carbohydrateGrams, .carbohydrates, .carbs) ?? 0,
            fatGrams: try container.decodeFirstDouble(.fatGrams, .fats, .fat) ?? 0,
            fiberGrams: try container.decodeFirstDouble(.fiberGrams, .fiber) ?? 0,
            sugarGrams: try container.decodeFirstDouble(.sugarGrams, .sugar) ?? 0,
            sodiumMilligrams: try container.decodeFirstDouble(.sodiumMilligrams, .sodium) ?? 0
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(calories, forKey: .calories)
        try container.encode(proteinGrams, forKey: .proteinGrams)
        try container.encode(carbohydrateGrams, forKey: .carbohydrateGrams)
        try container.encode(fatGrams, forKey: .fatGrams)
        try container.encode(fiberGrams, forKey: .fiberGrams)
        try container.encode(sugarGrams, forKey: .sugarGrams)
        try container.encode(sodiumMilligrams, forKey: .sodiumMilligrams)
    }
}

struct MealIngredient: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var grams: Double
    var estimatedVolumeMilliliters: Double?
    var densityUsed: Double?
    var gramsLow: Double?
    var gramsHigh: Double?
    var nutrition: MealNutritionTotals
    var micronutrients: [Micronutrient]
    var confidence: Double
    var regionID: UUID?
    var reasoning: String?
    var notes: String?
    var isAmbiguous: Bool?
    var ambiguityType: MealIngredientAmbiguityType?
    var clarificationQuestion: String?
    var suggestions: [String]?
    var visualEvidence: String?
    var requiresUserConfirmation: Bool?
    var originalName: String?
    var userResolvedName: String?
    var wasUserCorrected: Bool
    var nutritionNeedsRecalculation: Bool
    var wasKeptAsUnknown: Bool

    init(
        id: UUID = UUID(),
        name: String,
        grams: Double,
        estimatedVolumeMilliliters: Double? = nil,
        densityUsed: Double? = nil,
        gramsLow: Double? = nil,
        gramsHigh: Double? = nil,
        nutrition: MealNutritionTotals,
        micronutrients: [Micronutrient] = [],
        confidence: Double = 0,
        regionID: UUID? = nil,
        reasoning: String? = nil,
        notes: String? = nil,
        isAmbiguous: Bool? = nil,
        ambiguityType: MealIngredientAmbiguityType? = nil,
        clarificationQuestion: String? = nil,
        suggestions: [String]? = nil,
        visualEvidence: String? = nil,
        requiresUserConfirmation: Bool? = nil,
        originalName: String? = nil,
        userResolvedName: String? = nil,
        wasUserCorrected: Bool = false,
        nutritionNeedsRecalculation: Bool = false,
        wasKeptAsUnknown: Bool = false
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.grams = max(0, grams)
        self.estimatedVolumeMilliliters = estimatedVolumeMilliliters.map { max(0, $0) }
        self.densityUsed = densityUsed.map { max(0, $0) }
        self.gramsLow = gramsLow.map { max(0, $0) }
        self.gramsHigh = gramsHigh.map { max(0, $0) }
        self.nutrition = nutrition
        self.micronutrients = micronutrients
        self.confidence = min(max(confidence, 0), 1)
        self.regionID = regionID
        self.reasoning = reasoning?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isAmbiguous = isAmbiguous
        self.ambiguityType = ambiguityType
        self.clarificationQuestion = clarificationQuestion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedSuggestions = suggestions?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.suggestions = sanitizedSuggestions?.isEmpty == true ? nil : sanitizedSuggestions
        self.visualEvidence = visualEvidence?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.requiresUserConfirmation = requiresUserConfirmation
        self.originalName = originalName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.userResolvedName = userResolvedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.wasUserCorrected = wasUserCorrected
        self.nutritionNeedsRecalculation = nutritionNeedsRecalculation
        self.wasKeptAsUnknown = wasKeptAsUnknown
    }

    var estimatedGrams: Double {
        get { grams }
        set { setGramsProportionally(newValue) }
    }

    var calories: Double { nutrition.calories }
    var carbs: Double { nutrition.carbohydrateGrams }
    var protein: Double { nutrition.proteinGrams }
    var fat: Double { nutrition.fatGrams }
    var fiber: Double { nutrition.fiberGrams }
    var sugar: Double { nutrition.sugarGrams }
    var sodium: Double { nutrition.sodiumMilligrams }
    var proteinGrams: Double { nutrition.proteinGrams }
    var carbohydrateGrams: Double { nutrition.carbohydrateGrams }
    var fatGrams: Double { nutrition.fatGrams }
    var fiberGrams: Double { nutrition.fiberGrams }
    var sugarGrams: Double { nutrition.sugarGrams }
    var sodiumMilligrams: Double { nutrition.sodiumMilligrams }

    func scaled(toGrams newGrams: Double) -> MealIngredient {
        let clampedGrams = max(0, newGrams)
        let multiplier = grams > 0 ? clampedGrams / grams : 0

        return MealIngredient(
            id: id,
            name: name,
            grams: clampedGrams,
            estimatedVolumeMilliliters: estimatedVolumeMilliliters.map { $0 * multiplier },
            densityUsed: densityUsed,
            gramsLow: gramsLow.map { $0 * multiplier },
            gramsHigh: gramsHigh.map { $0 * multiplier },
            nutrition: nutrition.scaled(by: multiplier),
            micronutrients: micronutrients.map { $0.scaled(by: multiplier) },
            confidence: confidence,
            regionID: regionID,
            reasoning: reasoning,
            notes: notes,
            isAmbiguous: isAmbiguous,
            ambiguityType: ambiguityType,
            clarificationQuestion: clarificationQuestion,
            suggestions: suggestions,
            visualEvidence: visualEvidence,
            requiresUserConfirmation: requiresUserConfirmation,
            originalName: originalName,
            userResolvedName: userResolvedName,
            wasUserCorrected: wasUserCorrected,
            nutritionNeedsRecalculation: nutritionNeedsRecalculation,
            wasKeptAsUnknown: wasKeptAsUnknown
        )
    }

    mutating func setGramsProportionally(_ newGrams: Double) {
        self = scaled(toGrams: newGrams)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case grams
        case estimatedGrams
        case estimated_grams
        case estimatedVolumeMilliliters
        case estimated_volume_milliliters
        case densityUsed
        case density_used
        case gramsLow
        case grams_low
        case gramsHigh
        case grams_high
        case nutrition
        case calories
        case carbs
        case carbohydrates
        case protein
        case fat
        case fats
        case fiber
        case sugar
        case sodium
        case micronutrients
        case confidence
        case regionID
        case region_id
        case reasoning
        case notes
        case isAmbiguous
        case is_ambiguous
        case ambiguityType
        case ambiguity_type
        case clarificationQuestion
        case clarification_question
        case suggestions
        case visualEvidence
        case visual_evidence
        case requiresUserConfirmation
        case requires_user_confirmation
        case originalName
        case original_name
        case userResolvedName
        case user_resolved_name
        case wasUserCorrected
        case was_user_corrected
        case nutritionNeedsRecalculation
        case nutrition_needs_recalculation
        case wasKeptAsUnknown
        case was_kept_as_unknown
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedNutrition = try container.decodeIfPresent(MealNutritionTotals.self, forKey: .nutrition)
        let nutrition: MealNutritionTotals
        if let decodedNutrition {
            nutrition = decodedNutrition
        } else {
            nutrition = MealNutritionTotals(
                calories: try container.decodeFirstDouble(.calories) ?? 0,
                proteinGrams: try container.decodeFirstDouble(.protein) ?? 0,
                carbohydrateGrams: try container.decodeFirstDouble(.carbs, .carbohydrates) ?? 0,
                fatGrams: try container.decodeFirstDouble(.fat, .fats) ?? 0,
                fiberGrams: try container.decodeFirstDouble(.fiber) ?? 0,
                sugarGrams: try container.decodeFirstDouble(.sugar) ?? 0,
                sodiumMilligrams: try container.decodeFirstDouble(.sodium) ?? 0
            )
        }
        self.init(
            id: (try? container.decode(UUID.self, forKey: .id)) ?? UUID(),
            name: (try? container.decode(String.self, forKey: .name)) ?? "Detected food",
            grams: try container.decodeFirstDouble(.estimatedGrams, .estimated_grams, .grams) ?? 0,
            estimatedVolumeMilliliters: try container.decodeFirstDouble(.estimatedVolumeMilliliters, .estimated_volume_milliliters),
            densityUsed: try container.decodeFirstDouble(.densityUsed, .density_used),
            gramsLow: try container.decodeFirstDouble(.gramsLow, .grams_low),
            gramsHigh: try container.decodeFirstDouble(.gramsHigh, .grams_high),
            nutrition: nutrition,
            micronutrients: (try? container.decode([Micronutrient].self, forKey: .micronutrients)) ?? [],
            confidence: try container.decodeFirstDouble(.confidence) ?? 0,
            regionID: (try? container.decode(UUID.self, forKey: .regionID))
                ?? (try? container.decode(UUID.self, forKey: .region_id)),
            reasoning: try? container.decode(String.self, forKey: .reasoning),
            notes: try? container.decode(String.self, forKey: .notes),
            isAmbiguous: (try? container.decode(Bool.self, forKey: .isAmbiguous))
                ?? (try? container.decode(Bool.self, forKey: .is_ambiguous)),
            ambiguityType: (try? container.decode(MealIngredientAmbiguityType.self, forKey: .ambiguityType))
                ?? (try? container.decode(MealIngredientAmbiguityType.self, forKey: .ambiguity_type)),
            clarificationQuestion: (try? container.decode(String.self, forKey: .clarificationQuestion))
                ?? (try? container.decode(String.self, forKey: .clarification_question)),
            suggestions: try? container.decode([String].self, forKey: .suggestions),
            visualEvidence: (try? container.decode(String.self, forKey: .visualEvidence))
                ?? (try? container.decode(String.self, forKey: .visual_evidence)),
            requiresUserConfirmation: (try? container.decode(Bool.self, forKey: .requiresUserConfirmation))
                ?? (try? container.decode(Bool.self, forKey: .requires_user_confirmation)),
            originalName: (try? container.decode(String.self, forKey: .originalName))
                ?? (try? container.decode(String.self, forKey: .original_name)),
            userResolvedName: (try? container.decode(String.self, forKey: .userResolvedName))
                ?? (try? container.decode(String.self, forKey: .user_resolved_name)),
            wasUserCorrected: (try? container.decode(Bool.self, forKey: .wasUserCorrected))
                ?? (try? container.decode(Bool.self, forKey: .was_user_corrected))
                ?? false,
            nutritionNeedsRecalculation: (try? container.decode(Bool.self, forKey: .nutritionNeedsRecalculation))
                ?? (try? container.decode(Bool.self, forKey: .nutrition_needs_recalculation))
                ?? false,
            wasKeptAsUnknown: (try? container.decode(Bool.self, forKey: .wasKeptAsUnknown))
                ?? (try? container.decode(Bool.self, forKey: .was_kept_as_unknown))
                ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(grams, forKey: .grams)
        try container.encodeIfPresent(estimatedVolumeMilliliters, forKey: .estimatedVolumeMilliliters)
        try container.encodeIfPresent(densityUsed, forKey: .densityUsed)
        try container.encodeIfPresent(gramsLow, forKey: .gramsLow)
        try container.encodeIfPresent(gramsHigh, forKey: .gramsHigh)
        try container.encode(nutrition, forKey: .nutrition)
        try container.encode(micronutrients, forKey: .micronutrients)
        try container.encode(confidence, forKey: .confidence)
        try container.encodeIfPresent(regionID, forKey: .regionID)
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(isAmbiguous, forKey: .isAmbiguous)
        try container.encodeIfPresent(ambiguityType, forKey: .ambiguityType)
        try container.encodeIfPresent(clarificationQuestion, forKey: .clarificationQuestion)
        try container.encodeIfPresent(suggestions, forKey: .suggestions)
        try container.encodeIfPresent(visualEvidence, forKey: .visualEvidence)
        try container.encodeIfPresent(requiresUserConfirmation, forKey: .requiresUserConfirmation)
        try container.encodeIfPresent(originalName, forKey: .originalName)
        try container.encodeIfPresent(userResolvedName, forKey: .userResolvedName)
        try container.encode(wasUserCorrected, forKey: .wasUserCorrected)
        try container.encode(nutritionNeedsRecalculation, forKey: .nutritionNeedsRecalculation)
        try container.encode(wasKeptAsUnknown, forKey: .wasKeptAsUnknown)
    }
}

extension MealIngredient {
    var resolvedIsAmbiguous: Bool {
        if isAmbiguous == true { return true }
        return Self.detectAmbiguityType(name: name, reasoning: reasoning) != nil
    }

    var resolvedAmbiguityType: MealIngredientAmbiguityType {
        ambiguityType ?? Self.detectAmbiguityType(name: name, reasoning: reasoning) ?? .unknown
    }

    var needsUserClarification: Bool {
        resolvedIsAmbiguous && !wasUserCorrected && !wasKeptAsUnknown
    }

    var mealScannerCanSave: Bool {
        estimatedGrams > 0 && !needsUserClarification
    }

    var ambiguityEvidenceText: String? {
        let evidence = visualEvidence?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let evidence, !evidence.isEmpty { return evidence }
        let reason = reasoning?.trimmingCharacters(in: .whitespacesAndNewlines)
        return reason?.isEmpty == false ? reason : nil
    }

    var ambiguitySuggestions: [String] {
        let backendSuggestions = suggestions?.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
        if !backendSuggestions.isEmpty { return backendSuggestions }
        switch resolvedAmbiguityType {
        case .protein:
            return ["Chicken", "Beef", "Pork", "Fish", "Shrimp", "Tofu", "Egg", "Turkey"]
        case .sauce:
            return ["Salsa", "Cream sauce", "Cheese sauce", "Dressing", "Guacamole"]
        case .topping:
            return ["Onion", "Cilantro", "Cheese", "Tomato", "Avocado"]
        case .ingredient:
            return ["Rice", "Beans", "Vegetables", "Potato", "Bread"]
        case .unknown:
            return ["Chicken", "Beef", "Tofu", "Rice", "Beans"]
        }
    }

    var mealScannerSaveDetail: String {
        if wasKeptAsUnknown {
            return "3D Meal Scanner estimate - needs review"
        }
        if nutritionNeedsRecalculation {
            return "3D Meal Scanner estimate - nutrition pending verification"
        }
        if wasUserCorrected {
            return "3D Meal Scanner estimate - user confirmed"
        }
        return "3D Meal Scanner estimate"
    }

    var mealScannerAuditNote: String? {
        var parts: [String] = []
        if let originalName, originalName.caseInsensitiveCompare(name) != .orderedSame {
            parts.append("Original scan label: \(originalName)")
        }
        if nutritionNeedsRecalculation {
            parts.append("Nutrition pending recalculation; verify portion/type.")
        }
        if wasKeptAsUnknown {
            parts.append("Ingredient kept as unknown by user; needs review.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    func resolvingAmbiguity(as replacementName: String) -> MealIngredient {
        let resolvedName = replacementName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedName.isEmpty else { return self }
        var copy = self
        if copy.originalName?.isEmpty != false {
            copy.originalName = name
        }
        copy.name = resolvedName
        copy.userResolvedName = resolvedName
        copy.wasUserCorrected = true
        copy.wasKeptAsUnknown = false
        copy.nutritionNeedsRecalculation = true
        copy.requiresUserConfirmation = false
        copy.isAmbiguous = false
        return copy
    }

    func keepingAsUnknown() -> MealIngredient {
        var copy = self
        if copy.originalName?.isEmpty != false {
            copy.originalName = name
        }
        copy.wasKeptAsUnknown = true
        copy.wasUserCorrected = false
        copy.requiresUserConfirmation = false
        copy.confidence = min(confidence, 0.35)
        copy.isAmbiguous = true
        copy.notes = Self.appendNote("Needs review: user kept ambiguous scanner label.", to: notes)
        return copy
    }

    /// Phase 3: merges a backend-recalculated ingredient's nutrition into this (already
    /// user-resolved) ingredient. Preserves id, corrected name, and grams; scales the
    /// backend's per-gram nutrition to this ingredient's actual grams so a mismatch
    /// between the requested and returned mass never silently changes the portion size.
    func mergingRecalculatedNutrition(from recalculated: MealIngredient) -> MealIngredient {
        let backendGrams = recalculated.grams > 0 ? recalculated.grams : estimatedGrams
        let scaleFactor = backendGrams > 0 ? estimatedGrams / backendGrams : 1
        var copy = self
        copy.nutrition = recalculated.nutrition.scaled(by: scaleFactor)
        copy.micronutrients = recalculated.micronutrients.map { $0.scaled(by: scaleFactor) }
        copy.densityUsed = recalculated.densityUsed ?? densityUsed
        copy.gramsLow = recalculated.gramsLow.map { $0 * scaleFactor }
        copy.gramsHigh = recalculated.gramsHigh.map { $0 * scaleFactor }
        copy.confidence = max(confidence, recalculated.confidence)
        copy.nutritionNeedsRecalculation = false
        return copy
    }

    func reclassifyingAmbiguityAsGenericIngredient() -> MealIngredient {
        var copy = self
        if copy.originalName?.isEmpty != false {
            copy.originalName = name
        }
        copy.name = "Unspecified ingredient"
        copy.userResolvedName = copy.name
        copy.wasUserCorrected = true
        copy.wasKeptAsUnknown = false
        copy.nutritionNeedsRecalculation = false
        copy.ambiguityType = .ingredient
        copy.requiresUserConfirmation = false
        copy.isAmbiguous = false
        copy.confidence = min(confidence, 0.45)
        copy.notes = Self.appendNote("Reclassified by user as a generic ingredient.", to: notes)
        return copy
    }

    static func detectAmbiguityType(name: String, reasoning: String? = nil) -> MealIngredientAmbiguityType? {
        let haystack = ([name, reasoning ?? ""])
            .joined(separator: " ")
            .lowercased()
        let ambiguousTokens = [
            "unknown",
            "unidentified",
            "unclear",
            "uncertain",
            "type uncertain",
            "generic protein",
            "meat-like",
            "detected food",
            "unknown protein",
            "unknown meat",
            "unknown sauce",
            "unknown topping",
            "unknown ingredient"
        ]
        guard ambiguousTokens.contains(where: { haystack.contains($0) }) else { return nil }
        if haystack.contains("protein")
            || haystack.contains("meat")
            || haystack.contains("poultry")
            || haystack.contains("seafood")
            || haystack.contains("fish") {
            return .protein
        }
        if haystack.contains("sauce") || haystack.contains("dressing") {
            return .sauce
        }
        if haystack.contains("topping") || haystack.contains("garnish") {
            return .topping
        }
        if haystack.contains("detected food") || haystack.contains("ingredient") || haystack.contains("generic") {
            return .ingredient
        }
        return .unknown
    }

    private static func appendNote(_ note: String, to existing: String?) -> String {
        let trimmedExisting = existing?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedExisting, !trimmedExisting.isEmpty else { return note }
        if trimmedExisting.contains(note) { return trimmedExisting }
        return "\(trimmedExisting) \(note)"
    }
}

struct MealScanResult: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var createdAt: Date
    var mode: MealScanMode
    var title: String
    var summary: String
    var ingredients: [MealIngredient]
    var totals: MealNutritionTotals
    var micronutrients: [Micronutrient]
    var notes: [String]
    var accuracyDisclaimer: String
    var quality: MealScanQuality
    var plateEstimate: MealPlateEstimate?
    var foodRegions: [MealFoodRegion]
    var metadata: MealScanResultMetadata

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        mode: MealScanMode = .depthAssisted,
        title: String = "Scanned meal",
        summary: String = "",
        ingredients: [MealIngredient],
        totals: MealNutritionTotals? = nil,
        micronutrients: [Micronutrient] = [],
        notes: [String] = [],
        accuracyDisclaimer: String? = nil,
        quality: MealScanQuality,
        plateEstimate: MealPlateEstimate? = nil,
        foodRegions: [MealFoodRegion] = [],
        metadata: MealScanResultMetadata = MealScanResultMetadata()
    ) {
        self.id = id
        self.createdAt = createdAt
        self.mode = mode
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        self.ingredients = ingredients
        self.totals = totals ?? Self.recomputedTotals(from: ingredients)
        self.micronutrients = micronutrients
        self.notes = notes
        self.accuracyDisclaimer = accuracyDisclaimer ?? metadata.disclaimer
        self.quality = quality
        self.plateEstimate = plateEstimate
        self.foodRegions = foodRegions
        self.metadata = metadata
    }

    func updatingIngredientGrams(id ingredientID: UUID, grams newGrams: Double) -> MealScanResult {
        var copy = self
        copy.updateIngredientGrams(id: ingredientID, grams: newGrams)
        return copy
    }

    var totalEstimatedGrams: Double {
        ingredients.reduce(0) { partial, ingredient in
            partial + ingredient.grams
        }
    }

    var totalCalories: Double { totals.calories }
    var totalCarbs: Double { totals.carbohydrateGrams }
    var totalProtein: Double { totals.proteinGrams }
    var totalFat: Double { totals.fatGrams }
    var totalFiber: Double { totals.fiberGrams }
    var totalSugar: Double { totals.sugarGrams }
    var totalSodium: Double { totals.sodiumMilligrams }
    var confidence: Double { quality.confidence }
    var usesMeasuredDepthForPortionEstimate: Bool { quality.depthContributedToEstimate == true }
    var ambiguousIngredients: [MealIngredient] { ingredients.filter(\.needsUserClarification) }
    var hasUnresolvedAmbiguousIngredients: Bool { !ambiguousIngredients.isEmpty }
    var hasSavableMealScannerIngredients: Bool { ingredients.contains(where: \.mealScannerCanSave) }

    mutating func updateIngredient(id ingredientID: MealIngredient.ID, estimatedGrams: Double) {
        updateIngredientGrams(id: ingredientID, grams: estimatedGrams)
    }

    mutating func updateIngredientGrams(id ingredientID: UUID, grams newGrams: Double) {
        guard let index = ingredients.firstIndex(where: { $0.id == ingredientID }) else { return }
        ingredients[index].setGramsProportionally(newGrams)
        recomputeTotals()
    }

    mutating func updateIngredient(_ ingredient: MealIngredient) {
        guard let index = ingredients.firstIndex(where: { $0.id == ingredient.id }) else { return }
        ingredients[index] = ingredient
        recomputeTotals()
    }

    mutating func recomputeTotals() {
        totals = Self.recomputedTotals(from: ingredients)
    }

    static func recomputedTotals(from ingredients: [MealIngredient]) -> MealNutritionTotals {
        ingredients.reduce(.zero) { partial, ingredient in
            partial + ingredient.nutrition
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case created_at
        case mode
        case title
        case summary
        case ingredients
        case totals
        case totalCalories
        case total_calories
        case totalCarbs
        case total_carbs
        case totalProtein
        case total_protein
        case totalFat
        case total_fat
        case totalFiber
        case total_fiber
        case totalSugar
        case total_sugar
        case totalSodium
        case total_sodium
        case micronutrients
        case notes
        case accuracyDisclaimer
        case accuracy_disclaimer
        case quality
        case confidence
        case plateEstimate
        case plate_estimate
        case foodRegions
        case food_regions
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard Self.containsMealResultSignal(in: container) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "MealScanResult payload did not include meal result fields."
                )
            )
        }
        let ingredients = (try? container.decode([MealIngredient].self, forKey: .ingredients)) ?? []
        let metadata = (try? container.decode(MealScanResultMetadata.self, forKey: .metadata)) ?? MealScanResultMetadata()
        let decodedTotals = try container.decodeIfPresent(MealNutritionTotals.self, forKey: .totals)
        let flatTotals: MealNutritionTotals? = {
            let calories = (try? container.decodeDoubleIfPresent(for: .totalCalories))
                ?? (try? container.decodeDoubleIfPresent(for: .total_calories))
            let protein = (try? container.decodeDoubleIfPresent(for: .totalProtein))
                ?? (try? container.decodeDoubleIfPresent(for: .total_protein))
            let carbs = (try? container.decodeDoubleIfPresent(for: .totalCarbs))
                ?? (try? container.decodeDoubleIfPresent(for: .total_carbs))
            let fat = (try? container.decodeDoubleIfPresent(for: .totalFat))
                ?? (try? container.decodeDoubleIfPresent(for: .total_fat))
            let fiber = (try? container.decodeDoubleIfPresent(for: .totalFiber))
                ?? (try? container.decodeDoubleIfPresent(for: .total_fiber))
            let sugar = (try? container.decodeDoubleIfPresent(for: .totalSugar))
                ?? (try? container.decodeDoubleIfPresent(for: .total_sugar))
            let sodium = (try? container.decodeDoubleIfPresent(for: .totalSodium))
                ?? (try? container.decodeDoubleIfPresent(for: .total_sodium))
            guard calories != nil || protein != nil || carbs != nil || fat != nil || fiber != nil || sugar != nil || sodium != nil else {
                return nil
            }
            return MealNutritionTotals(
                calories: calories ?? 0,
                proteinGrams: protein ?? 0,
                carbohydrateGrams: carbs ?? 0,
                fatGrams: fat ?? 0,
                fiberGrams: fiber ?? 0,
                sugarGrams: sugar ?? 0,
                sodiumMilligrams: sodium ?? 0
            )
        }()
        let fallbackQualityConfidence = try container.decodeFirstDouble(.confidence) ?? 0.5
        let quality = (try? container.decode(MealScanQuality.self, forKey: .quality)) ?? MealScanQuality(
            level: .usable,
            confidence: fallbackQualityConfidence
        )
        self.init(
            id: (try? container.decode(UUID.self, forKey: .id)) ?? UUID(),
            createdAt: (try? container.decode(Date.self, forKey: .createdAt))
                ?? (try? container.decode(Date.self, forKey: .created_at))
                ?? Date(),
            mode: (try? container.decode(MealScanMode.self, forKey: .mode)) ?? .depthAssisted,
            title: (try? container.decode(String.self, forKey: .title)) ?? "Scanned meal",
            summary: (try? container.decode(String.self, forKey: .summary)) ?? "",
            ingredients: ingredients,
            totals: decodedTotals ?? flatTotals,
            micronutrients: (try? container.decode([Micronutrient].self, forKey: .micronutrients)) ?? [],
            notes: (try? container.decode([String].self, forKey: .notes)) ?? [],
            accuracyDisclaimer: (try? container.decode(String.self, forKey: .accuracyDisclaimer))
                ?? (try? container.decode(String.self, forKey: .accuracy_disclaimer)),
            quality: quality,
            plateEstimate: (try? container.decode(MealPlateEstimate.self, forKey: .plateEstimate))
                ?? (try? container.decode(MealPlateEstimate.self, forKey: .plate_estimate)),
            foodRegions: (try? container.decode([MealFoodRegion].self, forKey: .foodRegions))
                ?? (try? container.decode([MealFoodRegion].self, forKey: .food_regions))
                ?? [],
            metadata: metadata
        )
    }

    private static func containsMealResultSignal(in container: KeyedDecodingContainer<CodingKeys>) -> Bool {
        [
            .title,
            .ingredients,
            .totals,
            .totalCalories,
            .total_calories,
            .totalCarbs,
            .total_carbs,
            .totalProtein,
            .total_protein,
            .totalFat,
            .total_fat,
            .totalFiber,
            .total_fiber,
            .totalSugar,
            .total_sugar,
            .totalSodium,
            .total_sodium,
            .micronutrients,
            .quality,
            .plateEstimate,
            .plate_estimate,
            .foodRegions,
            .food_regions
        ].contains { container.contains($0) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(mode, forKey: .mode)
        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        try container.encode(ingredients, forKey: .ingredients)
        try container.encode(totals, forKey: .totals)
        try container.encode(micronutrients, forKey: .micronutrients)
        try container.encode(notes, forKey: .notes)
        try container.encode(accuracyDisclaimer, forKey: .accuracyDisclaimer)
        try container.encode(quality, forKey: .quality)
        try container.encodeIfPresent(plateEstimate, forKey: .plateEstimate)
        try container.encode(foodRegions, forKey: .foodRegions)
        try container.encode(metadata, forKey: .metadata)
    }
}

struct MealScanResultMetadata: Codable, Hashable, Sendable {
    var modelName: String?
    var backendVersion: String?
    var disclaimer: String
    var estimatedOnly: Bool
    var needsUserReview: Bool

    init(
        modelName: String? = nil,
        backendVersion: String? = nil,
        disclaimer: String = "Meal scanner nutrition is an estimate. Confirm portions before logging.",
        estimatedOnly: Bool = true,
        needsUserReview: Bool = true
    ) {
        self.modelName = modelName
        self.backendVersion = backendVersion
        self.disclaimer = disclaimer
        self.estimatedOnly = estimatedOnly
        self.needsUserReview = needsUserReview
    }
}

struct MealScanQuality: Codable, Hashable, Sendable {
    var level: MealScanQualityLevel
    var confidence: Double
    var hasDepth: Bool
    var hasLiDAR: Bool
    var depthContributedToEstimate: Bool?
    var confidenceBreakdown: MealScanConfidenceBreakdown?
    var depthSource: MealScanDepthSource
    var imageSharpnessEstimate: Double?
    var lightingEstimate: Double?
    var occlusionRisk: Double
    var warnings: [String]

    init(
        level: MealScanQualityLevel,
        confidence: Double,
        hasDepth: Bool = false,
        hasLiDAR: Bool = false,
        depthContributedToEstimate: Bool? = nil,
        confidenceBreakdown: MealScanConfidenceBreakdown? = nil,
        depthSource: MealScanDepthSource = .none,
        imageSharpnessEstimate: Double? = nil,
        lightingEstimate: Double? = nil,
        occlusionRisk: Double = 0.5,
        warnings: [String] = []
    ) {
        self.level = level
        self.confidence = min(max(confidence, 0), 1)
        self.hasDepth = hasDepth
        self.hasLiDAR = hasLiDAR
        self.depthContributedToEstimate = depthContributedToEstimate
        self.confidenceBreakdown = confidenceBreakdown
        self.depthSource = depthSource
        self.imageSharpnessEstimate = imageSharpnessEstimate.map { min(max($0, 0), 1) }
        self.lightingEstimate = lightingEstimate.map { min(max($0, 0), 1) }
        self.occlusionRisk = min(max(occlusionRisk, 0), 1)
        self.warnings = warnings
    }
}

struct MealScanConfidenceBreakdown: Codable, Hashable, Sendable {
    var foodRecognition: Double?
    var depthCoverage: Double?
    var portionVolume: Double?
    var density: Double?
    var overall: Double?

    init(
        foodRecognition: Double? = nil,
        depthCoverage: Double? = nil,
        portionVolume: Double? = nil,
        density: Double? = nil,
        overall: Double? = nil
    ) {
        self.foodRecognition = foodRecognition.map { min(max($0, 0), 1) }
        self.depthCoverage = depthCoverage.map { min(max($0, 0), 1) }
        self.portionVolume = portionVolume.map { min(max($0, 0), 1) }
        self.density = density.map { min(max($0, 0), 1) }
        self.overall = overall.map { min(max($0, 0), 1) }
    }
}

struct MealPlateEstimate: Codable, Hashable, Sendable {
    var diameterCentimeters: Double?
    var areaSquareCentimeters: Double?
    var volumeMilliliters: Double?
    var confidence: Double
    var source: String

    init(
        diameterCentimeters: Double? = nil,
        areaSquareCentimeters: Double? = nil,
        volumeMilliliters: Double? = nil,
        confidence: Double,
        source: String
    ) {
        self.diameterCentimeters = diameterCentimeters.map { max(0, $0) }
        self.areaSquareCentimeters = areaSquareCentimeters.map { max(0, $0) }
        self.volumeMilliliters = volumeMilliliters.map { max(0, $0) }
        self.confidence = min(max(confidence, 0), 1)
        self.source = source
    }
}

struct MealFoodRegion: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var label: String?
    var normalizedBoundingBox: MealScanNormalizedRect
    var estimatedGrams: Double?
    var estimatedVolumeMilliliters: Double?
    var confidence: Double

    init(
        id: UUID = UUID(),
        label: String? = nil,
        normalizedBoundingBox: MealScanNormalizedRect,
        estimatedGrams: Double? = nil,
        estimatedVolumeMilliliters: Double? = nil,
        confidence: Double
    ) {
        self.id = id
        self.label = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.normalizedBoundingBox = normalizedBoundingBox
        self.estimatedGrams = estimatedGrams.map { max(0, $0) }
        self.estimatedVolumeMilliliters = estimatedVolumeMilliliters.map { max(0, $0) }
        self.confidence = min(max(confidence, 0), 1)
    }
}

struct MealScanNormalizedRect: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
        self.width = min(max(width, 0), 1)
        self.height = min(max(height, 0), 1)
    }
}

struct MealScanCapturePayload: Codable, Hashable, Sendable {
    var metadata: MealScanCaptureMetadata
    var quality: MealScanQuality
    var depthStats: MealScanDepthStats?
    var camera: MealScanCameraMetadata?
    var plateEstimate: MealPlateEstimate?
    var volumeEstimate: MealVolumeEstimate?
    var foodRegions: [MealFoodRegion]?
    /// Per-food-form calibration correction factors learned from user-confirmed gram measurements.
    /// Keys are food form category strings (e.g. "loose_grains", "solid_protein").
    /// Values are bounded to [0.6, 1.7]. Only non-neutral factors are included.
    var calibrationFactors: [String: Double]?
    var clientHints: [String: String]

    init(
        metadata: MealScanCaptureMetadata,
        quality: MealScanQuality,
        depthStats: MealScanDepthStats? = nil,
        camera: MealScanCameraMetadata? = nil,
        plateEstimate: MealPlateEstimate? = nil,
        volumeEstimate: MealVolumeEstimate? = nil,
        foodRegions: [MealFoodRegion]? = nil,
        calibrationFactors: [String: Double]? = nil,
        clientHints: [String: String] = [:]
    ) {
        self.metadata = metadata
        self.quality = quality
        self.depthStats = depthStats
        self.camera = camera
        self.plateEstimate = plateEstimate
        self.volumeEstimate = volumeEstimate
        self.foodRegions = foodRegions?.isEmpty == true ? nil : foodRegions
        self.calibrationFactors = calibrationFactors.map { dict in
            dict.filter { abs($0.value - 1.0) > 0.03 }
        }.flatMap { $0.isEmpty ? nil : $0 }
        self.clientHints = clientHints
    }
}

typealias MealScanPayload = MealScanCapturePayload

struct MealScanSessionSummary: Hashable, Sendable {
    var photoCaptured: Bool
    var depthScanCompleted: Bool
    var coverageRatio: Double
    var coveredCellRatio: Double
    var depthFrameCount: Int
    var stableFrameCount: Int
    var coverageGridColumns: Int
    var coverageGridRows: Int

    init(
        photoCaptured: Bool,
        depthScanCompleted: Bool,
        coverageRatio: Double,
        coveredCellRatio: Double,
        depthFrameCount: Int,
        stableFrameCount: Int,
        coverageGridColumns: Int,
        coverageGridRows: Int
    ) {
        self.photoCaptured = photoCaptured
        self.depthScanCompleted = depthScanCompleted
        self.coverageRatio = min(max(coverageRatio, 0), 1)
        self.coveredCellRatio = min(max(coveredCellRatio, 0), 1)
        self.depthFrameCount = max(0, depthFrameCount)
        self.stableFrameCount = max(0, stableFrameCount)
        self.coverageGridColumns = max(0, coverageGridColumns)
        self.coverageGridRows = max(0, coverageGridRows)
    }

    var clientHints: [String: String] {
        [
            "photoPhaseCaptured": photoCaptured ? "true" : "false",
            "depthScanCompleted": depthScanCompleted ? "true" : "false",
            "lidarCoverageRatio": String(format: "%.2f", coverageRatio),
            "lidarCoveredCellRatio": String(format: "%.2f", coveredCellRatio),
            "lidarDepthFrameCount": "\(depthFrameCount)",
            "lidarStableFrameCount": "\(stableFrameCount)",
            "lidarCoverageGrid": "\(coverageGridColumns)x\(coverageGridRows)"
        ]
    }
}

struct MealScanCaptureMetadata: Codable, Hashable, Sendable {
    var capturedAt: Date
    var mode: MealScanMode
    var imageWidth: Int
    var imageHeight: Int
    var imageOrientation: String
    var jpegQuality: Double?
    var appFeatureVersion: String

    init(
        capturedAt: Date = Date(),
        mode: MealScanMode,
        imageWidth: Int,
        imageHeight: Int,
        imageOrientation: String,
        jpegQuality: Double? = nil,
        appFeatureVersion: String = "meal-scanner-v1"
    ) {
        self.capturedAt = capturedAt
        self.mode = mode
        self.imageWidth = max(0, imageWidth)
        self.imageHeight = max(0, imageHeight)
        self.imageOrientation = imageOrientation
        self.jpegQuality = jpegQuality.map { min(max($0, 0), 1) }
        self.appFeatureVersion = appFeatureVersion
    }
}

struct MealScanCameraMetadata: Codable, Hashable, Sendable {
    var trackingState: String?
    var exposureDurationSeconds: Double?
    var iso: Float?
    var cameraIntrinsics: [Float]?
    var cameraTransform: [Float]?
    var imageResolutionWidth: Int?
    var imageResolutionHeight: Int?

    init(
        trackingState: String? = nil,
        exposureDurationSeconds: Double? = nil,
        iso: Float? = nil,
        cameraIntrinsics: [Float]? = nil,
        cameraTransform: [Float]? = nil,
        imageResolutionWidth: Int? = nil,
        imageResolutionHeight: Int? = nil
    ) {
        self.trackingState = trackingState
        self.exposureDurationSeconds = exposureDurationSeconds
        self.iso = iso
        self.cameraIntrinsics = cameraIntrinsics
        self.cameraTransform = cameraTransform
        self.imageResolutionWidth = imageResolutionWidth
        self.imageResolutionHeight = imageResolutionHeight
    }
}

struct MealVolumeEstimate: Codable, Hashable, Sendable {
    var volumeMilliliters: Double
    var method: String
    var supportPlaneConfidence: Double
    var coverage: Double
    var uncertaintyMlLow: Double
    var uncertaintyMlHigh: Double
    var frameCount: Int?

    init(
        volumeMilliliters: Double,
        method: String,
        supportPlaneConfidence: Double,
        coverage: Double,
        uncertaintyMlLow: Double,
        uncertaintyMlHigh: Double,
        frameCount: Int? = nil
    ) {
        self.volumeMilliliters = max(0, volumeMilliliters)
        self.method = method.trimmingCharacters(in: .whitespacesAndNewlines)
        self.supportPlaneConfidence = min(max(supportPlaneConfidence, 0), 1)
        self.coverage = min(max(coverage, 0), 1)
        self.uncertaintyMlLow = max(0, uncertaintyMlLow)
        self.uncertaintyMlHigh = max(0, uncertaintyMlHigh)
        self.frameCount = frameCount.map { max(1, $0) }
    }
}

struct MealScanDepthStats: Codable, Hashable, Sendable {
    var source: MealScanDepthSource
    var width: Int
    var height: Int
    var validSampleCount: Int
    var sampledPixelCount: Int
    var minMeters: Float
    var maxMeters: Float
    var meanMeters: Float
    var percentile10Meters: Float
    var percentile50Meters: Float
    var percentile90Meters: Float
    var highConfidenceRatio: Double?

    init(
        source: MealScanDepthSource,
        width: Int,
        height: Int,
        validSampleCount: Int,
        sampledPixelCount: Int,
        minMeters: Float,
        maxMeters: Float,
        meanMeters: Float,
        percentile10Meters: Float,
        percentile50Meters: Float,
        percentile90Meters: Float,
        highConfidenceRatio: Double? = nil
    ) {
        self.source = source
        self.width = max(0, width)
        self.height = max(0, height)
        self.validSampleCount = max(0, validSampleCount)
        self.sampledPixelCount = max(0, sampledPixelCount)
        self.minMeters = max(0, minMeters)
        self.maxMeters = max(0, maxMeters)
        self.meanMeters = max(0, meanMeters)
        self.percentile10Meters = max(0, percentile10Meters)
        self.percentile50Meters = max(0, percentile50Meters)
        self.percentile90Meters = max(0, percentile90Meters)
        self.highConfidenceRatio = highConfidenceRatio.map { min(max($0, 0), 1) }
    }
}

struct MealScanAnalysisRequest: Encodable, Sendable {
    var prompt: String
    var instructions: String
    var imageBase64: String
    var payload: MealScanCapturePayload
}

struct MealScanAnalysisResponse: Decodable, Sendable {
    var result: MealScanResult
}

/// Phase 3: compact context sent alongside a resolve-ingredient request so the backend
/// can (optionally) fold the recalculated ingredient back into honest meal totals.
/// The client always recomputes authoritative totals locally regardless of this context.
struct MealIngredientResolveContext: Encodable, Sendable {
    var mode: MealScanMode? = nil
    var currentMealTotals: MealNutritionTotals? = nil
    var currentIngredientNutrition: MealNutritionTotals? = nil
    var volumeEstimate: MealVolumeEstimate? = nil
    var calibrationFactors: [String: Double]? = nil
}

/// Phase 3: request to recalculate honest nutrition for a single ingredient the user
/// just identified. The backend must not re-downgrade the confirmed identity.
struct MealIngredientResolveRequest: Encodable, Sendable {
    var ingredientId: String
    var originalName: String
    var replacementName: String
    var grams: Double
    var ambiguityType: String
    var recalculateNutrition: Bool = true
    var payloadContext: MealIngredientResolveContext? = nil
    var imageBase64: String? = nil
}

/// Phase 3: backend response carrying the recalculated ingredient. `updatedMealTotals`
/// is advisory only; the client always calls `MealScanResult.recomputeTotals()` after
/// merging `updatedIngredient` so totals stay authoritative on-device.
struct MealIngredientResolveResponse: Decodable, Sendable {
    var updatedIngredient: MealIngredient
    var updatedMealTotals: MealNutritionTotals?
}

private extension KeyedDecodingContainer {
    func decodeFirstDouble(_ keys: Key...) throws -> Double? {
        for key in keys {
            if let value = try decodeDoubleIfPresent(for: key) {
                return value
            }
        }
        return nil
    }

    func decodeDoubleIfPresent(for key: Key) throws -> Double? {
        if let value = try decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try decodeIfPresent(String.self, forKey: key) {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}
