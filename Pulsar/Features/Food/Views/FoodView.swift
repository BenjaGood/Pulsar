//
//  FoodView.swift
//  Pulsar
//

import SwiftUI

struct FoodView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ObservedObject private var store: PulsarNutritionStore
    @ObservedObject private var profileStore: ProfileStore
    @ObservedObject private var bottomChromeLayoutStore: PulsarBottomChromeLayoutStore
    @State private var activeSheet: NutritionSheet?
    @State private var isMealScannerPresented = false
    @State private var nutritionalCalculationPresentation: NutritionalCalculationPresentation?

    @MainActor
    init(
        store: PulsarNutritionStore,
        profileStore: ProfileStore? = nil,
        bottomChromeLayoutStore: PulsarBottomChromeLayoutStore? = nil
    ) {
        self.store = store
        self.profileStore = profileStore ?? ProfileStore(sideEffectsEnabled: false)
        self._bottomChromeLayoutStore = ObservedObject(
            wrappedValue: bottomChromeLayoutStore ?? PulsarBottomChromeLayoutStore()
        )
    }

    var body: some View {
        PulsarPerformanceSignposts.measureTabDestinationBody(.food) {
            NavigationStack {
                PulsarScreenScaffold(
                    layoutStore: bottomChromeLayoutStore,
                    header: PulsarScreenHeaderConfiguration(
                        title: "Nutrition",
                        trailing: [
                            .systemImage(
                                "plus",
                                accessibilityLabel: "Add food",
                                action: presentLunchCapture
                            )
                        ]
                    ),
                    horizontalPadding: PulsarTabLayout.horizontalPadding,
                    spacing: PulsarTabLayout.sectionSpacing,
                    onRefresh: {
                        store.reload()
                    },
                    background: {
                        PulsarTabWallpaper(style: .food)
                    },
                    expandedHeader: {
                        NutritionPageTitleHeader(onAdd: presentLunchCapture)
                    },
                    content: {
                        nutritionCards
                    }
                )
                .navigationTitle("")
                .toolbarTitleDisplayMode(.inline)
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
                .fullScreenCover(item: $nutritionalCalculationPresentation) { _ in
                    OrionNutritionalCalculationFlowView(
                        nutritionStore: store,
                        profile: profileStore.profile,
                        latestBodyCheckIn: store.dashboard.latestBodyCheckIn
                    )
                    .presentationBackground(.clear)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear {
                PulsarPerformanceSignposts.markTabDestinationAppeared(.food)
                PulsarPerformanceSignposts.markTabDestinationUseful(.food, cacheState: .notApplicable)
            }
        }
        .pulsarFitnessMonochromeAppearance()
    }

    @ViewBuilder
    private var nutritionCards: some View {
        if let error = store.lastPersistenceError {
            nutritionErrorCard(error)
        }

        NutritionCalorieSummaryCard(dashboard: store.dashboard)
        NutritionMacroTripletCard(dashboard: store.dashboard)

        featureCardsLayout {
            OrionNutritionalCalculationEntryCard(
                latestCalculation: store.latestNutritionalCalculation,
                action: presentNutritionalCalculation
            )

            MealScannerEntryCard(action: presentMealScanner)
        }

        NutritionMealsSection(
            categories: store.state.mealCategories,
            entriesForCategory: { store.entriesForToday(inCategory: $0.id) },
            onAdd: presentCapture,
            onEditEntry: presentEntryEditor,
            onDeleteEntry: store.deleteEntry,
            onEditMeals: presentMealsEditor
        )
    }

    private func defaultCategoryID(for moment: PulsarNutritionMealMoment) -> UUID {
        store.defaultMealCategory(for: moment).id
    }

    private func nutritionErrorCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(NutritionDesign.primaryText)
            Spacer(minLength: 0)
        }
        .padding(16)
        .nutritionCardSurface(cornerRadius: 20)
    }

    private func presentLunchCapture() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        activeSheet = .capture(defaultCategoryID(for: .lunch))
    }

    private func presentCapture(for category: PulsarMealCategory) {
        activeSheet = .capture(category.id)
    }

    private func presentEntryEditor(for entry: PulsarNutritionEntry) {
        activeSheet = .edit(entry)
    }

    private func presentMealsEditor() {
        activeSheet = .editMeals
    }

    private func presentMealScanner() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        isMealScannerPresented = true
    }

    private func presentNutritionalCalculation() {
        nutritionalCalculationPresentation = NutritionalCalculationPresentation()
    }

    private func featureCardsLayout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: PulsarTabLayout.sectionSpacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: PulsarTabLayout.sectionSpacing))

        return layout {
            content()
        }
    }

    @ViewBuilder
    private func sheetView(_ sheet: NutritionSheet) -> some View {
        switch sheet {
        case .capture(let categoryID):
            let category = store.resolvedMealCategory(id: categoryID, fallback: .lunch)
            PackagedProductAddFlowView(
                store: store,
                initialMoment: category.baseMoment,
                initialCategoryID: category.id
            )
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

private struct NutritionalCalculationPresentation: Identifiable {
    let id = UUID()
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
