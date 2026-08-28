import XCTest
@testable import Pulsar

final class ProductNutritionCalculatorTests: XCTestCase {
    func testPer100GramsScalesArbitraryGrams() throws {
        let product = product(basis: .per100Grams, serving: FoodServing(quantity: 43, unit: "g", gramWeight: 43))
        let result = try calculation(product: product, amount: 43, unit: .gram)
        assert(result, .energyKcal, equals: 107.5)
        assert(result, .protein, equals: 3.612)
        assert(result, .carbohydrates, equals: 18.361)
        assert(result, .fat, equals: 2.236)
    }

    func testPer100MillilitersScalesArbitraryVolume() throws {
        let product = product(basis: .per100Milliliters, serving: FoodServing(quantity: 250, unit: "ml", milliliterVolume: 250))
        let result = try calculation(product: product, amount: 250, unit: .milliliter)
        assert(result, .energyKcal, equals: 625)
        assert(result, .protein, equals: 21)
    }

    func testPerServingUsesManufacturerServingCount() throws {
        let product = product(basis: .perServing, serving: FoodServing(quantity: 1, unit: "bar", gramWeight: 60))
        let option = try XCTUnwrap(ProductServingOptions(product: product)?.defaultOption)
        let result = try XCTUnwrap(ProductNutritionCalculator(product: product).calculate(option: option, quantity: 2.5))
        assert(result, .energyKcal, equals: 625)
        assert(result, .protein, equals: 21)
    }

    func testOneSliceScalesToMultipleSlices() throws {
        let product = product(basis: .per100Grams, serving: FoodServing(quantity: 1, unit: "slice", gramWeight: 43))
        let option = try option(in: product, amount: 1, unit: .slice)
        let result = try XCTUnwrap(ProductNutritionCalculator(product: product).calculate(option: option, quantity: 2))
        XCTAssertEqual(try XCTUnwrap(result.measurement.grams), 86, accuracy: 1e-12)
        assert(result, .energyKcal, equals: 215)
    }

    func testFractionalSliceQuantitiesRemainExact() throws {
        let product = product(basis: .per100Grams, serving: FoodServing(quantity: 1, unit: "slice", gramWeight: 43))
        let option = try option(in: product, amount: 1, unit: .slice)
        let calculator = ProductNutritionCalculator(product: product)
        let half = try XCTUnwrap(calculator.calculate(option: option, quantity: 0.5))
        let oneAndHalf = try XCTUnwrap(calculator.calculate(option: option, quantity: 1.5))
        XCTAssertEqual(try XCTUnwrap(half.measurement.grams), 21.5, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(oneAndHalf.measurement.grams), 64.5, accuracy: 1e-12)
        assert(half, .energyKcal, equals: 53.75)
        assert(oneAndHalf, .energyKcal, equals: 161.25)
    }

    func testQuantityComposesWithMultiPieceServing() throws {
        let product = product(basis: .per100Grams, serving: FoodServing(quantity: 2, unit: "slice", gramWeight: 86))
        let option = try option(in: product, amount: 2, unit: .slice)
        let result = try XCTUnwrap(ProductNutritionCalculator(product: product).calculate(option: option, quantity: 2))
        XCTAssertEqual(result.measurement.amount, 4, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(result.measurement.grams), 172, accuracy: 1e-12)
        assert(result, .energyKcal, equals: 430)
    }

    func testOuncesUseExactGramConversion() throws {
        let product = product(basis: .per100Grams)
        let result = try calculation(product: product, amount: 1, unit: .ounce)
        XCTAssertEqual(try XCTUnwrap(result.measurement.grams), ProductServingUnit.gramsPerOunce, accuracy: 1e-12)
        assert(result, .energyKcal, equals: 70.8738078125)
    }

    func testKilogramsUseExactGramConversion() throws {
        let product = product(basis: .per100Grams)
        let result = try calculation(product: product, amount: 0.25, unit: .kilogram)
        XCTAssertEqual(try XCTUnwrap(result.measurement.grams), 250, accuracy: 1e-12)
        assert(result, .energyKcal, equals: 625)
    }

    func testPoundsUseExactGramConversion() throws {
        let product = product(basis: .per100Grams)
        let result = try calculation(product: product, amount: 0.5, unit: .pound)
        XCTAssertEqual(try XCTUnwrap(result.measurement.grams), 226.796185, accuracy: 1e-12)
        assert(result, .energyKcal, equals: 566.9904625)
    }

    func testLitersUseExactMilliliterConversion() throws {
        let product = product(basis: .per100Milliliters)
        let result = try calculation(product: product, amount: 0.25, unit: .liter)
        XCTAssertEqual(try XCTUnwrap(result.measurement.milliliters), 250, accuracy: 1e-12)
        assert(result, .energyKcal, equals: 625)
    }

    func testKilojoulesNormalizeToKilocalories() throws {
        let energy = FoodNutrient(key: .energyKilojoules, amount: 418.4, unit: "kJ", basis: .per100Grams)
        let product = FoodProduct(name: "Energy", source: .manual, verificationStatus: .communitySubmitted, nutrients: [energy])
        let result = try calculation(product: product, amount: 100, unit: .gram)
        assert(result, .energyKcal, equals: 100)
    }

    func testMicronutrientsScaleFromOriginalBase() throws {
        let product = product(
            basis: .per100Grams,
            extra: [FoodNutrient(key: .vitaminD, amount: 12.5, unit: "mcg", basis: .per100Grams)]
        )
        let result = try calculation(product: product, amount: 43, unit: .gram)
        assert(result, .vitaminD, equals: 5.375)
    }

    func testSodiumMilligramsScaleWithoutUnitConfusion() throws {
        let product = product(
            basis: .per100Grams,
            extra: [FoodNutrient(key: .sodium, amount: 197, unit: "mg", basis: .per100Grams)]
        )
        let result = try calculation(product: product, amount: 43, unit: .gram)
        assert(result, .sodium, equals: 84.71)
    }

    func testMissingNutrientRemainsMissingWhileExplicitZeroIsPreserved() throws {
        let product = product(
            basis: .per100Grams,
            extra: [FoodNutrient(key: .transFat, amount: 0, unit: "g", basis: .per100Grams)]
        )
        let result = try calculation(product: product, amount: 43, unit: .gram)
        XCTAssertNil(result.amount(for: .addedSugars))
        XCTAssertEqual(result.amount(for: .transFat), 0)
    }

    func testQuantityChangesNeverAccumulateRoundedValues() throws {
        let product = product(basis: .per100Grams, serving: FoodServing(quantity: 1, unit: "slice", gramWeight: 43))
        let option = try option(in: product, amount: 1, unit: .slice)
        let calculator = ProductNutritionCalculator(product: product)
        _ = calculator.calculate(option: option, quantity: 1)
        _ = calculator.calculate(option: option, quantity: 2)
        _ = calculator.calculate(option: option, quantity: 0.5)
        let final = try XCTUnwrap(calculator.calculate(option: option, quantity: 1))
        assert(final, .protein, equals: 3.612)
    }

    func testRepeatedServingSwitchesReturnOriginalResult() throws {
        let product = product(basis: .per100Grams, serving: FoodServing(quantity: 1, unit: "slice", gramWeight: 43))
        let calculator = ProductNutritionCalculator(product: product)
        let hundred = try option(in: product, amount: 100, unit: .gram)
        let slice = try option(in: product, amount: 1, unit: .slice)
        for _ in 0..<20 {
            _ = calculator.calculate(option: slice, quantity: 1.5)
            _ = calculator.calculate(option: hundred, quantity: 0.5)
        }
        let final = try XCTUnwrap(calculator.calculate(option: hundred, quantity: 1))
        assert(final, .energyKcal, equals: 250)
        assert(final, .protein, equals: 8.4)
    }

    func testMassSliceOunceMassCycleDoesNotDrift() throws {
        let product = product(basis: .per100Grams, serving: FoodServing(quantity: 1, unit: "slice", gramWeight: 43))
        let calculator = ProductNutritionCalculator(product: product)
        let hundred = try option(in: product, amount: 100, unit: .gram)
        let slice = try option(in: product, amount: 1, unit: .slice)
        let ounce = try option(in: product, amount: 1, unit: .ounce)
        _ = calculator.calculate(option: hundred, quantity: 1)
        _ = calculator.calculate(option: slice, quantity: 1)
        _ = calculator.calculate(option: ounce, quantity: 1)
        let final = try XCTUnwrap(calculator.calculate(option: hundred, quantity: 1))
        assert(final, .energyKcal, equals: 250)
    }

    func testZeroAndInvalidSelectionDataFailsSafely() {
        XCTAssertNil(ProductServingOption(id: "zero", amount: 0, unit: .gram))
        XCTAssertNil(ProductServingOption(id: "nan", amount: 1, unit: .slice, equivalentGrams: .nan))
        let product = product(basis: .per100Grams)
        let valid = ProductServingOption(id: "valid", amount: 100, unit: .gram)!
        XCTAssertNil(ProductNutritionCalculator(product: product).calculate(option: valid, quantity: .infinity))
    }

    func testUnsupportedVolumeToMassConversionIsNotOffered() throws {
        let product = product(basis: .per100Grams)
        let options = try XCTUnwrap(ProductServingOptions(product: product))
        XCTAssertFalse(options.customUnits.contains(.milliliter))
        XCTAssertNil(options.customOption(amount: 250, unit: .milliliter))
    }

    func testLiveBimboCeroCeroServingMatchesSourceMath() throws {
        let product = FoodProduct(
            name: "Bimbo Cero Cero by Bimbo",
            serving: FoodServing(quantity: 2, unit: "slice", gramWeight: 55),
            source: .openNutrition,
            verificationStatus: .imported,
            nutrients: [
                FoodNutrient(key: .energyKcal, amount: 218, unit: "kcal", basis: .per100Grams),
                FoodNutrient(key: .protein, amount: 10.9, unit: "g", basis: .per100Grams),
                FoodNutrient(key: .carbohydrates, amount: 45.4, unit: "g", basis: .per100Grams),
                FoodNutrient(key: .fat, amount: 1.82, unit: "g", basis: .per100Grams),
                FoodNutrient(key: .sodium, amount: 345, unit: "mg", basis: .per100Grams)
            ]
        )
        let option = try XCTUnwrap(ProductServingOptions(product: product)?.defaultOption)
        let result = try XCTUnwrap(ProductNutritionCalculator(product: product).calculate(option: option, quantity: 1))
        assert(result, .energyKcal, equals: 119.9)
        assert(result, .protein, equals: 5.995)
        assert(result, .carbohydrates, equals: 24.97)
        assert(result, .fat, equals: 1.001)
        assert(result, .sodium, equals: 189.75)
    }

    func testLiveYoplaitContainerServingMatchesSourceMath() throws {
        let product = FoodProduct(
            name: "Yoplait Cocoa Puffs by Yoplait",
            serving: FoodServing(quantity: 1, unit: "container", gramWeight: 121),
            source: .openNutrition,
            verificationStatus: .imported,
            nutrients: [
                FoodNutrient(key: .energyKcal, amount: 107, unit: "kcal", basis: .per100Grams),
                FoodNutrient(key: .protein, amount: 3.31, unit: "g", basis: .per100Grams),
                FoodNutrient(key: .carbohydrates, amount: 22.3, unit: "g", basis: .per100Grams),
                FoodNutrient(key: .fat, amount: 0.83, unit: "g", basis: .per100Grams),
                FoodNutrient(key: .sugars, amount: 14, unit: "g", basis: .per100Grams),
                FoodNutrient(key: .sodium, amount: 70, unit: "mg", basis: .per100Grams)
            ]
        )
        let option = try XCTUnwrap(ProductServingOptions(product: product)?.defaultOption)
        let result = try XCTUnwrap(ProductNutritionCalculator(product: product).calculate(option: option, quantity: 1))
        assert(result, .energyKcal, equals: 129.47)
        assert(result, .protein, equals: 4.0051)
        assert(result, .carbohydrates, equals: 26.983)
        assert(result, .fat, equals: 1.0043)
        assert(result, .sugars, equals: 16.94)
        assert(result, .sodium, equals: 84.7)
    }

    func testUnknownManufacturerUnitKeepsDeclaredLabelAndWeight() throws {
        let product = product(
            basis: .per100Grams,
            serving: FoodServing(quantity: 1, unit: "tube", gramWeight: 56)
        )
        let option = try XCTUnwrap(ProductServingOptions(product: product)?.defaultOption)
        XCTAssertEqual(option.title, "1 tube")
        let result = try XCTUnwrap(ProductNutritionCalculator(product: product).calculate(option: option, quantity: 1))
        XCTAssertEqual(try XCTUnwrap(result.measurement.grams), 56, accuracy: 1e-12)
        assert(result, .energyKcal, equals: 140)
    }

    func testProductSpecificMassVolumeRelationshipSupportsMixedBases() throws {
        let product = FoodProduct(
            name: "Known density fixture",
            serving: FoodServing(quantity: 1, unit: "container", gramWeight: 150, milliliterVolume: 120),
            source: .manual,
            verificationStatus: .communitySubmitted,
            nutrients: [
                FoodNutrient(key: .energyKcal, amount: 250, unit: "kcal", basis: .per100Grams),
                FoodNutrient(key: .sodium, amount: 40, unit: "mg", basis: .per100Milliliters)
            ]
        )
        let option = try XCTUnwrap(ProductServingOptions(product: product)?.customOption(amount: 240, unit: .milliliter))
        let result = try XCTUnwrap(ProductNutritionCalculator(product: product).calculate(option: option, quantity: 1))
        XCTAssertEqual(try XCTUnwrap(result.measurement.grams), 300, accuracy: 1e-12)
        assert(result, .energyKcal, equals: 750)
        assert(result, .sodium, equals: 96)
    }

    @MainActor
    func testLoggedFoodUsesSameExactCalculationAndPreservesAvailability() throws {
        let product = product(
            basis: .per100Grams,
            serving: FoodServing(quantity: 1, unit: "slice", gramWeight: 43),
            extra: [FoodNutrient(key: .sodium, amount: 197, unit: "mg", basis: .per100Grams)]
        )
        let slice = try option(in: product, amount: 1, unit: .slice)
        let result = try XCTUnwrap(ProductNutritionCalculator(product: product).calculate(option: slice, quantity: 2))
        let food = try XCTUnwrap(result.foodItem(for: product))
        XCTAssertEqual(food.nutritionPerServing.calories, try XCTUnwrap(result.amount(for: .energyKcal)), accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(food.serving.grams), 86, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(food.metadata?.calculatedNutrients?[FoodNutrientKey.sodium.rawValue]), 169.42, accuracy: 1e-12)
        XCTAssertFalse(food.nutritionPerServing.reportedNutrientKeys?.contains(FoodNutrientKey.transFat.rawValue) == true)
    }

    private func product(
        basis: FoodNutrientBasis,
        serving: FoodServing? = nil,
        extra: [FoodNutrient] = []
    ) -> FoodProduct {
        FoodProduct(
            name: "Calculation fixture",
            serving: serving,
            source: .manual,
            verificationStatus: .communitySubmitted,
            nutrients: [
                FoodNutrient(key: .energyKcal, amount: 250, unit: "kcal", basis: basis),
                FoodNutrient(key: .protein, amount: 8.4, unit: "g", basis: basis),
                FoodNutrient(key: .carbohydrates, amount: 42.7, unit: "g", basis: basis),
                FoodNutrient(key: .fat, amount: 5.2, unit: "g", basis: basis)
            ] + extra
        )
    }

    private func calculation(
        product: FoodProduct,
        amount: Double,
        unit: ProductServingUnit
    ) throws -> ProductNutritionCalculation {
        let option = try XCTUnwrap(ProductServingOptions(product: product)?.customOption(amount: amount, unit: unit))
        return try XCTUnwrap(ProductNutritionCalculator(product: product).calculate(option: option, quantity: 1))
    }

    private func option(
        in product: FoodProduct,
        amount: Double,
        unit: ProductServingUnit
    ) throws -> ProductServingOption {
        let options = try XCTUnwrap(ProductServingOptions(product: product))
        if let option = options.options.first(where: { $0.amount == amount && $0.unit == unit }) {
            return option
        }
        return try XCTUnwrap(options.customOption(amount: amount, unit: unit))
    }

    private func assert(
        _ result: ProductNutritionCalculation,
        _ key: FoodNutrientKey,
        equals expected: Double,
        accuracy: Double = 1e-10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual = result.amount(for: key) else {
            return XCTFail("Missing \(key.rawValue)", file: file, line: line)
        }
        XCTAssertEqual(actual, expected, accuracy: accuracy, file: file, line: line)
    }
}
