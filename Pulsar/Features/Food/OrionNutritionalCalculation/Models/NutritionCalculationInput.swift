//
//  NutritionCalculationInput.swift
//  Pulsar
//

import Foundation

enum NutritionCalculationGoal: String, CaseIterable, Identifiable, Codable, Hashable {
    case fatLoss
    case recomposition
    case muscleGain
    case maintenance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fatLoss: "Fat loss"
        case .recomposition: "Body recomposition"
        case .muscleGain: "Muscle gain"
        case .maintenance: "Maintain weight"
        }
    }

    var subtitle: String {
        switch self {
        case .fatLoss: "A conservative deficit that protects training and lean mass."
        case .recomposition: "Near-maintenance calories with a higher protein anchor."
        case .muscleGain: "A modest surplus designed to limit unnecessary fat gain."
        case .maintenance: "Fuel current activity and keep weight broadly stable."
        }
    }

    var symbolName: String {
        switch self {
        case .fatLoss: "arrow.down.right.circle.fill"
        case .recomposition: "arrow.triangle.2.circlepath.circle.fill"
        case .muscleGain: "arrow.up.right.circle.fill"
        case .maintenance: "equal.circle.fill"
        }
    }
}

enum NutritionGoalPace: String, CaseIterable, Identifiable, Codable, Hashable {
    case gentle
    case standard
    case ambitious

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gentle: "Gentle"
        case .standard: "Standard"
        case .ambitious: "Ambitious"
        }
    }

    var weeklyBodyWeightFraction: Double {
        switch self {
        case .gentle: 0.0025
        case .standard: 0.005
        case .ambitious: 0.0075
        }
    }
}

enum NutritionPrimaryTrainingType: String, CaseIterable, Identifiable, Codable, Hashable {
    case mixed
    case strength
    case endurance
    case teamSport
    case lowImpact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mixed: "Mixed"
        case .strength: "Strength"
        case .endurance: "Endurance"
        case .teamSport: "Team sport"
        case .lowImpact: "Low impact"
        }
    }
}

enum NutritionDietaryPreference: String, CaseIterable, Identifiable, Codable, Hashable {
    case unrestricted
    case vegetarian
    case vegan
    case pescatarian

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unrestricted: "No preference"
        case .vegetarian: "Vegetarian"
        case .vegan: "Vegan"
        case .pescatarian: "Pescatarian"
        }
    }
}

enum NutritionLifeStage: String, CaseIterable, Identifiable, Codable, Hashable {
    case none
    case pregnant
    case breastfeeding

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .pregnant: "Pregnant"
        case .breastfeeding: "Breastfeeding"
        }
    }
}

struct NutritionCalculationInput: Codable, Equatable {
    static let schemaVersion = 5

    var schemaVersion: Int
    var age: Int
    var biologicalSex: BiologicalSex
    var heightCentimeters: Double
    var weightKilograms: Double
    var bodyFatPercentage: Double?
    var goal: NutritionCalculationGoal
    var pace: NutritionGoalPace
    var targetWeightKilograms: Double?
    var targetDate: Date?
    var targetDurationWeeks: Int?
    var workoutPlan: NutritionWorkoutPlan
    var dietaryPreference: NutritionDietaryPreference
    var exclusions: String
    var lifeStage: NutritionLifeStage
    var medicalAcknowledgementAccepted: Bool
    var healthActivity: HealthActivitySummary?
    var trainsRegularly: Bool

    // Legacy fields retained for decoding v4 calculations only.
    var trainingSessionsPerWeek: Int?
    var primaryTrainingType: NutritionPrimaryTrainingType?

    init(
        schemaVersion: Int = Self.schemaVersion,
        age: Int,
        biologicalSex: BiologicalSex,
        heightCentimeters: Double,
        weightKilograms: Double,
        bodyFatPercentage: Double? = nil,
        goal: NutritionCalculationGoal,
        pace: NutritionGoalPace,
        targetWeightKilograms: Double? = nil,
        targetDate: Date? = nil,
        targetDurationWeeks: Int? = nil,
        workoutPlan: NutritionWorkoutPlan = .empty,
        dietaryPreference: NutritionDietaryPreference,
        exclusions: String,
        lifeStage: NutritionLifeStage,
        medicalAcknowledgementAccepted: Bool,
        healthActivity: HealthActivitySummary? = nil,
        trainsRegularly: Bool = true,
        trainingSessionsPerWeek: Int? = nil,
        primaryTrainingType: NutritionPrimaryTrainingType? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.age = age
        self.biologicalSex = biologicalSex
        self.heightCentimeters = heightCentimeters
        self.weightKilograms = weightKilograms
        self.bodyFatPercentage = bodyFatPercentage
        self.goal = goal
        self.pace = pace
        self.targetWeightKilograms = targetWeightKilograms
        self.targetDate = targetDate
        self.targetDurationWeeks = targetDurationWeeks
        self.workoutPlan = workoutPlan
        self.dietaryPreference = dietaryPreference
        self.exclusions = exclusions
        self.lifeStage = lifeStage
        self.medicalAcknowledgementAccepted = medicalAcknowledgementAccepted
        self.healthActivity = healthActivity
        self.trainsRegularly = trainsRegularly
        self.trainingSessionsPerWeek = trainingSessionsPerWeek
        self.primaryTrainingType = primaryTrainingType
    }

    static func prefilled(
        from profile: UserProfile,
        latestBodyCheckIn: PulsarBodyCheckIn?,
        date: Date = .now,
        calendar: Calendar = .current
    ) -> NutritionCalculationInput {
        let sessions = trainingSessions(for: profile.trainingLevel)
        var plan = NutritionWorkoutPlan.empty
        if sessions > 0, let entry = NutritionWorkoutPlanMigration.legacyEntry(
            sessionsPerWeek: sessions,
            trainingType: .mixed
        ) {
            plan.sessions = [entry]
        }
        return NutritionCalculationInput(
            age: profile.age(on: date, calendar: calendar) ?? 30,
            biologicalSex: profile.resolvedBiologicalSex,
            heightCentimeters: profile.resolvedHeightCentimeters ?? 170,
            weightKilograms: latestBodyCheckIn?.weightKilograms ?? profile.resolvedWeightKilograms ?? 70,
            bodyFatPercentage: latestBodyCheckIn?.bodyFatPercentage,
            goal: .maintenance,
            pace: .standard,
            workoutPlan: plan,
            dietaryPreference: .unrestricted,
            exclusions: "",
            lifeStage: .none,
            medicalAcknowledgementAccepted: false,
            trainsRegularly: sessions > 0
        )
    }

    mutating func migrateLegacyWorkoutFieldsIfNeeded() {
        guard workoutPlan.sessions.isEmpty,
              let sessions = trainingSessionsPerWeek,
              sessions > 0,
              let trainingType = primaryTrainingType,
              let entry = NutritionWorkoutPlanMigration.legacyEntry(
                sessionsPerWeek: sessions,
                trainingType: trainingType
              ) else { return }
        workoutPlan.sessions = [entry]
    }

    private static func trainingSessions(for level: TrainingLevel) -> Int {
        switch level {
        case .beginner: 2
        case .intermediate: 4
        case .advanced: 5
        case .athlete: 6
        }
    }
}

extension NutritionCalculationInput {
    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case age
        case biologicalSex
        case heightCentimeters
        case weightKilograms
        case bodyFatPercentage
        case goal
        case pace
        case targetWeightKilograms
        case targetDate
        case targetDurationWeeks
        case workoutPlan
        case dietaryPreference
        case exclusions
        case lifeStage
        case medicalAcknowledgementAccepted
        case healthActivity
        case trainsRegularly
        case trainingSessionsPerWeek
        case primaryTrainingType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 4
        age = try container.decode(Int.self, forKey: .age)
        biologicalSex = try container.decode(BiologicalSex.self, forKey: .biologicalSex)
        heightCentimeters = try container.decode(Double.self, forKey: .heightCentimeters)
        weightKilograms = try container.decode(Double.self, forKey: .weightKilograms)
        bodyFatPercentage = try container.decodeIfPresent(Double.self, forKey: .bodyFatPercentage)
        goal = try container.decode(NutritionCalculationGoal.self, forKey: .goal)
        pace = try container.decode(NutritionGoalPace.self, forKey: .pace)
        targetWeightKilograms = try container.decodeIfPresent(Double.self, forKey: .targetWeightKilograms)
        targetDate = try container.decodeIfPresent(Date.self, forKey: .targetDate)
        targetDurationWeeks = try container.decodeIfPresent(Int.self, forKey: .targetDurationWeeks)
        workoutPlan = try container.decodeIfPresent(NutritionWorkoutPlan.self, forKey: .workoutPlan) ?? .empty
        dietaryPreference = try container.decode(NutritionDietaryPreference.self, forKey: .dietaryPreference)
        exclusions = try container.decode(String.self, forKey: .exclusions)
        lifeStage = try container.decode(NutritionLifeStage.self, forKey: .lifeStage)
        medicalAcknowledgementAccepted = try container.decode(Bool.self, forKey: .medicalAcknowledgementAccepted)
        healthActivity = try container.decodeIfPresent(HealthActivitySummary.self, forKey: .healthActivity)
        trainsRegularly = try container.decodeIfPresent(Bool.self, forKey: .trainsRegularly) ?? true
        trainingSessionsPerWeek = try container.decodeIfPresent(Int.self, forKey: .trainingSessionsPerWeek)
        primaryTrainingType = try container.decodeIfPresent(NutritionPrimaryTrainingType.self, forKey: .primaryTrainingType)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(age, forKey: .age)
        try container.encode(biologicalSex, forKey: .biologicalSex)
        try container.encode(heightCentimeters, forKey: .heightCentimeters)
        try container.encode(weightKilograms, forKey: .weightKilograms)
        try container.encodeIfPresent(bodyFatPercentage, forKey: .bodyFatPercentage)
        try container.encode(goal, forKey: .goal)
        try container.encode(pace, forKey: .pace)
        try container.encodeIfPresent(targetWeightKilograms, forKey: .targetWeightKilograms)
        try container.encodeIfPresent(targetDate, forKey: .targetDate)
        try container.encodeIfPresent(targetDurationWeeks, forKey: .targetDurationWeeks)
        try container.encode(workoutPlan, forKey: .workoutPlan)
        try container.encode(dietaryPreference, forKey: .dietaryPreference)
        try container.encode(exclusions, forKey: .exclusions)
        try container.encode(lifeStage, forKey: .lifeStage)
        try container.encode(medicalAcknowledgementAccepted, forKey: .medicalAcknowledgementAccepted)
        try container.encodeIfPresent(healthActivity, forKey: .healthActivity)
        try container.encode(trainsRegularly, forKey: .trainsRegularly)
    }
}
