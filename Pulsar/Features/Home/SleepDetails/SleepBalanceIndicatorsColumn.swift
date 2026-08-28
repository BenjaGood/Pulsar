import SwiftUI

struct SleepBalanceIndicatorsColumn: View {
    var rows: [StageMetric]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Low")
                Spacer()
                Text("Ideal")
                Spacer()
                Text("High")
            }
            .pulsarTextStyle(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(height: 18)

            ForEach(rows) { row in
                SleepBalanceIndicator(
                    stage: row.stage,
                    percent: row.percentOfSleep,
                    minutes: row.minutes
                )
                .frame(height: 30)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
