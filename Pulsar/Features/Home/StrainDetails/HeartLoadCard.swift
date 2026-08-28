import SwiftUI

struct HeartLoadCard: View {
    var chart: StrainHeartLoadChartModel
    var peakHeartRate: Double?
    var averageActiveHeartRate: Double?
    var restingHeartRate: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeartLoadHeader()

            HeartMetricsRow(
                peakHeartRate: peakHeartRate,
                averageActiveHeartRate: averageActiveHeartRate,
                restingHeartRate: restingHeartRate
            )

            HeartLoadChart(chart: chart)
        }
        .padding(16)
        .strainCardSurface()
        .accessibilityElement(children: .contain)
    }
}
