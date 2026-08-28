//
//  StressSignalRow.swift
//  Pulsar
//

import SwiftUI

struct StressSignalRow: View {
    var signal: StressSignal

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                regularLayout
            }
        }
        .padding(.vertical, 17)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(displayTitle)
        .accessibilityValue("\(displayValue). \(statusText). \(explanation)")
    }

    private var regularLayout: some View {
        HStack(spacing: 14) {
            statusIcon

            LabeledContent {
                valueAndStatus(alignment: .trailing)
            } label: {
                titleAndExplanation
            }
        }
    }

    private var accessibilityLayout: some View {
        HStack(alignment: .top, spacing: 14) {
            statusIcon

            VStack(alignment: .leading, spacing: 12) {
                titleAndExplanation
                valueAndStatus(alignment: .leading)
            }
        }
    }

    private var statusIcon: some View {
        StressSignalStatusIcon(availability: signal.availability)
    }

    private var titleAndExplanation: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayTitle)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
        }
    }

    private func valueAndStatus(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(displayValue)
                .font(.title3)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.70)

            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var displayTitle: String {
        switch signal.id {
        case "hrv":
            "HRV"
        case "heart-rate":
            "Heart rate"
        case "resting-heart-rate":
            "Resting heart rate"
        case "respiratory-rate":
            "Respiratory rate"
        case "sleep-duration":
            "Sleep duration"
        case "non-activity-stress":
            "Non-activity stress"
        case "activity-adjusted-stress":
            "Activity-adjusted stress"
        case "movement-state":
            "Movement state"
        case "recent-load":
            "Recent strain/load"
        default:
            signal.title
        }
    }

    private var explanation: String {
        let context = switch signal.id {
        case "hrv": "Latest recovery HRV"
        case "heart-rate": "Current heart rate"
        case "resting-heart-rate": "Resting heart rate"
        case "respiratory-rate": "Respiratory rate"
        case "sleep-duration": "Recent sleep duration"
        case "non-activity-stress": "Inactive-only estimate"
        case "activity-adjusted-stress": "Movement adjusted estimate"
        case "movement-state": "Current movement context"
        case "recent-load": "Recent workout load"
        default: signal.title
        }

        guard let baseline = signal.baseline,
              !baseline.isEmpty,
              baseline.localizedCaseInsensitiveCompare(context) != .orderedSame else {
            return context
        }

        return "\(context) · \(baseline)"
    }

    private var displayValue: String {
        signal.value.replacing("breaths/min", with: "br/min")
    }

    private var statusText: String {
        switch signal.availability {
        case .available:
            "Available"
        case .limited:
            "Limited"
        case .unavailable:
            "Missing"
        }
    }
}
