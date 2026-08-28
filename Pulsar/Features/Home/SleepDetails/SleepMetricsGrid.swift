import SwiftUI

struct SleepMetricsGrid: View {
    var metrics: [SleepMetricTileModel]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LazyVGrid(
            columns: columns,
            spacing: 12
        ) {
            ForEach(metrics) { metric in
                SleepMetricTile(
                    metric: metric,
                    isEmphasized: metric.title == "Efficiency"
                        || metric.title == "Awakenings"
                )
            }
        }
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            [GridItem(.flexible())]
        } else {
            [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]
        }
    }
}

#Preview("Sleep Metrics") {
    SleepMetricsGrid(
        metrics: [
            SleepMetricTileModel(
                title: "Efficiency",
                value: "97%",
                subtitle: "Sleep / in bed"
            ),
            SleepMetricTileModel(
                title: "Awakenings",
                value: "5",
                subtitle: "During sleep"
            ),
            SleepMetricTileModel(
                title: "Sleep Start",
                value: "23:20",
                subtitle: nil
            ),
            SleepMetricTileModel(
                title: "Wake Time",
                value: "07:47",
                subtitle: nil
            )
        ]
    )
    .padding()
    .background(SleepDetailsBackground())
}
