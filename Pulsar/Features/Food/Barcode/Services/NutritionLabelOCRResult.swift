import Foundation

nonisolated struct NutritionLabelOCRResult: Sendable {
    var recognizedText: String
    var serving: FoodServing?
    var servingsPerContainer: Double?
    var basis: FoodNutrientBasis
    var nutrients: [FoodNutrient]
    var uncertainFields: Set<String>
}
