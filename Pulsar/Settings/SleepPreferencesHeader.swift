import SwiftUI

struct SleepPreferencesHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 10 : 7) {
            Text("Sleep")
                .font(.largeTitle)
                .bold()
                .foregroundStyle(.primary)

            Text("Optimize your rest. Improve your recovery.")
                .font(dynamicTypeSize.isAccessibilitySize ? .body : .subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
    }
}
