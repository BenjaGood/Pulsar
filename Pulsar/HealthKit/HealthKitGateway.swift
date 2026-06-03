//
//  HealthKitGateway.swift
//  Pulsar
//

import CoreLocation
import Foundation
import HealthKit

struct HealthKitProfilePayload {
    var heightCentimeters: Double?
    var weightKilograms: Double?
    var dateOfBirth: Date?
    var biologicalSex: BiologicalSex?
}

struct HealthKitAnchoredChanges {
    var samples: [HKSample]
    var deletedObjects: [HKDeletedObject]
    var newAnchor: HKQueryAnchor?
}

actor HealthKitGateway {
    private let store = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []
    private var observersStarted = false

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthKitGatewayError.healthDataUnavailable }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [], read: Self.requiredReadTypes) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume() }
                else { continuation.resume(throwing: HealthKitGatewayError.authorizationDenied) }
            }
        }
    }

    func authorizationRequestStatus() async -> HKAuthorizationRequestStatus {
        guard isAvailable else { return .unknown }
        return await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: Self.requiredReadTypes) { status, _ in
                continuation.resume(returning: status)
            }
        }
    }

    func fetchProfile() async -> HealthKitProfilePayload {
        let height = await fetchMostRecentQuantity(identifier: .height, unit: .meterUnit(with: .centi))
        let weight = await fetchMostRecentQuantity(identifier: .bodyMass, unit: .gramUnit(with: .kilo))
        let dateOfBirth: Date? = try? store.dateOfBirthComponents().date
        let biologicalSex = (try? store.biologicalSex().biologicalSex).map(mapBiologicalSex)
        return HealthKitProfilePayload(
            heightCentimeters: height?.value,
            weightKilograms: weight?.value,
            dateOfBirth: dateOfBirth,
            biologicalSex: biologicalSex
        )
    }

    func fetchSleepSegments(start: Date, end: Date) async -> [SleepSegment] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let samples = await fetchCategorySamples(type: type, start: start, end: end)
        #if DEBUG
        SleepDebugLogger.logQuery(platform: "iOS", start: start, end: end, samples: samples.map { sleepAnalysisSample(for: $0) })
        #endif
        return samples.map { sample in
            SleepSegment(
                id: sample.uuid,
                stage: mapSleepStage(sample.value),
                start: sample.startDate,
                end: sample.endDate,
                provenance: provenance(for: sample)
            )
        }
    }

    func fetchDailyBiometrics(date: Date, calendar: Calendar) async -> DailyBiometrics {
        let interval = calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86_400)
        async let hrv = fetchMostRecentQuantity(identifier: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), start: interval.start, end: interval.end)
        async let rhr = fetchMostRecentQuantity(identifier: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), start: interval.start, end: interval.end)
        async let respiratory = fetchMostRecentQuantity(identifier: .respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()), start: interval.start, end: interval.end)
        async let oxygen = fetchMostRecentQuantity(identifier: .oxygenSaturation, unit: .percent(), start: interval.start, end: interval.end)
        async let wristTemperature = fetchMostRecentQuantity(identifier: .appleSleepingWristTemperature, unit: .degreeCelsius(), start: interval.start, end: interval.end)
        let values = await (hrv, rhr, respiratory, oxygen, wristTemperature)
        var provenance: [String: SourceProvenance] = [:]
        provenance["hrv"] = values.0?.provenance
        provenance["rhr"] = values.1?.provenance
        provenance["respiratory"] = values.2?.provenance
        provenance["oxygen"] = values.3?.provenance
        provenance["wristTemperature"] = values.4?.provenance
        return DailyBiometrics(
            date: date,
            hrvSDNNMilliseconds: values.0?.value,
            restingHeartRateBPM: values.1?.value,
            respiratoryRate: values.2?.value,
            oxygenSaturation: values.3?.value,
            wristTemperatureDeviationCelsius: values.4?.value,
            sleepPerformance: nil,
            priorDayStrain: nil,
            provenance: provenance
        )
    }

    func fetchWalkingHeartRateAverage(date: Date, calendar: Calendar) async -> (value: Double, provenance: SourceProvenance)? {
        let interval = calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86_400)
        return await fetchMostRecentQuantity(
            identifier: .walkingHeartRateAverage,
            unit: HKUnit.count().unitDivided(by: .minute()),
            start: interval.start,
            end: interval.end
        )
    }

    func fetchMostRecentQuantitySample(identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> (value: Double, start: Date, end: Date, provenance: SourceProvenance)? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { [unit] _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (
                    sample.quantity.doubleValue(for: unit),
                    sample.startDate,
                    sample.endDate,
                    self.provenance(for: sample)
                ))
            }
            store.execute(query)
        }
    }

    func fetchActivity(date: Date, calendar: Calendar) async -> DailyActivityInput {
        let interval = calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86_400)
        return await fetchActivity(start: interval.start, end: interval.end)
    }

    func fetchActivity(start: Date, end: Date) async -> DailyActivityInput {
        async let steps = sumQuantity(identifier: .stepCount, unit: .count(), start: start, end: end)
        async let activeEnergy = sumQuantity(identifier: .activeEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        async let basalEnergy = sumQuantity(identifier: .basalEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        async let exercise = sumQuantity(identifier: .appleExerciseTime, unit: .minute(), start: start, end: end)
        async let walkingRunningDistance = sumQuantity(identifier: .distanceWalkingRunning, unit: .meter(), start: start, end: end)
        async let cyclingDistance = sumQuantity(identifier: .distanceCycling, unit: .meter(), start: start, end: end)
        let results = await (steps, activeEnergy, basalEnergy, exercise, walkingRunningDistance, cyclingDistance)
        let provenances = [results.0.provenance, results.1.provenance, results.2.provenance, results.3.provenance, results.4.provenance, results.5.provenance].compactMap { $0 }
        let fallbackExercise = results.1.value > 0 ? min(180, results.1.value / 8) : 0
        return DailyActivityInput(
            date: start,
            steps: results.0.value,
            activeEnergyKilocalories: results.1.value,
            basalEnergyKilocalories: results.2.value,
            distanceMeters: results.4.value + results.5.value,
            exerciseMinutes: results.3.value > 0 ? results.3.value : fallbackExercise,
            provenance: SourceResolver.uniqueSourceBadges(provenances)
        )
    }

    func fetchWorkouts(start: Date, end: Date) async -> [WorkoutLoadInput] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }
        var results: [WorkoutLoadInput] = []
        for workout in workouts {
            let heartRateSamples = await fetchHeartRateSamples(for: workout)
            let gymMetadata = pulsarGymMetadata(for: workout)
            let pulsarMetadata = pulsarWorkoutMetadata(for: workout)
            let workoutProvenance = provenance(for: workout)
            await recordAppleWatchHealthKitSourceIfNeeded(
                workout: workout,
                pulsarMetadata: pulsarMetadata,
                provenance: workoutProvenance,
                reason: "healthKitWorkoutLoad"
            )
            results.append(
                WorkoutLoadInput(
                    type: gymMetadata?.categoryName ?? workout.workoutActivityType.displayName,
                    start: workout.startDate,
                    end: workout.endDate,
                    heartRateSamples: heartRateSamples,
                    activeEnergyKilocalories: Self.activeEnergyKilocalories(for: workout),
                    distanceMeters: workout.totalDistance?.doubleValue(for: .meter()),
                    provenance: workoutProvenance
                )
            )
        }
        return results
    }

    func fetchWeeklyActivities(start: Date, end: Date, includesHeartRate: Bool = true) async -> [WeeklyActivity] {
        let workouts = await fetchWorkoutSamples(start: start, end: end, ascending: false)
        var activities: [WeeklyActivity] = []

        for workout in workouts {
            let heartRateSamples = includesHeartRate ? await fetchHeartRateSamples(for: workout) : []
            let heartRates = heartRateSamples.map(\.bpm).filter { $0 > 0 }
            let gymMetadata = pulsarGymMetadata(for: workout)
            let pulsarMetadata = pulsarWorkoutMetadata(for: workout)
            let metadataOutdoorKind = pulsarMetadata.workoutType.flatMap(PulsarOutdoorWorkoutKind.init(workoutTypeRawValue:))
            let displayActivityType = metadataOutdoorKind?.healthKitActivityType ?? workout.workoutActivityType
            let category = gymMetadata == nil ? fitnessCategory(for: displayActivityType) : .gym
            let workoutType = gymMetadata?.categoryName ?? metadataOutdoorKind?.displayName ?? workout.workoutActivityType.fitnessDisplayName
            let displayName = gymMetadata?.displayName ?? metadataOutdoorKind?.displayName ?? workout.workoutActivityType.fitnessDisplayName
            let provenance = provenance(for: workout)
            let route = gymMetadata == nil && Self.isRouteActivity(displayActivityType)
                ? await PulsarHealthKitWorkoutRouteImporter.route(for: workout, healthStore: store)
                : nil
            let routeSplits = Self.splitEstimates(from: route)
            let distanceMeters = workout.totalDistance?.doubleValue(for: .meter()) ?? Self.distanceMeters(for: route)
            await recordAppleWatchHealthKitSourceIfNeeded(
                workout: workout,
                pulsarMetadata: pulsarMetadata,
                provenance: provenance,
                reason: "healthKitActivityLogMetadata"
            )
            PulsarSyncDebugLogger.log("HealthKit Activity Log metadata received session=\(pulsarMetadata.sessionId?.uuidString ?? "none") type=\(pulsarMetadata.workoutType ?? workout.workoutActivityType.fitnessDisplayName) startedFrom=\(pulsarMetadata.startedFrom?.rawValue ?? "unknown") hkType=\(workout.workoutActivityType.rawValue) source=\(provenance.displayName)")
            var detailMetadata = [
                FitnessWorkoutMetadataItem(title: "App Source", value: provenance.sourceName)
            ]
            if let sourceVersion = provenance.sourceVersion {
                detailMetadata.append(FitnessWorkoutMetadataItem(title: "Source Version", value: sourceVersion))
            }
            if let productType = provenance.productType {
                detailMetadata.append(FitnessWorkoutMetadataItem(title: "Product", value: productType))
            }
            if let deviceModel = provenance.deviceModel {
                detailMetadata.append(FitnessWorkoutMetadataItem(title: "Device Model", value: deviceModel))
            }
            if let workoutType = pulsarMetadata.workoutType {
                detailMetadata.append(FitnessWorkoutMetadataItem(title: "Pulsar Type", value: workoutType))
            }
            if let sessionId = pulsarMetadata.sessionId {
                detailMetadata.append(FitnessWorkoutMetadataItem(title: "Session", value: sessionId.uuidString))
            }
            if let route {
                detailMetadata.append(FitnessWorkoutMetadataItem(title: "Route Points", value: "\(route.points.count)"))
            }

            activities.append(
                WeeklyActivity(
                    id: "healthkit-\(workout.uuid.uuidString)",
                    pulsarWorkoutSessionId: pulsarMetadata.sessionId,
                    workoutUUID: workout.uuid,
                    workoutType: workoutType,
                    displayName: displayName,
                    category: category,
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    duration: workout.duration,
                    calories: Self.activeEnergyKilocalories(for: workout),
                    distanceMeters: distanceMeters,
                    averageHeartRate: heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count),
                    maxHeartRate: heartRates.max(),
                    source: .healthKit,
                    sourceName: pulsarMetadata.isPulsarWorkout ? PulsarWorkoutMetadata.brandName : provenance.displayName,
                    sourceDeviceName: pulsarMetadata.startedFrom?.displayName ?? provenance.displayName,
                    trainingType: workoutType,
                    route: route?.runCoordinates ?? [],
                    splits: routeSplits,
                    metadata: detailMetadata
                )
            )
        }

        return activities
    }

    func fetchWorkoutStartDates(start: Date, end: Date) async -> [Date] {
        await fetchWorkoutSamples(start: start, end: end, ascending: true).map(\.startDate)
    }

    func fetchWorkoutNotificationEvents(start: Date, end: Date) async -> [WorkoutNotificationEvent] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let workouts: [HKWorkout] = await withCheckedContinuation { (continuation: CheckedContinuation<[HKWorkout], Never>) in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }

        var events: [WorkoutNotificationEvent] = []
        for workout in workouts {
            let heartRateSamples = await fetchHeartRateSamples(for: workout)
            let heartRates = heartRateSamples.map(\.bpm).filter { $0 > 0 }
            events.append(
                WorkoutNotificationEvent(
                    id: workout.uuid.uuidString,
                    workoutType: workout.workoutActivityType.displayName,
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    activeEnergyKilocalories: Self.activeEnergyKilocalories(for: workout),
                    averageHeartRate: heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count),
                    maxHeartRate: heartRates.max(),
                    sourceName: provenance(for: workout).displayName
                )
            )
        }
        return events
    }

    func fetchHeartRateSamples(start: Date, end: Date) async -> [HeartRateSample] {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return [] }
        let samples = await fetchQuantitySamples(type: type, start: start, end: end)
        return heartRateSamples(from: samples)
    }

    private func fetchHeartRateSamples(for workout: HKWorkout) async -> [HeartRateSample] {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return [] }
        let associatedSamples = await fetchQuantitySamples(
            type: type,
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        let samples: [HKQuantitySample]
        if associatedSamples.isEmpty {
            samples = await fetchQuantitySamples(type: type, start: workout.startDate, end: workout.endDate)
        } else {
            samples = associatedSamples
        }
        return heartRateSamples(from: samples)
    }

    private func heartRateSamples(from samples: [HKQuantitySample]) -> [HeartRateSample] {
        let unit = HKUnit.count().unitDivided(by: .minute())
        return samples.map { sample in
            HeartRateSample(
                start: sample.startDate,
                end: sample.endDate,
                bpm: sample.quantity.doubleValue(for: unit),
                provenance: provenance(for: sample)
            )
        }
    }

    func startObservers(onChange: @escaping @Sendable (HKSampleType) async -> Void) async {
        guard !observersStarted else { return }
        observersStarted = true
        for type in Self.incrementalSampleTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, _ in
                Task {
                    await onChange(type)
                    completionHandler()
                }
            }
            observerQueries.append(query)
            store.execute(query)
            try? await store.enableBackgroundDelivery(for: type, frequency: .immediate)
        }
    }

    func anchoredChanges(for type: HKSampleType, anchor: HKQueryAnchor?, start: Date? = nil) async -> HealthKitAnchoredChanges {
        let predicate = start.map { HKQuery.predicateForSamples(withStart: $0, end: nil, options: []) }
        return await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, deletedObjects, newAnchor, _ in
                continuation.resume(
                    returning: HealthKitAnchoredChanges(
                        samples: samples ?? [],
                        deletedObjects: deletedObjects ?? [],
                        newAnchor: newAnchor
                    )
                )
            }
            store.execute(query)
        }
    }

    func dailyStatisticsCollection(identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date, calendar: Calendar) async -> [(Date, Double)] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [] }
        let anchor = calendar.startOfDay(for: start)
        var interval = DateComponents()
        interval.day = 1
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, collection, _ in
                var values: [(Date, Double)] = []
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    values.append((statistics.startDate, statistics.sumQuantity()?.doubleValue(for: unit) ?? 0))
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    private func fetchMostRecentQuantity(identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date? = nil, end: Date? = nil) async -> (value: Double, provenance: SourceProvenance)? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { [unit] _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (sample.quantity.doubleValue(for: unit), self.provenance(for: sample)))
            }
            store.execute(query)
        }
    }

    private func sumQuantity(identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> (value: Double, provenance: SourceProvenance?) {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return (0, nil) }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sum: Double = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
        let source = await fetchFirstQuantitySample(type: type, start: start, end: end).map { provenance(for: $0) }
        return (sum, source)
    }

    private func fetchFirstQuantitySample(type: HKQuantityType, start: Date, end: Date) async -> HKQuantitySample? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKQuantitySample)
            }
            store.execute(query)
        }
    }

    private func fetchQuantitySamples(type: HKQuantityType, start: Date, end: Date) async -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await fetchQuantitySamples(type: type, predicate: predicate)
    }

    private func fetchQuantitySamples(type: HKQuantityType, predicate: NSPredicate) async -> [HKQuantitySample] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            store.execute(query)
        }
    }

    private func fetchWorkoutSamples(start: Date, end: Date, ascending: Bool) async -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: ascending)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }
    }

    private func fetchCategorySamples(type: HKCategoryType, start: Date, end: Date) async -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples as? [HKCategorySample] ?? [])
            }
            store.execute(query)
        }
    }

    nonisolated private func provenance(for sample: HKSample) -> SourceProvenance {
        let revision = sample.sourceRevision
        let os = revision.operatingSystemVersion
        return SourceProvenance(
            sourceName: revision.source.name,
            sourceBundleIdentifier: revision.source.bundleIdentifier,
            sourceVersion: revision.version,
            operatingSystemVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            productType: revision.productType,
            deviceName: sample.device?.name,
            deviceManufacturer: sample.device?.manufacturer,
            deviceModel: sample.device?.model
        )
    }

    private func recordAppleWatchHealthKitSourceIfNeeded(
        workout: HKWorkout,
        pulsarMetadata: (sessionId: UUID?, workoutType: String?, startedFrom: PulsarWorkoutStartedFrom?, isPulsarWorkout: Bool),
        provenance: SourceProvenance,
        reason: String
    ) async {
        let sourceText = [
            provenance.sourceName,
            provenance.sourceBundleIdentifier,
            provenance.productType,
            provenance.deviceName,
            provenance.deviceModel,
            workout.sourceRevision.source.name,
            workout.sourceRevision.source.bundleIdentifier
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        let isAppleWatchSource = pulsarMetadata.startedFrom?.isAppleWatchRecorder == true ||
            sourceText.localizedCaseInsensitiveContains("watch")
        guard isAppleWatchSource else { return }

        await MainActor.run {
            PulsarWatchConnectivitySyncStore.shared.recordAppleWatchSeen(
                reason: reason,
                payloadKind: "healthKitWorkoutMetadata"
            )
        }
    }

    nonisolated private func mapSleepStage(_ value: Int) -> SleepStage {
        switch value {
        case HKCategoryValueSleepAnalysis.awake.rawValue: return .awake
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue: return .core
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: return .deep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue: return .rem
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: return .asleepUnspecified
        case HKCategoryValueSleepAnalysis.inBed.rawValue: return .inBed
        default: return .asleepUnspecified
        }
    }

    nonisolated private func mapSleepAnalysisStage(_ value: Int) -> SleepAnalysisStage {
        switch value {
        case HKCategoryValueSleepAnalysis.awake.rawValue: return .awake
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue: return .asleepCore
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: return .asleepDeep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue: return .asleepREM
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: return .asleepUnspecified
        case HKCategoryValueSleepAnalysis.inBed.rawValue: return .inBed
        default: return .asleepUnspecified
        }
    }

    nonisolated private func sleepAnalysisSample(for sample: HKCategorySample) -> SleepAnalysisSample {
        SleepAnalysisSample(
            id: sample.uuid.uuidString,
            stage: mapSleepAnalysisStage(sample.value),
            start: sample.startDate,
            end: sample.endDate,
            sourceName: sample.sourceRevision.source.name,
            sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
            deviceName: sample.device?.name
        )
    }

    nonisolated private func mapBiologicalSex(_ sex: HKBiologicalSex) -> BiologicalSex {
        switch sex {
        case .female: return .female
        case .male: return .male
        case .other: return .other
        default: return .notSet
        }
    }

    nonisolated private func pulsarGymMetadata(for workout: HKWorkout) -> (kind: PulsarGymWorkoutKind, categoryName: String, displayName: String)? {
        guard let metadata = workout.metadata else { return nil }
        let rawCategory = (metadata["PulsarWorkoutCategory"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let rawKind = (metadata["PulsarWorkoutKind"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let routineName = metadata["PulsarRoutineName"] as? String
        let metadataDisplayName = metadata["PulsarWorkoutDisplayName"] as? String
        let decodedKind = rawKind.flatMap(PulsarGymWorkoutKind.init(rawValue:))

        let hasGymCategory = rawCategory == "gym" || rawKind?.lowercased() == "gym" || decodedKind != nil
        guard hasGymCategory else { return nil }

        let kind = decodedKind ?? PulsarGymWorkoutKind.inferred(
            routineName: metadataDisplayName ?? routineName ?? "",
            exerciseCount: 0
        )
        let displayName: String
        if kind == .freeWorkout {
            displayName = kind.displayName
        } else {
            let trimmedName = (metadataDisplayName ?? routineName ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            displayName = trimmedName.isEmpty ? kind.displayName : trimmedName
        }

        return (kind, kind.categoryName, displayName)
    }

    nonisolated private func pulsarWorkoutMetadata(for workout: HKWorkout) -> (sessionId: UUID?, workoutType: String?, startedFrom: PulsarWorkoutStartedFrom?, isPulsarWorkout: Bool) {
        let metadata = workout.metadata
        let sessionId = PulsarWorkoutMetadata.sessionId(from: metadata)
        let workoutType = PulsarWorkoutMetadata.workoutType(from: metadata)
        let startedFrom = PulsarWorkoutMetadata.startedFrom(from: metadata)
        let brandName = metadata?[HKMetadataKeyWorkoutBrandName] as? String
        let isPulsarWorkout = sessionId != nil ||
            workoutType != nil ||
            brandName?.localizedCaseInsensitiveCompare(PulsarWorkoutMetadata.brandName) == .orderedSame

        return (sessionId, workoutType, startedFrom, isPulsarWorkout)
    }

    nonisolated private static func activeEnergyKilocalories(for workout: HKWorkout) -> Double? {
        guard let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return nil }
        return workout.statistics(for: activeEnergyType)?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())
    }

    nonisolated private static func distanceMeters(for route: GPSWorkoutRoute?) -> Double? {
        guard let points = route?.points, points.count > 1 else { return nil }
        var distance = 0.0
        var previousLocation: CLLocation?
        for point in points {
            let location = CLLocation(
                coordinate: point.coordinate,
                altitude: point.altitude ?? 0,
                horizontalAccuracy: point.horizontalAccuracy ?? -1,
                verticalAccuracy: point.verticalAccuracy ?? -1,
                timestamp: point.timestamp
            )
            if let previousLocation {
                distance += max(0, location.distance(from: previousLocation))
            }
            previousLocation = location
        }
        return distance > 0 ? distance : nil
    }

    nonisolated private static func splitEstimates(from route: GPSWorkoutRoute?) -> [FitnessWorkoutSplit] {
        guard let points = route?.points, points.count > 1 else { return [] }
        var splits: [FitnessWorkoutSplit] = []
        var previousLocation: CLLocation?
        var cumulativeDistance = 0.0
        var splitStartDistance = 0.0
        var splitStartTime = points.first?.timestamp ?? Date()

        for point in points {
            let location = CLLocation(
                coordinate: point.coordinate,
                altitude: point.altitude ?? 0,
                horizontalAccuracy: point.horizontalAccuracy ?? -1,
                verticalAccuracy: point.verticalAccuracy ?? -1,
                timestamp: point.timestamp
            )
            if let previousLocation {
                cumulativeDistance += max(0, location.distance(from: previousLocation))
            }
            previousLocation = location

            while cumulativeDistance - splitStartDistance >= 1_000 {
                let movingTime = max(0, point.timestamp.timeIntervalSince(splitStartTime))
                splits.append(
                    FitnessWorkoutSplit(
                        index: splits.count + 1,
                        distanceMeters: 1_000,
                        movingTime: movingTime,
                        paceSecondsPerKilometer: movingTime > 0 ? movingTime : nil,
                        averageHeartRate: nil
                    )
                )
                splitStartDistance += 1_000
                splitStartTime = point.timestamp
            }
        }

        return splits
    }

    nonisolated private static func isRouteActivity(_ activityType: HKWorkoutActivityType) -> Bool {
        switch activityType {
        case .running, .walking, .hiking, .cycling:
            return true
        default:
            return false
        }
    }

    nonisolated private func fitnessCategory(for activityType: HKWorkoutActivityType) -> WeeklyActivityCategory {
        switch activityType {
        case .running: return .running
        case .walking: return .walking
        case .hiking: return .hiking
        case .cycling: return .cycling
        case .traditionalStrengthTraining, .functionalStrengthTraining, .crossTraining: return .strength
        case .highIntensityIntervalTraining: return .hiit
        case .yoga, .mindAndBody: return .yoga
        case .swimming, .waterFitness, .waterPolo: return .swimming
        case .rowing: return .rowing
        case .dance, .socialDance, .cardioDance: return .dance
        case .flexibility, .preparationAndRecovery, .cooldown: return .recovery
        default: return .other
        }
    }
}

enum HealthKitGatewayError: Error {
    case healthDataUnavailable
    case authorizationDenied
}

extension HealthKitGateway {
    static var requiredReadTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .heartRateVariabilitySDNN,
            .restingHeartRate,
            .walkingHeartRateAverage,
            .respiratoryRate,
            .heartRate,
            .oxygenSaturation,
            .appleSleepingWristTemperature,
            .stepCount,
            .appleExerciseTime,
            .activeEnergyBurned,
            .basalEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .bodyMass,
            .height
        ]
        quantityIdentifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) }.forEach { types.insert($0) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        types.insert(HKObjectType.workoutType())
        types.insert(HKSeriesType.workoutRoute())
        types.insert(HKObjectType.characteristicType(forIdentifier: .biologicalSex)!)
        types.insert(HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!)
        return types
    }

    static var incrementalSampleTypes: [HKSampleType] {
        var types: [HKSampleType] = []
        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .heartRateVariabilitySDNN,
            .restingHeartRate,
            .walkingHeartRateAverage,
            .respiratoryRate,
            .heartRate,
            .oxygenSaturation,
            .appleSleepingWristTemperature,
            .stepCount,
            .appleExerciseTime,
            .activeEnergyBurned,
            .basalEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .bodyMass,
            .height
        ]
        types.append(contentsOf: quantityIdentifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) })
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.append(sleep) }
        types.append(HKObjectType.workoutType())
        return types
    }
}

private extension HKWorkoutActivityType {
    nonisolated var fitnessDisplayName: String {
        switch self {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .traditionalStrengthTraining: return "Strength"
        case .functionalStrengthTraining: return "Functional Strength"
        case .crossTraining: return "Gym"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .highIntensityIntervalTraining: return "HIIT"
        case .rowing: return "Rowing"
        case .dance, .socialDance, .cardioDance: return "Dance"
        case .flexibility: return "Mobility"
        case .preparationAndRecovery, .cooldown: return "Recovery"
        default: return "Workout"
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .running: return "Run"
        case .cycling: return "Ride"
        case .walking: return "Walk"
        case .traditionalStrengthTraining: return "Strength"
        case .functionalStrengthTraining: return "Functional Strength"
        case .swimming: return "Swim"
        case .hiking: return "Hike"
        case .yoga: return "Yoga"
        case .highIntensityIntervalTraining: return "HIIT"
        default: return "Workout"
        }
    }
}
