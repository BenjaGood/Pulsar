import SwiftUI

struct StrainLoadPill: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)
                .overlay {
                    Circle().stroke(.primary.opacity(0.16), lineWidth: 1)
                }

            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 3)

            Text(value)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.42), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
    }
}
