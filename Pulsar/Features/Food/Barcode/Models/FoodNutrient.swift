import Foundation

nonisolated struct FoodNutrient: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var key: FoodNutrientKey
    var amount: Double
    var unit: String
    var basis: FoodNutrientBasis
    var confidence: Double?

    init(
        id: UUID = UUID(),
        key: FoodNutrientKey,
        amount: Double,
        unit: String? = nil,
        basis: FoodNutrientBasis,
        confidence: Double? = nil
    ) {
        self.id = id
        self.key = key
        self.amount = max(0, amount)
        self.unit = unit ?? key.canonicalUnit
        self.basis = basis
        self.confidence = confidence.map { min(max($0, 0), 1) }
    }
}
