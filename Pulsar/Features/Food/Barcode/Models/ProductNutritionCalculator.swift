import Foundation

nonisolated struct ProductNutritionCalculator: Sendable {
    static let kilojoulesPerKilocalorie = 4.184

    private let sourceNutrients: [FoodNutrient]

    init(product: FoodProduct) {
        sourceNutrients = product.nutrients
    }

    func calculate(option: ProductServingOption, quantity: Double) -> ProductNutritionCalculation? {
        guard let measurement = option.measurement(quantity: quantity) else { return nil }
        var values: [FoodNutrientKey: Double] = [:]

        let ordinaryKeys = Set(sourceNutrients.map(\.key)).subtracting([.energyKcal, .energyKilojoules])
        for key in ordinaryKeys {
            if let value = calculatedValue(for: key, measurement: measurement) {
                values[key] = value
            }
        }

        if let energy = calculatedValue(for: .energyKcal, measurement: measurement)
            ?? calculatedValue(for: .energyKilojoules, measurement: measurement) {
            values[.energyKcal] = energy
        }

        guard !values.isEmpty else { return nil }
        return ProductNutritionCalculation(measurement: measurement, nutrientValues: values)
    }

    private func calculatedValue(
        for key: FoodNutrientKey,
        measurement: ProductServingMeasurement
    ) -> Double? {
        let candidates = sourceNutrients.filter { $0.key == key }
        for basis in [FoodNutrientBasis.perServing, .per100Grams, .per100Milliliters, .perPackage] {
            for nutrient in candidates where nutrient.basis == basis {
                guard let normalized = normalizedAmount(nutrient),
                      let factor = factor(for: basis, measurement: measurement) else { continue }
                let result = normalized * factor
                if result.isFinite, result >= 0 { return result }
            }
        }
        return nil
    }

    private func factor(
        for basis: FoodNutrientBasis,
        measurement: ProductServingMeasurement
    ) -> Double? {
        let factor: Double?
        switch basis {
        case .perServing: factor = measurement.manufacturerServingCount
        case .per100Grams: factor = measurement.grams.map { $0 / 100 }
        case .per100Milliliters: factor = measurement.milliliters.map { $0 / 100 }
        case .perPackage: factor = measurement.packageCount
        }
        guard let factor, factor.isFinite, factor > 0 else { return nil }
        return factor
    }

    private func normalizedAmount(_ nutrient: FoodNutrient) -> Double? {
        guard nutrient.amount.isFinite, nutrient.amount >= 0 else { return nil }
        let unit = nutrient.unit
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "µ", with: "u")

        if nutrient.key == .energyKcal {
            switch unit {
            case "kcal", "cal", "kilocalorie", "kilocalories": return nutrient.amount
            case "kj", "kilojoule", "kilojoules": return nutrient.amount / Self.kilojoulesPerKilocalorie
            default: return nil
            }
        }
        if nutrient.key == .energyKilojoules {
            switch unit {
            case "kj", "kilojoule", "kilojoules": return nutrient.amount / Self.kilojoulesPerKilocalorie
            case "kcal", "cal", "kilocalorie", "kilocalories": return nutrient.amount
            default: return nil
            }
        }

        return convertedMass(amount: nutrient.amount, from: unit, to: nutrient.key.canonicalUnit)
    }

    private func convertedMass(amount: Double, from source: String, to target: String) -> Double? {
        let grams: Double
        switch source {
        case "g", "gram", "grams": grams = amount
        case "mg", "milligram", "milligrams": grams = amount / 1_000
        case "mcg", "ug", "microgram", "micrograms": grams = amount / 1_000_000
        case "kg", "kilogram", "kilograms": grams = amount * 1_000
        default: return nil
        }
        let result: Double
        switch target.lowercased() {
        case "g": result = grams
        case "mg": result = grams * 1_000
        case "mcg": result = grams * 1_000_000
        default: return nil
        }
        return result.isFinite && result >= 0 ? result : nil
    }
}
