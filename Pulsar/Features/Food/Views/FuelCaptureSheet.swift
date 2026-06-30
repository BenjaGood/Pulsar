//
//  FuelCaptureSheet.swift
//  Pulsar
//

import SwiftUI

struct FuelCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PulsarNutritionStore

    var initialMoment: PulsarNutritionMealMoment
    var editingEntry: PulsarNutritionEntry?

    @State private var foodName: String
    @State private var caloriesText: String
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatText: String
    @State private var servingAmountText: String
    @State private var mealMoment: PulsarNutritionMealMoment
    @State private var loggedAt: Date
    @State private var searchText = ""
    @State private var saveAsPrivateFood: Bool
    @State private var selectedFood: PulsarFoodItem?
    @State private var draftFoodID: UUID

    init(
        store: PulsarNutritionStore,
        initialMoment: PulsarNutritionMealMoment,
        editingEntry: PulsarNutritionEntry? = nil
    ) {
        self.store = store
        self.initialMoment = initialMoment
        self.editingEntry = editingEntry

        let entryFood = editingEntry?.food
        _foodName = State(initialValue: entryFood?.name ?? "")
        _caloriesText = State(initialValue: entryFood.map { PulsarNutritionFormatters.decimal($0.nutritionPerServing.calories) } ?? "")
        _proteinText = State(initialValue: entryFood.map { PulsarNutritionFormatters.decimal($0.nutritionPerServing.protein) } ?? "")
        _carbsText = State(initialValue: entryFood.map { PulsarNutritionFormatters.decimal($0.nutritionPerServing.carbohydrates) } ?? "")
        _fatText = State(initialValue: entryFood.map { PulsarNutritionFormatters.decimal($0.nutritionPerServing.fat) } ?? "")
        _servingAmountText = State(initialValue: PulsarNutritionFormatters.decimal(editingEntry?.servingMultiplier ?? 1))
        _mealMoment = State(initialValue: editingEntry?.mealMoment ?? initialMoment)
        _loggedAt = State(initialValue: editingEntry?.loggedAt ?? Date())
        _saveAsPrivateFood = State(initialValue: entryFood?.source == .privateFood)
        _selectedFood = State(initialValue: entryFood)
        _draftFoodID = State(initialValue: entryFood?.id ?? UUID())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if editingEntry == nil {
                        quickAddCard
                    }

                    foodEditorCard
                    timingCard
                    nutritionPreviewCard
                    saveButton
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }
            .scrollContentBackground(.hidden)
            .background(PulsarSectionBackground())
            .navigationTitle(editingEntry == nil ? "Add Food" : "Edit Food")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationBackground(.regularMaterial)
    }

    private var quickAddCard: some View {
        PulsarNutritionGlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                NutritionSectionHeader(
                    title: "Quick Add",
                    subtitle: "Common, recent, and private foods"
                )

                TextField("Search foods", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)

                quickFoodGroup(
                    title: searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Common" : "Matches",
                    foods: matchingFoods
                )

                if !recentEntries.isEmpty {
                    quickEntryGroup(title: "Recent", entries: recentEntries)
                }

                if !privateFoods.isEmpty {
                    quickFoodGroup(title: "Private", foods: privateFoods)
                }
            }
        }
    }

    private var foodEditorCard: some View {
        PulsarNutritionGlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                NutritionSectionHeader(
                    title: "Food",
                    subtitle: selectedFood?.serving.title ?? "Single food entry"
                )

                TextField("Food name", text: $foodName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .onChange(of: foodName) { _, _ in
                        if selectedFood?.name != foodName {
                            selectedFood = nil
                        }
                    }

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    FuelNumberField(title: "Calories", text: $caloriesText, keyboardType: .numberPad)
                    FuelNumberField(title: "Protein g", text: $proteinText)
                    FuelNumberField(title: "Carbs g", text: $carbsText)
                    FuelNumberField(title: "Fats g", text: $fatText)
                    FuelNumberField(title: "Serving amount", text: $servingAmountText)
                }

                servingAmountChips

                Toggle("Save to Private Foods", isOn: $saveAsPrivateFood)
                    .pulsarTextStyle(.label)
            }
        }
    }

    private var timingCard: some View {
        PulsarNutritionGlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                NutritionSectionHeader(title: "Logged At")

                Picker("Meal category", selection: $mealMoment) {
                    ForEach(PulsarNutritionMealMoment.allCases) { moment in
                        Label(moment.title, systemImage: moment.symbolName).tag(moment)
                    }
                }
                .pickerStyle(.menu)

                DatePicker(
                    "Time logged",
                    selection: $loggedAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
            }
        }
    }

    private var nutritionPreviewCard: some View {
        PulsarNutritionGlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 14) {
                NutritionSectionHeader(
                    title: "Entry Total",
                    subtitle: servingAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "\(PulsarNutritionFormatters.decimal(servingAmount)) servings"
                )

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    FuelPreviewPill(title: "Calories", value: PulsarNutritionFormatters.calories(previewFacts.calories), tint: .orange)
                    FuelPreviewPill(title: "Protein", value: PulsarNutritionFormatters.grams(previewFacts.protein), tint: .green)
                    FuelPreviewPill(title: "Carbs", value: PulsarNutritionFormatters.grams(previewFacts.carbohydrates), tint: .yellow)
                    FuelPreviewPill(title: "Fats", value: PulsarNutritionFormatters.grams(previewFacts.fat), tint: .pink)
                }
            }
        }
    }

    private var saveButton: some View {
        Button(action: confirm) {
            Text(editingEntry == nil ? "Add Food" : "Save Changes")
                .pulsarTextStyle(.cardTitle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
        }
        .buttonStyle(NutritionActionButtonStyle(tint: .green))
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.52)
    }

    private var servingAmountChips: some View {
        HStack(spacing: 8) {
            ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { value in
                Button("\(PulsarNutritionFormatters.decimal(value))x") {
                    servingAmountText = PulsarNutritionFormatters.decimal(value)
                }
                .pulsarTextStyle(.captionEmphasis)
                .buttonStyle(.bordered)
                .tint(.green)
            }
        }
        .buttonBorderShape(.capsule)
    }

    @ViewBuilder
    private func quickFoodGroup(title: String, foods: [PulsarFoodItem]) -> some View {
        if !foods.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(foods) { food in
                        FuelQuickFoodRow(
                            title: food.name,
                            subtitle: "\(PulsarNutritionFormatters.calories(food.nutritionPerServing.calories)) cal · \(PulsarNutritionFormatters.grams(food.nutritionPerServing.protein)) protein",
                            symbolName: food.source == .privateFood ? "lock.fill" : "fork.knife",
                            tint: food.source == .privateFood ? .purple : .green,
                            isSelected: selectedFood?.id == food.id,
                            selectAction: { apply(food) },
                            quickAddAction: { quickAdd(food, servingMultiplier: 1) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func quickEntryGroup(title: String, entries: [PulsarNutritionEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(entries) { entry in
                    FuelQuickFoodRow(
                        title: entry.food.name,
                        subtitle: "\(entry.servingText) · \(PulsarNutritionFormatters.calories(entry.nutrition.calories)) cal",
                        symbolName: "clock.arrow.circlepath",
                        tint: .blue,
                        isSelected: selectedFood?.id == entry.food.id && servingAmount == entry.servingMultiplier,
                        selectAction: { apply(entry) },
                        quickAddAction: { quickAdd(entry.food, servingMultiplier: entry.servingMultiplier) }
                    )
                }
            }
        }
    }

    private var matchingFoods: [PulsarFoodItem] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let foods = trimmed.isEmpty
            ? store.commonFoods(limit: 6)
            : store.searchFoods(trimmed)
        return Array(foods.filter(isFoodLoggable).prefix(trimmed.isEmpty ? 6 : 8))
    }

    private var recentEntries: [PulsarNutritionEntry] {
        var seenFoodIDs: Set<UUID> = []
        return store.state.entries
            .filter { $0.id != editingEntry?.id }
            .filter { isFoodLoggable($0.food) }
            .filter { entry in
                guard !seenFoodIDs.contains(entry.food.id) else { return false }
                seenFoodIDs.insert(entry.food.id)
                return true
            }
            .prefix(4)
            .map { $0 }
    }

    private var privateFoods: [PulsarFoodItem] {
        Array(store.state.privateFoods.filter(isFoodLoggable).prefix(4))
    }

    private var canSave: Bool {
        !trimmedFoodName.isEmpty && servingAmount > 0
    }

    private var servingAmount: Double {
        max(0, parsedDouble(servingAmountText))
    }

    private var previewFacts: PulsarNutritionFacts {
        draftNutrition.scaled(by: servingAmount)
    }

    private var draftNutrition: PulsarNutritionFacts {
        PulsarNutritionFacts(
            calories: max(0, parsedDouble(caloriesText)),
            protein: max(0, parsedDouble(proteinText)),
            carbohydrates: max(0, parsedDouble(carbsText)),
            fat: max(0, parsedDouble(fatText)),
            fiber: selectedFood?.nutritionPerServing.fiber ?? editingEntry?.food.nutritionPerServing.fiber ?? 0,
            sugar: selectedFood?.nutritionPerServing.sugar ?? editingEntry?.food.nutritionPerServing.sugar ?? 0,
            sodiumMilligrams: selectedFood?.nutritionPerServing.sodiumMilligrams ?? editingEntry?.food.nutritionPerServing.sodiumMilligrams ?? 0
        )
    }

    private var draftFood: PulsarFoodItem {
        PulsarFoodItem(
            id: draftFoodID,
            name: trimmedFoodName,
            detail: selectedFood?.detail ?? "Food log",
            brand: selectedFood?.brand,
            serving: selectedFood?.serving ?? PulsarNutritionServing(amount: 1, unit: "serving", grams: nil),
            nutritionPerServing: draftNutrition,
            source: selectedFood?.source ?? .userEntered,
            isSaved: saveAsPrivateFood,
            createdAt: selectedFood?.createdAt ?? editingEntry?.food.createdAt ?? Date(),
            updatedAt: Date()
        )
    }

    private var trimmedFoodName: String {
        foodName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func apply(_ food: PulsarFoodItem) {
        draftFoodID = food.id
        selectedFood = food
        foodName = food.name
        caloriesText = PulsarNutritionFormatters.decimal(food.nutritionPerServing.calories)
        proteinText = PulsarNutritionFormatters.decimal(food.nutritionPerServing.protein)
        carbsText = PulsarNutritionFormatters.decimal(food.nutritionPerServing.carbohydrates)
        fatText = PulsarNutritionFormatters.decimal(food.nutritionPerServing.fat)
        servingAmountText = "1"
        saveAsPrivateFood = food.source == .privateFood
    }

    private func apply(_ entry: PulsarNutritionEntry) {
        apply(entry.food)
        servingAmountText = PulsarNutritionFormatters.decimal(entry.servingMultiplier)
    }

    private func quickAdd(_ food: PulsarFoodItem, servingMultiplier: Double) {
        store.logFood(
            food,
            servingMultiplier: servingMultiplier,
            mealMoment: mealMoment,
            confidence: 1,
            source: food.source,
            loggedAt: loggedAt
        )
        dismiss()
    }

    private func confirm() {
        guard canSave else { return }

        var food = draftFood
        if saveAsPrivateFood {
            food = store.savePrivateFood(food)
        }

        if var editingEntry {
            editingEntry.food = food
            editingEntry.servingMultiplier = max(0.05, servingAmount)
            editingEntry.mealMoment = mealMoment
            editingEntry.loggedAt = loggedAt
            editingEntry.confidence = 1
            editingEntry.source = food.source
            store.updateEntry(editingEntry)
        } else {
            store.logFood(
                food,
                servingMultiplier: max(0.05, servingAmount),
                mealMoment: mealMoment,
                confidence: 1,
                source: food.source,
                loggedAt: loggedAt
            )
        }

        dismiss()
    }

    private func parsedDouble(_ text: String) -> Double {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(normalized) ?? 0
    }

    private func isFoodLoggable(_ food: PulsarFoodItem) -> Bool {
        food.source != .recipe && food.source != .mealTemplate
    }
}

private struct FuelQuickFoodRow: View {
    var title: String
    var subtitle: String
    var symbolName: String
    var tint: Color
    var isSelected: Bool
    var selectAction: () -> Void
    var quickAddAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: selectAction) {
                HStack(spacing: 10) {
                    Image(systemName: symbolName)
                        .pulsarTextStyle(.label)
                        .foregroundStyle(tint)
                        .frame(width: 32, height: 32)
                        .background(tint.opacity(0.13), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .pulsarTextStyle(.label)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(subtitle)
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer(minLength: 4)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .pulsarTextStyle(.label)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 10)
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: quickAddAction) {
                Image(systemName: "plus.circle.fill")
                    .pulsarTextStyle(.sectionHeader)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(NutritionIconButtonStyle(tint: tint, size: 36))
            .accessibilityLabel("Add \(title)")
        }
        .background(.white.opacity(isSelected ? 0.13 : 0.06), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

private struct FuelNumberField: View {
    var title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .decimalPad

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(keyboardType)
            .textFieldStyle(.roundedBorder)
    }
}

private struct FuelPreviewPill: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .pulsarTextStyle(.cardTitle)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(title)
                .pulsarTextStyle(.overline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
