import SwiftUI

struct SleepBalanceStageValuesColumn: View {
    var rows: [StageMetric]

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: 18)

            ForEach(rows) { row in
                GeometryReader { geometry in
                    let width = geometry.size.width

                    Circle()
                        .fill(SleepStageVisualStyle.color(for: row.stage))
                        .frame(width: 6, height: 6)
                        .frame(width: width * 0.08, height: 30)

                    Text(SleepStageVisualStyle.displayName(for: row.stage))
                        .pulsarTextStyle(.metadata)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(width: width * 0.27, height: 30, alignment: .leading)
                        .position(x: width * 0.215, y: 15)

                    Text(SleepDetailsViewModel.durationText(minutes: row.minutes))
                        .pulsarTextStyle(.metadata)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(width: width * 0.32, height: 30, alignment: .leading)
                        .position(x: width * 0.54, y: 15)

                    Text(
                        row.stage.isSleep
                            ? SleepDetailsViewModel.percentText(row.percentOfSleep)
                            : "–"
                    )
                    .pulsarTextStyle(.metadata)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(width: width * 0.26, height: 30, alignment: .trailing)
                    .position(x: width * 0.87, y: 15)
                }
                .frame(height: 30)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
