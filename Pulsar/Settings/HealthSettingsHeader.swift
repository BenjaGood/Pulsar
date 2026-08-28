//
//  HealthSettingsHeader.swift
//  Pulsar
//

import SwiftUI

struct HealthSettingsHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 12 : 14) {
            Text("Health Permissions")
                .font(.largeTitle)
                .bold()
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Text("Pulsar uses data from Apple Health to provide personalized insights about your sleep, recovery, and strain.")
                .font(dynamicTypeSize.isAccessibilitySize ? .body : .title3)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
