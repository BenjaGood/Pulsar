//
//  OrionNutritionalCalculationTests.swift
//  PulsarTests
//

import XCTest
@testable import Pulsar

@MainActor
final class OrionNutritionalCalculationTests: XCTestCase {
    func testMifflinStJeorMaleFixture() {
        let estimate = BasalMetabolicRateCalculator().calculate(input: input(bodyFatPercentage: nil))

        XCTAssertEqual(estimate.formula, .mifflinStJeor)
        XCTAssertEqual(estimate.calories, 1_780, accuracy: 0.001)
    }

    func testKatchMcArdleUsesPlausibleBodyFat() {
        let estimate = BasalMetabolicRateCalculator().calculate(input: input(bodyFatPercentage: 20))

        XCTAssertEqual(estimate.formula, .katchMcArdle)
        XCTAssertEqual(estimate.calories, 1_752.4, accuracy: 0.001)
    }

    func testNationalAcademiesFemaleLowActiveExample() {
        let calculator = EstimatedEnergyRequirementCalculator()
        let eer = calculator.eer(
            sex: .female,
            level: .lowActive,
            age: 22,
            heightCentimeters: 165,
            weightKilograms: 63
        )

        XCTAssertEqual(eer, 2_267, accuracy: 10)
    }

    func testAllEightAdultSexPALCoefficientCombinationsProducePositiveEER() {
        let calculator = EstimatedEnergyRequirementCalculator()
        let levels: [NutritionPhysicalActivityLevel] = [.inactive, .lowActive, .active, .veryActive]
        for sex in [BiologicalSex.male, .female] {
            for level in levels {
                let eer = calculator.eer(sex: sex, level: level, age: 30, heightCentimeters: 175, weightKilograms: 75)
                XCTAssertGreaterThan(eer, 1_200, "\(sex) \(level)")
            }
        }
    }

    func testContinuousPALInterpolationDoesNotJumpAtBoundaries() {
        let calculator = EstimatedEnergyRequirementCalculator()
        let samples = stride(from: 1.39, through: 2.06, by: 0.01).map { pal in
            calculator.interpolatedEER(
                sex: .female,
                pal: pal,
                age: 30,
                heightCentimeters: 165,
                weightKilograms: 63
            )
        }
        let deltas = zip(samples, samples.dropFirst()).map { abs($1 - $0) }
        XCTAssertTrue(deltas.allSatisfy { $0 < 60 })
    }

    func testWorkoutPlanEnergyUsesFrequencyDurationIntensityAndWeight() {
        var plan = NutritionWorkoutPlan.empty
        plan.sessions = [
            NutritionWorkoutPlanEntry(workoutType: .cycling, daysPerWeek: 4, minutesPerSession: 45, intensity: .moderate),
            NutritionWorkoutPlanEntry(workoutType: .gymStrength, daysPerWeek: 3, minutesPerSession: 60, intensity: .moderate)
        ]
        let weekly = NutritionWorkoutEnergyCalculator().weeklyNetWorkoutKilocalories(
            plan: plan,
            bodyWeightKilograms: 80
        )
        XCTAssertGreaterThan(weekly, 500)
    }

    func testWearableCalibrationCannotMoveMaintenanceMoreThanTenPercent() {
        var calculationInput = input()
        calculationInput.healthActivity = activitySummary(validEnergyDays: 21, robustMedian: 3_500)
        let estimate = TotalEnergyExpenditureEstimator().estimate(
            restingEnergy: 1_780,
            input: calculationInput,
            confidence: .high
        )

        XCTAssertLessThanOrEqual(
            abs(estimate.calories - estimate.modeledMaintenanceCalories),
            estimate.modeledMaintenanceCalories * 0.10 + 1
        )
    }

    func testWinsorizedMedianResistsOneExtremeDay() {
        let median = NutritionHealthKitCalibration.winsorizedMedian(
            [2_000, 2_050, 2_100, 2_080, 6_000]
        )
        XCTAssertEqual(median ?? 0, 2_080, accuracy: 80)
    }

    func testSparseTDEEFallsBackToFormulaOnly() {
        var calculationInput = input()
        calculationInput.healthActivity = activitySummary(validEnergyDays: 7)

        let estimate = TotalEnergyExpenditureEstimator().estimate(
            restingEnergy: 1_780,
            input: calculationInput,
            confidence: .moderate
        )

        XCTAssertFalse(estimate.usedMeasuredActivity)
        XCTAssertEqual(estimate.healthKitCalibrationWeight, 0)
        XCTAssertGreaterThan(estimate.calories, 2_000)
    }

    func testNewRoutineAddsOnlyDifferenceFromObservedHistory() {
        var calculationInput = input()
        calculationInput.workoutPlan.basis = .newOrIncreasedRoutine
        calculationInput.workoutPlan.sessions = [
            NutritionWorkoutPlanEntry(workoutType: .running, daysPerWeek: 5, minutesPerSession: 45, intensity: .moderate)
        ]
        calculationInput.healthActivity = activitySummary(
            validEnergyDays: 21,
            observedWeeklyWorkoutEnergy: 1_000
        )
        let summary = NutritionWorkoutEnergyCalculator().summarize(
            input: calculationInput,
            restingEnergy: 1_780,
            modeledMaintenance: 2_400
        )
        XCTAssertGreaterThan(summary.routineAdjustmentKilocaloriesPerDay, 0)
    }

    func testMacroAllocationIsNonNegativeAndReconcilesWithTarget() throws {
        var calculationInput = input(goal: .fatLoss)
        calculationInput.healthActivity = activitySummary(validEnergyDays: 21)
        let result = try NutritionalCalculationEngine().calculate(input: calculationInput, now: .now)
        let macroCalories = result.macros.reduce(0) { $0 + $1.calories }

        XCTAssertTrue(result.macros.allSatisfy { $0.grams >= 0 })
        XCTAssertNotNil(result.macro(.protein))
        XCTAssertNotNil(result.macro(.carbohydrates))
        XCTAssertNotNil(result.macro(.fat))
        XCTAssertEqual(macroCalories, result.energy.targetCalories, accuracy: 12)
        XCTAssertEqual(result.guidelineVersion, "2026.07-v2")
        XCTAssertEqual(result.energy.metTableVersion, NutritionMETCompendium.version)
    }

    func testInvalidBodyFatFallsBackWithoutBlockingCalculation() throws {
        let validation = try NutritionInputValidator().validate(input(bodyFatPercentage: 75))

        XCTAssertNil(validation.input.bodyFatPercentage)
        XCTAssertFalse(validation.warnings.isEmpty)
    }

    func testFatLossBlockedWhenBMIBelowReferenceRange() {
        var calculationInput = input(goal: .fatLoss)
        calculationInput.weightKilograms = 50
        calculationInput.heightCentimeters = 180

        XCTAssertThrowsError(try NutritionInputValidator().validate(calculationInput)) { error in
            XCTAssertEqual(error as? NutritionInputValidationError, .bodyMassIndexTooLow)
        }
    }

    func testUnchangedInputsProduceSameRoundedTarget() throws {
        var calculationInput = input(goal: .maintenance)
        calculationInput.healthActivity = activitySummary(validEnergyDays: 21)
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let first = try NutritionalCalculationEngine().calculate(input: calculationInput, now: now)
        let second = try NutritionalCalculationEngine().calculate(input: calculationInput, now: now)
        XCTAssertEqual(first.energy.targetCalories, second.energy.targetCalories)
    }

    func testLargeTargetChangeRequiresConfirmation() throws {
        var calculationInput = input(goal: .maintenance)
        calculationInput.healthActivity = activitySummary(validEnergyDays: 21)
        let result = try NutritionalCalculationEngine().calculate(
            input: calculationInput,
            now: .now,
            previousTargetCalories: 1_500
        )
        XCTAssertTrue(result.energy.requiresUserConfirmation)
    }

    func testVersionFourInputDecodesWithoutWorkoutPlanFields() throws {
        let legacyJSON = """
        {
          "age": 30,
          "biologicalSex": "Male",
          "heightCentimeters": 180,
          "weightKilograms": 80,
          "goal": "maintenance",
          "pace": "standard",
          "trainingSessionsPerWeek": 4,
          "primaryTrainingType": "mixed",
          "dietaryPreference": "unrestricted",
          "exclusions": "",
          "lifeStage": "none",
          "medicalAcknowledgementAccepted": true
        }
        """
        let decoded = try JSONDecoder().decode(
            NutritionCalculationInput.self,
            from: Data(legacyJSON.utf8)
        )

        XCTAssertEqual(decoded.schemaVersion, 4)
        XCTAssertEqual(decoded.trainingSessionsPerWeek, 4)
        XCTAssertTrue(decoded.workoutPlan.sessions.isEmpty)
    }

    func testVersionFiveWorkoutPlanRoundTrip() throws {
        var plan = NutritionWorkoutPlan.empty
        plan.sessions = [
            NutritionWorkoutPlanEntry(workoutType: .gymStrength, daysPerWeek: 3, minutesPerSession: 60, intensity: .moderate),
            NutritionWorkoutPlanEntry(workoutType: .cycling, daysPerWeek: 2, minutesPerSession: 45, intensity: .light)
        ]
        var calculationInput = input()
        calculationInput.workoutPlan = plan
        let data = try JSONEncoder().encode(calculationInput)
        let decoded = try JSONDecoder().decode(NutritionCalculationInput.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 5)
        XCTAssertEqual(decoded.workoutPlan.sessions.count, 2)
    }

    func testLegacySnapshotDecodesWithDerivedMacroFallback() throws {
        let snapshot = PulsarNutritionTargetSnapshot(
            fuelRange: 2_000...2_200,
            proteinRange: 120...145,
            fiberTarget: 28,
            hydrationTargetMilliliters: 2_500,
            recoveryScore: 70,
            activityLoad: "Moderate",
            rationale: "Legacy"
        )
        let data = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "source")
        object.removeValue(forKey: "calculationID")
        object.removeValue(forKey: "carbohydratesTargetGrams")
        object.removeValue(forKey: "fatTargetGrams")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(PulsarNutritionTargetSnapshot.self, from: legacyData)

        XCTAssertNil(decoded.carbohydratesTargetGrams)
        XCTAssertNil(decoded.fatTargetGrams)
        XCTAssertEqual(decoded.source, .heuristic)
    }

    func testStateWithoutCalculationsDecodesAsVersionFiveCompatible() throws {
        let data = try JSONEncoder().encode(PulsarNutritionState.empty)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "savedNutritionalCalculations")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(PulsarNutritionState.self, from: legacyData)

        XCTAssertTrue(decoded.savedNutritionalCalculations.isEmpty)
        XCTAssertEqual(PulsarNutritionPersistedState.currentVersion, 5)
    }

    func testApplyingCalculatedTargetsImmediatelyUpdatesDashboardGoals() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let provider = OrionNutritionTestProvider(state: .empty)
        let store = PulsarNutritionStore(provider: provider, nowProvider: { now })
        var calculationInput = input(goal: .maintenance)
        calculationInput.healthActivity = activitySummary(validEnergyDays: 21)
        let result = try NutritionalCalculationEngine().calculate(input: calculationInput, now: now)
        let saved = SavedNutritionalCalculation(input: calculationInput, result: result, savedAt: now)

        store.applyCalculatedTargets(saved)

        XCTAssertEqual(store.dashboard.target.source, .orionCalculation)
        XCTAssertEqual(store.dashboard.target.calculationID, saved.id)
        XCTAssertEqual(store.dashboard.carbohydratesGoal, result.macro(.carbohydrates)?.grams)
        XCTAssertEqual(store.dashboard.fatGoal, result.macro(.fat)?.grams)
        XCTAssertEqual(store.latestNutritionalCalculation?.id, saved.id)
        XCTAssertEqual(provider.savedState?.savedNutritionalCalculations.first?.id, saved.id)
    }

    func testOrionConfigurationBuildsNutritionExplainEndpoint() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://www.aetherial.tech"))
        let configuration = OrionConfiguration(
            backendBaseURL: baseURL,
            nutritionExplainPath: "/api/orion/nutrition-explain"
        )

        XCTAssertEqual(
            configuration.nutritionExplainEndpoint?.absoluteString,
            "https://www.aetherial.tech/api/orion/nutrition-explain"
        )
    }

    func testReassessmentProposesConservativeAdjustment() {
        let proposal = NutritionReassessmentEngine().evaluate(
            goal: .fatLoss,
            currentTarget: 2_000,
            originalModeledTarget: 2_200,
            cumulativeAdjustment: 0,
            weightTrendKilogramsPerWeek: -0.1,
            expectedWeeklyChangeKilograms: -0.4,
            adherenceConfirmed: true,
            safetyBlocked: false
        )

        XCTAssertEqual(proposal.adjustmentCalories, -100)
        XCTAssertTrue(proposal.requiresConfirmation)
    }

    private func input(
        bodyFatPercentage: Double? = nil,
        goal: NutritionCalculationGoal = .maintenance
    ) -> NutritionCalculationInput {
        var plan = NutritionWorkoutPlan.empty
        plan.sessions = [
            NutritionWorkoutPlanEntry(workoutType: .mixedOther, daysPerWeek: 4, minutesPerSession: 45, intensity: .moderate)
        ]
        return NutritionCalculationInput(
            age: 30,
            biologicalSex: .male,
            heightCentimeters: 180,
            weightKilograms: 80,
            bodyFatPercentage: bodyFatPercentage,
            goal: goal,
            pace: .standard,
            workoutPlan: plan,
            dietaryPreference: .unrestricted,
            exclusions: "",
            lifeStage: .none,
            medicalAcknowledgementAccepted: true
        )
    }

    private func activitySummary(
        validEnergyDays: Int,
        robustMedian: Double? = nil,
        observedWeeklyWorkoutEnergy: Double = 2_000
    ) -> HealthActivitySummary {
        HealthActivitySummary(
            startDate: .now.addingTimeInterval(-28 * 86_400),
            endDate: .now,
            requestedDayCount: 28,
            observedDayCount: validEnergyDays,
            validEnergyDayCount: validEnergyDays,
            basalEnergyCoverageDays: validEnergyDays,
            activeEnergyCoverageDays: validEnergyDays,
            stepCoverageDays: validEnergyDays,
            workoutCoverageDays: 8,
            averageSteps: 8_000,
            averageActiveEnergyKilocalories: 700,
            averageBasalEnergyKilocalories: 1_800,
            averageExerciseMinutes: 45,
            averageDistanceMeters: 6_000,
            workoutCount: 12,
            workoutMinutes: 540,
            workoutEnergyKilocalories: observedWeeklyWorkoutEnergy * 4,
            weeklyWorkoutMinutes: 540 / 4,
            weeklyObservedWorkoutEnergyKilocalories: observedWeeklyWorkoutEnergy,
            robustMedianDailyEnergyKilocalories: robustMedian ?? 2_500,
            observedWorkoutAggregates: [],
            workoutHeartRateCoverageFraction: 0.5,
            confidence: validEnergyDays >= 21 ? .high : .moderate,
            flags: [],
            anomalyCodes: []
        )
    }
}

@MainActor
private final class OrionNutritionTestProvider: PulsarNutritionProviding {
    private var state: PulsarNutritionState
    var savedState: PulsarNutritionState?

    init(state: PulsarNutritionState) {
        self.state = state
    }

    func loadState() -> PulsarNutritionState { state }

    func saveState(_ state: PulsarNutritionState) throws {
        self.state = state
        savedState = state
    }

    func recoveryContext(for date: Date) -> PulsarNutritionRecoveryContext {
        _ = date
        return .mock
    }

    func searchableFoods() -> [PulsarFoodItem] { [] }
}
