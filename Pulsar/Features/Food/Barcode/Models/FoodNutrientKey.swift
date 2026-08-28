import Foundation

nonisolated struct FoodNutrientKey: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        rawValue = value
    }

    static let energyKcal: Self = "energy_kcal"
    static let energyKilojoules: Self = "energy_kj"
    static let protein: Self = "protein_g"
    static let carbohydrates: Self = "carbohydrates_g"
    static let fat: Self = "fat_g"
    static let saturatedFat: Self = "saturated_fat_g"
    static let transFat: Self = "trans_fat_g"
    static let fiber: Self = "fiber_g"
    static let sugars: Self = "sugars_g"
    static let addedSugars: Self = "added_sugars_g"
    static let sodium: Self = "sodium_mg"
    static let salt: Self = "salt_g"
    static let cholesterol: Self = "cholesterol_mg"
    static let calcium: Self = "calcium_mg"
    static let iron: Self = "iron_mg"
    static let potassium: Self = "potassium_mg"
    static let vitaminD: Self = "vitamin_d_mcg"

    static let essentials: Set<Self> = [.energyKcal, .protein, .carbohydrates, .fat]

    var title: String {
        switch self {
        case .energyKcal: "Calories"
        case .energyKilojoules: "Energy"
        case .protein: "Protein"
        case .carbohydrates: "Carbohydrates"
        case .fat: "Total fat"
        case .saturatedFat: "Saturated fat"
        case .transFat: "Trans fat"
        case .fiber: "Fiber"
        case .sugars: "Sugars"
        case .addedSugars: "Added sugars"
        case .sodium: "Sodium"
        case .salt: "Salt"
        case .cholesterol: "Cholesterol"
        case .calcium: "Calcium"
        case .iron: "Iron"
        case .potassium: "Potassium"
        case .vitaminD: "Vitamin D"
        default: rawValue.replacing("_", with: " ").capitalized
        }
    }

    var canonicalUnit: String {
        switch self {
        case .energyKcal: "kcal"
        case .energyKilojoules: "kJ"
        case .sodium, .cholesterol, .calcium, .iron, .potassium: "mg"
        case .vitaminD: "mcg"
        default: "g"
        }
    }
}
