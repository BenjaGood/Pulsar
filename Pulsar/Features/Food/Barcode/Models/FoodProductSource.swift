import Foundation

nonisolated enum FoodProductSource: String, Codable, CaseIterable, Sendable {
    case pulsarCommunity = "pulsar_community"
    case openNutrition = "open_nutrition"
    case openFoodFacts = "open_food_facts"
    case labelOCR = "label_ocr"
    case manual

    var title: String {
        switch self {
        case .pulsarCommunity: "Pulsar Community"
        case .openNutrition: "OpenNutrition"
        case .openFoodFacts: "Open Food Facts"
        case .labelOCR: "Nutrition label"
        case .manual: "Manual entry"
        }
    }
}
