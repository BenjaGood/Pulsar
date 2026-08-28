//
//  GymSettingsHeader.swift
//  Pulsar
//

import SwiftUI

struct GymSettingsHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 12 : 10) {
            Text("Gym")
                .font(.largeTitle)
                .bold()
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Text("Configure how the app measures and displays your gym data.")
                .font(dynamicTypeSize.isAccessibilitySize ? .body : .title3)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
