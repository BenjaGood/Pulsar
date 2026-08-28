import SwiftUI

struct SleepBalanceCard: View {
    var totalSleepText: String
    var rows: [StageMetric]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sleep Balance")
                    .pulsarTextStyle(.sectionHeader)
                    .accessibilityAddTraits(.isHeader)

                Text("How much of each stage you got")
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 24) {
                    SleepBalanceRing(
                        totalSleepText: totalSleepText,
                        rows: rows
                    )

                    SleepBalanceAccessibleStageList(rows: rows)
                }
                .frame(maxWidth: .infinity)
            } else {
                SleepBalanceThreeColumnLayout {
                    SleepBalanceRing(
                        totalSleepText: totalSleepText,
                        rows: rows
                    )

                    SleepBalanceStageValuesColumn(rows: rows)

                    SleepBalanceIndicatorsColumn(rows: rows)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, SleepDetailsDesign.cardPadding)
        .sleepCardSurface()
    }
}

#Preview("Sleep Balance") {
    SleepBalanceCard(
        totalSleepText: SleepDetailsViewModel.durationText(
            minutes: MockHealthData.sleepSummary.totalSleepMinutes
        ),
        rows: MockHealthData.sleepSummary.stageBreakdown.filter {
            $0.stage != .inBed
        }
    )
    .padding()
    .background(SleepDetailsBackground())
}
