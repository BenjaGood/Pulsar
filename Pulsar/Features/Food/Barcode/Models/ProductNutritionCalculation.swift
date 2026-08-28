import Foundation

nonisolated struct ProductNutritionCalculation: Hashable, Sendable {
    let measurement: ProductServingMeasurement
    let nutrientValues: [FoodNutrientKey: Double]

    var isComplete: Bool {
        FoodNutrientKey.essentials.allSatisfy { nutrientValues[$0] != nil }
    }

    func amount(for key: FoodNutrientKey) -> Double? {
        nutrientValues[key]
    }

    @MainActor
    func foodItem(for product: FoodProduct) -> PulsarFoodItem? {
        guard let calories = amount(for: .energyKcal),
              let protein = amount(for: .protein),
              let carbohydrates = amount(for: .carbohydrates),
              let fat = amount(for: .fat) else { return nil }

        return PulsarFoodItem(
            id: product.id,
            name: product.name,
            detail: product.brand ?? product.genericName ?? product.source.title,
            brand: product.brand,
            serving: PulsarNutritionServing(
                amount: measurement.amount,
                unit: measurement.unit.displayName(amount: measurement.amount, override: measurement.unitLabel),
                grams: measurement.grams,
                milliliters: measurement.milliliters
            ),
            nutritionPerServing: PulsarNutritionFacts(
                calories: calories,
                protein: protein,
                carbohydrates: carbohydrates,
                fat: fat,
                fiber: amount(for: .fiber) ?? 0,
                sugar: amount(for: .sugars) ?? 0,
                sodiumMilligrams: amount(for: .sodium) ?? 0,
                reportedNutrientKeys: Set(nutrientValues.keys.map(\.rawValue))
            ),
            source: .barcodeScanner,
            metadata: PulsarFoodMetadata(
                barcode: product.barcode,
                externalReference: PulsarNutritionExternalReference(
                    provider: .barcodeScanner,
                    identifier: product.sourceProductID ?? product.barcode ?? product.id.uuidString,
                    lastSyncedAt: product.updatedAt
                ),
                calculatedNutrients: Dictionary(uniqueKeysWithValues: nutrientValues.map { ($0.key.rawValue, $0.value) }),
                servingMilliliters: measurement.milliliters
            )
        )
    }
}
