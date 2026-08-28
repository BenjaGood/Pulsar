import SwiftUI

struct SleepMetricTile: View {
    var metric: SleepMetricTileModel
    var isEmphasized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(metric.title)
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Image(systemName: symbol)
                    .font(.footnote)
                    .foregroundStyle(tint.opacity(0.68))
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
            }

            Text(metric.value)
                .font(
                    isEmphasized
                        ? .system(.title, design: .default, weight: .light)
                        : .system(.title2, design: .default, weight: .light)
                )
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if isEmphasized, let subtitle = metric.subtitle {
                Text(subtitle)
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(SleepDetailsDesign.cardPadding)
        .frame(
            maxWidth: .infinity,
            minHeight: isEmphasized ? 124 : 104,
            alignment: .topLeading
        )
        .sleepCardSurface()
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch metric.title {
        case "Efficiency":
            "gauge.with.dots.needle.50percent"
        case "Awakenings":
            "waveform.path.ecg"
        case "Sleep Start":
            "moon.fill"
        case "Wake Time":
            "sun.max.fill"
        default:
            "moon.stars.fill"
        }
    }

    private var tint: Color {
        switch metric.title {
        case "Efficiency":
            .green
        case "Wake Time":
            SleepDetailsDesign.awake
        default:
            SleepDetailsDesign.deep
        }
    }
}
