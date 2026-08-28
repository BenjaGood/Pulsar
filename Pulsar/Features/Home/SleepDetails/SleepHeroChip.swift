import SwiftUI

struct SleepHeroChip: View {
    var title: String
    var symbol: String
    var tint: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .pulsarTextStyle(.metadata)
            .foregroundStyle(.primary)
            .symbolRenderingMode(.hierarchical)
            .tint(tint)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .pulsarLiquidGlass(
                cornerRadius: 18,
                tint: tint.opacity(0.045),
                isClear: true
            )
    }
}
