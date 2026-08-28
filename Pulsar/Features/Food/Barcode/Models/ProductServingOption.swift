import Foundation

nonisolated struct ProductServingOption: Identifiable, Hashable, Sendable {
    let id: String
    let amount: Double
    let unit: ProductServingUnit
    let unitLabel: String
    let equivalentGrams: Double?
    let equivalentMilliliters: Double?
    let manufacturerServingCount: Double?
    let packageCount: Double?
    let isCustom: Bool

    init?(
        id: String,
        amount: Double,
        unit: ProductServingUnit,
        unitLabel: String? = nil,
        equivalentGrams: Double? = nil,
        equivalentMilliliters: Double? = nil,
        manufacturerServingCount: Double? = nil,
        packageCount: Double? = nil,
        isCustom: Bool = false
    ) {
        guard amount.isFinite, amount > 0 else { return nil }
        let resolvedGrams = equivalentGrams ?? unit.grams(for: amount)
        let resolvedMilliliters = equivalentMilliliters ?? unit.milliliters(for: amount)
        guard Self.isValid(resolvedGrams), Self.isValid(resolvedMilliliters),
              Self.isValid(manufacturerServingCount), Self.isValid(packageCount) else { return nil }
        self.id = id
        self.amount = amount
        self.unit = unit
        self.unitLabel = unitLabel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? unit.shortName
        self.equivalentGrams = resolvedGrams
        self.equivalentMilliliters = resolvedMilliliters
        self.manufacturerServingCount = manufacturerServingCount
        self.packageCount = packageCount
        self.isCustom = isCustom
    }

    var title: String {
        "\(amount.formatted(.number.precision(.fractionLength(0...2)))) \(unit.displayName(amount: amount, override: unitLabel))"
    }

    var detail: String? {
        if let equivalentGrams, !unit.isMass {
            return "\(equivalentGrams.formatted(.number.precision(.fractionLength(0...2)))) g"
        }
        if let equivalentMilliliters, !unit.isVolume {
            return "\(equivalentMilliliters.formatted(.number.precision(.fractionLength(0...2)))) ml"
        }
        if unit == .ounce, let equivalentGrams {
            return "\(equivalentGrams.formatted(.number.precision(.fractionLength(0...2)))) g"
        }
        return nil
    }

    func measurement(quantity: Double) -> ProductServingMeasurement? {
        guard quantity.isFinite, quantity > 0 else { return nil }
        return ProductServingMeasurement(
            amount: amount * quantity,
            unit: unit,
            unitLabel: unitLabel,
            grams: equivalentGrams.map { $0 * quantity },
            milliliters: equivalentMilliliters.map { $0 * quantity },
            manufacturerServingCount: manufacturerServingCount.map { $0 * quantity },
            packageCount: packageCount.map { $0 * quantity }
        )
    }

    private static func isValid(_ value: Double?) -> Bool {
        value == nil || (value!.isFinite && value! > 0)
    }
}

nonisolated private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
