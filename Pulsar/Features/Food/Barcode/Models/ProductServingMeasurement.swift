import Foundation

nonisolated struct ProductServingMeasurement: Hashable, Sendable {
    let amount: Double
    let unit: ProductServingUnit
    let unitLabel: String
    let grams: Double?
    let milliliters: Double?
    let manufacturerServingCount: Double?
    let packageCount: Double?

    var equivalentText: String? {
        if let grams {
            return "\(Self.formatted(grams)) g"
        }
        if let milliliters {
            return "\(Self.formatted(milliliters)) ml"
        }
        return nil
    }

    var servingText: String {
        let amountText = Self.formatted(amount)
        let unitText = unit.displayName(amount: amount, override: unitLabel)
        if let equivalentText, !(unit.isMass || unit.isVolume) {
            return "\(amountText) \(unitText) · \(equivalentText)"
        }
        return "\(amountText) \(unitText)"
    }

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
