//
//  MealIngredientEditView.swift
//  Pulsar
//

import SwiftUI

struct MealIngredientEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var gramsText: String
    @State private var didEditText = false
    private let ingredient: MealIngredient
    private let onSave: (Double) -> Void

    init(ingredient: MealIngredient, onSave: @escaping (Double) -> Void) {
        self.ingredient = ingredient
        self.onSave = onSave
        self._gramsText = State(initialValue: PulsarNutritionFormatters.decimal(ingredient.estimatedGrams))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PulsarNutritionGlassCard(cornerRadius: 26) {
                        VStack(alignment: .leading, spacing: 14) {
                            NutritionSectionHeader(
                                title: ingredient.name,
                                subtitle: "Adjust estimated grams"
                            )

                            TextField("Grams", text: $gramsText)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .font(.title3.monospacedDigit())

                            HStack(spacing: 8) {
                                ForEach([0.75, 1.0, 1.25, 1.5], id: \.self) { multiplier in
                                    Button("\(Int(multiplier * 100))%") {
                                        gramsText = PulsarNutritionFormatters.decimal(ingredient.estimatedGrams * multiplier)
                                        didEditText = true
                                    }
                                    .pulsarTextStyle(.captionEmphasis)
                                    .buttonStyle(.bordered)
                                    .tint(.green)
                                }
                            }
                            .buttonBorderShape(.capsule)
                        }
                    }

                    PulsarNutritionGlassCard(cornerRadius: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            NutritionSectionHeader(
                                title: "Recalculated Preview",
                                subtitle: "Macros scale proportionally from the AI estimate."
                            )

                            let preview = ingredient.scaled(toGrams: gramsValue)
                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())],
                                spacing: 10
                            ) {
                                MealScanMacroTile(title: "Calories", value: PulsarNutritionFormatters.calories(preview.calories), tint: .orange)
                                MealScanMacroTile(title: "Protein", value: PulsarNutritionFormatters.grams(preview.protein), tint: .green)
                                MealScanMacroTile(title: "Carbs", value: PulsarNutritionFormatters.grams(preview.carbs), tint: .teal)
                                MealScanMacroTile(title: "Fat", value: PulsarNutritionFormatters.grams(preview.fat), tint: .pink)
                            }
                        }
                    }

                    Button(action: save) {
                        Text("Save Portion")
                            .pulsarTextStyle(.buttonTitle)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(NutritionActionButtonStyle(tint: .green))
                    .disabled(gramsValue <= 0)
                    .opacity(gramsValue > 0 ? 1 : 0.55)
                }
                .padding(18)
            }
            .background(PulsarSectionBackground())
            .navigationTitle("Edit Portion")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: gramsText) { _, _ in
                didEditText = true
            }
        }
        .presentationBackground(.regularMaterial)
    }

    private var parsedGrams: Double? {
        Double(gramsText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
    }

    private var gramsValue: Double {
        parsedGrams ?? (didEditText ? 0 : ingredient.estimatedGrams)
    }

    private func save() {
        onSave(max(0, gramsValue))
        dismiss()
    }
}
