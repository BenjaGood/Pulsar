//
//  MealScanResultView.swift
//  Pulsar
//

import SwiftUI

struct MealScanResultView: View {
    @Binding var result: MealScanResult
    @ObservedObject var nutritionStore: PulsarNutritionStore
    var initialCategoryID: UUID?
    var onRescan: () -> Void

    @State private var editingIngredient: MealIngredient?
    @State private var hasSaved = false
    @State private var saveErrorMessage: String?
    @State private var showingCalibration = false
    @State private var selectedCategoryID: UUID?

    private let calibrationStore = MealScanCalibrationStore.shared

    init(
        result: Binding<MealScanResult>,
        nutritionStore: PulsarNutritionStore,
        initialCategoryID: UUID? = nil,
        onRescan: @escaping () -> Void
    ) {
        self._result = result
        self.nutritionStore = nutritionStore
        self.initialCategoryID = initialCategoryID
        self.onRescan = onRescan
        _selectedCategoryID = State(initialValue: initialCategoryID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard
                macroGrid
                ingredientsSection
                micronutrientsSection
                accuracySection
                actions
                if hasSaved && result.usesMeasuredDepthForPortionEstimate {
                    calibrationPrompt
                }
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
        .sheet(isPresented: $showingCalibration) {
            MealCalibrationFeedbackView(
                ingredients: result.ingredients,
                calibrationStore: calibrationStore
            )
        }
    }

    private var calibrationPrompt: some View {
        Button {
            showingCalibration = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Improve future estimates")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.primary)
                    Text("Weigh a portion and confirm grams to calibrate depth estimates.")
                        .pulsarTextStyle(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .pulsarTextStyle(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
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

                HStack(spacing: 8) {
                    MealScannerCapabilityPill(
                        title: qualityLevelTitle,
                        symbolName: qualityLevelSymbolName,
                        tint: qualityLevelTint
                    )
                    MealScannerCapabilityPill(
                        title: depthCapabilityTitle,
                        symbolName: depthCapabilitySymbolName,
                        tint: depthCapabilityTint
                    )
                }
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
                    subtitle: hasSaved ? "Saved to your nutrition log" : "Tap Adjust to edit portions"
                )

                VStack(spacing: 10) {
                    ForEach(result.ingredients) { ingredient in
                        MealIngredientRow(
                            ingredient: ingredient,
                            usesMeasuredDepth: result.usesMeasuredDepthForPortionEstimate,
                            onAdjust: hasSaved ? nil : { editingIngredient = ingredient }
                        )
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

                confidenceBreakdownRow

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

                if needsScaleCalibrationPrompt {
                    Button {
                        showingCalibration = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "scalemass.fill")
                                .foregroundStyle(.cyan)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Use a food scale to calibrate")
                                    .pulsarTextStyle(.captionEmphasis)
                                    .foregroundStyle(.primary)
                                Text("Portion estimates have high uncertainty. Weigh a serving and tap to improve future scans.")
                                    .pulsarTextStyle(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .pulsarTextStyle(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Picker("Meal category", selection: selectedCategoryBinding) {
                ForEach(nutritionStore.state.mealCategories) { category in
                    Label(category.name, systemImage: category.symbolName).tag(Optional(category.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(hasSaved)

            Button(action: saveToNutrition) {
                Label(hasSaved ? "Saved to Nutrition" : "Save to Nutrition", systemImage: hasSaved ? "checkmark.circle.fill" : "plus.circle.fill")
                    .pulsarTextStyle(.buttonTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(NutritionActionButtonStyle(tint: hasSaved || !hasSavableIngredients ? .gray : .green))
            .disabled(hasSaved || !hasSavableIngredients)

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

    @ViewBuilder
    private var confidenceBreakdownRow: some View {
        if let breakdown = result.quality.confidenceBreakdown {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], alignment: .leading, spacing: 6) {
                if let foodRecognition = breakdown.foodRecognition {
                    MealConfidenceChip(
                        label: "Food ID",
                        value: foodRecognition,
                        tint: foodRecognition >= 0.60 ? .green : .orange
                    )
                }
                if let depthCoverage = breakdown.depthCoverage {
                    MealConfidenceChip(
                        label: "Depth",
                        value: depthCoverage,
                        tint: depthCoverage >= 0.60 ? .cyan : .orange
                    )
                }
                if let portionVolume = breakdown.portionVolume {
                    MealConfidenceChip(
                        label: "Weight",
                        value: portionVolume,
                        tint: portionVolume >= 0.60 ? .cyan : .orange
                    )
                }
                if let density = breakdown.density {
                    MealConfidenceChip(
                        label: "Density",
                        value: density,
                        tint: density >= 0.60 ? .mint : .orange
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private var allMicronutrients: [Micronutrient] {
        if !result.micronutrients.isEmpty {
            return result.micronutrients
        }
        return result.ingredients.flatMap(\.micronutrients)
    }

    private var qualityLevelTitle: String {
        let warnings = result.quality.warnings
        switch result.quality.level {
        case .excellent: return "Excellent scan"
        case .good:      return "Good scan"
        case .usable:
            if warnings.contains(where: { $0.lowercased().contains("angle") }) {
                return "Needs better angle"
            }
            return "Review portions"
        case .limited:
            if warnings.contains(where: { $0.lowercased().contains("coverage") || $0.lowercased().contains("depth") }) {
                return "Low depth coverage"
            }
            return "Limited quality"
        case .insufficient:
            return "Depth unavailable"
        }
    }

    private var qualityLevelSymbolName: String {
        switch result.quality.level {
        case .excellent:    return "checkmark.circle.fill"
        case .good:         return "checkmark.circle"
        case .usable:       return "exclamationmark.circle"
        case .limited:      return "exclamationmark.triangle"
        case .insufficient: return "xmark.circle"
        }
    }

    private var qualityLevelTint: Color {
        switch result.quality.level {
        case .excellent:    return .green
        case .good:         return .mint
        case .usable:       return .yellow
        case .limited:      return .orange
        case .insufficient: return .red.opacity(0.8)
        }
    }

    private var needsScaleCalibrationPrompt: Bool {
        guard result.quality.level == .limited
                || result.quality.level == .insufficient
                || result.metadata.needsUserReview
        else { return false }
        // Only show when quality is truly limited OR there is measurable gram-range uncertainty.
        if result.quality.level == .limited || result.quality.level == .insufficient { return true }
        let hasHighUncertainty = result.ingredients.contains { ingredient in
            guard let low = ingredient.gramsLow, let high = ingredient.gramsHigh,
                  ingredient.estimatedGrams > 1 else { return false }
            return (high - low) / ingredient.estimatedGrams > 0.50
        }
        return hasHighUncertainty
    }

    private var estimateMethodText: String {
        if result.usesMeasuredDepthForPortionEstimate {
            return "Estimated using image + measured depth volume"
        }
        if result.mode == .depthAssisted && result.quality.hasDepth {
            return "Estimated using photo AI with depth context"
        }
        return "Estimated using photo AI analysis"
    }

    private var depthCapabilityTitle: String {
        if result.usesMeasuredDepthForPortionEstimate {
            return "LiDAR volume measured"
        }
        if result.mode == .depthAssisted && result.quality.hasDepth {
            return "Depth context captured"
        }
        return "Photo AI estimation mode"
    }

    private var depthCapabilitySymbolName: String {
        result.quality.hasDepth ? "viewfinder.circle.fill" : "camera.fill"
    }

    private var depthCapabilityTint: Color {
        if result.usesMeasuredDepthForPortionEstimate {
            return .green
        }
        return result.quality.hasDepth ? .cyan : .orange
    }

    private var hasSavableIngredients: Bool {
        result.hasSavableMealScannerIngredients
    }

    private var selectedCategoryBinding: Binding<UUID?> {
        Binding(
            get: {
                selectedCategoryID ?? initialCategoryID ?? nutritionStore.defaultMealCategory(for: PulsarNutritionMealMoment.currentMealMoment()).id
            },
            set: { selectedCategoryID = $0 }
        )
    }

    private var selectedCategory: PulsarMealCategory {
        nutritionStore.resolvedMealCategory(
            id: selectedCategoryID ?? initialCategoryID,
            fallback: PulsarNutritionMealMoment.currentMealMoment()
        )
    }

    private func saveToNutrition() {
        saveErrorMessage = nil
        let validIngredients = result.ingredients.filter(\.mealScannerCanSave)
        guard !validIngredients.isEmpty else {
            saveErrorMessage = "Resolve ambiguous ingredients or add a positive portion before saving."
            return
        }

        let category = selectedCategory
        var savedCount = 0
        for ingredient in validIngredients {
            let food = PulsarFoodItem(
                name: ingredient.name,
                detail: ingredient.mealScannerSaveDetail,
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
            let note = [result.accuracyDisclaimer, ingredient.mealScannerAuditNote]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            nutritionStore.logFood(
                food,
                servingMultiplier: 1,
                mealMoment: category.baseMoment,
                categoryID: category.id,
                note: note,
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
    /// Whether the result used measured LiDAR depth — unlocks dual confidence and gram range display.
    var usesMeasuredDepth: Bool = false
    /// When non-nil, an explicit "Adjust" button is shown and calls this closure on tap.
    var onAdjust: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ingredient.name)
                        .pulsarTextStyle(.cardTitle)
                        .foregroundStyle(.primary)
                    Text(gramsSubtitle)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.secondary)
                    statusBadges
                }
                Spacer()
                if let onAdjust {
                    Button(action: onAdjust) {
                        Label("Adjust", systemImage: "slider.horizontal.3")
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(.cyan.opacity(0.88))
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(.cyan.opacity(0.12), in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Adjust grams for \(ingredient.name)")
                } else {
                    Text("\(Int((ingredient.confidence * 100).rounded()))%")
                        .pulsarTextStyle(.captionEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(.green)
                }
            }

            if usesMeasuredDepth {
                dualConfidenceRow
            }

            if ingredient.nutritionNeedsRecalculation {
                Label("Nutrition pending - verify portion/type", systemImage: "exclamationmark.triangle.fill")
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(.orange.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
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

    private var gramsSubtitle: String {
        let base = "\(PulsarNutritionFormatters.grams(ingredient.estimatedGrams)) · \(PulsarNutritionFormatters.calories(ingredient.calories)) cal"
        guard let rangeText else { return base }
        return "\(base) · \(rangeText)"
    }

    /// Returns "±X%" when gramsLow/gramsHigh are present and the spread is non-trivial.
    private var rangeText: String? {
        guard let low = ingredient.gramsLow, let high = ingredient.gramsHigh,
              ingredient.estimatedGrams > 1, high > low else { return nil }
        let relHalfRange = (high - low) / ingredient.estimatedGrams * 50
        guard relHalfRange > 4 else { return nil }
        return "±\(Int(relHalfRange.rounded()))%"
    }

    @ViewBuilder
    private var dualConfidenceRow: some View {
        HStack(spacing: 6) {
            MealConfidenceChip(
                label: "ID",
                value: ingredient.confidence,
                tint: ingredient.confidence >= 0.60 ? .green : .orange
            )
            if let rangeText {
                MealScanRangeChip(label: rangeText)
            }
            if let weightConfidence {
                MealConfidenceChip(
                    label: "Weight",
                    value: weightConfidence,
                    tint: weightConfidence >= 0.60 ? .cyan : .orange
                )
            }
        }
    }

    private var weightConfidence: Double? {
        guard let low = ingredient.gramsLow,
              let high = ingredient.gramsHigh,
              ingredient.estimatedGrams > 1,
              high > low else {
            return ingredient.estimatedVolumeMilliliters != nil && ingredient.densityUsed != nil ? 0.70 : nil
        }
        let relativeRange = (high - low) / ingredient.estimatedGrams
        return min(max(1 - (relativeRange * 0.55), 0.20), 0.95)
    }

    @ViewBuilder
    private var statusBadges: some View {
        HStack(spacing: 6) {
            if ingredient.wasUserCorrected {
                MealIngredientStatusChip(title: "User confirmed", symbolName: "checkmark.circle.fill", tint: .green)
            }
            if ingredient.wasKeptAsUnknown {
                MealIngredientStatusChip(title: "Needs review", symbolName: "exclamationmark.triangle.fill", tint: .orange)
            }
            if ingredient.nutritionNeedsRecalculation {
                MealIngredientStatusChip(title: "Nutrition pending", symbolName: "clock.badge.exclamationmark", tint: .orange)
            }
        }
    }
}

private struct MealIngredientStatusChip: View {
    var title: String
    var symbolName: String
    var tint: Color

    var body: some View {
        Label(title, systemImage: symbolName)
            .pulsarTextStyle(.overline)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule(style: .continuous))
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

/// Compact pill showing "Label XX%" for a dual-confidence row in a MealIngredientRow.
private struct MealConfidenceChip: View {
    var label: String
    var value: Double
    var tint: Color

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .pulsarTextStyle(.overline)
                .foregroundStyle(.secondary)
            Text("\(Int((value * 100).rounded()))%")
                .pulsarTextStyle(.overline)
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule(style: .continuous))
    }
}

/// Compact pill showing a gram-range string like "±12%" derived from gramsLow/gramsHigh.
private struct MealScanRangeChip: View {
    var label: String

    var body: some View {
        Text(label)
            .pulsarTextStyle(.overline)
            .monospacedDigit()
            .foregroundStyle(.orange.opacity(0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.orange.opacity(0.12), in: Capsule(style: .continuous))
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

// MARK: - Calibration Feedback

struct MealCalibrationFeedbackView: View {
    var ingredients: [MealIngredient]
    var calibrationStore: MealScanCalibrationStore

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [CalibrationEntry] = []
    @State private var hasSaved = false

    struct CalibrationEntry: Identifiable {
        var id: UUID
        var name: String
        var estimatedGrams: Double
        var foodForm: MealScanFoodForm
        var measuredText: String = ""

        var measuredGrams: Double? {
            let trimmed = measuredText.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : Double(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Weigh a portion, enter the actual grams, and Pulsar will adjust future depth-based estimates for that food type. Only items you enter are used.")
                        .pulsarTextStyle(.label)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                Section("Ingredients") {
                    ForEach($entries) { $entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.name)
                                .pulsarTextStyle(.cardTitle)
                            HStack(spacing: 10) {
                                Text("Estimated: \(PulsarNutritionFormatters.grams(entry.estimatedGrams))")
                                    .pulsarTextStyle(.captionEmphasis)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                TextField("Actual g", text: $entry.measuredText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                    .pulsarTextStyle(.captionEmphasis)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if hasSaved {
                    Section {
                        Label("Calibration saved.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .pulsarTextStyle(.captionEmphasis)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Calibrate Estimates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveCalibration() }
                        .disabled(hasSaved || !hasAnyEntry)
                }
            }
        }
        .onAppear { buildEntries() }
    }

    private var hasAnyEntry: Bool {
        entries.contains { $0.measuredGrams != nil }
    }

    private func buildEntries() {
        entries = ingredients
            .filter { $0.estimatedGrams > 1 }
            .map { ingredient in
                CalibrationEntry(
                    id: ingredient.id,
                    name: ingredient.name,
                    estimatedGrams: ingredient.estimatedGrams,
                    foodForm: MealScanFoodForm.classify(from: ingredient.name)
                )
            }
    }

    private func saveCalibration() {
        for entry in entries {
            guard let measured = entry.measuredGrams, measured > 1 else { continue }
            calibrationStore.record(
                estimatedGrams: entry.estimatedGrams,
                measuredGrams: measured,
                foodForm: entry.foodForm
            )
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { hasSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
    }
}

// MARK: - Meal Moment

extension PulsarNutritionMealMoment {
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
