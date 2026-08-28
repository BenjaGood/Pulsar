//
//  MeasurementSourcesCard.swift
//  Pulsar
//

import SwiftUI

struct MeasurementSourcesCard: View {
    @Binding var bodyMassSource: ProfileValueSource
    @Binding var heightSource: ProfileValueSource
    var lastUpdated: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var feedbackSequence = 0

    var body: some View {
        VStack(spacing: 0) {
            if bodyMassSource == heightSource {
                MeasurementSourceRow(
                    source: bodyMassSource,
                    caption: "Primary Source",
                    selectSource: selectBothSources,
                    selectHeightSource: selectHeightSource,
                    selectWeightSource: selectWeightSource
                )
                .transition(.opacity)
            } else {
                MeasurementSourceRow(
                    source: heightSource,
                    caption: "Height Source",
                    menuSectionTitle: "Height",
                    selectSource: selectHeightSource
                )

                Divider()
                    .padding(.leading, 72)
                    .padding(.trailing, 16)

                MeasurementSourceRow(
                    source: bodyMassSource,
                    caption: "Weight Source",
                    menuSectionTitle: "Weight",
                    selectSource: selectWeightSource
                )
                .transition(.opacity)
            }

            Divider()
                .padding(.horizontal, 16)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Text("Last updated")
                    Spacer(minLength: 12)
                    Text(formattedLastUpdated)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Last updated")
                    Text(formattedLastUpdated)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .measurementsCardSurface()
        .animation(
            reduceMotion ? .easeOut(duration: 0.16) : MeasurementsDesign.spring,
            value: bodyMassSource == heightSource
        )
        .sensoryFeedback(.selection, trigger: feedbackSequence)
    }

    private var formattedLastUpdated: String {
        guard let lastUpdated else { return "Not saved yet" }

        let date = lastUpdated.formatted(
            Date.FormatStyle()
                .day()
                .month(.abbreviated)
                .year()
                .locale(Locale(identifier: "en_GB"))
        )
        let time = lastUpdated.formatted(
            Date.FormatStyle()
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .locale(Locale(identifier: "en_GB"))
        )

        return "\(date) • \(time)"
    }

    private func selectBothSources(_ source: ProfileValueSource) {
        guard bodyMassSource != source || heightSource != source else { return }
        bodyMassSource = source
        heightSource = source
        feedbackSequence += 1
    }

    private func selectHeightSource(_ source: ProfileValueSource) {
        guard heightSource != source else { return }
        heightSource = source
        feedbackSequence += 1
    }

    private func selectWeightSource(_ source: ProfileValueSource) {
        guard bodyMassSource != source else { return }
        bodyMassSource = source
        feedbackSequence += 1
    }
}

#Preview("Single Source") {
    MeasurementSourcesCard(
        bodyMassSource: .constant(.healthKit),
        heightSource: .constant(.healthKit),
        lastUpdated: .now
    )
    .padding(20)
    .background(MeasurementsDesign.background)
}
