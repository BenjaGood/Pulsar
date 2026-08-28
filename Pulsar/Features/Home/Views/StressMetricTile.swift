import SwiftUI

struct StressMetricTile: View {
    var title: String
    var value: String
    var interpretation: String
    var symbol: String
    var statusColor: Color? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(iconColor)
                .frame(width: 34, height: 34)
                .background(iconColor.opacity(0.055), in: Circle())
                .glassEffect(reduceTransparency ? .identity : .clear, in: .circle)
                .accessibilityHidden(true)

            Text(title)
                .font(.caption)
                .fontWidth(.condensed)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 30, alignment: .topLeading)

            Text(value)
                .font(.system(.title3, design: .default, weight: .medium))
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.64)

            Label(interpretation, systemImage: statusColor == nil ? "minus" : "circle.fill")
                .font(.caption)
                .foregroundStyle(statusColor ?? .secondary)
                .imageScale(.small)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .background(tileFill, in: .rect(cornerRadius: StressDetailsDesign.tileCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: StressDetailsDesign.tileCornerRadius)
                .stroke(.white.opacity(colorScheme == .dark ? 0.10 : 0.72), lineWidth: 0.7)
        }
        .glassEffect(
            reduceTransparency ? .identity : .clear,
            in: .rect(cornerRadius: StressDetailsDesign.tileCornerRadius)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.08 : 0.025), radius: 12, y: 5)
        .accessibilityElement(children: .combine)
    }

    private var iconColor: Color {
        statusColor ?? StressDetailsDesign.neutralIcon
    }

    private var valueColor: Color {
        statusColor ?? .primary
    }

    private var tileFill: Color {
        if colorScheme == .dark {
            return reduceTransparency ? Color(red: 31 / 255, green: 31 / 255, blue: 35 / 255) : .white.opacity(0.035)
        }

        return reduceTransparency ? .white : .white.opacity(0.72)
    }
}
