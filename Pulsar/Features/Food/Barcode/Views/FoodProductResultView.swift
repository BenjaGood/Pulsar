import SwiftUI

struct FoodProductResultView: View {
    var product: FoodProduct
    var addAction: (Double) -> Void
    var labelChangedAction: () -> Void

    @State private var servingMultiplier = 1.0

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                FoodProductIdentityView(product: product)
                FoodServingSelector(
                    serving: product.serving,
                    isEstimated: product.servingIsEstimated,
                    multiplier: $servingMultiplier
                )
                FoodProductNutrientsView(product: product, servingMultiplier: servingMultiplier)
                FoodProductDetailsView(product: product)

                Button("Add to Meal", systemImage: "plus.circle.fill", action: add)
                    .buttonStyle(NutritionActionButtonStyle(tint: .green))
                    .frame(maxWidth: .infinity)
                    .disabled(product.pulsarFoodItem() == nil)

                if product.barcode != nil {
                    Button("The label has changed", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90", action: labelChangedAction)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }

                FoodProductAttributionView(product: product)
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
        .background(PulsarSectionBackground())
        .navigationTitle("Product")
        .toolbarTitleDisplayMode(.inline)
    }

    private func add() {
        addAction(servingMultiplier)
    }
}

private struct FoodProductIdentityView: View {
    var product: FoodProduct

    var body: some View {
        PulsarNutritionGlassCard(cornerRadius: 24) {
            HStack(alignment: .top, spacing: 14) {
                AsyncImage(url: product.frontImageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        Image(systemName: "shippingbox.fill")
                            .resizable()
                            .scaledToFit()
                            .padding()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 92, height: 92)
                .background(.quaternary, in: .rect(cornerRadius: 16))
                .accessibilityLabel(product.name)

                VStack(alignment: .leading, spacing: 6) {
                    Text(product.name).font(.title3).bold()
                    if let brand = product.brand { Text(brand).foregroundStyle(.secondary) }
                    Label(product.verificationStatus.title, systemImage: verificationSymbol)
                        .font(.footnote)
                        .foregroundStyle(product.verificationStatus.isTrusted ? .green : .secondary)
                    if let verifiedAt = product.verifiedAt ?? product.sourceUpdatedAt {
                        Text("Verified \(verifiedAt, format: .dateTime.day().month().year())")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var verificationSymbol: String {
        product.verificationStatus.isTrusted ? "checkmark.seal.fill" : "info.circle"
    }
}

private struct FoodServingSelector: View {
    var serving: FoodServing?
    var isEstimated: Bool
    @Binding var multiplier: Double
    @State private var grams = 100.0

    var body: some View {
        PulsarNutritionGlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                NutritionSectionHeader(title: "Serving", subtitle: serving?.displayText ?? "1 serving")
                if serving != nil {
                    Text(productServingDisclosure)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if isEstimated {
                    TextField("Grams", value: $grams, format: .number)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: grams) { _, newValue in
                            multiplier = max(newValue, 0) / 100
                        }
                } else {
                    Stepper(value: $multiplier, in: 0.25...20, step: 0.25) {
                        LabeledContent("Amount") {
                            Text(multiplier, format: .number.precision(.fractionLength(0...2)))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private var productServingDisclosure: String {
        if serving == nil { return "Enter grams directly" }
        return isEstimated
            ? "No convertible serving was supplied; Pulsar uses a 100 g reference serving"
            : "Amounts use the dataset’s declared serving"
    }
}

private struct FoodProductNutrientsView: View {
    var product: FoodProduct
    var servingMultiplier: Double

    var body: some View {
        PulsarNutritionGlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                NutritionSectionHeader(title: "Nutrition")
                ForEach(availableNutrients, id: \.key) { item in
                    LabeledContent(item.key.title) {
                        Text(item.amount, format: .number.precision(.fractionLength(0...2)))
                            .monospacedDigit()
                        Text(" \(item.key.canonicalUnit)").foregroundStyle(.secondary)
                    }
                    if item.key != availableNutrients.last?.key { Divider() }
                }
            }
        }
    }

    private var availableNutrients: [(key: FoodNutrientKey, amount: Double)] {
        let ordered: [FoodNutrientKey] = [
            .energyKcal, .protein, .carbohydrates, .fat, .saturatedFat, .transFat, .fiber,
            .sugars, .addedSugars, .sodium, .salt, .cholesterol, .calcium, .iron, .potassium, .vitaminD
        ]
        return ordered.compactMap { key in
            product.nutrientAmount(key, servingMultiplier: servingMultiplier).map { (key, $0) }
        }
    }
}

private struct FoodProductDetailsView: View {
    var product: FoodProduct

    var body: some View {
        PulsarNutritionGlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                NutritionSectionHeader(title: "Product details")
                LabeledContent("Source", value: product.source.title)
                if let version = product.sourceDatasetVersion {
                    LabeledContent("Dataset version", value: version)
                }
                if let disclosure = product.estimationDisclosure {
                    Label(disclosure, systemImage: product.isAIEstimated == true ? "sparkles" : "questionmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let ingredients = product.ingredients, !ingredients.isEmpty {
                    Text("Ingredients").font(.headline)
                    Text(ingredients).foregroundStyle(.secondary)
                }
                if !product.allergens.isEmpty {
                    Text("Allergens").font(.headline)
                    Text(product.allergens.joined(separator: ", ")).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct FoodProductAttributionView: View {
    var product: FoodProduct

    var body: some View {
        if product.requiresOpenNutritionAttribution {
            VStack(alignment: .leading, spacing: 6) {
                Link(destination: URL(string: "https://www.opennutrition.app")!) {
                    Label("Nutrition data from OpenNutrition", systemImage: "arrow.up.right.square")
                }
                if product.requiresOpenFoodFactsAttribution,
                   let url = URL(string: "https://world.openfoodfacts.org") {
                    Link("(c) Open Food Facts contributors", destination: url)
                }
                Text("Open Database License (ODbL) · database contents under DbCL")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else if product.requiresOpenFoodFactsAttribution,
                  let url = URL(string: "https://world.openfoodfacts.org") {
            Link("(c) Open Food Facts contributors", destination: url)
                .font(.footnote)
        }
    }
}
