//
//  HomeModels.swift
//  Pulsar
//

import Foundation

enum ConfidenceGrade: String, CaseIterable, Identifiable, Codable, Equatable, Hashable {
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
    var bedtimeMinutesFromMidnight: Int
    var wakeTimeMinutesFromMidnight: Int
    var alarmEnabled: Bool
    var alarmTimeMinutesFromMidnight: Int
    var alarmUsesWakeTime: Bool
    var alarmSoundName: String
    var alarmHapticsEnabled: Bool
    var snoozeEnabled: Bool
    var smartWakeEnabled: Bool
    var wakeWindowMinutes: Int?

    static let standard = SleepSchedule(
        bedtimeMinutesFromMidnight: 22 * 60 + 30,
        wakeTimeMinutesFromMidnight: 6 * 60 + 30,
        alarmEnabled: false,
        alarmTimeMinutesFromMidnight: 6 * 60 + 30,
        alarmUsesWakeTime: true,
        alarmSoundName: "Default",
        alarmHapticsEnabled: true,
        snoozeEnabled: true,
        smartWakeEnabled: false,
        wakeWindowMinutes: 30
    )

    init(
        bedtimeMinutesFromMidnight: Int,
        wakeTimeMinutesFromMidnight: Int,
        alarmEnabled: Bool = false,
        alarmTimeMinutesFromMidnight: Int? = nil,
        alarmUsesWakeTime: Bool = true,
        alarmSoundName: String = "Default",
        alarmHapticsEnabled: Bool = true,
        snoozeEnabled: Bool = true,
        smartWakeEnabled: Bool = false,
        wakeWindowMinutes: Int? = 30
    ) {
        let bedtime = Self.normalizedMinutes(bedtimeMinutesFromMidnight)
        let wake = Self.normalizedMinutes(wakeTimeMinutesFromMidnight)
        self.bedtimeMinutesFromMidnight = bedtime
        self.wakeTimeMinutesFromMidnight = wake
        self.alarmUsesWakeTime = alarmUsesWakeTime
        self.alarmEnabled = alarmEnabled
        self.alarmTimeMinutesFromMidnight = Self.normalizedMinutes(alarmTimeMinutesFromMidnight ?? wake)
        self.alarmSoundName = alarmSoundName
        self.alarmHapticsEnabled = alarmHapticsEnabled
        self.snoozeEnabled = snoozeEnabled
        self.smartWakeEnabled = smartWakeEnabled
        self.wakeWindowMinutes = wakeWindowMinutes
        if alarmUsesWakeTime {
            self.alarmTimeMinutesFromMidnight = wake
        }
    }

    init(
        targetBedtimeHour: Int,
        targetBedtimeMinute: Int,
        targetWakeHour: Int,
        targetWakeMinute: Int,
        targetSleepHours: Double? = nil,
        alarmEnabled: Bool = false,
        alarmTimeMinutesFromMidnight: Int? = nil,
        alarmUsesWakeTime: Bool = true,
        alarmSoundName: String = "Default",
        alarmHapticsEnabled: Bool = true,
        snoozeEnabled: Bool = true,
        smartWakeEnabled: Bool = false,
        wakeWindowMinutes: Int? = 30
    ) {
        self.init(
            bedtimeMinutesFromMidnight: targetBedtimeHour * 60 + targetBedtimeMinute,
            wakeTimeMinutesFromMidnight: targetWakeHour * 60 + targetWakeMinute,
            alarmEnabled: alarmEnabled,
            alarmTimeMinutesFromMidnight: alarmTimeMinutesFromMidnight,
            alarmUsesWakeTime: alarmUsesWakeTime,
            alarmSoundName: alarmSoundName,
            alarmHapticsEnabled: alarmHapticsEnabled,
            snoozeEnabled: snoozeEnabled,
            smartWakeEnabled: smartWakeEnabled,
            wakeWindowMinutes: wakeWindowMinutes
        )
    }

    var targetBedtimeHour: Int {
        get { bedtimeMinutesFromMidnight / 60 }
        set { bedtimeMinutesFromMidnight = Self.normalizedMinutes(newValue * 60 + targetBedtimeMinute) }
    }

    var targetBedtimeMinute: Int {
        get { bedtimeMinutesFromMidnight % 60 }
        set { bedtimeMinutesFromMidnight = Self.normalizedMinutes(targetBedtimeHour * 60 + newValue) }
    }

    var targetWakeHour: Int {
        get { wakeTimeMinutesFromMidnight / 60 }
        set { setWakeTimeMinutes(newValue * 60 + targetWakeMinute) }
    }

    var targetWakeMinute: Int {
        get { wakeTimeMinutesFromMidnight % 60 }
        set { setWakeTimeMinutes(targetWakeHour * 60 + newValue) }
    }

    var targetSleepDurationMinutes: Int {
        Self.durationMinutes(from: bedtimeMinutesFromMidnight, to: wakeTimeMinutesFromMidnight)
    }

    var targetSleepHours: Double {
        Double(targetSleepDurationMinutes) / 60
    }

    var resolvedAlarmTimeMinutesFromMidnight: Int {
        alarmUsesWakeTime ? wakeTimeMinutesFromMidnight : alarmTimeMinutesFromMidnight
    }

    mutating func setBedtimeMinutes(_ minutes: Int) {
        bedtimeMinutesFromMidnight = Self.normalizedMinutes(minutes)
    }

    mutating func setWakeTimeMinutes(_ minutes: Int) {
        wakeTimeMinutesFromMidnight = Self.normalizedMinutes(minutes)
        if alarmUsesWakeTime {
            alarmTimeMinutesFromMidnight = wakeTimeMinutesFromMidnight
        }
    }

    mutating func setAlarmTimeMinutes(_ minutes: Int) {
        alarmUsesWakeTime = false
        alarmTimeMinutesFromMidnight = Self.normalizedMinutes(minutes)
    }

    mutating func resetAlarmToWakeTime() {
        alarmUsesWakeTime = true
        alarmTimeMinutesFromMidnight = wakeTimeMinutesFromMidnight
    }

    mutating func setAlarmEnabled(_ enabled: Bool) {
        alarmEnabled = enabled
        if enabled, alarmUsesWakeTime {
            alarmTimeMinutesFromMidnight = wakeTimeMinutesFromMidnight
        }
    }

    static func durationMinutes(from startMinutes: Int, to endMinutes: Int) -> Int {
        let normalizedStart = normalizedMinutes(startMinutes)
        let normalizedEnd = normalizedMinutes(endMinutes)
        return normalizedEnd >= normalizedStart ? (normalizedEnd - normalizedStart) : (24 * 60 - normalizedStart + normalizedEnd)
    }

    private static func normalizedMinutes(_ value: Int) -> Int {
        let day = 24 * 60
        let remainder = value % day
        return remainder >= 0 ? remainder : remainder + day
    }

    private enum CodingKeys: String, CodingKey {
        case bedtimeMinutesFromMidnight
        case wakeTimeMinutesFromMidnight
        case alarmEnabled
        case alarmTimeMinutesFromMidnight
        case alarmUsesWakeTime
        case alarmSoundName
        case alarmHapticsEnabled
        case snoozeEnabled
        case smartWakeEnabled
        case wakeWindowMinutes
        case targetBedtimeHour
        case targetBedtimeMinute
        case targetWakeHour
        case targetWakeMinute
        case targetSleepHours
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let bedtimeMinutes = try container.decodeIfPresent(Int.self, forKey: .bedtimeMinutesFromMidnight)
        let wakeMinutes = try container.decodeIfPresent(Int.self, forKey: .wakeTimeMinutesFromMidnight)
        let legacyBedtimeHour = try container.decodeIfPresent(Int.self, forKey: .targetBedtimeHour)
        let legacyBedtimeMinute = try container.decodeIfPresent(Int.self, forKey: .targetBedtimeMinute)
        let legacyWakeHour = try container.decodeIfPresent(Int.self, forKey: .targetWakeHour)
        let legacyWakeMinute = try container.decodeIfPresent(Int.self, forKey: .targetWakeMinute)
        let alarmEnabled = try container.decodeIfPresent(Bool.self, forKey: .alarmEnabled) ?? false
        let alarmSoundName = try container.decodeIfPresent(String.self, forKey: .alarmSoundName) ?? Self.standard.alarmSoundName
        let alarmHapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .alarmHapticsEnabled) ?? Self.standard.alarmHapticsEnabled
        let snoozeEnabled = try container.decodeIfPresent(Bool.self, forKey: .snoozeEnabled) ?? Self.standard.snoozeEnabled
        let smartWakeEnabled = try container.decodeIfPresent(Bool.self, forKey: .smartWakeEnabled) ?? Self.standard.smartWakeEnabled
        let wakeWindowMinutes = try container.decodeIfPresent(Int.self, forKey: .wakeWindowMinutes) ?? Self.standard.wakeWindowMinutes

        let resolvedBedtime = bedtimeMinutes ?? (
            (legacyBedtimeHour ?? Self.standard.targetBedtimeHour) * 60 +
            (legacyBedtimeMinute ?? Self.standard.targetBedtimeMinute)
        )
        let resolvedWake = wakeMinutes ?? (
            (legacyWakeHour ?? Self.standard.targetWakeHour) * 60 +
            (legacyWakeMinute ?? Self.standard.targetWakeMinute)
        )
        let resolvedAlarmUsesWakeTime = try container.decodeIfPresent(Bool.self, forKey: .alarmUsesWakeTime) ?? true
        let resolvedAlarmTime = try container.decodeIfPresent(Int.self, forKey: .alarmTimeMinutesFromMidnight)

        self.init(
            bedtimeMinutesFromMidnight: resolvedBedtime,
            wakeTimeMinutesFromMidnight: resolvedWake,
            alarmEnabled: alarmEnabled,
            alarmTimeMinutesFromMidnight: resolvedAlarmTime,
            alarmUsesWakeTime: resolvedAlarmUsesWakeTime,
            alarmSoundName: alarmSoundName,
            alarmHapticsEnabled: alarmHapticsEnabled,
            snoozeEnabled: snoozeEnabled,
            smartWakeEnabled: smartWakeEnabled,
            wakeWindowMinutes: wakeWindowMinutes
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bedtimeMinutesFromMidnight, forKey: .bedtimeMinutesFromMidnight)
        try container.encode(wakeTimeMinutesFromMidnight, forKey: .wakeTimeMinutesFromMidnight)
        try container.encode(alarmEnabled, forKey: .alarmEnabled)
        try container.encode(alarmTimeMinutesFromMidnight, forKey: .alarmTimeMinutesFromMidnight)
        try container.encode(alarmUsesWakeTime, forKey: .alarmUsesWakeTime)
        try container.encode(alarmSoundName, forKey: .alarmSoundName)
        try container.encode(alarmHapticsEnabled, forKey: .alarmHapticsEnabled)
        try container.encode(snoozeEnabled, forKey: .snoozeEnabled)
        try container.encode(smartWakeEnabled, forKey: .smartWakeEnabled)
        try container.encodeIfPresent(wakeWindowMinutes, forKey: .wakeWindowMinutes)
    }
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
    nonisolated var id: String { [sourceBundleIdentifier, sourceName, productType, deviceName].compactMap { $0 }.joined(separator: "|") }
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

    nonisolated static func == (lhs: SourceProvenance, rhs: SourceProvenance) -> Bool {
        lhs.sourceName == rhs.sourceName
            && lhs.sourceBundleIdentifier == rhs.sourceBundleIdentifier
            && lhs.sourceVersion == rhs.sourceVersion
            && lhs.operatingSystemVersion == rhs.operatingSystemVersion
            && lhs.productType == rhs.productType
            && lhs.deviceName == rhs.deviceName
            && lhs.deviceManufacturer == rhs.deviceManufacturer
            && lhs.deviceModel == rhs.deviceModel
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(sourceName)
        hasher.combine(sourceBundleIdentifier)
        hasher.combine(sourceVersion)
        hasher.combine(operatingSystemVersion)
        hasher.combine(productType)
        hasher.combine(deviceName)
        hasher.combine(deviceManufacturer)
        hasher.combine(deviceModel)
    }

    nonisolated var displayName: String {
        if let deviceName, !deviceName.isEmpty { return deviceName }
        return sourceName
    }

    nonisolated var isAppleWatchLike: Bool {
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

    nonisolated var durationMinutes: Double { max(0, end.timeIntervalSince(start) / 60) }
}

struct NightlySleepInput: Identifiable, Codable, Equatable {
    var id = UUID()
    var nightStart: Date
    var nightEnd: Date
    var segments: [SleepSegment]

    nonisolated var sourceBadges: [SourceProvenance] {
        SourceResolver.uniqueSourceBadges(segments.map(\.provenance))
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

enum StressLevel: String, Codable, Equatable, Hashable, CaseIterable, Identifiable {
    case low = "Low"
    case balanced = "Balanced"
    case elevated = "Elevated"
    case high = "High"

    nonisolated var id: String { rawValue }

    nonisolated static func level(for score: Int) -> StressLevel {
        switch PulsarStressCategory.category(for: score) {
        case .low: .low
        case .balanced: .balanced
        case .elevated: .elevated
        case .high: .high
        }
    }

    nonisolated static func legacyLevel(named name: String?) -> StressLevel? {
        guard let name else { return nil }
        if let level = StressLevel(rawValue: name) {
            return level
        }
        if name == "Medium" {
            return .balanced
        }
        if name == "Moderate" {
            return .balanced
        }
        if name == "Very High" {
            return .high
        }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = StressLevel.legacyLevel(named: value) ?? .balanced
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum StressDriverSeverity: String, Codable, Equatable {
    case supportive
    case neutral
    case elevated
    case high
}

struct StressDriver: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var detail: String
    var severity: StressDriverSeverity
    var relatedMetric: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        detail: String,
        severity: StressDriverSeverity,
        relatedMetric: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
        self.relatedMetric = relatedMetric
    }
}

enum StressContext: String, Codable, Equatable, Hashable {
    case sleep
    case workout
    case rest
    case active
    case movementFiltered
    case cooldown
    case recovery
    case unknown
}

struct StressSample: Identifiable, Codable, Equatable, Hashable {
    var id: Date { timestamp }
    var timestamp: Date
    var score: Double
    var confidence: ConfidenceGrade
    var context: StressContext?
}

enum StressSignalAvailability: String, Codable, Equatable {
    case available
    case limited
    case unavailable
}

struct StressSignal: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var value: String
    var baseline: String?
    var availability: StressSignalAvailability
}

enum StressSummaryState: String, Codable, Equatable {
    case noData
    case buildingBaseline
    case ready
    case lowConfidence
    case workoutPaused
    case cooldown
}

struct StressSummary: Codable, Equatable {
    var date: Date?
    var score: Int?
    var dailyAverageScore: Int?
    var level: StressLevel?
    var confidence: ConfidenceGrade
    var state: StressSummaryState
    var driverInsights: [String]
    var drivers: [StressDriver]
    var signals: [StressSignal]
    var dailySamples: [StressSample]
    var analyzedSampleCount: Int
    var baselineWindowDays: Int
    var availableSignalCount: Int
    var lastHeartRate: Double?
    var lastHeartRateTimestamp: Date?
    var lastHRV: Double?
    var lastHRVTimestamp: Date?
    var nonActivityStress: Int?
    var activityAdjustedStress: Int?
    var movementStateText: String?
    var stressStatusText: String?
    var queryStart: Date?
    var queryEnd: Date?
    var lastUpdated: Date?
    var sourceBadges: [SourceProvenance]
    var explanation: String
    var subtext: String

    var currentScore: Double? {
        score.map(Double.init)
    }

    static let estimateSubtext = "Estimated from recent HR, HRV, movement, workouts, and personal baseline"

    init(
        date: Date?,
        score: Int?,
        dailyAverageScore: Int? = nil,
        level: StressLevel?,
        confidence: ConfidenceGrade,
        state: StressSummaryState,
        driverInsights: [String],
        drivers: [StressDriver] = [],
        signals: [StressSignal] = [],
        dailySamples: [StressSample] = [],
        analyzedSampleCount: Int,
        baselineWindowDays: Int,
        availableSignalCount: Int,
        lastHeartRate: Double? = nil,
        lastHeartRateTimestamp: Date? = nil,
        lastHRV: Double? = nil,
        lastHRVTimestamp: Date? = nil,
        nonActivityStress: Int? = nil,
        activityAdjustedStress: Int? = nil,
        movementStateText: String? = nil,
        stressStatusText: String? = nil,
        queryStart: Date?,
        queryEnd: Date?,
        lastUpdated: Date?,
        sourceBadges: [SourceProvenance],
        explanation: String,
        subtext: String
    ) {
        self.date = date
        self.score = score
        self.dailyAverageScore = dailyAverageScore
        self.level = level
        self.confidence = confidence
        self.state = state
        self.driverInsights = driverInsights
        self.drivers = drivers
        self.signals = signals
        self.dailySamples = dailySamples
        self.analyzedSampleCount = analyzedSampleCount
        self.baselineWindowDays = baselineWindowDays
        self.availableSignalCount = availableSignalCount
        self.lastHeartRate = lastHeartRate
        self.lastHeartRateTimestamp = lastHeartRateTimestamp
        self.lastHRV = lastHRV
        self.lastHRVTimestamp = lastHRVTimestamp
        self.nonActivityStress = nonActivityStress
        self.activityAdjustedStress = activityAdjustedStress
        self.movementStateText = movementStateText
        self.stressStatusText = stressStatusText
        self.queryStart = queryStart
        self.queryEnd = queryEnd
        self.lastUpdated = lastUpdated
        self.sourceBadges = sourceBadges
        self.explanation = explanation
        self.subtext = subtext
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case score
        case dailyAverageScore
        case level
        case band
        case confidence
        case state
        case driverInsights
        case drivers
        case signals
        case dailySamples
        case analyzedSampleCount
        case baselineWindowDays
        case availableSignalCount
        case lastHeartRate
        case lastHeartRateTimestamp
        case lastHRV
        case lastHRVTimestamp
        case nonActivityStress
        case activityAdjustedStress
        case movementStateText
        case stressStatusText
        case queryStart
        case queryEnd
        case lastUpdated
        case sourceBadges
        case explanation
        case subtext
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decodeIfPresent(Date.self, forKey: .date)
        score = try container.decodeIfPresent(Int.self, forKey: .score)
        dailyAverageScore = try container.decodeIfPresent(Int.self, forKey: .dailyAverageScore)
        let legacyBand = try container.decodeIfPresent(String.self, forKey: .band)
        level = try container.decodeIfPresent(StressLevel.self, forKey: .level) ??
            StressLevel.legacyLevel(named: legacyBand) ??
            score.map(StressLevel.level(for:))
        confidence = try container.decodeIfPresent(ConfidenceGrade.self, forKey: .confidence) ?? .missing
        state = try container.decodeIfPresent(StressSummaryState.self, forKey: .state) ?? .noData
        driverInsights = try container.decodeIfPresent([String].self, forKey: .driverInsights) ?? []
        drivers = try container.decodeIfPresent([StressDriver].self, forKey: .drivers) ?? []
        signals = try container.decodeIfPresent([StressSignal].self, forKey: .signals) ?? []
        dailySamples = try container.decodeIfPresent([StressSample].self, forKey: .dailySamples) ?? []
        analyzedSampleCount = try container.decodeIfPresent(Int.self, forKey: .analyzedSampleCount) ?? 0
        baselineWindowDays = try container.decodeIfPresent(Int.self, forKey: .baselineWindowDays) ?? 0
        availableSignalCount = try container.decodeIfPresent(Int.self, forKey: .availableSignalCount) ?? 0
        lastHeartRate = try container.decodeIfPresent(Double.self, forKey: .lastHeartRate)
        lastHeartRateTimestamp = try container.decodeIfPresent(Date.self, forKey: .lastHeartRateTimestamp)
        lastHRV = try container.decodeIfPresent(Double.self, forKey: .lastHRV)
        lastHRVTimestamp = try container.decodeIfPresent(Date.self, forKey: .lastHRVTimestamp)
        nonActivityStress = try container.decodeIfPresent(Int.self, forKey: .nonActivityStress)
        activityAdjustedStress = try container.decodeIfPresent(Int.self, forKey: .activityAdjustedStress)
        movementStateText = try container.decodeIfPresent(String.self, forKey: .movementStateText)
        stressStatusText = try container.decodeIfPresent(String.self, forKey: .stressStatusText)
        queryStart = try container.decodeIfPresent(Date.self, forKey: .queryStart)
        queryEnd = try container.decodeIfPresent(Date.self, forKey: .queryEnd)
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated)
        sourceBadges = try container.decodeIfPresent([SourceProvenance].self, forKey: .sourceBadges) ?? []
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? "Estimated stress compares available wearable signals with your personal baseline."
        subtext = try container.decodeIfPresent(String.self, forKey: .subtext) ?? Self.estimateSubtext
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encodeIfPresent(score, forKey: .score)
        try container.encodeIfPresent(dailyAverageScore, forKey: .dailyAverageScore)
        try container.encodeIfPresent(level, forKey: .level)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(state, forKey: .state)
        try container.encode(driverInsights, forKey: .driverInsights)
        try container.encode(drivers, forKey: .drivers)
        try container.encode(signals, forKey: .signals)
        try container.encode(dailySamples, forKey: .dailySamples)
        try container.encode(analyzedSampleCount, forKey: .analyzedSampleCount)
        try container.encode(baselineWindowDays, forKey: .baselineWindowDays)
        try container.encode(availableSignalCount, forKey: .availableSignalCount)
        try container.encodeIfPresent(lastHeartRate, forKey: .lastHeartRate)
        try container.encodeIfPresent(lastHeartRateTimestamp, forKey: .lastHeartRateTimestamp)
        try container.encodeIfPresent(lastHRV, forKey: .lastHRV)
        try container.encodeIfPresent(lastHRVTimestamp, forKey: .lastHRVTimestamp)
        try container.encodeIfPresent(nonActivityStress, forKey: .nonActivityStress)
        try container.encodeIfPresent(activityAdjustedStress, forKey: .activityAdjustedStress)
        try container.encodeIfPresent(movementStateText, forKey: .movementStateText)
        try container.encodeIfPresent(stressStatusText, forKey: .stressStatusText)
        try container.encodeIfPresent(queryStart, forKey: .queryStart)
        try container.encodeIfPresent(queryEnd, forKey: .queryEnd)
        try container.encodeIfPresent(lastUpdated, forKey: .lastUpdated)
        try container.encode(sourceBadges, forKey: .sourceBadges)
        try container.encode(explanation, forKey: .explanation)
        try container.encode(subtext, forKey: .subtext)
    }

    static let missing = StressSummary(
        date: nil,
        score: nil,
        level: nil,
        confidence: .missing,
        state: .noData,
        driverInsights: [
            "Waiting for recent HR or HRV",
            "Allow Health access or wear a device to start stress tracking"
        ],
        drivers: [
            StressDriver(
                id: "missing-signals",
                title: "Recent stress signals unavailable",
                detail: "Stress needs recent HR or HRV plus a personal baseline.",
                severity: .neutral,
                relatedMetric: "Permissions"
            )
        ],
        signals: [],
        dailySamples: [],
        analyzedSampleCount: 0,
        baselineWindowDays: 0,
        availableSignalCount: 0,
        queryStart: nil,
        queryEnd: nil,
        lastUpdated: nil,
        sourceBadges: [],
        explanation: "Stress needs recent HR or HRV plus a personal baseline.",
        subtext: estimateSubtext
    )

    static func buildingBaseline(date: Date?, baselineWindowDays: Int, analyzedSampleCount: Int, sourceBadges: [SourceProvenance]) -> StressSummary {
        StressSummary(
            date: date,
            score: nil,
            level: nil,
            confidence: .low,
            state: .buildingBaseline,
            driverInsights: [
                "Building your personal baseline",
                "More overnight wear improves accuracy"
            ],
            drivers: [
                StressDriver(
                    id: "building-baseline",
                    title: "Building your personal baseline",
                    detail: "Stress confidence improves after 7 or more baseline days.",
                    severity: .neutral,
                    relatedMetric: "Baseline"
                )
            ],
            signals: [],
            dailySamples: [],
            analyzedSampleCount: analyzedSampleCount,
            baselineWindowDays: baselineWindowDays,
            availableSignalCount: 0,
            queryStart: nil,
            queryEnd: nil,
            lastUpdated: nil,
            sourceBadges: sourceBadges,
            explanation: "Stress load needs at least 7 baseline days before showing a score.",
            subtext: estimateSubtext
        )
    }
}

struct HomeDashboard: Codable, Equatable {
    var profile: UserProfile
    var sleep: SleepSummary
    var recovery: RecoverySummary
    var strain: StrainSummary
    var stress: StressSummary
    var healthMonitor: HealthMonitorSummary
    var generatedAt: Date
    var usingSampleData: Bool

    init(
        profile: UserProfile,
        sleep: SleepSummary,
        recovery: RecoverySummary,
        strain: StrainSummary,
        stress: StressSummary = .missing,
        healthMonitor: HealthMonitorSummary = .missing(),
        generatedAt: Date,
        usingSampleData: Bool
    ) {
        self.profile = profile
        self.sleep = sleep
        self.recovery = recovery
        self.strain = strain
        self.stress = stress
        self.healthMonitor = healthMonitor
        self.generatedAt = generatedAt
        self.usingSampleData = usingSampleData
    }

    private enum CodingKeys: String, CodingKey {
        case profile, sleep, recovery, strain, stress, healthMonitor, generatedAt, usingSampleData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decode(UserProfile.self, forKey: .profile)
        sleep = try container.decode(SleepSummary.self, forKey: .sleep)
        recovery = try container.decode(RecoverySummary.self, forKey: .recovery)
        strain = try container.decode(StrainSummary.self, forKey: .strain)
        stress = try container.decodeIfPresent(StressSummary.self, forKey: .stress) ?? .missing
        healthMonitor = try container.decodeIfPresent(HealthMonitorSummary.self, forKey: .healthMonitor) ?? .missing()
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        usingSampleData = try container.decode(Bool.self, forKey: .usingSampleData)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profile, forKey: .profile)
        try container.encode(sleep, forKey: .sleep)
        try container.encode(recovery, forKey: .recovery)
        try container.encode(strain, forKey: .strain)
        try container.encode(stress, forKey: .stress)
        try container.encode(healthMonitor, forKey: .healthMonitor)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(usingSampleData, forKey: .usingSampleData)
    }

    #if DEBUG
    static let sample = HomeDashboard(
        profile: MockHealthData.profile,
        sleep: MockHealthData.sleepSummary,
        recovery: MockHealthData.recoverySummary,
        strain: MockHealthData.strainSummary,
        stress: MockHealthData.stressSummary,
        healthMonitor: MockHealthData.healthMonitorSummary,
        generatedAt: .now,
        usingSampleData: true
    )
    #endif

    static let empty = HomeDashboard(
        profile: .empty,
        sleep: .missing,
        recovery: .missing,
        strain: .missing,
        stress: .missing,
        healthMonitor: .missing(),
        generatedAt: .now,
        usingSampleData: false
    )
}

enum SourceResolver {
    nonisolated static func primarySleepSegments(from segments: [SleepSegment], nightStart: Date, nightEnd: Date) -> [SleepSegment] {
        guard !segments.isEmpty else { return [] }
        let grouped = Dictionary(grouping: segments, by: { $0.provenance.id })
        let best = grouped.max { lhs, rhs in
            guard let lhsProvenance = lhs.value.first?.provenance,
                  let rhsProvenance = rhs.value.first?.provenance else {
                return false
            }
            return scoreSleepSource(lhs.value, nightStart: nightStart, nightEnd: nightEnd, provenance: lhsProvenance) <
                scoreSleepSource(rhs.value, nightStart: nightStart, nightEnd: nightEnd, provenance: rhsProvenance)
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
        var seen = Set<String>()
        var unique: [SourceProvenance] = []
        for provenance in provenances where seen.insert(provenance.id).inserted {
            unique.append(provenance)
        }
        return unique.sorted { $0.displayName < $1.displayName }
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
