import SwiftUI

struct SleepBalanceRing: View {
    var totalSleepText: String
    var rows: [StageMetric]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var ringProgress: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.08), lineWidth: 8)

            ForEach(rows.indices, id: \.self) { index in
                let start = startFraction(for: index)
                let fraction = stageFraction(at: index)
                let animatedEnd = start + (fraction * ringProgress)
                let visibleStart = min(start + 0.004, animatedEnd)

                Circle()
                    .trim(from: visibleStart, to: animatedEnd)
                    .stroke(
                        SleepStageVisualStyle.color(for: rows[index].stage),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 5) {
                Text(totalSleepText)
                    .font(.system(.title3, design: .default, weight: .light))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.30)
                    .frame(width: centerTextWidth)

                Text("Total Sleep")
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .frame(width: centerTextWidth)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: diameter, maxHeight: diameter)
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.86),
            value: ringProgress
        )
        .task { ringProgress = 1 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep balance")
        .accessibilityValue(totalSleepText)
    }

    private var stageTotal: Double {
        max(1, rows.reduce(0) { $0 + $1.minutes })
    }

    private var diameter: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 180 : 116
    }

    private var centerTextWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 154 : 98
    }

    private func startFraction(for index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        let elapsed = rows[..<index].reduce(0) { $0 + $1.minutes }
        return CGFloat(elapsed / stageTotal)
    }

    private func stageFraction(at index: Int) -> CGFloat {
        CGFloat(rows[index].minutes / stageTotal)
    }
}
