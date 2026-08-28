import SwiftUI

struct MovementGoalSummary: View {
    var goal: Int
    var horizontal: Bool

    var body: some View {
        let layout = horizontal
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(alignment: .trailing, spacing: 6))

        layout {
            Text("Goal \(goal.formatted())")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .fill(StrainDetailsDesign.movementTeal.opacity(0.10))

                Image(systemName: "figure.walk")
                    .font(.title3)
                    .foregroundStyle(StrainDetailsDesign.movementTeal)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)
        }
    }
}
