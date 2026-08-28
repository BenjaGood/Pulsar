import SwiftUI

struct MovementSummaryHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var steps: Int
    var goal: Int

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    MovementValueSummary(steps: steps)
                    MovementGoalSummary(goal: goal, horizontal: true)
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    MovementValueSummary(steps: steps)

                    Spacer(minLength: 8)

                    MovementGoalSummary(goal: goal, horizontal: false)
                }
            }
        }
    }
}
