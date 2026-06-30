//
//  MealScanResultView.swift
//  Pulsar
//

import SwiftUI

struct MealScanResultView: View {
    @Binding var result: MealScanResult
    @ObservedObject var nutritionStore: PulsarNutritionStore
    var onRescan: () -> Void

    @State private var editingIngredient: MealIngredient?
    @State private var hasSaved = false
    @State private var saveErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard
                macroGrid
                ingredientsSection
                micronutrientsSection
                accuracySection
                actions
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .background(PulsarSectionBackground())
        .sheet(item: $editingIngredient) { ingredient in
            MealIngredientEditView(ingredient: ingredient) { newGrams in
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    result.updateIngredient(id: ingredient.id, estimatedGrams: newGrams)
                    editingIngredient = nil
                }
            }
        }
    }

    private var summaryCard: some View {
        PulsarNutritionGlassCard(cornerRadius: 32) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.title)
                            .pulsarTextStyle(.sectionTitle)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(result.summary.isEmpty ? "\(estimateMethodText)." : result.summary)
                            .pulsarTextStyle(.screenSubtitle)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(Int((result.confidence * 100).rounded()))%")
                            .pulsarMonospacedMetric(.metricValue)
                            .foregroundStyle(.green)
                        Text("confidence")
                            .pulsarTextStyle(.overline)
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: 10) {
                    MealScanHeroMetric(
                        title: "Calories",
                        value: PulsarNutritionFormatters.calories(result.totalCalories),
                        unit: "cal",
                        tint: .orange
                    )
                    MealScanHeroMetric(
                        title: "Total",
                        value: PulsarNutritionFormatters.grams(result.totalEstimatedGrams),
                        unit: "est.",
                        tint: .cyan
                    )
                }

                MealScannerCapabilityPill(
                    title: result.mode == .depthAssisted && result.quality.hasDepth ? "LiDAR depth enabled" : "Photo AI estimation mode",
                    symbolName: result.quality.hasDepth ? "viewfinder.circle.fill" : "camera.fill",
                    tint: result.quality.hasDepth ? .cyan : .orange
                )
            }
        }
    }

    private var macroGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MealScanMacroTile(title: "Carbohydrates", value: PulsarNutritionFormatters.grams(result.totalCarbs), tint: .teal)
            MealScanMacroTile(title: "Protein", value: PulsarNutritionFormatters.grams(result.totalProtein), tint: .green)
            MealScanMacroTile(title: "Fat", value: PulsarNutritionFormatters.grams(result.totalFat), tint: .pink)
            MealScanMacroTile(title: "Fiber", value: PulsarNutritionFormatters.grams(result.totalFiber), tint: .mint)
        }
    }

    private var ingredientsSection: some View {
        PulsarNutritionGlassCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 14) {
                NutritionSectionHeader(
                    title: "Ingredients",
                    subtitle: hasSaved ? "Saved to your nutrition log" : "Tap a row to adjust grams"
                )

                VStack(spacing: 10) {
                    ForEach(result.ingredients) { ingredient in
                        if hasSaved {
                            MealIngredientRow(ingredient: ingredient)
                        } else {
                            Button {
                                editingIngredient = ingredient
                            } label: {
                                MealIngredientRow(ingredient: ingredient)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if hasSaved {
                    Text("Saved entries can be adjusted from the Food tab.")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var micronutrientsSection: some View {
        let nutrients = allMicronutrients
        if !nutrients.isEmpty {
            PulsarNutritionGlassCard(cornerRadius: 30) {
                VStack(alignment: .leading, spacing: 14) {
                    NutritionSectionHeader(title: "Micronutrients", subtitle: "Vitamins and minerals from visible foods")

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(nutrients.prefix(8)) { nutrient in
                            MealMicronutrientPill(nutrient: nutrient)
                        }
                    }
                }
            }
        }
    }

    private var accuracySection: some View {
        PulsarNutritionGlassCard(cornerRadius: 28) {
            VStack(alignment: .leading, spacing: 10) {
                NutritionSectionHeader(title: "Accuracy", subtitle: estimateMethodText)

                Text(result.accuracyDisclaimer)
                    .pulsarTextStyle(.label)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !result.quality.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(result.quality.warnings.prefix(3), id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .pulsarTextStyle(.captionEmphasis)
                                .foregroundStyle(.orange.opacity(0.88))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button(action: saveToNutrition) {
                Label(hasSaved ? "Saved to Nutrition" : "Save to Nutrition", systemImage: hasSaved ? "checkmark.circle.fill" : "plus.circle.fill")
                    .pulsarTextStyle(.buttonTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(NutritionActionButtonStyle(tint: hasSaved ? .gray : .green))
            .disabled(hasSaved)

            if let saveErrorMessage {
                Label(saveErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(.orange.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onRescan) {
                Label("Rescan", systemImage: "arrow.clockwise")
                    .pulsarTextStyle(.buttonTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(NutritionActionButtonStyle(tint: .cyan))
        }
    }

    private var allMicronutrients: [Micronutrient] {
        if !result.micronutrients.isEmpty {
            return result.micronutrients
        }
        return result.ingredients.flatMap(\.micronutrients)
    }

    private var estimateMethodText: String {
        result.mode == .depthAssisted && result.quality.hasDepth
            ? "Estimated using image + depth analysis"
            : "Estimated using photo AI analysis"
    }

    private func saveToNutrition() {
        saveErrorMessage = nil
        let validIngredients = result.ingredients.filter { $0.estimatedGrams > 0 }
        guard !validIngredients.isEmpty else {
            saveErrorMessage = "No positive ingredient portions are available to save."
            return
        }

        let moment = PulsarNutritionMealMoment.currentMealMoment()
        var savedCount = 0
        for ingredient in validIngredients {
            let food = PulsarFoodItem(
                name: ingredient.name,
                detail: "3D Meal Scanner estimate",
                serving: PulsarNutritionServing(amount: 1, unit: "scan", grams: ingredient.estimatedGrams),
                nutritionPerServing: PulsarNutritionFacts(
                    calories: ingredient.calories,
                    protein: ingredient.protein,
                    carbohydrates: ingredient.carbs,
                    fat: ingredient.fat,
                    fiber: ingredient.fiber,
                    sugar: ingredient.sugar,
                    sodiumMilligrams: ingredient.sodium
                ),
                source: .aiMealRecognition,
                metadata: PulsarFoodMetadata(
                    externalReference: PulsarNutritionExternalReference(
                        provider: .aiMealRecognition,
                        identifier: result.id.uuidString,
                        lastSyncedAt: result.createdAt
                    )
                )
            )
            nutritionStore.logFood(
                food,
                servingMultiplier: 1,
                mealMoment: moment,
                note: result.accuracyDisclaimer,
                confidence: min(result.confidence, ingredient.confidence),
                source: .aiMealRecognition,
                loggedAt: result.createdAt
            )
            savedCount += 1
            if let persistenceError = nutritionStore.lastPersistenceError {
                saveErrorMessage = persistenceError
                return
            }
        }

        guard savedCount > 0 else {
            saveErrorMessage = "No meal items were saved."
            return
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            hasSaved = true
        }
    }
}

struct MealScanHeroMetric: View {
    var title: String
    var value: String
    var unit: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .pulsarTextStyle(.overline)
                .foregroundStyle(.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .pulsarMonospacedMetric(.metricValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(unit)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(tint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct MealScanMacroTile: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .pulsarTextStyle(.metricLabel)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            Text(value)
                .pulsarTextStyle(.cardTitle)
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct MealIngredientRow: View {
    var ingredient: MealIngredient

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ingredient.name)
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(.primary)
                    Text("\(PulsarNutritionFormatters.grams(ingredient.estimatedGrams)) · \(PulsarNutritionFormatters.calories(ingredient.calories)) cal")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int((ingredient.confidence * 100).rounded()))%")
                    .pulsarTextStyle(.captionEmphasis)
                    .monospacedDigit()
                    .foregroundStyle(.green)
            }

            HStack(spacing: 8) {
                MealMiniMacro(title: "P", value: ingredient.protein, tint: .green)
                MealMiniMacro(title: "C", value: ingredient.carbs, tint: .teal)
                MealMiniMacro(title: "F", value: ingredient.fat, tint: .pink)
                MealMiniMacro(title: "Fiber", value: ingredient.fiber, tint: .mint)
            }

            if let reasoning = ingredient.reasoning, !reasoning.isEmpty {
                Text(reasoning)
                    .pulsarTextStyle(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.060), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct MealMiniMacro: View {
    var title: String
    var value: Double
    var tint: Color

    var body: some View {
        Text("\(title) \(PulsarNutritionFormatters.grams(value))")
            .pulsarTextStyle(.overline)
            .lineLimit(1)
            .minimumScaleFactor(0.70)
            .foregroundStyle(tint.opacity(0.94))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule(style: .continuous))
    }
}

private struct MealMicronutrientPill: View {
    var nutrient: Micronutrient

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(nutrient.name)
                .pulsarTextStyle(.captionEmphasis)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            Text(amountText)
                .pulsarTextStyle(.overline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.070), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var amountText: String {
        let amount = PulsarNutritionFormatters.decimal(nutrient.amount)
        if let percent = nutrient.percentDailyValue {
            return "\(amount)\(nutrient.unit) · \(Int(percent.rounded()))% DV"
        }
        return "\(amount)\(nutrient.unit)"
    }
}

private extension PulsarNutritionMealMoment {
    static func currentMealMoment(date: Date = Date(), calendar: Calendar = .current) -> PulsarNutritionMealMoment {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<22: return .dinner
        default: return .snacks
        }
    }
}
