//
//  NutritionMealsEditView.swift
//  Pulsar
//

import SwiftUI

struct NutritionMealsEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PulsarNutritionStore

    @State private var editorMode: NutritionMealCategoryEditorMode?
    @State private var pendingDeleteCategory: PulsarMealCategory?
    @State private var draggingCategoryID: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                NutritionMealsSheetBackground()

                ScrollView {
                    PulsarGlassEffectGroup(spacing: NutritionMealsEditorDesign.sectionSpacing) {
                        VStack(spacing: NutritionMealsEditorDesign.sectionSpacing) {
                            NutritionMealsEditorHeader(onDone: dismiss.callAsFunction)

                            NutritionMealsEditorCard(
                                categories: store.state.mealCategories,
                                entryCount: { category in
                                    store.entriesForToday(inCategory: category.id).count
                                },
                                draggingCategoryID: $draggingCategoryID,
                                onEdit: editCategory,
                                onDelete: requestDelete,
                                onAdd: addCategory,
                                onMove: store.moveMealCategory
                            )
                        }
                    }
                    .padding(.horizontal, NutritionMealsEditorDesign.horizontalPadding)
                    .padding(.top, NutritionMealsEditorDesign.topPadding)
                    .padding(.bottom, 44)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editorMode) { mode in
                NutritionMealCategoryEditorSheet(store: store, mode: mode)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .confirmationDialog(
                "Move foods to...",
                isPresented: deleteConfirmationBinding,
                titleVisibility: .visible
            ) {
                if let category = pendingDeleteCategory {
                    ForEach(store.state.mealCategories.filter { $0.id != category.id }) { target in
                        Button(target.name) {
                            reassignAndDelete(category, to: target)
                        }
                    }
                    Button("Delete foods", role: .destructive) {
                        deleteCategoryAndEntries(category)
                    }
                }
                Button("Cancel", role: .cancel, action: cancelDelete)
            } message: {
                if let category = pendingDeleteCategory {
                    Text("Choose where foods logged under \(category.name) should go.")
                }
            }
        }
        .pulsarFitnessMonochromeAppearance()
        .presentationBackground(.clear)
        .presentationCornerRadius(NutritionMealsEditorDesign.sheetCornerRadius)
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteCategory != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteCategory = nil
                }
            }
        )
    }

    private func editCategory(_ category: PulsarMealCategory) {
        editorMode = .edit(category)
    }

    private func addCategory() {
        editorMode = .add
    }

    private func requestDelete(_ category: PulsarMealCategory) {
        guard store.state.mealCategories.count > 1 else { return }

        if store.state.entries.contains(where: { $0.categoryID == category.id }) {
            pendingDeleteCategory = category
        } else {
            store.deleteMealCategory(category, reassignTo: nil)
        }
    }

    private func reassignAndDelete(_ category: PulsarMealCategory, to target: PulsarMealCategory) {
        store.deleteMealCategory(category, reassignTo: target.id)
        pendingDeleteCategory = nil
    }

    private func deleteCategoryAndEntries(_ category: PulsarMealCategory) {
        store.deleteMealCategoryAndEntries(category)
        pendingDeleteCategory = nil
    }

    private func cancelDelete() {
        pendingDeleteCategory = nil
    }
}

private enum NutritionMealCategoryEditorMode: Identifiable {
    case add
    case edit(PulsarMealCategory)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let category): "edit-\(category.id.uuidString)"
        }
    }
}

private struct NutritionMealCategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: PulsarNutritionStore
    var mode: NutritionMealCategoryEditorMode

    @State private var preset: NutritionMealCategoryPreset
    @State private var name: String
    @State private var symbolName: String
    @State private var palette: PulsarMealCategoryPalette
    @State private var baseMoment: PulsarNutritionMealMoment

    init(store: PulsarNutritionStore, mode: NutritionMealCategoryEditorMode) {
        self.store = store
        self.mode = mode
        let category: PulsarMealCategory?
        if case .edit(let existingCategory) = mode {
            category = existingCategory
        } else {
            category = nil
        }
        _preset = State(initialValue: .custom)
        _name = State(initialValue: category?.name ?? "")
        _symbolName = State(initialValue: category?.symbolName ?? "fork.knife")
        _palette = State(initialValue: category?.palette ?? .green)
        _baseMoment = State(initialValue: category?.baseMoment ?? .lunch)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Preset") {
                    Picker("Type", selection: $preset) {
                        ForEach(NutritionMealCategoryPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .onChange(of: preset) { _, newValue in
                        apply(newValue)
                    }
                }

                Section("Meal") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    Picker("Base moment", selection: $baseMoment) {
                        ForEach(PulsarNutritionMealMoment.allCases) { moment in
                            Text(moment.title).tag(moment)
                        }
                    }
                }

                Section("Symbol") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                        ForEach(Self.symbols, id: \.self) { symbol in
                            Button {
                                symbolName = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .frame(width: 42, height: 42)
                                    .foregroundStyle(symbolName == symbol ? .white : palette.color)
                                    .background(symbolName == symbol ? palette.color : palette.color.opacity(0.12), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                        }
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 12)], spacing: 12) {
                        ForEach(PulsarMealCategoryPalette.allCases) { option in
                            Button {
                                palette = option
                            } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if palette == option {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.title)
                        }
                    }
                }
            }
            .navigationTitle(modeTitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var modeTitle: String {
        if case .edit = mode { return "Edit Meal" }
        return "Add Meal"
    }

    private func apply(_ preset: NutritionMealCategoryPreset) {
        guard preset != .custom else { return }
        name = preset.name
        symbolName = preset.symbolName
        palette = preset.palette
        baseMoment = preset.baseMoment
    }

    private func save() {
        switch mode {
        case .add:
            store.addMealCategory(
                name: name,
                symbolName: symbolName,
                palette: palette,
                baseMoment: baseMoment
            )
        case .edit(let category):
            var updated = category
            updated.name = name
            updated.symbolName = symbolName
            updated.palette = palette
            updated.baseMoment = baseMoment
            store.updateMealCategory(updated)
        }
        dismiss()
    }

    private static let symbols = [
        "sunrise.fill",
        "sun.max.fill",
        "moon.stars.fill",
        "leaf.fill",
        "fork.knife",
        "takeoutbag.and.cup.and.straw.fill",
        "cup.and.saucer.fill",
        "carrot.fill",
        "flame.fill",
        "bolt.fill",
        "figure.strengthtraining.traditional",
        "sparkles"
    ]
}

private enum NutritionMealCategoryPreset: String, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case snacks
    case custom
    case preWorkout
    case postWorkout
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snacks: "Snacks / Colaciones"
        case .custom: "Custom"
        case .preWorkout: "Pre-workout"
        case .postWorkout: "Post-workout"
        case .other: "Other"
        }
    }

    var name: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snacks: "Snacks / Colaciones"
        case .custom: ""
        case .preWorkout: "Pre-workout"
        case .postWorkout: "Post-workout"
        case .other: "Comida"
        }
    }

    var symbolName: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snacks: "leaf.fill"
        case .custom: "fork.knife"
        case .preWorkout: "bolt.fill"
        case .postWorkout: "figure.strengthtraining.traditional"
        case .other: "takeoutbag.and.cup.and.straw.fill"
        }
    }

    var palette: PulsarMealCategoryPalette {
        switch self {
        case .breakfast: .orange
        case .lunch: .yellow
        case .dinner: .indigo
        case .snacks: .mint
        case .custom: .green
        case .preWorkout: .blue
        case .postWorkout: .purple
        case .other: .teal
        }
    }

    var baseMoment: PulsarNutritionMealMoment {
        switch self {
        case .breakfast: .breakfast
        case .lunch, .custom, .preWorkout, .postWorkout, .other: .lunch
        case .dinner: .dinner
        case .snacks: .snacks
        }
    }
}

#Preview("Edit Meals") {
    NutritionMealsEditView(store: PulsarNutritionStore())
}
