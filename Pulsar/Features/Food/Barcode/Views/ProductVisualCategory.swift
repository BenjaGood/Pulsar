import Foundation

nonisolated enum ProductVisualCategory: String, CaseIterable, Sendable {
    case bakery
    case yogurt
    case snack
    case proteinBar
    case drink
    case cereal
    case milk
    case cheese
    case frozen
    case candy
    case unknown

    static func resolve(name: String, genericName: String? = nil) -> ProductVisualCategory {
        let searchableText = [name, genericName]
            .compactMap { $0 }
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        if searchableText.contains(anyOf: ["protein bar", "energy bar", "nutrition bar", "granola bar", "barra de proteina"]) {
            return .proteinBar
        }
        if searchableText.contains(anyOf: ["cereal", "cocoa puffs", "corn flakes", "bran flakes", "cheerios", "muesli", "oatmeal", "avena", "granola"]) {
            return .cereal
        }
        if searchableText.contains(anyOf: ["frozen", "ice cream", "helado", "sorbet", "congelado"]) {
            return .frozen
        }
        if searchableText.contains(anyOf: ["cheese", "queso", "mozzarella", "cheddar", "parmesan"]) {
            return .cheese
        }
        if searchableText.contains(anyOf: ["yogurt", "yoghurt", "yoghourt", "kefir", "skyr", "crema lactea"]) {
            return .yogurt
        }
        if searchableText.contains(anyOf: ["candy", "chocolate", "gummy", "caramel", "toffee", "dulce", "gomita"]) {
            return .candy
        }
        if searchableText.contains(anyOf: ["milk", "leche", "lactose", "half and half"]) {
            return .milk
        }
        if searchableText.contains(anyOf: ["bread", "loaf", "bun", "bagel", "croissant", "muffin", "pastry", "cake", "tortilla", "pan de", "galleta"]) {
            return .bakery
        }
        if searchableText.contains(anyOf: ["chips", "crisps", "cracker", "popcorn", "pretzel", "snack", "nuts", "papas", "botana"]) {
            return .snack
        }
        if searchableText.contains(anyOf: ["drink", "beverage", "soda", "juice", "water", "coffee", "tea", "cola", "shake", "bebida", "jugo", "agua"]) {
            return .drink
        }
        return .unknown
    }
}

nonisolated private extension String {
    func contains(anyOf terms: [String]) -> Bool {
        terms.contains(where: contains)
    }
}
