import SwiftUI

struct StressSignalStatusIcon: View {
    var availability: StressSignalAvailability

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Image(systemName: symbol)
            .font(.subheadline)
            .bold()
            .foregroundStyle(tint)
            .frame(width: 42, height: 42)
            .background(tint.opacity(0.07), in: Circle())
            .glassEffect(
                reduceTransparency ? .identity : .clear.tint(tint.opacity(0.08)),
                in: .circle
            )
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch availability {
        case .available:
            "checkmark"
        case .limited:
            "clock.fill"
        case .unavailable:
            "minus"
        }
    }

    private var tint: Color {
        switch availability {
        case .available:
            Color(red: 0.20, green: 0.64, blue: 0.43)
        case .limited:
            Color(red: 0.84, green: 0.56, blue: 0.18)
        case .unavailable:
            Color(red: 0.48, green: 0.52, blue: 0.59)
        }
    }
}
