import Foundation
import Observation

enum FoodContributionCaptureStep: String, CaseIterable, Identifiable {
    case front
    case nutrition
    case ingredients
    case review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front: "Front of package"
        case .nutrition: "Nutrition label"
        case .ingredients: "Ingredients list"
        case .review: "Review product"
        }
    }

    var guidance: String {
        switch self {
        case .front: "Center the product name and brand."
        case .nutrition: "Keep the full nutrition panel flat and readable."
        case .ingredients: "Capture the complete ingredients and allergen statement."
        case .review: "Confirm every value before submitting."
        }
    }
}

enum FoodContributionInputMode: Equatable, Sendable {
    case assistedOCR
    case manual
}

struct EditableFoodNutrient: Identifiable {
    var id: FoodNutrientKey { key }
    var key: FoodNutrientKey
    var amount: Double?
    var confidence: Double?
}

@MainActor
@Observable
final class FoodContributionDraftModel {
    var step: FoodContributionCaptureStep = .front
    private(set) var inputMode: FoodContributionInputMode = .assistedOCR
    var name: String
    var brand: String
    var allergensText: String
    var packageQuantity: Double?
    var packageUnit: String
    var servingQuantity: Double?
    var servingUnit: String
    var servingWeight: Double?
    var servingWeightUnit: String
    var servingsPerContainer: Double?
    var ingredients: String
    var basis: FoodNutrientBasis
    var nutrients: [EditableFoodNutrient]
    var evidence = FoodEvidenceImages()
    var uncertainFields: Set<String> = []
    var isRecognizing = false
    var isSubmitting = false
    var errorMessage: String?
    private(set) var submissionStatus: FoodContributionSubmissionStatus = .draft

    let originalProduct: FoodProduct
    let contributionType: FoodContributionType
    private let submissionID = UUID()
    private let ocr: any NutritionLabelOCRServing
    private let contributions: any FoodContributionServing
    private let packageTextParser = FoodPackageTextParser()

    private var sourceBasis: FoodNutrientBasis

    init(
        product: FoodProduct,
        contributionType: FoodContributionType,
        ocr: any NutritionLabelOCRServing = NutritionLabelOCRService(),
        contributions: any FoodContributionServing = FoodContributionService.live()
    ) {
        originalProduct = product
        self.contributionType = contributionType
        name = product.name
        brand = product.brand ?? ""
        allergensText = product.allergens.joined(separator: ", ")
        packageQuantity = product.packageQuantity
        packageUnit = product.packageUnit ?? "g"
        servingQuantity = product.serving?.quantity
        servingUnit = product.serving?.unit ?? "serving"
        servingWeight = product.serving?.gramWeight ?? product.serving?.milliliterVolume
        servingWeightUnit = product.serving?.milliliterVolume != nil ? "ml" : "g"
        servingsPerContainer = product.servingsPerContainer
        ingredients = product.ingredients ?? ""
        let initialBasis = product.nutrients.first?.basis ?? FoodNutrientBasis.perServing
        sourceBasis = initialBasis
        basis = Self.preferredDisplayBasis(for: product, sourceBasis: initialBasis)
        let keys: [FoodNutrientKey] = [
            .energyKcal, .protein, .carbohydrates, .fat, .saturatedFat, .transFat, .fiber,
            .sugars, .addedSugars, .sodium, .salt, .cholesterol, .calcium, .iron, .potassium, .vitaminD
        ]
        nutrients = keys.map { key in
            let existing = product.nutrient(for: key, preferredBasis: initialBasis)
            return EditableFoodNutrient(key: key, amount: existing?.amount, confidence: existing?.confidence)
        }
        self.ocr = ocr
        self.contributions = contributions
    }

    var availableBases: [FoodNutrientBasis] {
        FoodNutrientBasis.allCases.filter { nutritionAmount(for: .energyKcal, basis: $0) != nil }
    }

    func nutrientAmount(for key: FoodNutrientKey) -> Double? {
        nutritionAmount(for: key, basis: basis)
    }

    var canReview: Bool {
        inputMode == .manual || evidence.nutrition != nil
    }

    var canSubmit: Bool {
        blockingValidationMessage == nil && !isSubmitting
    }

    var blockingValidationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add a product name to save."
        }
        guard let barcode = originalProduct.barcode,
              barcode.count == 14,
              barcode.allSatisfy({ $0.isNumber }) else {
            return "A barcode is required to save this product."
        }
        if !canReview {
            return "Capture the nutrition label or enter the product manually."
        }
        if let packageQuantity, !isPositiveFinite(packageQuantity) {
            return "Package amount must be greater than zero."
        }
        if let servingQuantity, !isPositiveFinite(servingQuantity) {
            return "Serving size must be greater than zero."
        }
        if let servingWeight, !isPositiveFinite(servingWeight) {
            return "Serving weight must be greater than zero."
        }
        if let servingsPerContainer, !isPositiveFinite(servingsPerContainer) {
            return "Servings per container must be greater than zero."
        }
        if nutrients.contains(where: { nutrient in
            guard let amount = nutrient.amount else { return false }
            return !amount.isFinite || amount < 0
        }) {
            return "Nutrition values must be zero or greater."
        }
        return nil
    }

    func captured(_ data: Data, for step: FoodContributionCaptureStep) async {
        switch step {
        case .front:
            evidence.front = data
            await recognizePackageText(data) { [self] text in
                let proposal = packageTextParser.frontProposal(from: text)
                if name.isEmpty, let proposedName = proposal.name { name = proposedName }
                if brand.isEmpty, let proposedBrand = proposal.brand { brand = proposedBrand }
            }
            self.step = .nutrition
        case .nutrition:
            evidence.nutrition = data
            isRecognizing = true
            do {
                let result = try await ocr.recognize(imageData: data)
                apply(result)
            } catch {
                errorMessage = "Pulsar could not read this label automatically. You can enter the values during review."
            }
            isRecognizing = false
            self.step = .ingredients
        case .ingredients:
            evidence.ingredients = data
            await recognizePackageText(data) { [self] text in
                if let extracted = packageTextParser.ingredientsText(from: text) {
                    ingredients = extracted
                }
            }
            self.step = .review
        case .review:
            break
        }
    }

    func enterManualEntry() {
        inputMode = .manual
        step = .review
    }

    private func recognizePackageText(_ data: Data, apply: @escaping @MainActor (String) -> Void) async {
        isRecognizing = true
        if let result = try? await ocr.recognize(imageData: data) {
            apply(result.recognizedText)
        }
        isRecognizing = false
    }

    func submit() async throws -> FoodProduct {
        guard canSubmit else { throw FoodCommunityServiceError.invalidResponse }
        isSubmitting = true
        defer { isSubmitting = false }
        let product = confirmedProduct()
        submissionStatus = .saving
        do {
            let savedContribution = try await contributions.submit(
                submissionID: submissionID,
                product: product,
                type: contributionType
            )
            submissionStatus = .pendingReview
            var savedProduct = product
            if let productID = savedContribution.productID {
                savedProduct.id = productID
            }
            evidence = FoodEvidenceImages()
            return savedProduct
        } catch {
            submissionStatus = .failed
            throw error
        }
    }

    func confirmedProduct() -> FoodProduct {
        var product = originalProduct
        product.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        product.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        product.allergens = allergensText
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        product.packageQuantity = packageQuantity
        product.packageUnit = packageUnit.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if servingQuantity != nil || servingWeight != nil {
            product.serving = FoodServing(
                quantity: servingQuantity ?? 1,
                unit: servingUnit,
                gramWeight: servingWeightIfMass,
                milliliterVolume: servingWeightIfVolume
            )
        } else {
            product.serving = nil
        }
        product.servingsPerContainer = servingsPerContainer
        product.ingredients = ingredients.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        product.source = .pulsarCommunity
        product.verificationStatus = .photoVerified
        product.nutrients = nutrients.compactMap { nutrient in
            nutrient.amount.map {
                FoodNutrient(
                    key: nutrient.key,
                    amount: $0,
                    basis: sourceBasis,
                    confidence: nutrient.confidence
                )
            }
        }
        product.updatedAt = .now
        return product
    }

    private func apply(_ result: NutritionLabelOCRResult) {
        if let serving = result.serving {
            servingQuantity = serving.quantity
            servingUnit = serving.unit
            servingWeight = serving.gramWeight ?? serving.milliliterVolume
            servingWeightUnit = serving.milliliterVolume != nil ? "ml" : "g"
        }
        servingsPerContainer = result.servingsPerContainer ?? servingsPerContainer
        sourceBasis = result.basis
        basis = Self.preferredDisplayBasis(for: currentProduct, sourceBasis: sourceBasis)
        uncertainFields.formUnion(result.uncertainFields)
        for detected in result.nutrients {
            guard let index = nutrients.firstIndex(where: { $0.key == detected.key }) else { continue }
            nutrients[index].amount = detected.amount
            nutrients[index].confidence = detected.confidence
        }
    }

    private var servingWeightIfMass: Double? {
        guard servingWeightUnit.lowercased() != "ml" else { return nil }
        return servingWeight
    }

    private var servingWeightIfVolume: Double? {
        guard servingWeightUnit.lowercased() == "ml" else { return nil }
        return servingWeight
    }

    private var currentProduct: FoodProduct { confirmedProduct() }

    private func isPositiveFinite(_ value: Double) -> Bool {
        value.isFinite && value > 0
    }

    private func nutritionAmount(for key: FoodNutrientKey, basis targetBasis: FoodNutrientBasis) -> Double? {
        let product = currentProduct
        guard let options = ProductServingOptions(product: product),
              let option = option(for: targetBasis, product: product, options: options),
              let calculation = ProductNutritionCalculator(product: product).calculate(option: option, quantity: 1)
        else { return nil }
        return calculation.amount(for: key)
    }

    private func option(
        for targetBasis: FoodNutrientBasis,
        product: FoodProduct,
        options: ProductServingOptions
    ) -> ProductServingOption? {
        switch targetBasis {
        case .perServing:
            guard let serving = product.serving else { return nil }
            return ProductServingOption(
                id: "review-serving",
                amount: serving.quantity,
                unit: ProductServingUnit.normalized(serving.unit) ?? .serving,
                unitLabel: serving.unit,
                equivalentGrams: serving.gramWeight,
                equivalentMilliliters: serving.milliliterVolume,
                manufacturerServingCount: 1
            )
        case .per100Grams:
            return options.options.first { $0.unit == .gram && abs($0.amount - 100) < 0.0001 }
        case .per100Milliliters:
            return options.options.first { $0.unit == .milliliter && abs($0.amount - 100) < 0.0001 }
        case .perPackage:
            return nil
        }
    }

    private static func preferredDisplayBasis(for product: FoodProduct, sourceBasis: FoodNutrientBasis) -> FoodNutrientBasis {
        guard let serving = product.serving else { return sourceBasis }
        let hasMassServing = serving.gramWeight?.isFinite == true && (serving.gramWeight ?? 0) > 0
        let hasVolumeServing = serving.milliliterVolume?.isFinite == true && (serving.milliliterVolume ?? 0) > 0
        if sourceBasis == .perServing || (hasMassServing && sourceBasis == .per100Grams) || (hasVolumeServing && sourceBasis == .per100Milliliters) {
            return .perServing
        }
        return sourceBasis
    }
}

enum FoodContributionSubmissionStatus: Equatable, Sendable {
    case draft
    case saving
    case pendingReview
    case failed
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
