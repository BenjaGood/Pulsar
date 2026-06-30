//
//  NutritionUtilitySheets.swift
//  Pulsar
//

import SwiftUI

struct BodyCheckInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PulsarNutritionStore

    @State private var weight = ""
    @State private var waist = ""
    @State private var bodyFat = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PulsarNutritionGlassCard(cornerRadius: 28) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Body Check-In", systemImage: "figure.stand")
                                .pulsarTextStyle(.cardTitle)
                            Text("Weekly-first nutrition context. This stays focused on nourishment signals, not profile management.")
                                .pulsarTextStyle(.label)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    PulsarNutritionGlassCard(cornerRadius: 24) {
                        VStack(spacing: 12) {
                            TextField("Weight kg", text: $weight)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                            TextField("Waist cm", text: $waist)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                            TextField("Body fat % optional", text: $bodyFat)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                            TextField("Optional note", text: $note, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...4)
                        }
                    }

                    Button(action: save) {
                        Text("Save Check-In")
                            .pulsarTextStyle(.cardTitle)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(NutritionActionButtonStyle(tint: .purple))
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }
            .background(PulsarSectionBackground())
            .navigationTitle("Body Context")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationBackground(.regularMaterial)
    }

    private func save() {
        store.saveBodyCheckIn(
            weightKilograms: Double(weight),
            waistCentimeters: Double(waist),
            bodyFatPercentage: Double(bodyFat),
            note: note
        )
        dismiss()
    }
}

struct MealTemplateComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PulsarNutritionStore

    @State private var name = ""
    @State private var moment: PulsarNutritionMealMoment

    init(store: PulsarNutritionStore, initialMoment: PulsarNutritionMealMoment = .lunch) {
        self.store = store
        _moment = State(initialValue: initialMoment)
    }

    private var entries: [PulsarNutritionEntry] {
        store.entriesForToday(in: moment)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PulsarNutritionGlassCard(cornerRadius: 28) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Save Meal Template", systemImage: "rectangle.stack.badge.plus")
                                .pulsarTextStyle(.cardTitle)
                            Text("Turn a meal moment from today into a reusable private template.")
                                .pulsarTextStyle(.label)
                                .foregroundStyle(.secondary)
                        }
                    }

                    PulsarNutritionGlassCard(cornerRadius: 24) {
                        VStack(alignment: .leading, spacing: 14) {
                            TextField("Template name", text: $name)
                                .textFieldStyle(.roundedBorder)
                            Picker("Meal moment", selection: $moment) {
                                ForEach(PulsarNutritionMealMoment.allCases) { moment in
                                    Text(moment.title).tag(moment)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    PulsarNutritionGlassCard(cornerRadius: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            NutritionSectionHeader(
                                title: "\(moment.title) entries",
                                subtitle: entries.isEmpty ? "Nothing to save yet" : "\(entries.count) foods"
                            )
                            if entries.isEmpty {
                                Text("Add food to this meal moment first, then come back to save it as a template.")
                                    .pulsarTextStyle(.label)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(entries) { entry in
                                    HStack {
                                        Text(entry.food.name)
                                            .pulsarTextStyle(.label)
                                        Spacer()
                                        Text(PulsarNutritionFormatters.grams(entry.nutrition.protein))
                                            .pulsarTextStyle(.captionEmphasis)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 5)
                                }
                            }
                        }
                    }

                    Button(action: save) {
                        Text("Save Template")
                            .pulsarTextStyle(.cardTitle)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(NutritionActionButtonStyle(tint: .green))
                    .disabled(entries.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity((entries.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.5 : 1)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }
            .background(PulsarSectionBackground())
            .navigationTitle("Meal Template")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationBackground(.regularMaterial)
    }

    private func save() {
        _ = store.saveTemplate(name: name, moment: moment, entries: entries)
        dismiss()
    }
}

struct RecipeStudioSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PulsarNutritionStore

    @State private var name = ""
    @State private var search = ""
    @State private var servings: Double = 4
    @State private var ingredients: [PulsarRecipeIngredient] = []
    @State private var note = ""
    @State private var saveAsPrivateFood = true

    private var total: PulsarNutritionFacts {
        ingredients.reduce(.zero) { $0 + $1.nutrition }
    }

    private var perServing: PulsarNutritionFacts {
        total.scaled(by: 1 / max(servings, 1))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PulsarNutritionGlassCard(cornerRadius: 28) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Recipe Studio", systemImage: "book.closed.fill")
                                .pulsarTextStyle(.cardTitle)
                            Text("Build a private recipe from searchable foods and save one serving as reusable nutrition memory.")
                                .pulsarTextStyle(.label)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    recipeBasics
                    ingredientSearch
                    ingredientList
                    recipePreview

                    Button(action: save) {
                        Text("Save Recipe")
                            .pulsarTextStyle(.cardTitle)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .buttonStyle(NutritionActionButtonStyle(tint: .green))
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ingredients.isEmpty)
                    .opacity((name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ingredients.isEmpty) ? 0.5 : 1)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }
            .background(PulsarSectionBackground())
            .navigationTitle("Recipe Studio")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationBackground(.regularMaterial)
    }

    private var recipeBasics: some View {
        PulsarNutritionGlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Recipe name", text: $name)
                    .textFieldStyle(.roundedBorder)
                Stepper(value: $servings, in: 1...12, step: 1) {
                    HStack {
                        Text("Servings")
                            .pulsarTextStyle(.label)
                        Spacer()
                        Text("\(Int(servings))")
                            .pulsarTextStyle(.cardTitle)
                            .monospacedDigit()
                    }
                }
                TextField("Optional note", text: $note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                Toggle("Save one serving to Private Foods", isOn: $saveAsPrivateFood)
                    .pulsarTextStyle(.label)
            }
        }
    }

    private var ingredientSearch: some View {
        PulsarNutritionGlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                NutritionSectionHeader(title: "Ingredients", subtitle: "Add from mock search or private foods")
                TextField("Search ingredient", text: $search)
                    .textFieldStyle(.roundedBorder)

                VStack(spacing: 10) {
                    ForEach(store.searchFoods(search).prefix(5)) { food in
                        Button {
                            ingredients.append(PulsarRecipeIngredient(food: food, servingMultiplier: 1))
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(food.name)
                                        .pulsarTextStyle(.label)
                                    Text(food.serving.title)
                                        .pulsarTextStyle(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                            }
                            .padding(12)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var ingredientList: some View {
        PulsarNutritionGlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                NutritionSectionHeader(
                    title: "Recipe build",
                    subtitle: ingredients.isEmpty ? "No ingredients yet" : "\(ingredients.count) ingredients"
                )

                if ingredients.isEmpty {
                    Text("Add ingredients above to preview per-serving nutrition.")
                        .pulsarTextStyle(.label)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($ingredients) { $ingredient in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ingredient.food.name)
                                    .pulsarTextStyle(.label)
                                Text("\(PulsarNutritionFormatters.decimal(ingredient.servingMultiplier))x \(ingredient.food.serving.title)")
                                    .pulsarTextStyle(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Stepper("", value: $ingredient.servingMultiplier, in: 0.25...8, step: 0.25)
                                .labelsHidden()
                            Button(role: .destructive) {
                                ingredients.removeAll { $0.id == ingredient.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
        }
    }

    private var recipePreview: some View {
        PulsarNutritionGlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                NutritionSectionHeader(title: "Per serving", subtitle: "Calculated from ingredients")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    RecipePreviewMetric(title: "Fuel", value: PulsarNutritionFormatters.calories(perServing.calories), tint: .orange)
                    RecipePreviewMetric(title: "Protein", value: PulsarNutritionFormatters.grams(perServing.protein), tint: .green)
                    RecipePreviewMetric(title: "Carbs", value: PulsarNutritionFormatters.grams(perServing.carbohydrates), tint: .yellow)
                    RecipePreviewMetric(title: "Fiber", value: PulsarNutritionFormatters.grams(perServing.fiber), tint: .mint)
                }
            }
        }
    }

    private func save() {
        let recipe = PulsarRecipe(
            name: name,
            servings: servings,
            ingredients: ingredients,
            note: note
        )
        store.saveRecipe(recipe, saveAsPrivateFood: saveAsPrivateFood)
        dismiss()
    }
}

private struct RecipePreviewMetric: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .pulsarTextStyle(.cardTitle)
                .monospacedDigit()
            Text(title)
                .pulsarTextStyle(.overline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
