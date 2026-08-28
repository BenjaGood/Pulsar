//
//  ProfileInfoFooterCard.swift
//  Pulsar
//

import SwiftUI

struct ProfileInfoFooterCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsIcon(symbol: "shield", tint: .black, size: 40)
                    informationText
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    SettingsIcon(symbol: "shield", tint: .black, size: 40)
                    informationText
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulsarSettingsCardSurface(cornerRadius: 22)
    }

    private var informationText: some View {
        Text("Used to personalize estimates. Pulsar is not a diagnostic medical device.")
        .font(dynamicTypeSize.isAccessibilitySize ? .subheadline : .footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Profile Information Footer") {
    ProfileInfoFooterCard()
        .padding(24)
        .background(PulsarSettingsBackground())
}
