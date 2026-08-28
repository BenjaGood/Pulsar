import SwiftUI

struct SleepBalanceAccessibleStageList: View {
    var rows: [StageMetric]

    var body: some View {
        VStack(spacing: 18) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(SleepStageVisualStyle.color(for: row.stage))
                            .frame(width: 9, height: 9)

                        Text(SleepStageVisualStyle.displayName(for: row.stage))
                            .pulsarTextStyle(.body)

                        Spacer(minLength: 8)

                        Text(SleepDetailsViewModel.durationText(minutes: row.minutes))
                            .pulsarTextStyle(.body)
                            .monospacedDigit()

                        if row.stage.isSleep {
                            Text(SleepDetailsViewModel.percentText(row.percentOfSleep))
                                .pulsarTextStyle(.metadata)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Spacer()

                        VStack(spacing: 2) {
                            HStack {
                                Text("Low")
                                Spacer()
                                Text("Ideal")
                                Spacer()
                                Text("High")
                            }
                            .pulsarTextStyle(.metadata)
                            .foregroundStyle(.tertiary)

                            SleepBalanceIndicator(
                                stage: row.stage,
                                percent: row.percentOfSleep,
                                minutes: row.minutes
                            )
                            .frame(width: 180)
                        }
                        .frame(width: 180)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
