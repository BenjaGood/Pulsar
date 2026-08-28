import Foundation

nonisolated enum FoodNutrientBasis: String, Codable, CaseIterable, Sendable {
    case perServing = "per_serving"
    case per100Grams = "per_100g"
    case per100Milliliters = "per_100ml"
    case perPackage = "per_package"

    var title: String {
        switch self {
        case .perServing: "Per serving"
        case .per100Grams: "Per 100 g"
        case .per100Milliliters: "Per 100 ml"
        case .perPackage: "Per package"
        }
    }
}
