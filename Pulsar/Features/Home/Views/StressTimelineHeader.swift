import SwiftUI

struct StressTimelineHeader: View {
    var datePhrase: String
    var statusText: String
    var tint: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    copy
                    statusPill
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    copy
                    Spacer(minLength: 8)
                    statusPill
                }
            }
        }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Daily Stress Timeline")
                .font(.title2)
                .bold()
                .accessibilityAddTraits(.isHeader)

            Text("How your physiological load moved \(datePhrase)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statusPill: some View {
        Label {
            Text(statusText)
        } icon: {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
        }
        .font(.subheadline)
        .foregroundStyle(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.74)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.06), in: Capsule())
        .glassEffect(reduceTransparency ? .identity : .clear, in: .capsule)
    }
}
