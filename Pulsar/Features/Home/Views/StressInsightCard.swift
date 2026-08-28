import SwiftUI

struct StressInsightCard: View {
    var insight: StressInsight

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text(insight.title)
                    .pulsarTextStyle(.insightHeadline)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: insight.symbol)
                    .font(.body)
                    .bold()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.07), in: .circle)
                    .glassEffect(
                        reduceTransparency ? .identity : .clear.tint(tint.opacity(0.06)),
                        in: .circle
                    )
                    .accessibilityHidden(true)
            }

            Text(insight.description)
                .pulsarTextStyle(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(StressDetailsDesign.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stressInsightCardSurface()
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch insight.tone {
        case .calm:
            Color(red: 0.24, green: 0.58, blue: 0.42)
        case .recovery:
            Color(red: 0.40, green: 0.38, blue: 0.68)
        case .movement:
            Color(red: 0.34, green: 0.48, blue: 0.58)
        case .signal:
            Color(red: 0.39, green: 0.46, blue: 0.55)
        case .caution:
            Color(red: 0.72, green: 0.45, blue: 0.21)
        case .neutral:
            .secondary
        }
    }
}
