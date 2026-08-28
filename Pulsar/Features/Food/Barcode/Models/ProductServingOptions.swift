import Foundation

nonisolated struct ProductServingOptions: Sendable {
    let options: [ProductServingOption]
    let defaultOption: ProductServingOption
    let customUnits: [ProductServingUnit]

    private let product: FoodProduct
    private let sourceServingUnit: ProductServingUnit?
    private let packageGrams: Double?
    private let packageMilliliters: Double?

    init?(product: FoodProduct) {
        self.product = product
        sourceServingUnit = ProductServingUnit.normalized(product.serving?.unit)
            ?? (product.serving?.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? .serving : nil)
        packageGrams = Self.packageMass(for: product)
        packageMilliliters = Self.packageVolume(for: product)

        let calculator = ProductNutritionCalculator(product: product)
        var candidates: [ProductServingOption] = []

        if let manufacturer = Self.manufacturerOption(product: product) {
            candidates.append(manufacturer)
            candidates.append(contentsOf: Self.householdOptions(product: product, manufacturer: manufacturer))
        }

        if Self.canCalculateMass(product: product, packageGrams: packageGrams) {
            candidates.append(contentsOf: Self.massOptions(product: product, packageGrams: packageGrams))
        }
        if Self.canCalculateVolume(product: product, packageMilliliters: packageMilliliters) {
            candidates.append(contentsOf: Self.volumeOptions(product: product, packageMilliliters: packageMilliliters))
        }
        if candidates.isEmpty, product.nutrients.contains(where: { $0.basis == .perServing }),
           let serving = Self.servingOnlyOption(product: product) {
            candidates.append(serving)
        }

        var seen = Set<String>()
        let calculable = candidates.filter { candidate in
            seen.insert(candidate.id).inserted && calculator.calculate(option: candidate, quantity: 1) != nil
        }
        guard let first = calculable.first else { return nil }
        options = calculable
        defaultOption = first

        var supported: [ProductServingUnit] = []
        if Self.canCalculateMass(product: product, packageGrams: packageGrams) {
            supported += [.gram, .kilogram, .ounce, .pound]
        }
        if Self.canCalculateVolume(product: product, packageMilliliters: packageMilliliters) {
            supported += [.milliliter, .liter, .cup, .tablespoon, .teaspoon, .fluidOunce]
        }
        if let sourceServingUnit, sourceServingUnit.isHousehold {
            supported.append(sourceServingUnit)
        }
        if product.nutrients.contains(where: { $0.basis == .perServing }) {
            supported.append(.serving)
        }
        customUnits = supported.uniqued()
    }

    func customOption(amount: Double, unit: ProductServingUnit) -> ProductServingOption? {
        guard customUnits.contains(unit), amount.isFinite, amount > 0 else { return nil }
        var grams = unit.grams(for: amount) ?? householdGrams(amount: amount, unit: unit)
        var milliliters = unit.milliliters(for: amount) ?? householdMilliliters(amount: amount, unit: unit)
        let servingCount = manufacturerServingCount(amount: amount, unit: unit, grams: grams, milliliters: milliliters)
        if let servingCount, grams == nil, let sourceGrams = product.serving?.gramWeight, Self.valid(sourceGrams) {
            grams = sourceGrams * servingCount
        }
        if let servingCount, milliliters == nil,
           let sourceMilliliters = product.serving?.milliliterVolume, Self.valid(sourceMilliliters) {
            milliliters = sourceMilliliters * servingCount
        }
        let packageCount = resolvedPackageCount(grams: grams, milliliters: milliliters, servingCount: servingCount)
        let option = ProductServingOption(
            id: "custom-\(unit.rawValue)-\(amount)",
            amount: amount,
            unit: unit,
            equivalentGrams: grams,
            equivalentMilliliters: milliliters,
            manufacturerServingCount: servingCount,
            packageCount: packageCount,
            isCustom: true
        )
        guard let option, ProductNutritionCalculator(product: product).calculate(option: option, quantity: 1) != nil else {
            return nil
        }
        return option
    }

    private func householdGrams(amount: Double, unit: ProductServingUnit) -> Double? {
        guard unit.isHousehold, unit == sourceServingUnit,
              let serving = product.serving, Self.valid(serving.quantity),
              let grams = serving.gramWeight, Self.valid(grams) else { return nil }
        return grams * amount / serving.quantity
    }

    private func householdMilliliters(amount: Double, unit: ProductServingUnit) -> Double? {
        guard unit.isHousehold, unit == sourceServingUnit,
              let serving = product.serving, Self.valid(serving.quantity),
              let milliliters = serving.milliliterVolume, Self.valid(milliliters) else { return nil }
        return milliliters * amount / serving.quantity
    }

    private func manufacturerServingCount(
        amount: Double,
        unit: ProductServingUnit,
        grams: Double?,
        milliliters: Double?
    ) -> Double? {
        guard let serving = product.serving, Self.valid(serving.quantity) else {
            return unit == .serving ? amount : nil
        }
        if unit == .serving { return amount }
        if unit.isHousehold, unit == sourceServingUnit { return amount / serving.quantity }
        if let grams, let servingGrams = serving.gramWeight, Self.valid(servingGrams) {
            return grams / servingGrams
        }
        if let milliliters, let servingMilliliters = serving.milliliterVolume, Self.valid(servingMilliliters) {
            return milliliters / servingMilliliters
        }
        return nil
    }

    private func resolvedPackageCount(
        grams: Double?,
        milliliters: Double?,
        servingCount: Double?
    ) -> Double? {
        if let grams, let packageGrams { return grams / packageGrams }
        if let milliliters, let packageMilliliters { return milliliters / packageMilliliters }
        if let servingCount, let servings = product.servingsPerContainer, Self.valid(servings) {
            return servingCount / servings
        }
        return nil
    }

    private static func manufacturerOption(product: FoodProduct) -> ProductServingOption? {
        guard !product.servingIsEstimated, let serving = product.serving,
              valid(serving.quantity) else { return nil }
        let unit = ProductServingUnit.normalized(serving.unit) ?? .serving
        let packageCount = packageFactor(
            grams: serving.gramWeight,
            milliliters: serving.milliliterVolume,
            manufacturerServingCount: 1,
            product: product
        )
        return ProductServingOption(
            id: "manufacturer",
            amount: serving.quantity,
            unit: unit,
            unitLabel: serving.unit,
            equivalentGrams: valid(serving.gramWeight) ? serving.gramWeight : nil,
            equivalentMilliliters: valid(serving.milliliterVolume) ? serving.milliliterVolume : nil,
            manufacturerServingCount: 1,
            packageCount: packageCount
        )
    }

    private static func householdOptions(
        product: FoodProduct,
        manufacturer: ProductServingOption
    ) -> [ProductServingOption] {
        guard manufacturer.unit.isHousehold else { return [] }
        let sourceAmount = manufacturer.amount
        let amounts = sourceAmount == 1 ? [0.5, 2] : [1]
        return amounts.compactMap { amount in
            let ratio = amount / sourceAmount
            return ProductServingOption(
                id: "household-\(amount)-\(manufacturer.unit.rawValue)",
                amount: amount,
                unit: manufacturer.unit,
                unitLabel: manufacturer.unitLabel,
                equivalentGrams: manufacturer.equivalentGrams.map { $0 * ratio },
                equivalentMilliliters: manufacturer.equivalentMilliliters.map { $0 * ratio },
                manufacturerServingCount: ratio,
                packageCount: manufacturer.packageCount.map { $0 * ratio }
            )
        }
    }

    private static func massOptions(product: FoodProduct, packageGrams: Double?) -> [ProductServingOption] {
        [(100.0, ProductServingUnit.gram), (50, .gram), (30, .gram), (1, .ounce)].compactMap { amount, unit in
            guard let grams = unit.grams(for: amount) else { return nil }
            let servingCount = servingCount(forGrams: grams, product: product)
            return ProductServingOption(
                id: "mass-\(amount)-\(unit.rawValue)",
                amount: amount,
                unit: unit,
                equivalentMilliliters: servingCount.flatMap { count in
                    product.serving?.milliliterVolume.flatMap { valid($0) ? $0 * count : nil }
                },
                manufacturerServingCount: servingCount,
                packageCount: packageGrams.map { grams / $0 }
            )
        }
    }

    private static func volumeOptions(product: FoodProduct, packageMilliliters: Double?) -> [ProductServingOption] {
        [(100.0, ProductServingUnit.milliliter), (250, .milliliter)].compactMap { amount, unit in
            guard let milliliters = unit.milliliters(for: amount) else { return nil }
            let servingCount = servingCount(forMilliliters: milliliters, product: product)
            return ProductServingOption(
                id: "volume-\(amount)-\(unit.rawValue)",
                amount: amount,
                unit: unit,
                equivalentGrams: servingCount.flatMap { count in
                    product.serving?.gramWeight.flatMap { valid($0) ? $0 * count : nil }
                },
                manufacturerServingCount: servingCount,
                packageCount: packageMilliliters.map { milliliters / $0 }
            )
        }
    }

    private static func servingOnlyOption(product: FoodProduct) -> ProductServingOption? {
        ProductServingOption(
            id: "serving-1",
            amount: 1,
            unit: .serving,
            manufacturerServingCount: 1,
            packageCount: product.servingsPerContainer.flatMap { valid($0) ? 1 / $0 : nil }
        )
    }

    private static func canCalculateMass(product: FoodProduct, packageGrams: Double?) -> Bool {
        product.nutrients.contains(where: { $0.basis == .per100Grams })
            || (valid(product.serving?.gramWeight) && product.nutrients.contains(where: { $0.basis == .perServing }))
            || (packageGrams != nil && product.nutrients.contains(where: { $0.basis == .perPackage }))
    }

    private static func canCalculateVolume(product: FoodProduct, packageMilliliters: Double?) -> Bool {
        product.nutrients.contains(where: { $0.basis == .per100Milliliters })
            || (valid(product.serving?.milliliterVolume) && product.nutrients.contains(where: { $0.basis == .perServing }))
            || (packageMilliliters != nil && product.nutrients.contains(where: { $0.basis == .perPackage }))
    }

    private static func servingCount(forGrams grams: Double, product: FoodProduct) -> Double? {
        guard let servingGrams = product.serving?.gramWeight, valid(servingGrams) else { return nil }
        return grams / servingGrams
    }

    private static func servingCount(forMilliliters milliliters: Double, product: FoodProduct) -> Double? {
        guard let servingMilliliters = product.serving?.milliliterVolume, valid(servingMilliliters) else { return nil }
        return milliliters / servingMilliliters
    }

    private static func packageMass(for product: FoodProduct) -> Double? {
        guard let amount = product.packageQuantity, valid(amount),
              let unit = ProductServingUnit.normalized(product.packageUnit) else { return nil }
        return unit.grams(for: amount)
    }

    private static func packageVolume(for product: FoodProduct) -> Double? {
        guard let amount = product.packageQuantity, valid(amount),
              let unit = ProductServingUnit.normalized(product.packageUnit) else { return nil }
        return unit.milliliters(for: amount)
    }

    private static func packageFactor(
        grams: Double?,
        milliliters: Double?,
        manufacturerServingCount: Double,
        product: FoodProduct
    ) -> Double? {
        if let grams, let packageGrams = packageMass(for: product), valid(grams) {
            return grams / packageGrams
        }
        if let milliliters, let packageMilliliters = packageVolume(for: product), valid(milliliters) {
            return milliliters / packageMilliliters
        }
        if let servings = product.servingsPerContainer, valid(servings) {
            return manufacturerServingCount / servings
        }
        return nil
    }

    private static func valid(_ value: Double?) -> Bool {
        guard let value else { return false }
        return value.isFinite && value > 0
    }
}

nonisolated private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
