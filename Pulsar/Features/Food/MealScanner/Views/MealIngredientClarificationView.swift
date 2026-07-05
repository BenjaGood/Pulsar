//
//  MealIngredientClarificationView.swift
//  Pulsar
//

import SwiftUI

struct MealIngredientClarificationView: View {
    @State private var workingResult: MealScanResult
    @State private var typedName = ""
    @State private var selectedSuggestion: String?
    @State private var isResolving = false
    @State private var resolveErrorMessage: String?
    @FocusState private var isTextFieldFocused: Bool

    private let initialAmbiguousCount: Int
    private let nutritionAIService: MealNutritionAIServicing
    private let onComplete: (MealScanResult) -> Void

    init(
        result: MealScanResult,
        nutritionAIService: MealNutritionAIServicing = MealNutritionAIService(),
        onComplete: @escaping (MealScanResult) -> Void
    ) {
        self._workingResult = State(initialValue: result)
        self.initialAmbiguousCount = max(1, result.ambiguousIngredients.count)
        self.nutritionAIService = nutritionAIService
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard

                    if let ingredient = currentIngredient {
                        evidenceCard(for: ingredient)
                        inputCard(for: ingredient)
                        if let resolveErrorMessage {
                            resolveErrorCard(resolveErrorMessage)
                        }
                        actionButtons(for: ingredient)
                    }
                }
                .padding(18)
            }
            .background(PulsarSectionBackground())
            .navigationTitle("Confirm ingredient")
            .toolbarTitleDisplayMode(.inline)
        }
        .presentationBackground(.regularMaterial)
        .onChange(of: currentIngredient?.id) { _, _ in
            typedName = ""
            selectedSuggestion = nil
            resolveErrorMessage = nil
        }
    }

    private func resolveErrorCard(_ message: String) -> some View {
        Label(message, systemImage: "wifi.exclamationmark")
            .pulsarTextStyle(.captionEmphasis)
            .foregroundStyle(.orange.opacity(0.9))
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var currentIngredient: MealIngredient? {
        workingResult.ambiguousIngredients.first
    }

    private var currentStepText: String {
        let remaining = workingResult.ambiguousIngredients.count
        let current = min(initialAmbiguousCount, max(1, initialAmbiguousCount - remaining + 1))
        return "\(current) of \(initialAmbiguousCount)"
    }

    private var resolvedInputName: String {
        let typed = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return selectedSuggestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var headerCard: some View {
        PulsarNutritionGlassCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    MealScannerCapabilityPill(
                        title: currentStepText,
                        symbolName: "questionmark.bubble.fill",
                        tint: .cyan
                    )
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Help Pulsar identify this ingredient")
                        .pulsarTextStyle(.sectionTitle)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle(for: currentIngredient?.resolvedAmbiguityType ?? .unknown))
                        .pulsarTextStyle(.label)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func evidenceCard(for ingredient: MealIngredient) -> some View {
        PulsarNutritionGlassCard(cornerRadius: 26) {
            VStack(alignment: .leading, spacing: 12) {
                NutritionSectionHeader(
                    title: ingredient.name,
                    subtitle: "\(PulsarNutritionFormatters.decimal(ingredient.estimatedGrams))g estimated"
                )

                if let evidence = ingredient.ambiguityEvidenceText {
                    Text(evidence)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Current nutrition is from the uncertain label. Pulsar will mark it pending until recalculated or verified.")
                    .pulsarTextStyle(.caption)
                    .foregroundStyle(.orange.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func inputCard(for ingredient: MealIngredient) -> some View {
        PulsarNutritionGlassCard(cornerRadius: 26) {
            VStack(alignment: .leading, spacing: 14) {
                NutritionSectionHeader(title: "Confirm type", subtitle: ingredient.clarificationQuestion)

                TextField(placeholder(for: ingredient.resolvedAmbiguityType), text: $typedName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(false)
                    .textFieldStyle(.roundedBorder)
                    .focused($isTextFieldFocused)
                    .onChange(of: typedName) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            selectedSuggestion = nil
                        }
                    }

                FlowLayout(spacing: 8, rowSpacing: 8) {
                    ForEach(ingredient.ambiguitySuggestions, id: \.self) { suggestion in
                        Button {
                            selectedSuggestion = suggestion
                            typedName = ""
                            isTextFieldFocused = false
                        } label: {
                            Text(suggestion)
                                .pulsarTextStyle(.captionEmphasis)
                                .foregroundStyle(selectedSuggestion == suggestion ? .black : .cyan)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedSuggestion == suggestion ? .cyan : .cyan.opacity(0.14), in: Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        selectedSuggestion = nil
                        typedName = ""
                        isTextFieldFocused = true
                    } label: {
                        Label("Other", systemImage: "keyboard")
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.08), in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func actionButtons(for ingredient: MealIngredient) -> some View {
        VStack(spacing: 10) {
            Button {
                confirmResolution(for: ingredient)
            } label: {
                HStack(spacing: 8) {
                    if isResolving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    Text(isResolving ? "Recalculating..." : "Confirm")
                }
                .pulsarTextStyle(.buttonTitle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
            }
            .buttonStyle(NutritionActionButtonStyle(tint: .green))
            .disabled(resolvedInputName.isEmpty || isResolving)
            .opacity(resolvedInputName.isEmpty ? 0.55 : 1)

            Button {
                apply(ingredient.keepingAsUnknown())
            } label: {
                Label("Keep as unknown", systemImage: "exclamationmark.triangle.fill")
                    .pulsarTextStyle(.buttonTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(NutritionActionButtonStyle(tint: .orange))
            .disabled(isResolving)

            if ingredient.resolvedAmbiguityType == .protein {
                Button {
                    apply(ingredient.reclassifyingAmbiguityAsGenericIngredient())
                } label: {
                    Text("Not a protein")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .disabled(isResolving)
            }
        }
    }

    private func confirmResolution(for ingredient: MealIngredient) {
        let locallyResolved = ingredient.resolvingAmbiguity(as: resolvedInputName)
        guard locallyResolved.wasUserCorrected else { return }
        Task { await performResolution(originalIngredient: ingredient, locallyResolved: locallyResolved) }
    }

    /// Calls the Phase 3 resolve endpoint to derive honest nutrition for the confirmed
    /// food. On any failure this falls back to the Phase 1 behavior (corrected name,
    /// unchanged grams, `nutritionNeedsRecalculation = true`) rather than faking macros.
    @MainActor
    private func performResolution(originalIngredient: MealIngredient, locallyResolved: MealIngredient) async {
        isResolving = true
        resolveErrorMessage = nil
        defer { isResolving = false }

        let request = MealIngredientResolveRequest(
            ingredientId: locallyResolved.id.uuidString,
            originalName: locallyResolved.originalName ?? originalIngredient.name,
            replacementName: locallyResolved.name,
            grams: locallyResolved.estimatedGrams,
            ambiguityType: originalIngredient.resolvedAmbiguityType.rawValue,
            recalculateNutrition: true,
            payloadContext: MealIngredientResolveContext(
                mode: workingResult.mode,
                currentMealTotals: workingResult.totals,
                currentIngredientNutrition: originalIngredient.nutrition,
                volumeEstimate: nil,
                calibrationFactors: nil
            ),
            imageBase64: nil
        )

        do {
            let response = try await nutritionAIService.resolveIngredient(request)
            apply(locallyResolved.mergingRecalculatedNutrition(from: response.updatedIngredient))
        } catch {
            resolveErrorMessage = "Live nutrition recalculation is unavailable right now. Using an estimate you can verify later."
            apply(locallyResolved)
        }
    }

    private func subtitle(for type: MealIngredientAmbiguityType) -> String {
        switch type {
        case .protein:
            return "We detected a protein, but need your confirmation for better nutrition accuracy."
        case .sauce:
            return "We detected a sauce or dressing, but need your confirmation before saving."
        case .topping:
            return "We detected a topping, but need your confirmation before saving."
        case .ingredient:
            return "We detected a food item, but need your confirmation for better nutrition accuracy."
        case .unknown:
            return "The image evidence is ambiguous. Confirm the ingredient or keep it marked for review."
        }
    }

    private func placeholder(for type: MealIngredientAmbiguityType) -> String {
        switch type {
        case .protein:
            return "Type protein, e.g. chicken, beef, tofu..."
        case .sauce:
            return "Type sauce, e.g. salsa, dressing..."
        case .topping:
            return "Type topping, e.g. onion, cilantro..."
        case .ingredient, .unknown:
            return "Type ingredient, e.g. rice, beans..."
        }
    }

    private func apply(_ ingredient: MealIngredient) {
        var next = workingResult
        next.updateIngredient(ingredient)
        guard next.hasUnresolvedAmbiguousIngredients else {
            onComplete(next)
            return
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            workingResult = next
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? 0)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: rows.last.map { $0.y + $0.height } ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        for row in rows(for: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
        }
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> [FlowRow] {
        var rows: [FlowRow] = []
        var currentItems: [FlowItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0
        var y: CGFloat = 0
        let effectiveMaxWidth = maxWidth > 0 ? maxWidth : .greatestFiniteMagnitude

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = currentItems.isEmpty ? size.width : currentWidth + spacing + size.width
            if proposedWidth > effectiveMaxWidth, !currentItems.isEmpty {
                rows.append(FlowRow(y: y, width: currentWidth, height: currentHeight, items: currentItems))
                y += currentHeight + rowSpacing
                currentItems = [FlowItem(index: index, size: size)]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentItems.append(FlowItem(index: index, size: size))
                currentWidth = proposedWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentItems.isEmpty {
            rows.append(FlowRow(y: y, width: currentWidth, height: currentHeight, items: currentItems))
        }
        return rows
    }

    private struct FlowRow {
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
        var items: [FlowItem]
    }

    private struct FlowItem {
        var index: Int
        var size: CGSize
    }
}
