import SwiftUI

struct DataPrivacyHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 10 : 6) {
            Text("Data & Privacy")
                .font(.largeTitle)
                .bold()
                .foregroundStyle(.primary)

            Text("Manage how Pulsar uses and protects your data.")
                .font(dynamicTypeSize.isAccessibilitySize ? .body : .subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
