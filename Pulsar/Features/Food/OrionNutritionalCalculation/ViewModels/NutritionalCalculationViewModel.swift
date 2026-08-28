//
//  NutritionalCalculationViewModel.swift
//  Pulsar
//

import Foundation
import Observation

@MainActor
@Observable
final class NutritionalCalculationViewModel {
    enum Step: Int, CaseIterable {
        case introduction
        case body
        case activity
        case workoutPlan
        case goal
        case preferences
        case results

        var title: String {
            switch self {
            case .introduction: "Your calculation"
            case .body: "Confirm body info"
            case .activity: "Activity Summary"
            case .workoutPlan: "Log your workout plan"
            case .goal: "Choose your goal"
            case .preferences: "Preferences & safety"
            case .results: "Your targets"
            }
        }
    }

    var input: NutritionCalculationInput
    private(set) var step: Step = .introduction
    private(set) var result: NutritionalCalculationResult?
    private(set) var explanation: OrionNutritionExplanation?
    private(set) var isLoadingActivity = false
    private(set) var isGenerating = false
    private(set) var isLoadingExplanation = false
    private(set) var pendingTargetConfirmation: NutritionTargetChangeAssessment?
    var allowsOrionExplanation = false
    var errorMessage: String?
    private(set) var healthKitWeightKilograms: Double?
    private(set) var healthKitBodyFatPercentage: Double?
    var editingWorkoutEntry: NutritionWorkoutPlanEntry?

    let preferredUnits: UnitPreference

    private let activityAnalyzer: NutritionHealthActivityAnalyzing
    private let engine: NutritionalCalculationEngineProtocol
    private let aiService: OrionNutritionAIServicing
    private let hadProfileWeight: Bool
    private let previousTargetCalories: Double?

    convenience init(
        profile: UserProfile,
        latestBodyCheckIn: PulsarBodyCheckIn?,
        previousTargetCalories: Double? = nil
    ) {
        self.init(
            profile: profile,
            latestBodyCheckIn: latestBodyCheckIn,
            previousTargetCalories: previousTargetCalories,
            activityAnalyzer: NutritionHealthActivityAnalyzer(),
            engine: NutritionalCalculationEngine(),
            aiService: OrionNutritionAIService()
        )
    }

    init(
        profile: UserProfile,
        latestBodyCheckIn: PulsarBodyCheckIn?,
        previousTargetCalories: Double? = nil,
        activityAnalyzer: NutritionHealthActivityAnalyzing,
        engine: NutritionalCalculationEngineProtocol,
        aiService: OrionNutritionAIServicing
    ) {
        input = .prefilled(from: profile, latestBodyCheckIn: latestBodyCheckIn)
        preferredUnits = profile.preferredUnits
        hadProfileWeight = latestBodyCheckIn?.weightKilograms != nil || profile.resolvedWeightKilograms != nil
        self.previousTargetCalories = previousTargetCalories
        self.activityAnalyzer = activityAnalyzer
        self.engine = engine
        self.aiService = aiService
    }

    var progress: Double {
        Double(step.rawValue + 1) / Double(Step.allCases.count)
    }

    var canMoveBack: Bool { step != .introduction }

    func moveForward() {
        errorMessage = nil
        guard step != .results else { return }
        if step == .preferences {
            generate()
            return
        }
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func moveBack() {
        errorMessage = nil
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func loadActivityIfNeeded() async {
        guard input.healthActivity == nil, !isLoadingActivity else { return }
        await reloadActivity()
    }

    func reloadActivity() async {
        isLoadingActivity = true
        errorMessage = nil
        let restingEnergy = BasalMetabolicRateCalculator().calculate(input: input).calories
        let analysis = await activityAnalyzer.analyze(
            profileWeightKilograms: input.weightKilograms,
            restingEnergyKilocalories: restingEnergy,
            plannedWeeklySessions: input.workoutPlan.totalSessionsPerWeek,
            age: input.age
        )
        guard !Task.isCancelled else {
            isLoadingActivity = false
            return
        }
        input.healthActivity = analysis.summary
        healthKitWeightKilograms = analysis.latestWeightKilograms
        healthKitBodyFatPercentage = analysis.latestBodyFatPercentage
        if !hadProfileWeight, let weight = analysis.latestWeightKilograms {
            input.weightKilograms = weight
        }
        if input.bodyFatPercentage == nil, let bodyFat = analysis.latestBodyFatPercentage, (5...60).contains(bodyFat) {
            input.bodyFatPercentage = bodyFat
        }
        isLoadingActivity = false
    }

    func useHealthKitWeight() {
        guard let healthKitWeightKilograms else { return }
        input.weightKilograms = healthKitWeightKilograms
    }

    func importObservedWorkoutPlan() {
        let aggregates = input.healthActivity?.observedWorkoutAggregates ?? []
        input.workoutPlan.sessions = NutritionWorkoutTypeMapper.suggestedPlanEntries(from: aggregates)
        input.trainsRegularly = !input.workoutPlan.sessions.isEmpty
    }

    func addWorkoutEntry(_ entry: NutritionWorkoutPlanEntry) {
        input.workoutPlan.sessions.append(entry)
        input.trainsRegularly = true
    }

    func updateWorkoutEntry(_ entry: NutritionWorkoutPlanEntry) {
        guard let index = input.workoutPlan.sessions.firstIndex(where: { $0.id == entry.id }) else { return }
        input.workoutPlan.sessions[index] = entry
    }

    func deleteWorkoutEntry(id: UUID) {
        input.workoutPlan.sessions.removeAll { $0.id == id }
        if input.workoutPlan.sessions.isEmpty {
            input.trainsRegularly = false
        }
    }

    func generate() {
        isGenerating = true
        errorMessage = nil
        Task { @MainActor in
            await Task.yield()
            do {
                result = try engine.calculate(
                    input: input,
                    now: .now,
                    previousTargetCalories: previousTargetCalories
                )
                explanation = nil
                pendingTargetConfirmation = result.map { calculation in
                    NutritionTargetChangeAssessment(
                        requiresConfirmation: calculation.energy.requiresUserConfirmation,
                        previousTargetCalories: calculation.energy.previousTargetCalories,
                        proposedTargetCalories: calculation.energy.targetCalories,
                        deltaCalories: calculation.energy.previousTargetCalories.map {
                            calculation.energy.targetCalories - $0
                        } ?? 0,
                        deltaPercent: {
                            guard let previous = calculation.energy.previousTargetCalories, previous > 0 else { return 0 }
                            return abs(calculation.energy.targetCalories - previous) / previous
                        }(),
                        reasons: calculation.energy.confirmationReasons
                    )
                }
                step = .results
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }

    func requestExplanation() async {
        guard allowsOrionExplanation, let result else { return }
        isLoadingExplanation = true
        errorMessage = nil
        do {
            explanation = try await aiService.explain(input: input, result: result)
        } catch is CancellationError {
            isLoadingExplanation = false
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingExplanation = false
    }

    func savedCalculation(at date: Date = .now) -> SavedNutritionalCalculation? {
        guard let result else { return nil }
        return SavedNutritionalCalculation(
            input: input,
            result: result,
            explanation: explanation,
            savedAt: date
        )
    }

    func openLegacyCalculationForEditing(_ saved: SavedNutritionalCalculation) {
        var editableInput = saved.input
        editableInput.migrateLegacyWorkoutFieldsIfNeeded()
        input = editableInput
        result = saved.result
        explanation = saved.explanation
        step = .workoutPlan
    }
}
