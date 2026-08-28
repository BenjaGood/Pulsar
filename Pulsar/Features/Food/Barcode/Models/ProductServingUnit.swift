import Foundation

nonisolated enum ProductServingUnit: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case gram
    case kilogram
    case ounce
    case pound
    case milliliter
    case liter
    case cup
    case tablespoon
    case teaspoon
    case fluidOunce
    case slice
    case piece
    case bar
    case container
    case bottle
    case can
    case serving

    var id: String { rawValue }

    static let gramsPerKilogram = 1_000.0
    static let gramsPerOunce = 28.349523125
    static let gramsPerPound = 453.59237
    static let millilitersPerLiter = 1_000.0
    static let millilitersPerUSCup = 236.5882365
    static let millilitersPerUSTablespoon = 14.78676478125
    static let millilitersPerUSTeaspoon = 4.92892159375
    static let millilitersPerUSFluidOunce = 29.5735295625

    var shortName: String {
        switch self {
        case .gram: "g"
        case .kilogram: "kg"
        case .ounce: "oz"
        case .pound: "lb"
        case .milliliter: "ml"
        case .liter: "L"
        case .cup: "cup"
        case .tablespoon: "tbsp"
        case .teaspoon: "tsp"
        case .fluidOunce: "fl oz"
        case .slice: "slice"
        case .piece: "piece"
        case .bar: "bar"
        case .container: "container"
        case .bottle: "bottle"
        case .can: "can"
        case .serving: "serving"
        }
    }

    var isMass: Bool {
        switch self {
        case .gram, .kilogram, .ounce, .pound: true
        default: false
        }
    }

    var isVolume: Bool {
        switch self {
        case .milliliter, .liter, .cup, .tablespoon, .teaspoon, .fluidOunce: true
        default: false
        }
    }

    var isHousehold: Bool { !isMass && !isVolume }

    func grams(for amount: Double) -> Double? {
        guard amount.isFinite, amount > 0 else { return nil }
        switch self {
        case .gram: return amount
        case .kilogram: return amount * Self.gramsPerKilogram
        case .ounce: return amount * Self.gramsPerOunce
        case .pound: return amount * Self.gramsPerPound
        default: return nil
        }
    }

    func milliliters(for amount: Double) -> Double? {
        guard amount.isFinite, amount > 0 else { return nil }
        switch self {
        case .milliliter: return amount
        case .liter: return amount * Self.millilitersPerLiter
        case .cup: return amount * Self.millilitersPerUSCup
        case .tablespoon: return amount * Self.millilitersPerUSTablespoon
        case .teaspoon: return amount * Self.millilitersPerUSTeaspoon
        case .fluidOunce: return amount * Self.millilitersPerUSFluidOunce
        default: return nil
        }
    }

    func displayName(amount: Double, override: String? = nil) -> String {
        let label = override?.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = label?.isEmpty == false ? label! : shortName
        guard isHousehold, amount != 1 else { return base }
        if base.hasSuffix("s") { return base }
        return "\(base)s"
    }

    static func normalized(_ rawValue: String?) -> ProductServingUnit? {
        guard let rawValue else { return nil }
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "_", with: " ")
        return switch value {
        case "g", "gram", "grams", "gramo", "gramos": .gram
        case "kg", "kilogram", "kilograms", "kilogramo", "kilogramos": .kilogram
        case "oz", "ounce", "ounces", "onza", "onzas": .ounce
        case "lb", "lbs", "pound", "pounds", "libra", "libras": .pound
        case "ml", "milliliter", "milliliters", "millilitre", "millilitres", "mililitro", "mililitros": .milliliter
        case "l", "liter", "liters", "litre", "litres", "litro", "litros": .liter
        case "cup", "cups", "taza", "tazas": .cup
        case "tbsp", "tablespoon", "tablespoons", "cucharada", "cucharadas": .tablespoon
        case "tsp", "teaspoon", "teaspoons", "cucharadita", "cucharaditas": .teaspoon
        case "fl oz", "fluid ounce", "fluid ounces": .fluidOunce
        case "slice", "slices", "rebanada", "rebanadas": .slice
        case "piece", "pieces", "pieza", "piezas": .piece
        case "bar", "bars", "barra", "barras": .bar
        case "container", "containers", "envase", "envases": .container
        case "bottle", "bottles", "botella", "botellas": .bottle
        case "can", "cans", "lata", "latas": .can
        case "serving", "servings", "portion", "portions", "porción", "porciones", "porcion": .serving
        default: nil
        }
    }
}
