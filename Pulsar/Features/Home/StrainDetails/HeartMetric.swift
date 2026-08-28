import SwiftUI

struct HeartMetric: View {
    @ScaledMetric(relativeTo: .title2) private var valueSize = 25.0

    var title: String
    var value: Double?
    var symbol: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label {
                Text(title)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
            }
                .font(.caption)
                .symbolRenderingMode(.monochrome)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(valueText)
                    .font(.system(size: valueSize, weight: .regular, design: .serif))
                    .monospacedDigit()
                    .lineLimit(1)

                if value != nil {
                    Text("bpm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            value.map {
                "\(title), \(Int($0.rounded())) beats per minute"
            } ?? "\(title), unavailable"
        )
    }

    private var valueText: String {
        value.map { "\(Int($0.rounded()))" } ?? "—"
    }
}
