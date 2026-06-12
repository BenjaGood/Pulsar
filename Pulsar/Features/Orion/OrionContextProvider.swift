//
//  OrionContextProvider.swift
//  Pulsar
//

import Foundation

@MainActor
protocol OrionContextProviding {
    func makeContext(for question: String) async -> OrionUserContext
}

struct OrionUserContext: Codable, Equatable, Sendable {
    var generatedAt: Date
    var questionFocus: [String]
    var todayWorkoutSummary: OrionWorkoutDayContext
    var recentWorkouts: [OrionWorkoutSummary]
    var nutritionSummary: OrionNutritionSummary
    var recoverySummary: OrionRecoveryContext
    var sleepSummary: OrionSleepContext
    var userGoals: OrionUserGoals
    var notes: [String]
}

struct OrionWorkoutDayContext: Codable, Equatable, Sendable {
    var date: Date?
    var strainScore: Int?
    var steps: Int?
    var stepGoal: Int?
    var activeEnergyKilocalories: Int?
    var exerciseMinutes: Int?
    var workoutMinutes: Int?
    var workoutCount: Int
    var summary: String
}

struct OrionWorkoutSummary: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var startDate: Date
    var durationMinutes: Int
    var activeEnergyKilocalories: Int?
    var averageHeartRate: Int?
    var sourceName: String?
}

struct OrionNutritionSummary: Codable, Equatable, Sendable {
    var date: Date?
    var calories: Int?
    var calorieGoal: Int?
    var proteinGrams: Int?
    var proteinGoalGrams: Int?
    var carbohydratesGrams: Int?
    var fatGrams: Int?
    var fiberGrams: Int?
    var hydrationMilliliters: Int?
    var hydrationGoalMilliliters: Int?
    var insightCount: Int
    var summary: String
}

struct OrionRecoveryContext: Codable, Equatable, Sendable {
    var date: Date?
    var score: Int?
    var status: String
    var confidence: String
    var hrvMilliseconds: Int?
    var restingHeartRateBPM: Int?
    var respiratoryRate: Double?
    var explanation: String
}

struct OrionSleepContext: Codable, Equatable, Sendable {
    var wakeUpDate: Date?
    var score: Int?
    var confidence: String
    var totalSleepMinutes: Int?
    var sleepEfficiencyPercent: Int?
    var awakenings: Int?
    var sleepStart: Date?
    var wakeTime: Date?
    var summary: String
}

struct OrionUserGoals: Codable, Equatable, Sendable {
    var trainingLevel: String
    var preferredUnits: String
    var sleepGoalMinutes: Int
    var sleepGoalDays: String
    var preferredDataSource: String
    var primarySleepSource: String
    var nutritionCalorieRange: String?
    var nutritionProteinRange: String?
}

@MainActor
final class OrionContextProvider: OrionContextProviding {
    private let homeViewModel: HomeViewModel?
    private let nutritionStore: PulsarNutritionStore?
    private let calendar: Calendar
    private let nowProvider: () -> Date

    init(
        homeViewModel: HomeViewModel? = nil,
        nutritionStore: PulsarNutritionStore? = nil,
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.homeViewModel = homeViewModel
        self.nutritionStore = nutritionStore
        self.calendar = calendar
        self.nowProvider = nowProvider
    }

    func makeContext(for question: String) async -> OrionUserContext {
        let dashboard = homeViewModel?.dashboard
        let nutritionDashboard = nutritionStore?.dashboard
        let profile = homeViewModel?.profileStore.profile ?? dashboard?.profile ?? .empty

        return OrionUserContext(
            generatedAt: nowProvider(),
            questionFocus: focusTags(for: question),
            todayWorkoutSummary: workoutDayContext(from: dashboard),
            recentWorkouts: recentWorkouts(from: dashboard),
            nutritionSummary: nutritionSummary(from: nutritionDashboard),
            recoverySummary: recoveryContext(from: dashboard),
            sleepSummary: sleepContext(from: dashboard),
            userGoals: userGoals(from: profile, nutritionDashboard: nutritionDashboard),
            notes: [
                "Context is summarized from Pulsar app state; raw HealthKit samples and full local databases are not included.",
                "Orion is informational and should not provide medical diagnosis."
            ]
        )
    }

    private func focusTags(for question: String) -> [String] {
        let normalized = question.lowercased()
        let tags: [(String, [String])] = [
            ("workouts", ["workout", "run", "gym", "training", "strain", "steps"]),
            ("recovery", ["recovery", "readiness", "hrv", "resting heart", "rest"]),
            ("nutrition", ["nutrition", "food", "protein", "calorie", "hydration", "meal"]),
            ("sleep", ["sleep", "bed", "wake", "tired", "nap"]),
            ("goals", ["goal", "plan", "target", "improve"])
        ]
        let matches = tags.compactMap { tag, words in
            words.contains { normalized.contains($0) } ? tag : nil
        }
        return matches.isEmpty ? ["general"] : matches
    }

    private func workoutDayContext(from dashboard: HomeDashboard?) -> OrionWorkoutDayContext {
        guard let strain = dashboard?.strain else {
            return OrionWorkoutDayContext(
                date: nil,
                strainScore: nil,
                steps: nil,
                stepGoal: nil,
                activeEnergyKilocalories: nil,
                exerciseMinutes: nil,
                workoutMinutes: nil,
                workoutCount: 0,
                summary: "No workout or activity summary is loaded yet."
            )
        }

        let activeEnergy = strain.activeEnergyKilocalories.map { Int($0.rounded()) }
        let exerciseMinutes = Int(strain.exerciseMinutes.rounded())
        let workoutMinutes = Int(strain.workoutMinutes.rounded())

        return OrionWorkoutDayContext(
            date: strain.date,
            strainScore: strain.confidence == .missing ? nil : strain.score,
            steps: strain.steps > 0 ? strain.steps : nil,
            stepGoal: strain.stepGoal > 0 ? strain.stepGoal : nil,
            activeEnergyKilocalories: activeEnergy,
            exerciseMinutes: exerciseMinutes > 0 ? exerciseMinutes : nil,
            workoutMinutes: workoutMinutes > 0 ? workoutMinutes : nil,
            workoutCount: strain.workouts.count,
            summary: workoutSummaryText(strain: strain)
        )
    }

    private func recentWorkouts(from dashboard: HomeDashboard?) -> [OrionWorkoutSummary] {
        guard let workouts = dashboard?.strain.workouts else { return [] }
        return workouts
            .sorted { $0.startDate > $1.startDate }
            .prefix(4)
            .map { workout in
                OrionWorkoutSummary(
                    id: workout.id,
                    title: workout.workoutType,
                    startDate: workout.startDate,
                    durationMinutes: Int(workout.durationMinutes.rounded()),
                    activeEnergyKilocalories: workout.activeEnergyKilocalories.map { Int($0.rounded()) },
                    averageHeartRate: workout.averageHeartRate.map { Int($0.rounded()) },
                    sourceName: workout.sourceName
                )
            }
    }

    private func nutritionSummary(from dashboard: PulsarNutritionDashboard?) -> OrionNutritionSummary {
        guard let dashboard else {
            return OrionNutritionSummary(
                date: nil,
                calories: nil,
                calorieGoal: nil,
                proteinGrams: nil,
                proteinGoalGrams: nil,
                carbohydratesGrams: nil,
                fatGrams: nil,
                fiberGrams: nil,
                hydrationMilliliters: nil,
                hydrationGoalMilliliters: nil,
                insightCount: 0,
                summary: "No nutrition dashboard is loaded yet."
            )
        }

        let totals = dashboard.totals
        return OrionNutritionSummary(
            date: dashboard.date,
            calories: Int(totals.calories.rounded()),
            calorieGoal: Int(dashboard.calorieGoal.rounded()),
            proteinGrams: Int(totals.protein.rounded()),
            proteinGoalGrams: Int(dashboard.proteinGoal.rounded()),
            carbohydratesGrams: Int(totals.carbohydrates.rounded()),
            fatGrams: Int(totals.fat.rounded()),
            fiberGrams: Int(totals.fiber.rounded()),
            hydrationMilliliters: Int(dashboard.hydrationTotal.rounded()),
            hydrationGoalMilliliters: Int(dashboard.target.hydrationTargetMilliliters.rounded()),
            insightCount: dashboard.insights.count,
            summary: "Nutrition is summarized from today's entries and targets only."
        )
    }

    private func recoveryContext(from dashboard: HomeDashboard?) -> OrionRecoveryContext {
        guard let recovery = dashboard?.recovery else {
            return OrionRecoveryContext(
                date: nil,
                score: nil,
                status: "Not enough data",
                confidence: ConfidenceGrade.missing.rawValue,
                hrvMilliseconds: nil,
                restingHeartRateBPM: nil,
                respiratoryRate: nil,
                explanation: "No recovery summary is loaded yet."
            )
        }

        return OrionRecoveryContext(
            date: recovery.date,
            score: recovery.confidence == .missing ? nil : recovery.score,
            status: recovery.status.label,
            confidence: recovery.confidence.rawValue,
            hrvMilliseconds: recovery.hrvSDNN.map { Int($0.rounded()) },
            restingHeartRateBPM: recovery.restingHeartRate.map { Int($0.rounded()) },
            respiratoryRate: recovery.respiratoryRate.map { ($0 * 10).rounded() / 10 },
            explanation: recovery.explanation
        )
    }

    private func sleepContext(from dashboard: HomeDashboard?) -> OrionSleepContext {
        guard let sleep = dashboard?.sleep else {
            return OrionSleepContext(
                wakeUpDate: nil,
                score: nil,
                confidence: ConfidenceGrade.missing.rawValue,
                totalSleepMinutes: nil,
                sleepEfficiencyPercent: nil,
                awakenings: nil,
                sleepStart: nil,
                wakeTime: nil,
                summary: "No sleep summary is loaded yet."
            )
        }

        let totalMinutes = Int(sleep.totalSleepMinutes.rounded())
        let efficiency = Int((sleep.sleepEfficiency * 100).rounded())
        return OrionSleepContext(
            wakeUpDate: sleep.wakeUpDate,
            score: sleep.confidence == .missing ? nil : sleep.score,
            confidence: sleep.confidence.rawValue,
            totalSleepMinutes: totalMinutes > 0 ? totalMinutes : nil,
            sleepEfficiencyPercent: efficiency > 0 ? efficiency : nil,
            awakenings: sleep.analyzedSampleCount > 0 ? sleep.awakenings : nil,
            sleepStart: sleep.sleepStart,
            wakeTime: sleep.wakeTime,
            summary: sleep.confidenceExplanation
        )
    }

    private func userGoals(
        from profile: UserProfile,
        nutritionDashboard: PulsarNutritionDashboard?
    ) -> OrionUserGoals {
        OrionUserGoals(
            trainingLevel: profile.trainingLevel.rawValue,
            preferredUnits: profile.preferredUnits.rawValue,
            sleepGoalMinutes: profile.sleepSchedule.targetSleepDurationMinutes,
            sleepGoalDays: profile.sleepGoalDays.rawValue,
            preferredDataSource: profile.preferredDataSource.rawValue,
            primarySleepSource: profile.primarySleepSource.rawValue,
            nutritionCalorieRange: nutritionDashboard.map { rangeText($0.target.fuelRange, suffix: "kcal") },
            nutritionProteinRange: nutritionDashboard.map { rangeText($0.target.proteinRange, suffix: "g") }
        )
    }

    private func workoutSummaryText(strain: StrainSummary) -> String {
        if strain.confidence == .missing {
            return "Activity data is missing or permission-limited."
        }

        let workoutCount = strain.workouts.count
        let workoutText = workoutCount == 1 ? "1 workout" : "\(workoutCount) workouts"
        let stepsText = strain.steps > 0 ? "\(strain.steps) steps" : "no step total"
        return "Strain \(strain.score), \(stepsText), \(workoutText), \(Int(strain.workoutMinutes.rounded())) workout minutes."
    }

    private func rangeText(_ range: ClosedRange<Double>, suffix: String) -> String {
        "\(Int(range.lowerBound.rounded()))-\(Int(range.upperBound.rounded())) \(suffix)"
    }
}
