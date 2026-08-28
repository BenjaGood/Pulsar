//
//  MeasurementBMICard.swift
//  Pulsar
//

import SwiftUI

struct MeasurementBMICard: View {
    var value: Double
    var status: MeasurementBMIStatus

    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "figure")
                    .font(.system(size: 22))
                    .bold()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(MeasurementsDesign.accent)
                    .frame(width: 50, height: 50)
                    .background(MeasurementsDesign.accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("BMI")
                        .font(.headline)
                        .bold()

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(value, format: .number.precision(.fractionLength(1)))
                            .font(.system(size: valueSize, weight: .regular))
                            .foregroundStyle(.primary)

                        HealthStatusBadge(text: status.label, tint: status.tint)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            Text("A screening estimate based on height and weight.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .measurementsCardSurface()
        .accessibilityElement(children: .combine)
    }
}

#Preview("BMI Insight") {
    MeasurementBMICard(
        value: 30.9,
        status: .obese
    )
    .padding(20)
    .background(MeasurementsDesign.background)
}
