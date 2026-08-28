//
//  GymFreeWorkoutMetricsCard.swift
//  Pulsar
//

import SwiftUI

struct GymFreeWorkoutMetricsCard: View {
    let currentHeartRate: Double?
    let activeEnergyKilocalories: Double?
    let averageHeartRate: Double?
    let zoneProfile: PulsarHeartRateZoneProfile

    private var zone: PulsarHeartRateZone? {
        zoneProfile.zone(for: currentHeartRate)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            GymFreeWorkoutMetricColumn(
                symbolName: "heart",
                value: PulsarGymFormatters.heartRate(currentHeartRate),
                unit: "BPM",
                accessibilityLabel: "Heart rate"
            )

            metricSeparator

            GymFreeWorkoutMetricColumn(
                symbolName: "flame",
                value: GymFreeWorkoutTelemetry.caloriesText(activeEnergyKilocalories),
                unit: "KCAL",
                accessibilityLabel: "Active energy"
            )

            metricSeparator

            GymFreeWorkoutMetricColumn(
                symbolName: "heart.pulse",
                value: zone.map { "\($0.number)" } ?? "--",
                unit: "ZONE",
                accessibilityLabel: "Heart rate zone",
                accessibilityValue: zoneAccessibilityValue
            ) {
                GymFreeWorkoutZoneIndicator(
                    zones: zoneProfile.zones,
                    activeZoneNumber: zone?.number
                )
            }

            metricSeparator

            GymFreeWorkoutMetricColumn(
                symbolName: "waveform.path.ecg",
                value: PulsarGymFormatters.heartRate(averageHeartRate),
                unit: "AVG",
                accessibilityLabel: "Average heart rate",
                accessibilityValue: averageHeartRateAccessibilityValue
            )
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 6)
        .gymWorkoutWhiteGlassSurface(cornerRadius: 30, shadowOpacity: 0.028)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
    }

    private var metricSeparator: some View {
        Rectangle()
            .fill(PulsarFitnessMonochromeDesign.separator)
            .frame(width: 1)
            .padding(.vertical, 16)
            .accessibilityHidden(true)
    }

    private var zoneAccessibilityValue: String {
        guard let zone else {
            return zoneProfile.maxHeartRate == nil
                ? "Set max heart rate in Settings"
                : "Unavailable"
        }
        return "Zone \(zone.number), \(zone.title)"
    }

    private var averageHeartRateAccessibilityValue: String {
        guard let averageHeartRate, averageHeartRate > 0 else { return "Unavailable" }
        return "\(Int(averageHeartRate.rounded())) beats per minute"
    }
}

private struct GymFreeWorkoutMetricColumn<Accessory: View>: View {
    let symbolName: String
    let value: String
    let unit: String
    let accessibilityLabel: String
    var accessibilityValue: String?
    @ViewBuilder var accessory: () -> Accessory

    init(
        symbolName: String,
        value: String,
        unit: String,
        accessibilityLabel: String,
        accessibilityValue: String? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.symbolName = symbolName
        self.value = value
        self.unit = unit
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.accessory = accessory
    }

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbolName)
                .font(.body.weight(.medium))
                .accessibilityHidden(true)

            Text(value)
                .font(.title2.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            Text(unit)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PulsarFitnessMonochromeDesign.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            accessory()
                .frame(height: 8)
        }
        .foregroundStyle(Color.black)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(resolvedAccessibilityValue)
    }

    private var resolvedAccessibilityValue: String {
        if let accessibilityValue {
            return accessibilityValue
        }
        return value == "--" ? "Unavailable" : "\(value) \(unit)"
    }
}

private extension GymFreeWorkoutMetricColumn where Accessory == EmptyView {
    init(
        symbolName: String,
        value: String,
        unit: String,
        accessibilityLabel: String,
        accessibilityValue: String? = nil
    ) {
        self.init(
            symbolName: symbolName,
            value: value,
            unit: unit,
            accessibilityLabel: accessibilityLabel,
            accessibilityValue: accessibilityValue
        ) {
            EmptyView()
        }
    }
}

private struct GymFreeWorkoutZoneIndicator: View {
    let zones: [PulsarHeartRateZone]
    let activeZoneNumber: Int?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(zones) { zone in
                let isActive = zone.number == activeZoneNumber
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(zone.color.opacity(isActive ? 1 : (activeZoneNumber == nil ? 0.28 : 0.38)))
                    .frame(width: 7, height: isActive ? 8 : 5)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}
