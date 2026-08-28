import Foundation

nonisolated struct ProductVisualDescriptor: Equatable, Sendable {
    let category: ProductVisualCategory
    let brandMonogram: String?

    init(product: FoodProduct) {
        self.init(
            name: product.name,
            genericName: product.genericName,
            brand: product.brand
        )
    }

    init(name: String, genericName: String? = nil, brand: String? = nil) {
        category = ProductVisualCategory.resolve(name: name, genericName: genericName)
        brandMonogram = Self.monogram(for: brand)
    }

    private static func monogram(for brand: String?) -> String? {
        guard let scalar = brand?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .first(where: CharacterSet.alphanumerics.contains) else {
            return nil
        }
        return String(scalar).uppercased()
    }
}
