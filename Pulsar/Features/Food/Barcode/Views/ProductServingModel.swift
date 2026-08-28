import Foundation
import Observation

@MainActor
@Observable
final class ProductServingModel {
    let options: [ProductServingOption]
    let customUnits: [ProductServingUnit]
    private(set) var selectedOption: ProductServingOption
    private(set) var quantity = 1.0
    private(set) var calculation: ProductNutritionCalculation?

    private let calculator: ProductNutritionCalculator
    private let servingOptions: ProductServingOptions

    init?(product: FoodProduct) {
        guard let servingOptions = ProductServingOptions(product: product) else { return nil }
        self.servingOptions = servingOptions
        calculator = ProductNutritionCalculator(product: product)
        options = servingOptions.options
        customUnits = servingOptions.customUnits
        selectedOption = servingOptions.defaultOption
        calculation = calculator.calculate(option: servingOptions.defaultOption, quantity: 1)
    }

    var canDecrement: Bool { quantity > 0.5 }
    var quantityText: String { quantity.formatted(.number.precision(.fractionLength(0...1))) }
    var selectedTitle: String { selectedOption.title }
    var equivalentText: String { calculation?.measurement.equivalentText ?? "—" }

    func increment() {
        setQuantity(quantity + 0.5)
    }

    func decrement() {
        setQuantity(quantity - 0.5)
    }

    func select(_ option: ProductServingOption) {
        selectedOption = option
        recalculate()
    }

    @discardableResult
    func selectCustom(amount: Double, unit: ProductServingUnit) -> Bool {
        guard let option = servingOptions.customOption(amount: amount, unit: unit) else { return false }
        quantity = 1
        selectedOption = option
        recalculate()
        return calculation != nil
    }

    private func setQuantity(_ newValue: Double) {
        guard newValue.isFinite else { return }
        quantity = min(max(newValue, 0.5), 100)
        recalculate()
    }

    private func recalculate() {
        calculation = calculator.calculate(option: selectedOption, quantity: quantity)
    }
}
