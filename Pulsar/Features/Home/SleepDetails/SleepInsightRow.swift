import SwiftUI

struct SleepInsightRow: View {
    var text: String
    var symbol: String
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.08), in: Circle())
                .accessibilityHidden(true)

            Text(text)
                .pulsarTextStyle(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
