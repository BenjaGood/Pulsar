import SwiftUI

struct HeartMetricsRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var peakHeartRate: Double?
    var averageActiveHeartRate: Double?
    var restingHeartRate: Double?

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 14))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))

        layout {
            HeartMetric(
                title: "Peak HR",
                value: peakHeartRate,
                symbol: "waveform.path.ecg",
                tint: StrainDetailsDesign.strainOrange
            )

            HeartMetric(
                title: "Avg Active HR",
                value: averageActiveHeartRate,
                symbol: "heart.fill",
                tint: StrainDetailsDesign.strainRed
            )

            HeartMetric(
                title: "Resting HR",
                value: restingHeartRate,
                symbol: "heart",
                tint: StrainDetailsDesign.restingViolet
            )
        }
    }
}
