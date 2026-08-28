//
//  MeasurementBMIDetailView.swift
//  Pulsar
//

import SwiftUI

struct MeasurementBMIDetailView: View {
    var value: Double
    var status: MeasurementBMIStatus

    @ScaledMetric(relativeTo: .largeTitle) private var valueSize: CGFloat = 64

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                Image(systemName: "figure")
                    .font(.system(size: 34))
                    .bold()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(MeasurementsDesign.accent)
                    .frame(width: 76, height: 76)
                    .background(MeasurementsDesign.accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 24))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 10) {
                    Text("BMI")
                        .font(.title2)
                        .bold()

                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(value, format: .number.precision(.fractionLength(1)))
                            .font(.system(size: valueSize, weight: .regular))
                            .tracking(-1.5)

                        HealthStatusBadge(text: status.label, tint: status.tint)
                    }
                }

                Text("BMI is a screening measure based on height and weight, not a diagnosis.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MeasurementsDesign.horizontalPadding)
            .padding(.top, 34)
            .padding(.bottom, 44)
        }
        .scrollIndicators(.hidden)
        .background(MeasurementsDesign.background.ignoresSafeArea())
        .navigationTitle("BMI")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .preferredColorScheme(.light)
    }
}
