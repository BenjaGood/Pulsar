//
//  ProfileHeader.swift
//  Pulsar
//

import SwiftUI

struct ProfileHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 10 : 6) {
            Text("Profile")
                .font(.largeTitle)
                .bold()
                .foregroundStyle(.primary)

            Text("Manage your personal details to improve your insights.")
                .font(dynamicTypeSize.isAccessibilitySize ? .body : .subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
