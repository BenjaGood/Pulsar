//
//  PulsarNutritionModels.swift
//  Pulsar
//

import Foundation

enum PulsarNutritionMealMoment: String, CaseIterable, Codable, Identifiable, Hashable {
    case breakfast
    case lunch
    case dinner
    case snacks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snacks: "Snacks"
        }
    }

    var subtitle: String {
        switch self {
        case .breakfast: "Start steady"
        case .lunch: "Midday fuel"
        case .dinner: "Evening balance"
        case .snacks: "Small moments"
        }
    }

    var symbolName: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snacks: "leaf.fill"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "morning":
            self = .breakfast
        case "midday":
            self = .lunch
        case "evening":
            self = .dinner
        case "snack", "recovery":
            self = .snacks
        default:
            guard let value = Self(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown nutrition meal category: \(rawValue)"
                )
            }
            self = value
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

typealias PulsarNutritionMealCategory = PulsarNutritionMealMoment

enum PulsarNutritionSource: String, Codable, Identifiable, Hashable {
    case userEntered
    case quickEstimate
    case privateFood
    case savedFood
    case recipe
    case mealTemplate
    case mockHealthContext
    case healthKit
    case aiMealRecognition
    case barcodeScanner
    case cloudSync

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userEntered: "Manual"
        case .quickEstimate: "Estimate"
        case .privateFood: "Private"
        case .savedFood: "Saved"
        case .recipe: "Recipe"
        case .mealTemplate: "Template"
        case .mockHealthContext: "Pulsar context"
        case .healthKit: "HealthKit"
        case .aiMealRecognition: "AI recognition"
        case .barcodeScanner: "Barcode"
        case .cloudSync: "Cloud sync"
        }
    }
}

enum PulsarNutritionExternalProvider: String, Codable, Hashable {
    case healthKit
    case aiMealRecognition
    case barcodeScanner
    case cloudSync
}

enum PulsarNutritionSyncStatus: String, Codable, Hashable {
    case localOnly
    case pendingUpload
    case synced
    case failed
}

struct PulsarNutritionExternalReference: Codable, Equatable, Hashable {
    var provider: PulsarNutritionExternalProvider
    var identifier: String
    var lastSyncedAt: Date?

    init(
        provider: PulsarNutritionExternalProvider,
        identifier: String,
        lastSyncedAt: Date? = nil
    ) {
        self.provider = provider
        self.identifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lastSyncedAt = lastSyncedAt
    }
}

struct PulsarFoodMetadata: Codable, Equatable, Hashable {
    var barcode: String?
    var externalReference: PulsarNutritionExternalReference?

    init(barcode: String? = nil, externalReference: PulsarNutritionExternalReference? = nil) {
        self.barcode = barcode?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.externalReference = externalReference
    }
}

struct PulsarNutritionEntryMetadata: Codable, Equatable, Hashable {
    var externalReference: PulsarNutritionExternalReference?
    var syncStatus: PulsarNutritionSyncStatus

    init(
        externalReference: PulsarNutritionExternalReference? = nil,
        syncStatus: PulsarNutritionSyncStatus = .localOnly
    ) {
        self.externalReference = externalReference
        self.syncStatus = syncStatus
    }
}

struct PulsarNutritionFacts: Codable, Equatable, Hashable {
    var calories: Double
    var protein: Double
    var carbohydrates: Double
    var fat: Double
    var fiber: Double
    var sugar: Double
    var sodiumMilligrams: Double

    init(
        calories: Double,
        protein: Double,
        carbohydrates: Double,
        fat: Double,
        fiber: Double = 0,
        sugar: Double = 0,
        sodiumMilligrams: Double = 0
    ) {
        self.calories = max(0, calories)
        self.protein = max(0, protein)
        self.carbohydrates = max(0, carbohydrates)
        self.fat = max(0, fat)
        self.fiber = max(0, fiber)
        self.sugar = max(0, sugar)
        self.sodiumMilligrams = max(0, sodiumMilligrams)
    }

    init(
        calories: Double,
        protein: Double,
        carbs: Double,
        fats: Double,
        fiber: Double = 0,
        sugar: Double = 0,
        sodiumMilligrams: Double = 0
    ) {
        self.init(
            calories: calories,
            protein: protein,
            carbohydrates: carbs,
            fat: fats,
            fiber: fiber,
            sugar: sugar,
            sodiumMilligrams: sodiumMilligrams
        )
    }

    static let zero = PulsarNutritionFacts(
        calories: 0,
        protein: 0,
        carbohydrates: 0,
        fat: 0,
        fiber: 0,
        sugar: 0,
        sodiumMilligrams: 0
    )

    var carbs: Double {
        get { carbohydrates }
        set { carbohydrates = max(0, newValue) }
    }

    var fats: Double {
        get { fat }
        set { fat = max(0, newValue) }
    }

    func scaled(by multiplier: Double) -> PulsarNutritionFacts {
        PulsarNutritionFacts(
            calories: calories * multiplier,
            protein: protein * multiplier,
            carbohydrates: carbohydrates * multiplier,
            fat: fat * multiplier,
            fiber: fiber * multiplier,
            sugar: sugar * multiplier,
            sodiumMilligrams: sodiumMilligrams * multiplier
        )
    }

    static func + (lhs: PulsarNutritionFacts, rhs: PulsarNutritionFacts) -> PulsarNutritionFacts {
        PulsarNutritionFacts(
            calories: lhs.calories + rhs.calories,
            protein: lhs.protein + rhs.protein,
            carbohydrates: lhs.carbohydrates + rhs.carbohydrates,
            fat: lhs.fat + rhs.fat,
            fiber: lhs.fiber + rhs.fiber,
            sugar: lhs.sugar + rhs.sugar,
            sodiumMilligrams: lhs.sodiumMilligrams + rhs.sodiumMilligrams
        )
    }
}

struct PulsarNutritionServing: Codable, Equatable, Hashable {
    var amount: Double
    var unit: String
    var grams: Double?

    init(amount: Double, unit: String, grams: Double? = nil) {
        self.amount = max(0.05, amount)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        self.unit = trimmedUnit.isEmpty ? "serving" : trimmedUnit
        self.grams = grams.map { max(0, $0) }
    }

    var title: String {
        let amountText = amount.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(amount))"
            : String(format: "%.1f", amount)
        if let grams {
            return "\(amountText) \(unit) / \(Int(grams.rounded()))g"
        }
        return "\(amountText) \(unit)"
    }
}

struct PulsarFoodItem: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var detail: String
    var brand: String?
    var serving: PulsarNutritionServing
    var nutritionPerServing: PulsarNutritionFacts
    var source: PulsarNutritionSource
    var isSaved: Bool
    var metadata: PulsarFoodMetadata?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        detail: String,
        brand: String? = nil,
        serving: PulsarNutritionServing,
        nutritionPerServing: PulsarNutritionFacts,
        source: PulsarNutritionSource = .userEntered,
        isSaved: Bool = false,
        metadata: PulsarFoodMetadata? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        self.brand = brand?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.serving = serving
        self.nutritionPerServing = nutritionPerServing
        self.source = source
        self.isSaved = isSaved
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var calories: Double { nutritionPerServing.calories }
    var protein: Double { nutritionPerServing.protein }
    var carbs: Double { nutritionPerServing.carbohydrates }
    var fats: Double { nutritionPerServing.fat }
    var servingAmount: Double { serving.amount }
}

struct PulsarNutritionEntry: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var food: PulsarFoodItem
    var servingMultiplier: Double
    var mealMoment: PulsarNutritionMealMoment
    var loggedAt: Date
    var note: String?
    var confidence: Double
    var source: PulsarNutritionSource
    var metadata: PulsarNutritionEntryMetadata?

    init(
        id: UUID = UUID(),
        food: PulsarFoodItem,
        servingMultiplier: Double,
        mealMoment: PulsarNutritionMealMoment,
        loggedAt: Date = Date(),
        note: String? = nil,
        confidence: Double = 1,
        source: PulsarNutritionSource? = nil,
        metadata: PulsarNutritionEntryMetadata? = nil
    ) {
        self.id = id
        self.food = food
        self.servingMultiplier = max(0.05, servingMultiplier)
        self.mealMoment = mealMoment
        self.loggedAt = loggedAt
        self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.confidence = min(max(confidence, 0), 1)
        self.source = source ?? food.source
        self.metadata = metadata
    }

    init(
        id: UUID = UUID(),
        foodName: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fats: Double,
        servingAmount: Double,
        servingUnit: String = "serving",
        mealCategory: PulsarNutritionMealCategory,
        timeLogged: Date = Date(),
        note: String? = nil,
        confidence: Double = 1,
        source: PulsarNutritionSource = .userEntered,
        foodMetadata: PulsarFoodMetadata? = nil,
        entryMetadata: PulsarNutritionEntryMetadata? = nil
    ) {
        let food = PulsarFoodItem(
            name: foodName,
            detail: "Manual food log",
            serving: PulsarNutritionServing(amount: servingAmount, unit: servingUnit),
            nutritionPerServing: PulsarNutritionFacts(
                calories: calories,
                protein: protein,
                carbs: carbs,
                fats: fats
            ),
            source: source,
            metadata: foodMetadata
        )
        self.init(
            id: id,
            food: food,
            servingMultiplier: 1,
            mealMoment: mealCategory,
            loggedAt: timeLogged,
            note: note,
            confidence: confidence,
            source: source,
            metadata: entryMetadata
        )
    }

    var nutrition: PulsarNutritionFacts {
        food.nutritionPerServing.scaled(by: servingMultiplier)
    }

    var foodName: String {
        get { food.name }
        set { food.name = newValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    var calories: Double { nutrition.calories }
    var protein: Double { nutrition.protein }
    var carbs: Double { nutrition.carbohydrates }
    var fats: Double { nutrition.fat }

    var servingAmount: Double {
        get { food.serving.amount * servingMultiplier }
        set {
            food.serving.amount = max(0.05, newValue)
            servingMultiplier = 1
        }
    }

    var mealCategory: PulsarNutritionMealCategory {
        get { mealMoment }
        set { mealMoment = newValue }
    }

    var timeLogged: Date {
        get { loggedAt }
        set { loggedAt = newValue }
    }

    var servingText: String {
        if servingMultiplier == 1 {
            return food.serving.title
        }
        return "\(PulsarNutritionFormatters.decimal(servingMultiplier)) x \(food.serving.title)"
    }
}

struct PulsarHydrationEntry: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var amountMilliliters: Double
    var loggedAt: Date
    var source: PulsarNutritionSource

    init(
        id: UUID = UUID(),
        amountMilliliters: Double,
        loggedAt: Date = Date(),
        source: PulsarNutritionSource = .userEntered
    ) {
        self.id = id
        self.amountMilliliters = max(0, amountMilliliters)
        self.loggedAt = loggedAt
        self.source = source
    }
}

struct PulsarBodyCheckIn: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var date: Date
    var weightKilograms: Double?
    var waistCentimeters: Double?
    var bodyFatPercentage: Double?
    var note: String?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        weightKilograms: Double? = nil,
        waistCentimeters: Double? = nil,
        bodyFatPercentage: Double? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.date = date
        self.weightKilograms = weightKilograms
        self.waistCentimeters = waistCentimeters
        self.bodyFatPercentage = bodyFatPercentage
        self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PulsarNutritionTargetSnapshot: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var date: Date
    var fuelRange: ClosedRange<Double>
    var proteinRange: ClosedRange<Double>
    var fiberTarget: Double
    var hydrationTargetMilliliters: Double
    var recoveryScore: Int
    var activityLoad: String
    var rationale: String

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        fuelRange: ClosedRange<Double>,
        proteinRange: ClosedRange<Double>,
        fiberTarget: Double,
        hydrationTargetMilliliters: Double,
        recoveryScore: Int,
        activityLoad: String,
        rationale: String
    ) {
        self.id = id
        self.date = date
        self.fuelRange = fuelRange
        self.proteinRange = proteinRange
        self.fiberTarget = fiberTarget
        self.hydrationTargetMilliliters = hydrationTargetMilliliters
        self.recoveryScore = min(max(recoveryScore, 0), 100)
        self.activityLoad = activityLoad
        self.rationale = rationale
    }
}

struct PulsarMealTemplateItem: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var food: PulsarFoodItem
    var servingMultiplier: Double

    init(id: UUID = UUID(), food: PulsarFoodItem, servingMultiplier: Double) {
        self.id = id
        self.food = food
        self.servingMultiplier = max(0.05, servingMultiplier)
    }

    var nutrition: PulsarNutritionFacts {
        food.nutritionPerServing.scaled(by: servingMultiplier)
    }
}

struct PulsarMealTemplate: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var defaultMoment: PulsarNutritionMealMoment
    var items: [PulsarMealTemplateItem]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        defaultMoment: PulsarNutritionMealMoment,
        items: [PulsarMealTemplateItem],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.defaultMoment = defaultMoment
        self.items = items
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var nutrition: PulsarNutritionFacts {
        items.reduce(.zero) { $0 + $1.nutrition }
    }
}

struct PulsarRecipeIngredient: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var food: PulsarFoodItem
    var servingMultiplier: Double

    init(id: UUID = UUID(), food: PulsarFoodItem, servingMultiplier: Double) {
        self.id = id
        self.food = food
        self.servingMultiplier = max(0.05, servingMultiplier)
    }

    var nutrition: PulsarNutritionFacts {
        food.nutritionPerServing.scaled(by: servingMultiplier)
    }
}

struct PulsarRecipe: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var servings: Double
    var ingredients: [PulsarRecipeIngredient]
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        servings: Double,
        ingredients: [PulsarRecipeIngredient],
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.servings = max(1, servings)
        self.ingredients = ingredients
        self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var totalNutrition: PulsarNutritionFacts {
        ingredients.reduce(.zero) { $0 + $1.nutrition }
    }

    var nutritionPerServing: PulsarNutritionFacts {
        totalNutrition.scaled(by: 1 / servings)
    }

    var reusableFood: PulsarFoodItem {
        PulsarFoodItem(
            name: name,
            detail: "Recipe serving",
            serving: PulsarNutritionServing(amount: 1, unit: "serving", grams: nil),
            nutritionPerServing: nutritionPerServing,
            source: .recipe,
            isSaved: true
        )
    }
}

struct PulsarNutritionRecoveryContext: Codable, Equatable, Hashable {
    var recoveryScore: Int
    var activityLoad: String
    var activeEnergyKilocalories: Double
    var sleepContext: String
    var proteinAdjustmentGrams: Double
    var hydrationAdjustmentMilliliters: Double

    static let mock = PulsarNutritionRecoveryContext(
        recoveryScore: 82,
        activityLoad: "Steady training day",
        activeEnergyKilocalories: 640,
        sleepContext: "Sleep supported recovery",
        proteinAdjustmentGrams: 12,
        hydrationAdjustmentMilliliters: 350
    )
}

struct PulsarNutritionInsight: Identifiable, Codable, Equatable, Hashable {
    enum Kind: String, Codable {
        case coachBrief
        case trend
        case timing
        case recovery
        case weekly
    }

    var id: UUID
    var kind: Kind
    var title: String
    var message: String
    var symbolName: String
    var confidence: Double

    init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        message: String,
        symbolName: String,
        confidence: Double = 1
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
        self.symbolName = symbolName
        self.confidence = min(max(confidence, 0), 1)
    }
}

struct PulsarNutritionWeekPoint: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var date: Date
    var protein: Double
    var fiber: Double
    var hydrationMilliliters: Double
    var consistency: Double

    init(
        id: UUID = UUID(),
        date: Date,
        protein: Double,
        fiber: Double,
        hydrationMilliliters: Double,
        consistency: Double
    ) {
        self.id = id
        self.date = date
        self.protein = protein
        self.fiber = fiber
        self.hydrationMilliliters = hydrationMilliliters
        self.consistency = min(max(consistency, 0), 1)
    }
}

struct PulsarEatingWindow: Codable, Equatable, Hashable {
    var isEnabled: Bool
    var startHour: Int
    var endHour: Int

    static let `default` = PulsarEatingWindow(isEnabled: true, startHour: 8, endHour: 20)
}

struct PulsarNutritionState: Codable, Equatable {
    var entries: [PulsarNutritionEntry]
    var hydrationEntries: [PulsarHydrationEntry]
    var privateFoods: [PulsarFoodItem]
    var mealTemplates: [PulsarMealTemplate]
    var recipes: [PulsarRecipe]
    var bodyCheckIns: [PulsarBodyCheckIn]
    var targetSnapshots: [PulsarNutritionTargetSnapshot]
    var eatingWindow: PulsarEatingWindow

    static let empty = PulsarNutritionState(
        entries: [],
        hydrationEntries: [],
        privateFoods: [],
        mealTemplates: [],
        recipes: [],
        bodyCheckIns: [],
        targetSnapshots: [],
        eatingWindow: .default
    )
}

struct PulsarNutritionDashboard: Equatable {
    var date: Date
    var entries: [PulsarNutritionEntry]
    var hydrationEntries: [PulsarHydrationEntry]
    var bodyCheckIns: [PulsarBodyCheckIn]
    var target: PulsarNutritionTargetSnapshot
    var recoveryContext: PulsarNutritionRecoveryContext
    var weeklyPoints: [PulsarNutritionWeekPoint]
    var insights: [PulsarNutritionInsight]
    var eatingWindow: PulsarEatingWindow

    var totals: PulsarNutritionFacts {
        entries.reduce(.zero) { $0 + $1.nutrition }
    }

    var hydrationTotal: Double {
        hydrationEntries.reduce(0) { $0 + $1.amountMilliliters }
    }

    var latestBodyCheckIn: PulsarBodyCheckIn? {
        bodyCheckIns.max { $0.date < $1.date }
    }

    var caloriesProgress: Double {
        guard calorieGoal > 0 else { return 0 }
        return min(max(totals.calories / calorieGoal, 0), 1.2)
    }

    var proteinProgress: Double {
        guard proteinGoal > 0 else { return 0 }
        return min(max(totals.protein / proteinGoal, 0), 1.2)
    }

    var carbohydratesProgress: Double {
        guard carbohydratesGoal > 0 else { return 0 }
        return min(max(totals.carbohydrates / carbohydratesGoal, 0), 1.2)
    }

    var fatProgress: Double {
        guard fatGoal > 0 else { return 0 }
        return min(max(totals.fat / fatGoal, 0), 1.2)
    }

    var fiberProgress: Double {
        guard target.fiberTarget > 0 else { return 0 }
        return min(max(totals.fiber / target.fiberTarget, 0), 1.2)
    }

    var hydrationProgress: Double {
        guard target.hydrationTargetMilliliters > 0 else { return 0 }
        return min(max(hydrationTotal / target.hydrationTargetMilliliters, 0), 1.2)
    }

    var calorieGoal: Double {
        (target.fuelRange.lowerBound + target.fuelRange.upperBound) / 2
    }

    var remainingCalories: Double {
        max(0, calorieGoal - totals.calories)
    }

    var proteinGoal: Double {
        target.proteinRange.lowerBound
    }

    var carbohydratesGoal: Double {
        max(1, calorieGoal * 0.45 / 4)
    }

    var fatGoal: Double {
        max(1, calorieGoal * 0.30 / 9)
    }
}

enum PulsarNutritionFormatters {
    static func calories(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    static func grams(_ value: Double) -> String {
        "\(Int(value.rounded()))g"
    }

    static func milliliters(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fL", value / 1000)
        }
        return "\(Int(value.rounded()))ml"
    }

    static func decimal(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(value))"
        }
        return String(format: "%.2f", value).replacingOccurrences(of: ".00", with: "")
    }
}
