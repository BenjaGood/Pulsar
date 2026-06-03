//
//  PulsarNutritionStore.swift
//  Pulsar
//

import Combine
import Foundation
import UIKit

protocol PulsarNutritionProviding {
    func loadState() -> PulsarNutritionState
    func saveState(_ state: PulsarNutritionState) throws
    func recoveryContext(for date: Date) -> PulsarNutritionRecoveryContext
    func searchableFoods() -> [PulsarFoodItem]
}

struct PulsarNutritionPersistedState: Codable, Equatable {
    var version: Int
    var state: PulsarNutritionState

    static let currentVersion = 2
    static let empty = PulsarNutritionPersistedState(version: currentVersion, state: .empty)
}

struct PulsarNutritionFileStore {
    private let fileManager: FileManager
    private let directoryURL: URL
    private let fileName = "nutrition-state-v1.json"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.directoryURL = applicationSupport
                .appendingPathComponent("Pulsar", isDirectory: true)
                .appendingPathComponent("Nutrition", isDirectory: true)
        }
    }

    func load() -> PulsarNutritionPersistedState {
        let url = directoryURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let persisted = try? decoder.decode(PulsarNutritionPersistedState.self, from: data) else {
            return .empty
        }
        return persisted
    }

    func save(_ persisted: PulsarNutritionPersistedState) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(persisted)
        try data.write(to: directoryURL.appendingPathComponent(fileName), options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}

struct PulsarNutritionLocalProvider: PulsarNutritionProviding {
    private let fileStore: PulsarNutritionFileStore
    private let calendar: Calendar

    init(fileStore: PulsarNutritionFileStore = PulsarNutritionFileStore(), calendar: Calendar = .current) {
        self.fileStore = fileStore
        self.calendar = calendar
    }

    func loadState() -> PulsarNutritionState {
        let persisted = fileStore.load()
        return normalized(persisted.state)
    }

    func saveState(_ state: PulsarNutritionState) throws {
        try fileStore.save(PulsarNutritionPersistedState(version: PulsarNutritionPersistedState.currentVersion, state: normalized(state)))
    }

    func recoveryContext(for date: Date) -> PulsarNutritionRecoveryContext {
        _ = date
        return .mock
    }

    func searchableFoods() -> [PulsarFoodItem] {
        PulsarNutritionFixtures.searchFoods
    }

    private func normalized(_ state: PulsarNutritionState) -> PulsarNutritionState {
        var entriesByID: [UUID: PulsarNutritionEntry] = [:]
        for entry in state.entries {
            entriesByID[entry.id] = entry
        }

        var hydrationByID: [UUID: PulsarHydrationEntry] = [:]
        for entry in state.hydrationEntries {
            hydrationByID[entry.id] = entry
        }

        var foodsByID: [UUID: PulsarFoodItem] = [:]
        for food in state.privateFoods {
            foodsByID[food.id] = food
        }

        var templatesByID: [UUID: PulsarMealTemplate] = [:]
        for template in state.mealTemplates {
            templatesByID[template.id] = template
        }

        var recipesByID: [UUID: PulsarRecipe] = [:]
        for recipe in state.recipes {
            recipesByID[recipe.id] = recipe
        }

        var bodyByID: [UUID: PulsarBodyCheckIn] = [:]
        for checkIn in state.bodyCheckIns {
            bodyByID[checkIn.id] = checkIn
        }

        var targetsByID: [UUID: PulsarNutritionTargetSnapshot] = [:]
        for target in state.targetSnapshots {
            targetsByID[target.id] = target
        }

        return PulsarNutritionState(
            entries: entriesByID.values.sorted { $0.loggedAt > $1.loggedAt },
            hydrationEntries: hydrationByID.values.sorted { $0.loggedAt > $1.loggedAt },
            privateFoods: foodsByID.values.sorted { $0.updatedAt > $1.updatedAt },
            mealTemplates: templatesByID.values.sorted { $0.updatedAt > $1.updatedAt },
            recipes: recipesByID.values.sorted { $0.updatedAt > $1.updatedAt },
            bodyCheckIns: bodyByID.values.sorted { $0.date > $1.date },
            targetSnapshots: targetsByID.values.sorted { $0.date > $1.date },
            eatingWindow: state.eatingWindow
        )
    }
}

@MainActor
final class PulsarNutritionStore: ObservableObject {
    @Published private(set) var state: PulsarNutritionState
    @Published private(set) var dashboard: PulsarNutritionDashboard
    @Published private(set) var lastPersistenceError: String?

    private let provider: PulsarNutritionProviding
    private let calendar: Calendar
    private let nowProvider: () -> Date

    init(
        provider: PulsarNutritionProviding? = nil,
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        let provider = provider ?? PulsarNutritionLocalProvider(calendar: calendar)
        self.provider = provider
        self.calendar = calendar
        self.nowProvider = nowProvider
        let loaded = provider.loadState()
        let target = Self.targetSnapshot(
            for: nowProvider(),
            context: provider.recoveryContext(for: nowProvider()),
            calendar: calendar
        )
        let stateWithTarget = Self.stateByEnsuringTarget(
            target,
            in: loaded,
            calendar: calendar
        )
        self.state = stateWithTarget
        self.dashboard = Self.dashboard(
            from: stateWithTarget,
            date: nowProvider(),
            context: provider.recoveryContext(for: nowProvider()),
            calendar: calendar
        )
    }

    func reload() {
        updateState(provider.loadState(), persist: false)
    }

    func searchFoods(_ query: String) -> [PulsarFoodItem] {
        let allFoods = Array((recentFoods(limit: 12) + state.privateFoods + provider.searchableFoods()).uniqued(by: \.id))
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Array(allFoods.prefix(10))
        }
        return allFoods.filter { food in
            food.name.localizedCaseInsensitiveContains(trimmed) ||
                food.detail.localizedCaseInsensitiveContains(trimmed) ||
                (food.brand?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    func commonFoods(limit: Int = 8) -> [PulsarFoodItem] {
        Array(provider.searchableFoods().prefix(limit))
    }

    func recentFoods(limit: Int = 8) -> [PulsarFoodItem] {
        Array(
            state.entries
                .sorted { $0.loggedAt > $1.loggedAt }
                .map(\.food)
                .uniqued(by: \.name)
                .prefix(limit)
        )
    }

    @discardableResult
    func logFood(
        _ food: PulsarFoodItem,
        servingMultiplier: Double,
        mealMoment: PulsarNutritionMealMoment,
        note: String? = nil,
        confidence: Double = 1,
        source: PulsarNutritionSource? = nil,
        loggedAt: Date = Date()
    ) -> PulsarNutritionEntry {
        let entry = PulsarNutritionEntry(
            food: food,
            servingMultiplier: servingMultiplier,
            mealMoment: mealMoment,
            loggedAt: loggedAt,
            note: note,
            confidence: confidence,
            source: source
        )
        var next = state
        next.entries.insert(entry, at: 0)
        updateState(next)
        haptic(.soft)
        return entry
    }

    @discardableResult
    func logFoodEntry(
        foodName: String,
        calories: Double,
        protein: Double,
        carbs: Double,
        fats: Double,
        servingAmount: Double,
        servingUnit: String = "serving",
        mealCategory: PulsarNutritionMealCategory,
        timeLogged: Date? = nil,
        note: String? = nil,
        source: PulsarNutritionSource = .userEntered,
        foodMetadata: PulsarFoodMetadata? = nil,
        entryMetadata: PulsarNutritionEntryMetadata? = nil
    ) -> PulsarNutritionEntry? {
        let trimmedName = foodName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        let entry = PulsarNutritionEntry(
            foodName: trimmedName,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fats: fats,
            servingAmount: servingAmount,
            servingUnit: servingUnit,
            mealCategory: mealCategory,
            timeLogged: timeLogged ?? nowProvider(),
            note: note,
            source: source,
            foodMetadata: foodMetadata,
            entryMetadata: entryMetadata
        )
        var next = state
        next.entries.insert(entry, at: 0)
        updateState(next)
        haptic(.soft)
        return entry
    }

    func updateEntry(_ entry: PulsarNutritionEntry) {
        var next = state
        next.entries.removeAll { $0.id == entry.id }
        next.entries.insert(entry, at: 0)
        updateState(next)
        haptic(.light)
    }

    @discardableResult
    func updateFoodEntry(
        id: UUID,
        foodName: String? = nil,
        calories: Double? = nil,
        protein: Double? = nil,
        carbs: Double? = nil,
        fats: Double? = nil,
        servingAmount: Double? = nil,
        servingUnit: String? = nil,
        mealCategory: PulsarNutritionMealCategory? = nil,
        timeLogged: Date? = nil,
        note: String? = nil,
        source: PulsarNutritionSource? = nil,
        foodMetadata: PulsarFoodMetadata? = nil,
        entryMetadata: PulsarNutritionEntryMetadata? = nil
    ) -> PulsarNutritionEntry? {
        guard var entry = state.entries.first(where: { $0.id == id }) else { return nil }

        if let foodName {
            let trimmedName = foodName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty {
                entry.foodName = trimmedName
            }
        }
        if let servingAmount {
            entry.servingAmount = servingAmount
        }
        if let servingUnit {
            let trimmedUnit = servingUnit.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedUnit.isEmpty {
                entry.food.serving.unit = trimmedUnit
            }
        }

        let divisor = max(entry.servingMultiplier, 0.05)
        if let calories {
            entry.food.nutritionPerServing.calories = max(0, calories) / divisor
        }
        if let protein {
            entry.food.nutritionPerServing.protein = max(0, protein) / divisor
        }
        if let carbs {
            entry.food.nutritionPerServing.carbs = max(0, carbs) / divisor
        }
        if let fats {
            entry.food.nutritionPerServing.fats = max(0, fats) / divisor
        }
        if let mealCategory {
            entry.mealCategory = mealCategory
        }
        if let timeLogged {
            entry.timeLogged = timeLogged
        }
        if let note {
            entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let source {
            entry.source = source
            entry.food.source = source
        }
        if let foodMetadata {
            entry.food.metadata = foodMetadata
        }
        if let entryMetadata {
            entry.metadata = entryMetadata
        }

        updateEntry(entry)
        return entry
    }

    func deleteEntry(_ entry: PulsarNutritionEntry) {
        var next = state
        next.entries.removeAll { $0.id == entry.id }
        updateState(next)
    }

    func deleteEntry(id: UUID) {
        var next = state
        next.entries.removeAll { $0.id == id }
        updateState(next)
    }

    @discardableResult
    func duplicateEntry(_ entry: PulsarNutritionEntry, mealMoment: PulsarNutritionMealMoment? = nil) -> PulsarNutritionEntry {
        let duplicate = PulsarNutritionEntry(
            food: entry.food,
            servingMultiplier: entry.servingMultiplier,
            mealMoment: mealMoment ?? entry.mealMoment,
            loggedAt: nowProvider(),
            note: entry.note,
            confidence: entry.confidence,
            source: entry.source
        )
        var next = state
        next.entries.insert(duplicate, at: 0)
        updateState(next)
        haptic(.soft)
        return duplicate
    }

    func moveEntry(_ entry: PulsarNutritionEntry, to mealMoment: PulsarNutritionMealMoment) {
        var moved = entry
        moved.mealMoment = mealMoment
        moved.loggedAt = nowProvider()
        updateEntry(moved)
    }

    func repeatEntry(_ entry: PulsarNutritionEntry) {
        duplicateEntry(entry)
    }

    @discardableResult
    func quickAddFood(
        _ food: PulsarFoodItem,
        mealMoment: PulsarNutritionMealMoment,
        loggedAt: Date? = nil
    ) -> PulsarNutritionEntry {
        logFood(
            food,
            servingMultiplier: 1,
            mealMoment: mealMoment,
            confidence: food.source == .quickEstimate ? 0.72 : 1,
            source: food.source,
            loggedAt: loggedAt ?? nowProvider()
        )
    }

    @discardableResult
    func savePrivateFood(_ food: PulsarFoodItem) -> PulsarFoodItem {
        var saved = food
        saved.source = .privateFood
        saved.isSaved = true
        saved.updatedAt = nowProvider()
        var next = state
        next.privateFoods.removeAll { $0.id == saved.id || $0.name.caseInsensitiveCompare(saved.name) == .orderedSame }
        next.privateFoods.insert(saved, at: 0)
        updateState(next)
        haptic(.soft)
        return saved
    }

    func addHydration(_ amountMilliliters: Double, loggedAt: Date = Date()) {
        var next = state
        next.hydrationEntries.insert(
            PulsarHydrationEntry(amountMilliliters: amountMilliliters, loggedAt: loggedAt),
            at: 0
        )
        updateState(next)
        haptic(.light)
    }

    func deleteHydration(_ entry: PulsarHydrationEntry) {
        var next = state
        next.hydrationEntries.removeAll { $0.id == entry.id }
        updateState(next)
    }

    @discardableResult
    func saveBodyCheckIn(
        weightKilograms: Double?,
        waistCentimeters: Double?,
        bodyFatPercentage: Double?,
        note: String?
    ) -> PulsarBodyCheckIn {
        let checkIn = PulsarBodyCheckIn(
            weightKilograms: weightKilograms,
            waistCentimeters: waistCentimeters,
            bodyFatPercentage: bodyFatPercentage,
            note: note
        )
        var next = state
        next.bodyCheckIns.insert(checkIn, at: 0)
        updateState(next)
        haptic(.soft)
        return checkIn
    }

    @discardableResult
    func saveTemplate(
        name: String,
        moment: PulsarNutritionMealMoment,
        entries: [PulsarNutritionEntry]
    ) -> PulsarMealTemplate? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = entries.map { PulsarMealTemplateItem(food: $0.food, servingMultiplier: $0.servingMultiplier) }
        guard !trimmed.isEmpty, !items.isEmpty else { return nil }
        let template = PulsarMealTemplate(name: trimmed, defaultMoment: moment, items: items)
        var next = state
        next.mealTemplates.insert(template, at: 0)
        updateState(next)
        haptic(.soft)
        return template
    }

    func applyTemplate(_ template: PulsarMealTemplate, to moment: PulsarNutritionMealMoment? = nil) {
        let resolvedMoment = moment ?? template.defaultMoment
        var next = state
        let entries = template.items.map {
            PulsarNutritionEntry(
                food: $0.food,
                servingMultiplier: $0.servingMultiplier,
                mealMoment: resolvedMoment,
                loggedAt: nowProvider(),
                confidence: 1,
                source: .mealTemplate
            )
        }
        next.entries.insert(contentsOf: entries, at: 0)
        updateState(next)
        haptic(.soft)
    }

    func duplicateTemplate(_ template: PulsarMealTemplate) {
        let duplicate = PulsarMealTemplate(
            name: "\(template.name) Copy",
            defaultMoment: template.defaultMoment,
            items: template.items
        )
        var next = state
        next.mealTemplates.insert(duplicate, at: 0)
        updateState(next)
    }

    func deleteTemplate(_ template: PulsarMealTemplate) {
        var next = state
        next.mealTemplates.removeAll { $0.id == template.id }
        updateState(next)
    }

    @discardableResult
    func saveRecipe(_ recipe: PulsarRecipe, saveAsPrivateFood: Bool) -> PulsarRecipe {
        var next = state
        var saved = recipe
        saved.updatedAt = nowProvider()
        next.recipes.removeAll { $0.id == saved.id }
        next.recipes.insert(saved, at: 0)
        if saveAsPrivateFood {
            next.privateFoods.removeAll { $0.name.caseInsensitiveCompare(saved.name) == .orderedSame }
            next.privateFoods.insert(saved.reusableFood, at: 0)
        }
        updateState(next)
        haptic(.soft)
        return saved
    }

    func deleteRecipe(_ recipe: PulsarRecipe) {
        var next = state
        next.recipes.removeAll { $0.id == recipe.id }
        updateState(next)
    }

    func toggleEatingWindow() {
        var next = state
        next.eatingWindow.isEnabled.toggle()
        updateState(next)
        haptic(.light)
    }

    func setEatingWindow(startHour: Int, endHour: Int) {
        var next = state
        next.eatingWindow.startHour = min(max(startHour, 0), 23)
        next.eatingWindow.endHour = min(max(endHour, 1), 24)
        updateState(next)
    }

    func entries(on date: Date = Date(), in moment: PulsarNutritionMealMoment? = nil) -> [PulsarNutritionEntry] {
        state.entries
            .filter { calendar.isDate($0.loggedAt, inSameDayAs: date) }
            .filter { moment == nil || $0.mealMoment == moment }
            .sorted { $0.loggedAt < $1.loggedAt }
    }

    func entriesForToday(in moment: PulsarNutritionMealMoment? = nil) -> [PulsarNutritionEntry] {
        entries(on: nowProvider(), in: moment)
    }

    func macroTotals(on date: Date = Date(), in mealCategory: PulsarNutritionMealCategory? = nil) -> PulsarNutritionFacts {
        entries(on: date, in: mealCategory).reduce(.zero) { $0 + $1.nutrition }
    }

    private func updateState(_ candidate: PulsarNutritionState, persist: Bool = true) {
        let context = provider.recoveryContext(for: nowProvider())
        let target = Self.targetSnapshot(for: nowProvider(), context: context, calendar: calendar)
        let next = Self.stateByEnsuringTarget(target, in: candidate, calendar: calendar)
        state = sorted(next)
        dashboard = Self.dashboard(from: state, date: nowProvider(), context: context, calendar: calendar)
        guard persist else { return }
        do {
            try provider.saveState(state)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = "Nutrition data could not be saved locally."
        }
    }

    private func sorted(_ state: PulsarNutritionState) -> PulsarNutritionState {
        PulsarNutritionState(
            entries: state.entries.sorted { $0.loggedAt > $1.loggedAt },
            hydrationEntries: state.hydrationEntries.sorted { $0.loggedAt > $1.loggedAt },
            privateFoods: state.privateFoods.sorted { $0.updatedAt > $1.updatedAt },
            mealTemplates: state.mealTemplates.sorted { $0.updatedAt > $1.updatedAt },
            recipes: state.recipes.sorted { $0.updatedAt > $1.updatedAt },
            bodyCheckIns: state.bodyCheckIns.sorted { $0.date > $1.date },
            targetSnapshots: state.targetSnapshots.sorted { $0.date > $1.date },
            eatingWindow: state.eatingWindow
        )
    }

    private static func dashboard(
        from state: PulsarNutritionState,
        date: Date,
        context: PulsarNutritionRecoveryContext,
        calendar: Calendar
    ) -> PulsarNutritionDashboard {
        let todayEntries = state.entries.filter { calendar.isDate($0.loggedAt, inSameDayAs: date) }
        let todayHydration = state.hydrationEntries.filter { calendar.isDate($0.loggedAt, inSameDayAs: date) }
        let target = state.targetSnapshots.first { calendar.isDate($0.date, inSameDayAs: date) }
            ?? targetSnapshot(for: date, context: context, calendar: calendar)
        let points = weeklyPoints(from: state, date: date, target: target, calendar: calendar)
        let tempDashboard = PulsarNutritionDashboard(
            date: date,
            entries: todayEntries,
            hydrationEntries: todayHydration,
            bodyCheckIns: state.bodyCheckIns,
            target: target,
            recoveryContext: context,
            weeklyPoints: points,
            insights: [],
            eatingWindow: state.eatingWindow
        )
        return PulsarNutritionDashboard(
            date: date,
            entries: todayEntries,
            hydrationEntries: todayHydration,
            bodyCheckIns: state.bodyCheckIns,
            target: target,
            recoveryContext: context,
            weeklyPoints: points,
            insights: insights(for: tempDashboard),
            eatingWindow: state.eatingWindow
        )
    }

    private static func stateByEnsuringTarget(
        _ target: PulsarNutritionTargetSnapshot,
        in state: PulsarNutritionState,
        calendar: Calendar
    ) -> PulsarNutritionState {
        var next = state
        if !next.targetSnapshots.contains(where: { calendar.isDate($0.date, inSameDayAs: target.date) }) {
            next.targetSnapshots.insert(target, at: 0)
        }
        return next
    }

    private static func targetSnapshot(
        for date: Date,
        context: PulsarNutritionRecoveryContext,
        calendar: Calendar
    ) -> PulsarNutritionTargetSnapshot {
        _ = calendar
        let activityBoost = min(max(context.activeEnergyKilocalories - 400, 0), 500)
        let lowerFuel = 2050 + activityBoost * 0.35
        let upperFuel = lowerFuel + 360
        let proteinLower = 118 + context.proteinAdjustmentGrams
        let proteinUpper = proteinLower + 28
        let hydration = 2400 + context.hydrationAdjustmentMilliliters
        let rationale = context.recoveryScore >= 80
            ? "Recovery is strong, so Pulsar keeps fuel steady and protein anchored for adaptation."
            : "Recovery is asking for ease, so Pulsar narrows the day around steady protein, fiber, and hydration."
        return PulsarNutritionTargetSnapshot(
            date: date,
            fuelRange: lowerFuel...upperFuel,
            proteinRange: proteinLower...proteinUpper,
            fiberTarget: 28,
            hydrationTargetMilliliters: hydration,
            recoveryScore: context.recoveryScore,
            activityLoad: context.activityLoad,
            rationale: rationale
        )
    }

    private static func weeklyPoints(
        from state: PulsarNutritionState,
        date: Date,
        target: PulsarNutritionTargetSnapshot,
        calendar: Calendar
    ) -> [PulsarNutritionWeekPoint] {
        (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { return nil }
            let entries = state.entries.filter { calendar.isDate($0.loggedAt, inSameDayAs: day) }
            let hydration = state.hydrationEntries.filter { calendar.isDate($0.loggedAt, inSameDayAs: day) }
            let totals = entries.reduce(PulsarNutritionFacts.zero) { $0 + $1.nutrition }
            let hydrationTotal = hydration.reduce(0) { $0 + $1.amountMilliliters }
            let proteinConsistency = min(totals.protein / max(target.proteinRange.lowerBound, 1), 1)
            let fiberConsistency = min(totals.fiber / max(target.fiberTarget, 1), 1)
            let hydrationConsistency = min(hydrationTotal / max(target.hydrationTargetMilliliters, 1), 1)
            let consistency = entries.isEmpty && hydration.isEmpty
                ? 0
                : (proteinConsistency * 0.42 + fiberConsistency * 0.25 + hydrationConsistency * 0.33)
            return PulsarNutritionWeekPoint(
                date: day,
                protein: totals.protein,
                fiber: totals.fiber,
                hydrationMilliliters: hydrationTotal,
                consistency: consistency
            )
        }
        .reversed()
    }

    private static func insights(for dashboard: PulsarNutritionDashboard) -> [PulsarNutritionInsight] {
        var insights: [PulsarNutritionInsight] = []
        let proteinRemaining = max(0, dashboard.target.proteinRange.lowerBound - dashboard.totals.protein)
        let hydrationRemaining = max(0, dashboard.target.hydrationTargetMilliliters - dashboard.hydrationTotal)

        insights.append(
            PulsarNutritionInsight(
                kind: .coachBrief,
                title: "Coach brief",
                message: proteinRemaining <= 8
                    ? "Protein is anchored. Keep the rest of the day light and steady."
                    : "A protein-forward meal would support today's recovery signal.",
                symbolName: "sparkles"
            )
        )

        insights.append(
            PulsarNutritionInsight(
                kind: .recovery,
                title: "Recovery note",
                message: "\(dashboard.recoveryContext.sleepContext). Hydration target is nudged up by \(PulsarNutritionFormatters.milliliters(dashboard.recoveryContext.hydrationAdjustmentMilliliters)).",
                symbolName: "arrow.clockwise.heart.fill",
                confidence: 0.82
            )
        )

        if hydrationRemaining > 250 {
            insights.append(
                PulsarNutritionInsight(
                    kind: .trend,
                    title: "Hydration rhythm",
                    message: "\(PulsarNutritionFormatters.milliliters(hydrationRemaining)) would bring today's hydration signal into range.",
                    symbolName: "drop.fill",
                    confidence: 0.78
                )
            )
        }

        if let eveningEntry = dashboard.entries.first(where: { $0.mealMoment == .dinner }),
           eveningEntry.nutrition.fiber >= 8 {
            insights.append(
                PulsarNutritionInsight(
                    kind: .timing,
                    title: "Evening balance",
                    message: "Dinner already has a strong fiber base. Pulsar will keep later prompts quiet.",
                    symbolName: "moon.stars.fill",
                    confidence: 0.74
                )
            )
        }

        let weeklyAverage = dashboard.weeklyPoints.isEmpty
            ? 0
            : dashboard.weeklyPoints.reduce(0) { $0 + $1.consistency } / Double(dashboard.weeklyPoints.count)
        insights.append(
            PulsarNutritionInsight(
                kind: .weekly,
                title: "Weekly rewind",
                message: "Your nutrition consistency is \(Int((weeklyAverage * 100).rounded()))%. The strongest signals are protein and water.",
                symbolName: "calendar.badge.clock",
                confidence: 0.76
            )
        )

        return insights
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

private extension Array {
    func uniqued<ID: Hashable>(by keyPath: KeyPath<Element, ID>) -> [Element] {
        var seen = Set<ID>()
        return filter { element in
            let id = element[keyPath: keyPath]
            guard !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }
    }
}
