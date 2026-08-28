import SwiftUI

struct MovementSummaryCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var steps: Int
    var goal: Int
    var progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MovementSummaryHeader(steps: steps, goal: goal)

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(StrainDetailsDesign.movementTeal)
                .scaleEffect(x: 1, y: 2.2)
                .clipShape(Capsule())

            Text(progressDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(height: dynamicTypeSize.isAccessibilitySize ? nil : 110)
        .strainCardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(steps.formatted()) steps, goal \(goal.formatted()) steps"
        )
        .accessibilityValue(progressDescription)
    }

    private var progressDescription: String {
        guard goal > 0 else { return "No step goal set" }
        return "\(Int((progress * 100).rounded()))% of your step goal"
    }
}
