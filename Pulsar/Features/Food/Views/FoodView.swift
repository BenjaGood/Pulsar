//
//  FoodView.swift
//  Pulsar
//

import SwiftUI

struct FoodView: View {
    @ObservedObject private var store: PulsarNutritionStore
    @ObservedObject private var bottomChromeLayoutStore: PulsarBottomChromeLayoutStore
    @State private var activeSheet: NutritionSheet?
    @State private var isMealScannerPresented = false

    init(
        store: PulsarNutritionStore,
        bottomChromeLayoutStore: PulsarBottomChromeLayoutStore = PulsarBottomChromeLayoutStore()
    ) {
        self.store = store
        self._bottomChromeLayoutStore = ObservedObject(wrappedValue: bottomChromeLayoutStore)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NutritionBackground()
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        nutritionContent

                        PulsarBottomChromeSpacer(layoutStore: bottomChromeLayoutStore)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 24)
                    .padding(.bottom, 34)
                }
                .pulsarBottomChromeScrollContainer(layoutStore: bottomChromeLayoutStore)
                .scrollContentBackground(.hidden)
                .premiumScrollHeaderBlur()
                .refreshable {
                    store.reload()
                }
            }
            .navigationTitle("")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .capture(defaultCategoryID(for: .lunch))
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add food")
                }
            }
            .sheet(item: $activeSheet) { sheet in
                sheetView(sheet)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: $isMealScannerPresented) {
                MealScannerView(
                    nutritionStore: store,
                    initialCategoryID: defaultCategoryID(for: PulsarNutritionMealMoment.currentMealMoment())
                )
                .presentationBackground(.clear)
            }
        }
        .background(NutritionBackground())
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var nutritionContent: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 16) {
                dailyStack
            }
        } else {
            dailyStack
        }
    }

    private var dailyStack: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            NutritionPageTitleHeader()

            if let error = store.lastPersistenceError {
                nutritionErrorCard(error)
            }

            NutritionCalorieSummaryCard(dashboard: store.dashboard)
            NutritionMacroTripletCard(dashboard: store.dashboard)

            MealScannerEntryCard {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                isMealScannerPresented = true
            }

            NutritionMealsSection(
                categories: store.state.mealCategories,
                entriesForCategory: { store.entriesForToday(inCategory: $0.id) },
                onAdd: { category in activeSheet = .capture(category.id) },
                onEditEntry: { entry in activeSheet = .edit(entry) },
                onDeleteEntry: store.deleteEntry,
                onEditMeals: { activeSheet = .editMeals }
            )
        }
    }

    private func defaultCategoryID(for moment: PulsarNutritionMealMoment) -> UUID {
        store.defaultMealCategory(for: moment).id
    }

    private func nutritionErrorCard(_ message: String) -> some View {
        PulsarNutritionGlassCard(cornerRadius: 22) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .pulsarTextStyle(.label)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func sheetView(_ sheet: NutritionSheet) -> some View {
        switch sheet {
        case .capture(let categoryID):
            let category = store.resolvedMealCategory(id: categoryID, fallback: .lunch)
            FuelCaptureSheet(store: store, initialMoment: category.baseMoment, initialCategoryID: category.id)
        case .edit(let entry):
            FuelCaptureSheet(
                store: store,
                initialMoment: entry.mealMoment,
                initialCategoryID: entry.categoryID,
                editingEntry: entry
            )
        case .editMeals:
            NutritionMealsEditView(store: store)
        }
    }
}

private enum NutritionSheet: Identifiable {
    case capture(UUID?)
    case edit(PulsarNutritionEntry)
    case editMeals

    var id: String {
        switch self {
        case .capture(let categoryID): "capture-\(categoryID?.uuidString ?? "default")"
        case .edit(let entry): "edit-\(entry.id.uuidString)"
        case .editMeals: "edit-meals"
        }
    }
}

#Preview {
    FoodView(store: PulsarNutritionStore())
}
