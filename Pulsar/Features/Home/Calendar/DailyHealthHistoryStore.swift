//
//  DailyHealthHistoryStore.swift
//  Pulsar
//

import Foundation

struct DailyHealthHistoryStore {
    private final class State {
        var records: [DailyStrainRecord]

        init(records: [DailyStrainRecord]) {
            self.records = records
        }
    }

    private let recordsKey = "pulsar.calendar.dailyHealthRecords.v1"
    private let fileCache: PulsarSyncPayloadFileCache
    private let state: State

    init(
        defaults: UserDefaults = .standard,
        fileCache: PulsarSyncPayloadFileCache = .shared
    ) {
        self.fileCache = fileCache
        let data = fileCache.migrateLegacyData(
            from: defaults,
            key: recordsKey,
            to: .dailyHealthHistory,
            validating: { (try? JSONDecoder().decode([DailyStrainRecord].self, from: $0)) != nil }
        )
        self.state = State(records: data.flatMap { try? JSONDecoder().decode([DailyStrainRecord].self, from: $0) } ?? [])
    }

    func loadRecords(calendar: Calendar = .current) -> [DailyStrainRecord] {
        normalized(state.records, calendar: calendar)
    }

    @discardableResult
    func upsert(_ record: DailyStrainRecord, calendar: Calendar = .current) -> [DailyStrainRecord] {
        upsert([record], calendar: calendar)
    }

    @discardableResult
    func upsert(_ incomingRecords: [DailyStrainRecord], calendar: Calendar = .current) -> [DailyStrainRecord] {
        let incoming = incomingRecords.filter(\.hasRecordedData)
        guard !incoming.isEmpty else { return loadRecords(calendar: calendar) }

        var recordsByKey: [String: DailyStrainRecord] = [:]
        for record in loadRecords(calendar: calendar) {
            recordsByKey[record.dateKey] = recordsByKey[record.dateKey].map { $0.merged(with: record, calendar: calendar) } ?? record
        }
        for record in incoming {
            let normalizedRecord = DailyStrainRecord(
                date: calendar.startOfDay(for: record.date),
                dateKey: record.dateKey,
                calendar: calendar,
                sleepScore: record.sleepScore,
                sleepMinutes: record.sleepMinutes,
                recoveryScore: record.recoveryScore,
                stressScore: record.stressScore,
                stressTimelineSamples: record.stressTimelineSamples,
                strainScore: record.strainScore,
                respiratoryRate: record.respiratoryRate,
                respiratoryRateStatus: record.respiratoryRateStatus,
                restingHeartRate: record.restingHeartRate,
                restingHeartRateStatus: record.restingHeartRateStatus,
                hrv: record.hrv,
                hrvStatus: record.hrvStatus,
                oxygenSaturation: record.oxygenSaturation,
                oxygenSaturationStatus: record.oxygenSaturationStatus,
                wristTemperatureDeviation: record.wristTemperatureDeviation,
                wristTemperatureStatus: record.wristTemperatureStatus,
                sleepDurationStatus: record.sleepDurationStatus,
                workoutMinutes: record.workoutMinutes,
                steps: record.steps,
                activeEnergyKilocalories: record.activeEnergyKilocalories,
                confidence: record.confidence,
                sourceName: record.sourceName,
                syncedAt: record.syncedAt
            )
            recordsByKey[normalizedRecord.dateKey] = recordsByKey[normalizedRecord.dateKey]
                .map { $0.merged(with: normalizedRecord, calendar: calendar) } ?? normalizedRecord
        }

        let records = normalized(Array(recordsByKey.values), calendar: calendar)
        save(records)
        return records
    }

    private func save(_ records: [DailyStrainRecord]) {
        state.records = records
        let revision = DispatchTime.now().uptimeNanoseconds
        Task {
            _ = await fileCache.save(records, for: .dailyHealthHistory, revision: revision)
        }
    }

    private func normalized(_ records: [DailyStrainRecord], calendar: Calendar) -> [DailyStrainRecord] {
        let normalizedRecords = records
            .filter(\.hasRecordedData)
            .map { record in
                DailyStrainRecord(
                    date: calendar.startOfDay(for: record.date),
                    dateKey: record.dateKey,
                    calendar: calendar,
                    sleepScore: record.sleepScore,
                    sleepMinutes: record.sleepMinutes,
                    recoveryScore: record.recoveryScore,
                    stressScore: record.stressScore,
                    stressTimelineSamples: record.stressTimelineSamples,
                    strainScore: record.strainScore,
                    respiratoryRate: record.respiratoryRate,
                    respiratoryRateStatus: record.respiratoryRateStatus,
                    restingHeartRate: record.restingHeartRate,
                    restingHeartRateStatus: record.restingHeartRateStatus,
                    hrv: record.hrv,
                    hrvStatus: record.hrvStatus,
                    oxygenSaturation: record.oxygenSaturation,
                    oxygenSaturationStatus: record.oxygenSaturationStatus,
                    wristTemperatureDeviation: record.wristTemperatureDeviation,
                    wristTemperatureStatus: record.wristTemperatureStatus,
                    sleepDurationStatus: record.sleepDurationStatus,
                    workoutMinutes: record.workoutMinutes,
                    steps: record.steps,
                    activeEnergyKilocalories: record.activeEnergyKilocalories,
                    confidence: record.confidence,
                    sourceName: record.sourceName,
                    syncedAt: record.syncedAt
                )
            }
        var recordsByKey: [String: DailyStrainRecord] = [:]
        for record in normalizedRecords {
            recordsByKey[record.dateKey] = recordsByKey[record.dateKey].map { $0.merged(with: record, calendar: calendar) } ?? record
        }
        return recordsByKey.values
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.syncedAt < rhs.syncedAt
                }
                return lhs.date < rhs.date
            }
    }
}
