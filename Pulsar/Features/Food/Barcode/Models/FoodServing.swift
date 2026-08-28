import Foundation

nonisolated struct FoodServing: Codable, Hashable, Sendable {
    var quantity: Double
    var unit: String
    var gramWeight: Double?
    var milliliterVolume: Double?

    init(quantity: Double, unit: String, gramWeight: Double? = nil, milliliterVolume: Double? = nil) {
        self.quantity = max(quantity, 0.01)
        self.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "serving" : unit
        self.gramWeight = gramWeight.map { max($0, 0.01) }
        self.milliliterVolume = milliliterVolume.map { max($0, 0.01) }
    }

    var displayText: String {
        let quantityText = quantity.formatted(.number.precision(.fractionLength(0...2)))
        if let gramWeight {
            return "\(quantityText) \(unit) (\(gramWeight.formatted(.number.precision(.fractionLength(0...1)))) g)"
        }
        if let milliliterVolume {
            return "\(quantityText) \(unit) (\(milliliterVolume.formatted(.number.precision(.fractionLength(0...1)))) ml)"
        }
        return "\(quantityText) \(unit)"
    }
}
