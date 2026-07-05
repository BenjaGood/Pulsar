//
//  NutritionStoreTests.swift
//  PulsarTests
//

import XCTest
@testable import Pulsar

@MainActor
final class NutritionStoreTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
    }

    override func tearDown() {
        calendar = nil
        super.tearDown()
    }

    func testStoreStartsWithEmptyLocalFoodLog() {
        let now = date(year: 2026, month: 5, day: 23, hour: 9)
        let provider = NutritionTestProvider(state: .empty)
        let store = PulsarNutritionStore(provider: provider, calendar: calendar, nowProvider: { now })

        XCTAssertTrue(store.state.entries.isEmpty)
        XCTAssertTrue(store.dashboard.entries.isEmpty)
        XCTAssertEqual(store.dashboard.totals, .zero)
        XCTAssertTrue(store.recentFoods().isEmpty)
        XCTAssertEqual(PulsarNutritionMealMoment.allCases, [.breakfast, .lunch, .dinner, .snacks])
        XCTAssertEqual(store.state.mealCategories.map(\.id), PulsarMealCategory.defaultCategories.map(\.id))
        XCTAssertNil(provider.savedState)
    }

    func testDefaultMealCategoriesAreSeededWithStableIDs() {
        let now = date(year: 2026, month: 5, day: 23, hour: 9)
        let provider = NutritionTestProvider(state: .empty)
        let store = PulsarNutritionStore(provider: provider, calendar: calendar, nowProvider: { now })

        XCTAssertEqual(store.state.mealCategories.count, 4)
        XCTAssertEqual(store.state.mealCategories.map(\.id), PulsarMealCategory.defaultCategories.map(\.id))
        XCTAssertEqual(store.state.mealCategories.map(\.baseMoment), [.breakfast, .lunch, .dinner, .snacks])
        XCTAssertTrue(store.state.mealCategories.allSatisfy { $0.isDefault })
    }

    func testLegacyEntryWithNilCategoryIDMigratesToDefaultCategory() throws {
        let now = date(year: 2026, month: 5, day: 23, hour: 12)
        let legacyEntry = PulsarNutritionEntry(
            foodName: "Legacy Soup",
            calories: 320,
            protein: 18,
            carbs: 42,
            fats: 8,
            servingAmount: 1,
            mealCategory: .lunch,
            timeLogged: now
        )
        XCTAssertNil(legacyEntry.categoryID)

        let state = PulsarNutritionState(
            entries: [legacyEntry],
            hydrationEntries: [],
            privateFoods: [],
            mealTemplates: [],
            recipes: [],
            bodyCheckIns: [],
            targetSnapshots: [],
            eatingWindow: .default
        )
        let store = PulsarNutritionStore(provider: NutritionTestProvider(state: state), calendar: calendar, nowProvider: { now })
        let migrated = try XCTUnwrap(store.entriesForToday(in: .lunch).first)

        XCTAssertEqual(migrated.categoryID, PulsarMealCategory.lunchID)
        XCTAssertEqual(store.entriesForToday(inCategory: PulsarMealCategory.lunchID).map(\.foodName), ["Legacy Soup"])
    }

    func testMealCategoryAddUpdateAndReorderPersistSortOrder() throws {
        let now = date(year: 2026, month: 5, day: 23, hour: 10)
        let provider = NutritionTestProvider(state: .empty)
        let store = PulsarNutritionStore(provider: provider, calendar: calendar, nowProvider: { now })

        let category = try XCTUnwrap(store.addMealCategory(
            name: "Post-workout",
            symbolName: "figure.strengthtraining.traditional",
            palette: .purple,
            baseMoment: .snacks
        ))
        XCTAssertEqual(store.state.mealCategories.last?.id, category.id)

        var updated = category
        updated.name = "Recovery Shake"
        updated.palette = .blue
        store.updateMealCategory(updated)

        let savedCategory = try XCTUnwrap(store.mealCategory(id: category.id))
        XCTAssertEqual(savedCategory.name, "Recovery Shake")
        XCTAssertEqual(savedCategory.palette, .blue)

        let sourceIndex = try XCTUnwrap(store.state.mealCategories.firstIndex { $0.id == category.id })
        store.moveMealCategory(fromOffsets: IndexSet(integer: sourceIndex), toOffset: 0)

        XCTAssertEqual(store.state.mealCategories.first?.id, category.id)
        XCTAssertEqual(store.state.mealCategories.map(\.sortOrder), Array(0..<store.state.mealCategories.count))
        XCTAssertEqual(provider.savedState?.mealCategories.first?.id, category.id)
    }

    func testDeleteMealCategoryReassignsEntriesWithoutDeletingFood() throws {
        let now = date(year: 2026, month: 5, day: 23, hour: 16)
        let provider = NutritionTestProvider(state: .empty)
        let store = PulsarNutritionStore(provider: provider, calendar: calendar, nowProvider: { now })
        let source = try XCTUnwrap(store.addMealCategory(
            name: "Colación",
            symbolName: "leaf.fill",
            palette: .teal,
            baseMoment: .snacks
        ))
        let target = store.defaultMealCategory(for: .lunch)

        let entry = try XCTUnwrap(store.logFoodEntry(
            foodName: "Protein Bite",
            calories: 180,
            protein: 16,
            carbs: 12,
            fats: 7,
            servingAmount: 1,
            mealCategory: source.baseMoment,
            categoryID: source.id,
            timeLogged: now
        ))
        XCTAssertEqual(entry.categoryID, source.id)

        XCTAssertFalse(store.deleteMealCategory(source, reassignTo: nil))
        XCTAssertTrue(store.deleteMealCategory(source, reassignTo: target.id))

        XCTAssertNil(store.mealCategory(id: source.id))
        XCTAssertEqual(store.state.entries.count, 1)
        let moved = try XCTUnwrap(store.state.entries.first)
        XCTAssertEqual(moved.categoryID, target.id)
        XCTAssertEqual(moved.mealMoment, target.baseMoment)
        XCTAssertEqual(store.entriesForToday(inCategory: target.id).map(\.foodName), ["Protein Bite"])
    }

    func testLogsBreakfastLunchDinnerAndSnacks() throws {
        let now = date(year: 2026, month: 5, day: 23, hour: 8)
        let provider = NutritionTestProvider(state: .empty)
        let store = PulsarNutritionStore(provider: provider, calendar: calendar, nowProvider: { now })

        let meals: [(PulsarNutritionMealCategory, String, Double, Double, Double, Double)] = [
            (.breakfast, "Oats", 410, 24, 58, 10),
            (.lunch, "Chicken Wrap", 560, 42, 52, 18),
            (.dinner, "Lentil Soup", 430, 24, 56, 12),
            (.snacks, "Greek Yogurt", 160, 23, 10, 4)
        ]

        for (offset, meal) in meals.enumerated() {
            let loggedAt = now.addingTimeInterval(Double(offset) * 60 * 60)
            let entry = try XCTUnwrap(store.logFoodEntry(
                foodName: meal.1,
                calories: meal.2,
                protein: meal.3,
                carbs: meal.4,
                fats: meal.5,
                servingAmount: 1,
                mealCategory: meal.0,
                timeLogged: loggedAt
            ))
            XCTAssertEqual(entry.foodName, meal.1)
            XCTAssertEqual(entry.mealCategory, meal.0)
            XCTAssertEqual(entry.timeLogged, loggedAt)
        }

        XCTAssertEqual(store.entriesForToday(in: .breakfast).count, 1)
        XCTAssertEqual(store.entriesForToday(in: .lunch).count, 1)
        XCTAssertEqual(store.entriesForToday(in: .dinner).count, 1)
        XCTAssertEqual(store.entriesForToday(in: .snacks).count, 1)
        XCTAssertEqual(store.dashboard.totals.calories, 1560, accuracy: 0.001)
        XCTAssertEqual(store.dashboard.totals.protein, 113, accuracy: 0.001)
        XCTAssertEqual(store.dashboard.totals.carbs, 176, accuracy: 0.001)
        XCTAssertEqual(store.dashboard.totals.fats, 44, accuracy: 0.001)
        XCTAssertEqual(provider.savedState?.entries.count, 4)
    }

    func testEditingAndDeletingFoodEntriesPersistState() throws {
        let now = date(year: 2026, month: 5, day: 23, hour: 8)
        let provider = NutritionTestProvider(state: .empty)
        let store = PulsarNutritionStore(provider: provider, calendar: calendar, nowProvider: { now })
        let entry = try XCTUnwrap(store.logFoodEntry(
            foodName: "Toast",
            calories: 180,
            protein: 7,
            carbs: 28,
            fats: 4,
            servingAmount: 1,
            mealCategory: .breakfast,
            timeLogged: now
        ))

        let updated = try XCTUnwrap(store.updateFoodEntry(
            id: entry.id,
            foodName: "Yogurt Bowl",
            calories: 260,
            protein: 28,
            carbs: 32,
            fats: 6,
            servingAmount: 1.5,
            servingUnit: "bowl",
            mealCategory: .snacks,
            timeLogged: now.addingTimeInterval(3600),
            note: "Edited locally"
        ))

        XCTAssertTrue(store.entriesForToday(in: .breakfast).isEmpty)
        XCTAssertEqual(store.entriesForToday(in: .snacks).count, 1)
        XCTAssertEqual(updated.foodName, "Yogurt Bowl")
        XCTAssertEqual(updated.calories, 260, accuracy: 0.001)
        XCTAssertEqual(updated.protein, 28, accuracy: 0.001)
        XCTAssertEqual(updated.carbs, 32, accuracy: 0.001)
        XCTAssertEqual(updated.fats, 6, accuracy: 0.001)
        XCTAssertEqual(updated.servingAmount, 1.5, accuracy: 0.001)
        XCTAssertEqual(updated.food.serving.unit, "bowl")
        XCTAssertEqual(provider.savedState?.entries.first?.foodName, "Yogurt Bowl")

        store.deleteEntry(id: updated.id)

        XCTAssertTrue(store.entriesForToday().isEmpty)
        XCTAssertEqual(provider.savedState?.entries.count, 0)
    }

    func testFileStorePersistsNutritionStateAcrossStoreRestart() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = date(year: 2026, month: 5, day: 23, hour: 18)
        let barcodeReference = PulsarNutritionExternalReference(provider: .barcodeScanner, identifier: "012345678905")
        let provider = PulsarNutritionLocalProvider(
            fileStore: PulsarNutritionFileStore(directoryURL: directory),
            calendar: calendar
        )
        let store = PulsarNutritionStore(provider: provider, calendar: calendar, nowProvider: { now })

        _ = try XCTUnwrap(store.logFoodEntry(
            foodName: "Pasta Bowl",
            calories: 640,
            protein: 31,
            carbs: 82,
            fats: 20,
            servingAmount: 1,
            mealCategory: .dinner,
            timeLogged: now,
            source: .barcodeScanner,
            foodMetadata: PulsarFoodMetadata(barcode: "012345678905", externalReference: barcodeReference),
            entryMetadata: PulsarNutritionEntryMetadata(externalReference: barcodeReference, syncStatus: .pendingUpload)
        ))

        let reloadedProvider = PulsarNutritionLocalProvider(
            fileStore: PulsarNutritionFileStore(directoryURL: directory),
            calendar: calendar
        )
        let reloaded = PulsarNutritionStore(provider: reloadedProvider, calendar: calendar, nowProvider: { now })
        let persisted = try XCTUnwrap(reloaded.entriesForToday(in: .dinner).first)

        XCTAssertEqual(reloaded.state.entries.count, 1)
        XCTAssertEqual(persisted.foodName, "Pasta Bowl")
        XCTAssertEqual(persisted.source, .barcodeScanner)
        XCTAssertEqual(persisted.food.metadata?.barcode, "012345678905")
        XCTAssertEqual(persisted.metadata?.syncStatus, .pendingUpload)
        XCTAssertEqual(persisted.metadata?.externalReference?.provider, .barcodeScanner)
    }

    func testMacroCalculationsScaleAndCanBeQueriedByMeal() throws {
        let now = date(year: 2026, month: 5, day: 23, hour: 12)
        let provider = NutritionTestProvider(state: .empty)
        let store = PulsarNutritionStore(provider: provider, calendar: calendar, nowProvider: { now })

        store.logFood(PulsarNutritionFixtures.greekYogurt, servingMultiplier: 2.5, mealMoment: .lunch, loggedAt: now)
        let entry = try XCTUnwrap(store.entriesForToday(in: .lunch).first)
        let totals = store.macroTotals(on: now, in: .lunch)

        XCTAssertEqual(entry.servingMultiplier, 2.5, accuracy: 0.001)
        XCTAssertEqual(totals.calories, 400, accuracy: 0.001)
        XCTAssertEqual(totals.protein, 57.5, accuracy: 0.001)
        XCTAssertEqual(totals.carbs, 25, accuracy: 0.001)
        XCTAssertEqual(totals.fats, 10, accuracy: 0.001)
    }

    func testRecentAndCommonFoodsSupportFastRelogging() throws {
        let now = date(year: 2026, month: 5, day: 23, hour: 10)
        let provider = NutritionTestProvider(state: .empty)
        let store = PulsarNutritionStore(provider: provider, calendar: calendar, nowProvider: { now })

        XCTAssertTrue(store.recentFoods().isEmpty)
        XCTAssertTrue(store.commonFoods().contains { $0.name == "Greek Yogurt" })

        _ = try XCTUnwrap(store.logFoodEntry(
            foodName: "Custom Burrito",
            calories: 530,
            protein: 27,
            carbs: 62,
            fats: 18,
            servingAmount: 1,
            mealCategory: .lunch,
            timeLogged: now
        ))
        store.logFood(PulsarNutritionFixtures.oats, servingMultiplier: 1, mealMoment: .breakfast, loggedAt: now.addingTimeInterval(1800))
        _ = try XCTUnwrap(store.logFoodEntry(
            foodName: "Custom Burrito",
            calories: 530,
            protein: 27,
            carbs: 62,
            fats: 18,
            servingAmount: 1,
            mealCategory: .lunch,
            timeLogged: now.addingTimeInterval(3600)
        ))

        XCTAssertEqual(store.recentFoods(limit: 2).map(\.name), ["Custom Burrito", "Overnight Oats"])
        XCTAssertEqual(store.searchFoods("").first?.name, "Custom Burrito")
        XCTAssertTrue(store.searchFoods("oats").contains { $0.name == "Overnight Oats" })
    }

    func testHydrationTemplatesAndRecipesUpdateLocalNutritionState() {
        let now = date(year: 2026, month: 5, day: 23, hour: 9)
        let provider = NutritionTestProvider(state: .empty)
        let store = PulsarNutritionStore(provider: provider, calendar: calendar, nowProvider: { now })

        store.addHydration(500, loggedAt: now)
        XCTAssertEqual(store.dashboard.hydrationTotal, 500, accuracy: 0.001)

        store.logFood(PulsarNutritionFixtures.oats, servingMultiplier: 1, mealMoment: .breakfast, loggedAt: now)
        store.logFood(PulsarNutritionFixtures.greekYogurt, servingMultiplier: 1, mealMoment: .breakfast, loggedAt: now)
        let template = store.saveTemplate(name: "Morning Anchor", moment: .breakfast, entries: store.entriesForToday(in: .breakfast))

        XCTAssertNotNil(template)
        XCTAssertEqual(store.state.mealTemplates.count, 1)

        store.applyTemplate(template!, to: .snacks)
        XCTAssertEqual(store.entriesForToday(in: .snacks).count, 2)

        let recipe = PulsarRecipe(
            name: "Test Bowl",
            servings: 2,
            ingredients: [
                PulsarRecipeIngredient(food: PulsarNutritionFixtures.salmonBowl, servingMultiplier: 1),
                PulsarRecipeIngredient(food: PulsarNutritionFixtures.lentilSoup, servingMultiplier: 1)
            ]
        )
        store.saveRecipe(recipe, saveAsPrivateFood: true)

        XCTAssertEqual(store.state.recipes.count, 1)
        XCTAssertTrue(store.state.privateFoods.contains { $0.name == "Test Bowl" })
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pulsar-nutrition-tests-\(UUID().uuidString)", isDirectory: true)
    }
}

private final class NutritionTestProvider: PulsarNutritionProviding {
    private var state: PulsarNutritionState
    var savedState: PulsarNutritionState?

    init(state: PulsarNutritionState) {
        self.state = state
    }

    func loadState() -> PulsarNutritionState {
        state
    }

    func saveState(_ state: PulsarNutritionState) throws {
        self.state = state
        savedState = state
    }

    func recoveryContext(for date: Date) -> PulsarNutritionRecoveryContext {
        _ = date
        return .mock
    }

    func searchableFoods() -> [PulsarFoodItem] {
        PulsarNutritionFixtures.searchFoods
    }
}
