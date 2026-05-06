//
//  HomeModels.swift
//  Pulsar
//

import Foundation

enum ConfidenceGrade: String, CaseIterable, Identifiable, Codable, Equatable {
    case high = "High"
    case moderate = "Moderate"
    case low = "Low"
    case missing = "Missing"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .high: "High confidence"
        case .moderate: "Moderate confidence"
        case .low: "Low confidence"
        case .missing: "Missing data"
        }
    }
}

enum BiologicalSex: String, CaseIterable, Identifiable, Codable {
    case notSet = "Not set"
    case female = "Female"
    case male = "Male"
    case other = "Other"

    var id: String { rawValue }
}

enum UnitPreference: String, CaseIterable, Identifiable, Codable {
    case automatic = "Automatic"
    case metric = "Metric"
    case imperial = "Imperial"

    var id: String { rawValue }
}

enum ProfileValueSource: String, CaseIterable, Identifiable, Codable {
    case manual = "Manual"
    case healthKit = "HealthKit"

    var id: String { rawValue }
}

enum TrainingLevel: String, CaseIterable, Identifiable, Codable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
    case athlete = "Athlete"

    var id: String { rawValue }
}

enum HeartRateZoneMethod: String, CaseIterable, Identifiable, Codable {
    case automatic = "Auto"
    case percentMaxHeartRate = "% Max HR"
    case heartRateReserve = "HR Reserve"
    case manualZones = "Manual Zones"

    var id: String { rawValue }
}

enum SleepGoalDays: String, CaseIterable, Identifiable, Codable {
    case weekdays = "Weekdays"
    case everyDay = "Every day"
    case custom = "Custom"

    var id: String { rawValue }
}

enum PreferredDataSource: String, CaseIterable, Identifiable, Codable {
    case automatic = "Auto"
    case appleWatch = "Apple Watch"
    case healthKit = "HealthKit"
    case garmin = "Garmin"
    case oura = "Oura"
    case other = "Other"

    var id: String { rawValue }
}

enum PrimarySleepSource: String, CaseIterable, Identifiable, Codable {
    case automatic = "Auto"
    case appleWatch = "Apple Watch"
    case oura = "Oura"
    case garmin = "Garmin"
    case otherHealthKit = "Other HealthKit Source"

    var id: String { rawValue }
}

struct SleepSchedule: Codable, Equatable {
    var targetBedtimeHour: Int
    var targetBedtimeMinute: Int
    var targetWakeHour: Int
    var targetWakeMinute: Int
    var targetSleepHours: Double

    static let standard = SleepSchedule(
        targetBedtimeHour: 22,
        targetBedtimeMinute: 30,
        targetWakeHour: 6,
        targetWakeMinute: 30,
        targetSleepHours: 8
    )
}

struct UserProfile: Codable, Equatable {
    var name: String
    var photoData: Data?
    var heightCentimeters: Double?
    var weightKilograms: Double?
    var dateOfBirth: Date?
    var biologicalSex: BiologicalSex
    var preferredUnits: UnitPreference
    var manualMaxHeartRate: Double?
    var restingHeartRateBaselineBPM: Double?
    var hrvBaselineMilliseconds: Double?
    var trainingLevel: TrainingLevel
    var heartRateZoneMethod: HeartRateZoneMethod
    var bodyMassSource: ProfileValueSource
    var heightSource: ProfileValueSource
    var sleepSchedule: SleepSchedule
    var sleepGoalDays: SleepGoalDays
    var preferredDataSource: PreferredDataSource
    var primarySleepSource: PrimarySleepSource
    var lastUpdated: Date?
    var healthKitHeightCentimeters: Double?
    var healthKitWeightKilograms: Double?
    var healthKitDateOfBirth: Date?
    var healthKitBiologicalSex: BiologicalSex?

    static let empty = UserProfile(
        name: "",
        photoData: nil,
        heightCentimeters: nil,
        weightKilograms: nil,
        dateOfBirth: nil,
        biologicalSex: .notSet,
        preferredUnits: .metric,
        manualMaxHeartRate: nil,
        restingHeartRateBaselineBPM: nil,
        hrvBaselineMilliseconds: nil,
        trainingLevel: .intermediate,
        heartRateZoneMethod: .automatic,
        bodyMassSource: .manual,
        heightSource: .manual,
        sleepSchedule: .standard,
        sleepGoalDays: .everyDay,
        preferredDataSource: .automatic,
        primarySleepSource: .automatic,
        lastUpdated: nil,
        healthKitHeightCentimeters: nil,
        healthKitWeightKilograms: nil,
        healthKitDateOfBirth: nil,
        healthKitBiologicalSex: nil
    )

    init(
        name: String,
        photoData: Data?,
        heightCentimeters: Double?,
        weightKilograms: Double?,
        dateOfBirth: Date?,
        biologicalSex: BiologicalSex,
        preferredUnits: UnitPreference,
        manualMaxHeartRate: Double?,
        restingHeartRateBaselineBPM: Double? = nil,
        hrvBaselineMilliseconds: Double? = nil,
        trainingLevel: TrainingLevel = .intermediate,
        heartRateZoneMethod: HeartRateZoneMethod = .automatic,
        bodyMassSource: ProfileValueSource = .manual,
        heightSource: ProfileValueSource = .manual,
        sleepSchedule: SleepSchedule,
        sleepGoalDays: SleepGoalDays = .everyDay,
        preferredDataSource: PreferredDataSource = .automatic,
        primarySleepSource: PrimarySleepSource = .automatic,
        lastUpdated: Date? = nil,
        healthKitHeightCentimeters: Double?,
        healthKitWeightKilograms: Double?,
        healthKitDateOfBirth: Date?,
        healthKitBiologicalSex: BiologicalSex?
    ) {
        self.name = name
        self.photoData = photoData
        self.heightCentimeters = heightCentimeters
        self.weightKilograms = weightKilograms
        self.dateOfBirth = dateOfBirth
        self.biologicalSex = biologicalSex
        self.preferredUnits = preferredUnits == .automatic ? .metric : preferredUnits
        self.manualMaxHeartRate = manualMaxHeartRate
        self.restingHeartRateBaselineBPM = restingHeartRateBaselineBPM
        self.hrvBaselineMilliseconds = hrvBaselineMilliseconds
        self.trainingLevel = trainingLevel
        self.heartRateZoneMethod = heartRateZoneMethod
        self.bodyMassSource = bodyMassSource
        self.heightSource = heightSource
        self.sleepSchedule = sleepSchedule
        self.sleepGoalDays = sleepGoalDays
        self.preferredDataSource = preferredDataSource
        self.primarySleepSource = primarySleepSource
        self.lastUpdated = lastUpdated
        self.healthKitHeightCentimeters = healthKitHeightCentimeters
        self.healthKitWeightKilograms = healthKitWeightKilograms
        self.healthKitDateOfBirth = healthKitDateOfBirth
        self.healthKitBiologicalSex = healthKitBiologicalSex
    }

    private enum CodingKeys: String, CodingKey {
        case name, photoData, heightCentimeters, weightKilograms, dateOfBirth, biologicalSex, preferredUnits, manualMaxHeartRate
        case restingHeartRateBaselineBPM, hrvBaselineMilliseconds, trainingLevel, heartRateZoneMethod, bodyMassSource, heightSource
        case sleepSchedule, sleepGoalDays, preferredDataSource, primarySleepSource, lastUpdated
        case healthKitHeightCentimeters, healthKitWeightKilograms, healthKitDateOfBirth, healthKitBiologicalSex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.photoData = try container.decodeIfPresent(Data.self, forKey: .photoData)
        self.heightCentimeters = try container.decodeIfPresent(Double.self, forKey: .heightCentimeters)
        self.weightKilograms = try container.decodeIfPresent(Double.self, forKey: .weightKilograms)
        self.dateOfBirth = try container.decodeIfPresent(Date.self, forKey: .dateOfBirth)
        self.biologicalSex = try container.decodeIfPresent(BiologicalSex.self, forKey: .biologicalSex) ?? .notSet
        let decodedUnits = try container.decodeIfPresent(UnitPreference.self, forKey: .preferredUnits) ?? .metric
        self.preferredUnits = decodedUnits == .automatic ? .metric : decodedUnits
        self.manualMaxHeartRate = try container.decodeIfPresent(Double.self, forKey: .manualMaxHeartRate)
        self.restingHeartRateBaselineBPM = try container.decodeIfPresent(Double.self, forKey: .restingHeartRateBaselineBPM)
        self.hrvBaselineMilliseconds = try container.decodeIfPresent(Double.self, forKey: .hrvBaselineMilliseconds)
        self.trainingLevel = try container.decodeIfPresent(TrainingLevel.self, forKey: .trainingLevel) ?? .intermediate
        self.heartRateZoneMethod = try container.decodeIfPresent(HeartRateZoneMethod.self, forKey: .heartRateZoneMethod) ?? .automatic
        self.bodyMassSource = try container.decodeIfPresent(ProfileValueSource.self, forKey: .bodyMassSource) ?? .manual
        self.heightSource = try container.decodeIfPresent(ProfileValueSource.self, forKey: .heightSource) ?? .manual
        self.sleepSchedule = try container.decodeIfPresent(SleepSchedule.self, forKey: .sleepSchedule) ?? .standard
        self.sleepGoalDays = try container.decodeIfPresent(SleepGoalDays.self, forKey: .sleepGoalDays) ?? .everyDay
        self.preferredDataSource = try container.decodeIfPresent(PreferredDataSource.self, forKey: .preferredDataSource) ?? .automatic
        self.primarySleepSource = try container.decodeIfPresent(PrimarySleepSource.self, forKey: .primarySleepSource) ?? .automatic
        self.lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated)
        self.healthKitHeightCentimeters = try container.decodeIfPresent(Double.self, forKey: .healthKitHeightCentimeters)
        self.healthKitWeightKilograms = try container.decodeIfPresent(Double.self, forKey: .healthKitWeightKilograms)
        self.healthKitDateOfBirth = try container.decodeIfPresent(Date.self, forKey: .healthKitDateOfBirth)
        self.healthKitBiologicalSex = try container.decodeIfPresent(BiologicalSex.self, forKey: .healthKitBiologicalSex)
    }

    var resolvedHeightCentimeters: Double? { heightCentimeters ?? healthKitHeightCentimeters }
    var resolvedWeightKilograms: Double? { weightKilograms ?? healthKitWeightKilograms }
    var resolvedDateOfBirth: Date? { dateOfBirth ?? healthKitDateOfBirth }
    var resolvedBiologicalSex: BiologicalSex { biologicalSex == .notSet ? (healthKitBiologicalSex ?? .notSet) : biologicalSex }

    func age(on date: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let resolvedDateOfBirth else { return nil }
        return calendar.dateComponents([.year], from: resolvedDateOfBirth, to: date).year
    }

    func resolvedMaxHeartRate(on date: Date = .now, calendar: Calendar = .current) -> MaxHeartRateResolution? {
        if let manualMaxHeartRate, manualMaxHeartRate > 0 {
            return MaxHeartRateResolution(value: manualMaxHeartRate, source: .manual)
        }
        guard let age = age(on: date, calendar: calendar), age > 0 else { return nil }
        return MaxHeartRateResolution(value: 208 - 0.7 * Double(age), source: .fallbackTanaka)
    }
}

struct MaxHeartRateResolution: Equatable {
    enum Source: Equatable {
        case manual
        case fallbackTanaka
    }

    var value: Double
    var source: Source
}

struct SourceProvenance: Identifiable, Hashable, Codable, Equatable {
    var id: String { [sourceBundleIdentifier, sourceName, productType, deviceName].compactMap { $0 }.joined(separator: "|") }
    var sourceName: String
    var sourceBundleIdentifier: String?
    var sourceVersion: String?
    var operatingSystemVersion: String?
    var productType: String?
    var deviceName: String?
    var deviceManufacturer: String?
    var deviceModel: String?

    static let sample = SourceProvenance(
        sourceName: "Sample Apple Watch",
        sourceBundleIdentifier: "com.apple.health",
        sourceVersion: "26.0",
        operatingSystemVersion: "26.0",
        productType: "Watch7,9",
        deviceName: "Apple Watch",
        deviceManufacturer: "Apple Inc.",
        deviceModel: "Apple Watch"
    )

    var displayName: String {
        if let deviceName, !deviceName.isEmpty { return deviceName }
        return sourceName
    }

    var isAppleWatchLike: Bool {
        let text = [sourceName, sourceBundleIdentifier, productType, deviceName, deviceManufacturer, deviceModel]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return text.contains("apple") && text.contains("watch")
    }
}

enum SleepStage: String, CaseIterable, Identifiable, Codable, Equatable {
    case awake = "Awake"
    case core = "Core"
    case deep = "Deep"
    case rem = "REM"
    case asleepUnspecified = "Asleep"
    case inBed = "In Bed"

    var id: String { rawValue }
    var isSleep: Bool { self == .core || self == .deep || self == .rem || self == .asleepUnspecified }
    var contributesToStageBreakdown: Bool { self == .awake || self == .core || self == .deep || self == .rem || self == .asleepUnspecified }
}

struct SleepSegment: Identifiable, Codable, Equatable {
    var id = UUID()
    var stage: SleepStage
    var start: Date
    var end: Date
    var provenance: SourceProvenance

    var durationMinutes: Double { max(0, end.timeIntervalSince(start) / 60) }
}

struct NightlySleepInput: Identifiable, Codable, Equatable {
    var id = UUID()
    var nightStart: Date
    var nightEnd: Date
    var segments: [SleepSegment]

    var sourceBadges: [SourceProvenance] {
        Array(Set(segments.map(\.provenance))).sorted { $0.displayName < $1.displayName }
    }
}

struct StageMetric: Identifiable, Codable, Equatable {
    var id: SleepStage { stage }
    var stage: SleepStage
    var minutes: Double
    var percentOfSleep: Double
}

struct SleepStageInterval: Identifiable, Codable, Equatable {
    var id: String { "\(stage.rawValue)-\(startDate.timeIntervalSinceReferenceDate)-\(endDate.timeIntervalSinceReferenceDate)" }
    var stage: SleepStage
    var startDate: Date
    var endDate: Date

    var duration: TimeInterval { max(0, endDate.timeIntervalSince(startDate)) }
    var durationMinutes: Double { duration / 60 }
}

struct SleepSummary: Codable, Equatable {
    var wakeUpDate: Date?
    var score: Int
    var confidence: ConfidenceGrade
    var confidenceExplanation: String
    var timeInBedMinutes: Double
    var totalSleepMinutes: Double
    var sleepEfficiency: Double
    var awakeMinutes: Double
    var wasoMinutes: Double
    var sleepConsistency: Double
    var sleepPerformance: Double
    var durationAdequacy: Double
    var regularity: Double
    var continuity: Double
    var stageBreakdown: [StageMetric]
    var intervals: [SleepStageInterval]
    var sleepStart: Date?
    var wakeTime: Date?
    var awakenings: Int
    var analyzedSampleCount: Int
    var queryStart: Date?
    var queryEnd: Date?
    var lastUpdated: Date?
    var sourceBadges: [SourceProvenance]
    var notes: [String]

    static let missing = SleepSummary(
        wakeUpDate: nil,
        score: 0,
        confidence: .missing,
        confidenceExplanation: "No sleep samples were available from HealthKit.",
        timeInBedMinutes: 0,
        totalSleepMinutes: 0,
        sleepEfficiency: 0,
        awakeMinutes: 0,
        wasoMinutes: 0,
        sleepConsistency: 0,
        sleepPerformance: 0,
        durationAdequacy: 0,
        regularity: 0,
        continuity: 0,
        stageBreakdown: [],
        intervals: [],
        sleepStart: nil,
        wakeTime: nil,
        awakenings: 0,
        analyzedSampleCount: 0,
        queryStart: nil,
        queryEnd: nil,
        lastUpdated: nil,
        sourceBadges: [],
        notes: ["Connect Apple Watch or allow a companion app such as Garmin or Oura to write sleep into Apple Health."]
    )

    static let permissionRequired = SleepSummary(
        wakeUpDate: nil,
        score: 0,
        confidence: .missing,
        confidenceExplanation: "Health permission required.",
        timeInBedMinutes: 0,
        totalSleepMinutes: 0,
        sleepEfficiency: 0,
        awakeMinutes: 0,
        wasoMinutes: 0,
        sleepConsistency: 0,
        sleepPerformance: 0,
        durationAdequacy: 0,
        regularity: 0,
        continuity: 0,
        stageBreakdown: [],
        intervals: [],
        sleepStart: nil,
        wakeTime: nil,
        awakenings: 0,
        analyzedSampleCount: 0,
        queryStart: nil,
        queryEnd: nil,
        lastUpdated: nil,
        sourceBadges: [],
        notes: ["Grant HealthKit sleep permission to show real Apple Health sleep data. Pulsar does not substitute demo sleep values at runtime."]
    )
}

struct DailyBiometrics: Codable, Equatable {
    var date: Date
    var hrvSDNNMilliseconds: Double?
    var restingHeartRateBPM: Double?
    var respiratoryRate: Double?
    var oxygenSaturation: Double? = nil
    var wristTemperatureDeviationCelsius: Double? = nil
    var sleepPerformance: Double?
    var priorDayStrain: Double?
    var provenance: [String: SourceProvenance]
}

enum RecoveryStatus: String, Codable, Equatable, CaseIterable {
    case excellent
    case balanced
    case moderate
    case low
    case needsAttention
    case unknown

    var label: String {
        switch self {
        case .excellent: "Ready to perform"
        case .balanced: "Balanced recovery"
        case .moderate: "Moderate recovery"
        case .low: "Recovery is lower today"
        case .needsAttention: "Build more baseline data"
        case .unknown: "Not enough data"
        }
    }
}

struct RecoveryTrendPoint: Identifiable, Codable, Equatable {
    var id: String { "\(date.timeIntervalSinceReferenceDate)" }
    var date: Date
    var recoveryScore: Double?
    var hrv: Double?
    var restingHeartRate: Double?
    var sleepDuration: TimeInterval?
    var strainScore: Double?
}

struct RecoveryComponent: Identifiable, Codable, Equatable {
    var id: String { title }
    var title: String
    var valueText: String
    var contribution: Double?
    var status: RecoveryStatus
    var detail: String?
}

struct RecoverySummary: Codable, Equatable {
    var date: Date?
    var score: Int
    var confidence: ConfidenceGrade
    var status: RecoveryStatus
    var hrvSDNN: Double?
    var hrvBaseline: Double?
    var restingHeartRate: Double?
    var restingHeartRateBaseline: Double?
    var sleepDuration: TimeInterval?
    var sleepEfficiency: Double?
    var deepSleep: TimeInterval?
    var remSleep: TimeInterval?
    var strainScore: Double?
    var respiratoryRate: Double?
    var oxygenSaturation: Double?
    var wristTemperatureDeviation: Double?
    var hrvReadiness: Double
    var restingHeartRateReadiness: Double
    var respiratoryStability: Double
    var sleepContribution: Double
    var strainPenalty: Double
    var components: [RecoveryComponent]
    var trend: [RecoveryTrendPoint]
    var analyzedSampleCount: Int
    var queryStart: Date?
    var queryEnd: Date?
    var lastUpdated: Date?
    var baselineWindowDays: Int
    var explanation: String
    var sourceBadges: [SourceProvenance]
    var notes: [String]

    static let missing = RecoverySummary(
        date: nil,
        score: 0,
        confidence: .missing,
        status: .unknown,
        hrvSDNN: nil,
        hrvBaseline: nil,
        restingHeartRate: nil,
        restingHeartRateBaseline: nil,
        sleepDuration: nil,
        sleepEfficiency: nil,
        deepSleep: nil,
        remSleep: nil,
        strainScore: nil,
        respiratoryRate: nil,
        oxygenSaturation: nil,
        wristTemperatureDeviation: nil,
        hrvReadiness: 0,
        restingHeartRateReadiness: 0,
        respiratoryStability: 0,
        sleepContribution: 0,
        strainPenalty: 0,
        components: [],
        trend: [],
        analyzedSampleCount: 0,
        queryStart: nil,
        queryEnd: nil,
        lastUpdated: nil,
        baselineWindowDays: 0,
        explanation: "Recovery needs HRV, resting heart rate, respiratory rate, and recent sleep history.",
        sourceBadges: [],
        notes: ["Pulsar uses baseline-relative readiness and does not diagnose illness or medical conditions."]
    )
}

struct HeartRateSample: Codable, Equatable {
    var start: Date
    var end: Date
    var bpm: Double
    var provenance: SourceProvenance
}

struct WorkoutLoadInput: Identifiable, Codable, Equatable {
    var id = UUID()
    var type: String
    var start: Date
    var end: Date
    var heartRateSamples: [HeartRateSample]
    var activeEnergyKilocalories: Double?
    var distanceMeters: Double?
    var provenance: SourceProvenance

    var durationMinutes: Double { max(0, end.timeIntervalSince(start) / 60) }
}

struct StrainWorkoutSummary: Identifiable, Codable, Equatable {
    var id = UUID()
    var workoutType: String
    var startDate: Date
    var endDate: Date
    var activeEnergyKilocalories: Double?
    var averageHeartRate: Double?
    var peakHeartRate: Double?
    var sourceName: String?

    var duration: TimeInterval { max(0, endDate.timeIntervalSince(startDate)) }
    var durationMinutes: Double { duration / 60 }
}

struct HeartRatePoint: Identifiable, Codable, Equatable {
    var id: String { "\(date.timeIntervalSinceReferenceDate)-\(bpm)-\(source ?? "")" }
    var date: Date
    var bpm: Double
    var source: String?
}

struct WorkoutTimelineBand: Identifiable, Codable, Equatable {
    var id: String { "\(workoutType)-\(startDate.timeIntervalSinceReferenceDate)-\(endDate.timeIntervalSinceReferenceDate)" }
    var workoutType: String
    var startDate: Date
    var endDate: Date
    var duration: TimeInterval
    var averageHeartRate: Double?
    var peakHeartRate: Double?
}

enum StrainIntensityZone: String, Codable, CaseIterable, Equatable {
    case rest
    case light
    case moderate
    case hard
    case peak

    var label: String {
        switch self {
        case .rest: "Rest"
        case .light: "Light"
        case .moderate: "Moderate"
        case .hard: "Hard"
        case .peak: "Peak"
        }
    }
}

struct StrainTimelineInterval: Identifiable, Codable, Equatable {
    var id: String { "\(intensity.rawValue)-\(startDate.timeIntervalSinceReferenceDate)-\(endDate.timeIntervalSinceReferenceDate)-\(source ?? "")" }
    var startDate: Date
    var endDate: Date
    var intensity: StrainIntensityZone
    var value: Double
    var source: String?
    var isWorkout: Bool

    var duration: TimeInterval { max(0, endDate.timeIntervalSince(startDate)) }
    var durationMinutes: Double { duration / 60 }
}

struct TimeInZone: Identifiable, Codable, Equatable {
    var id: Int { zone }
    var zone: Int
    var minutes: Double
}

struct WorkoutLedgerEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var start: Date
    var durationMinutes: Double
    var load: Double
    var timeInZones: [TimeInZone]
    var provenance: SourceProvenance
}

struct DailyActivityInput: Codable, Equatable {
    var date: Date
    var steps: Double
    var activeEnergyKilocalories: Double
    var basalEnergyKilocalories: Double
    var distanceMeters: Double
    var exerciseMinutes: Double
    var provenance: [SourceProvenance]
}

struct DailyStrainInput: Codable, Equatable {
    var date: Date
    var maxHeartRate: Double?
    var workouts: [WorkoutLoadInput]
    var activity: DailyActivityInput
    var recentRawLoads: [Double]
    var sevenDayRawLoad: Double
    var twentyEightDayRawLoad: Double
}

struct StrainSummary: Codable, Equatable {
    var date: Date?
    var score: Int
    var confidence: ConfidenceGrade
    var rawLoad: Double
    var workoutLoad: Double
    var movementLoad: Double
    var sevenDayLoad: Double
    var twentyEightDayAverageLoad: Double
    var sevenVsTwentyEightRatio: Double
    var steps: Int
    var stepGoal: Int
    var activeEnergyKilocalories: Double?
    var basalEnergyKilocalories: Double?
    var exerciseMinutes: Double
    var averageActiveHeartRate: Double?
    var peakHeartRate: Double?
    var restingHeartRate: Double?
    var hrvSDNNMilliseconds: Double?
    var workoutMinutes: Double
    var workouts: [StrainWorkoutSummary]
    var timeline: [StrainTimelineInterval]
    var heartRatePoints: [HeartRatePoint]
    var workoutBands: [WorkoutTimelineBand]
    var analyzedSampleCount: Int
    var queryStart: Date?
    var queryEnd: Date?
    var lastUpdated: Date?
    var timeInZones: [TimeInZone]
    var ledger: [WorkoutLedgerEntry]
    var sourceBadges: [SourceProvenance]
    var notes: [String]

    static let missing = StrainSummary(
        date: nil,
        score: 0,
        confidence: .missing,
        rawLoad: 0,
        workoutLoad: 0,
        movementLoad: 0,
        sevenDayLoad: 0,
        twentyEightDayAverageLoad: 0,
        sevenVsTwentyEightRatio: 0,
        steps: 0,
        stepGoal: 10_000,
        activeEnergyKilocalories: nil,
        basalEnergyKilocalories: nil,
        exerciseMinutes: 0,
        averageActiveHeartRate: nil,
        peakHeartRate: nil,
        restingHeartRate: nil,
        hrvSDNNMilliseconds: nil,
        workoutMinutes: 0,
        workouts: [],
        timeline: [],
        heartRatePoints: [],
        workoutBands: [],
        analyzedSampleCount: 0,
        queryStart: nil,
        queryEnd: nil,
        lastUpdated: nil,
        timeInZones: [],
        ledger: [],
        sourceBadges: [],
        notes: ["Strain prioritizes heart-rate-derived training load over calorie estimates."]
    )
}

struct HomeDashboard: Codable, Equatable {
    var profile: UserProfile
    var sleep: SleepSummary
    var recovery: RecoverySummary
    var strain: StrainSummary
    var generatedAt: Date
    var usingSampleData: Bool

    static let sample = HomeDashboard(
        profile: MockHealthData.profile,
        sleep: MockHealthData.sleepSummary,
        recovery: MockHealthData.recoverySummary,
        strain: MockHealthData.strainSummary,
        generatedAt: .now,
        usingSampleData: true
    )

    static let empty = HomeDashboard(
        profile: .empty,
        sleep: .missing,
        recovery: .missing,
        strain: .missing,
        generatedAt: .now,
        usingSampleData: false
    )
}

enum SourceResolver {
    nonisolated static func primarySleepSegments(from segments: [SleepSegment], nightStart: Date, nightEnd: Date) -> [SleepSegment] {
        guard !segments.isEmpty else { return [] }
        let grouped = Dictionary(grouping: segments, by: { $0.provenance })
        let best = grouped.max { lhs, rhs in
            scoreSleepSource(lhs.value, nightStart: nightStart, nightEnd: nightEnd, provenance: lhs.key) <
                scoreSleepSource(rhs.value, nightStart: nightStart, nightEnd: nightEnd, provenance: rhs.key)
        }
        return best?.value.sorted { $0.start < $1.start } ?? []
    }

    nonisolated private static func scoreSleepSource(_ segments: [SleepSegment], nightStart: Date, nightEnd: Date, provenance: SourceProvenance) -> Double {
        let windowMinutes = max(1, nightEnd.timeIntervalSince(nightStart) / 60)
        let coveredMinutes = segments.reduce(0) { $0 + $1.durationMinutes }
        let coverage = min(1, coveredMinutes / windowMinutes)
        let stagedMinutes = segments.filter { $0.stage == .core || $0.stage == .deep || $0.stage == .rem }.reduce(0) { $0 + $1.durationMinutes }
        let stageRichness = min(1, stagedMinutes / max(1, coveredMinutes))
        let watchBonus = provenance.isAppleWatchLike ? 0.05 : 0
        return coverage * 0.65 + stageRichness * 0.30 + watchBonus
    }

    nonisolated static func uniqueSourceBadges(_ provenances: [SourceProvenance]) -> [SourceProvenance] {
        Array(Set(provenances)).sorted { $0.displayName < $1.displayName }
    }
}

enum ScoreMath {
    static func clamp(_ value: Double, _ lower: Double = 0, _ upper: Double = 1) -> Double {
        min(upper, max(lower, value))
    }

    static func roundedScore(_ value: Double) -> Int {
        Int((clamp(value) * 100).rounded())
    }

    static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter { $0.isFinite }.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    static func medianAbsoluteDeviation(_ values: [Double], median: Double) -> Double? {
        self.median(values.map { abs($0 - median) })
    }

    static func robustZScore(value: Double, baseline: [Double], outlierLimit: Double = 3) -> Double? {
        guard let median = median(baseline), let mad = medianAbsoluteDeviation(baseline, median: median) else { return nil }
        let robustSigma = max(1, mad * 1.4826)
        return clamp((value - median) / robustSigma, -outlierLimit, outlierLimit)
    }
}
