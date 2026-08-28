//
//  SettingsProfileCard.swift
//  Pulsar
//

import SwiftUI

struct SettingsProfileCard: View {
    var profile: UserProfile

    var body: some View {
        HStack(spacing: 16) {
            AvatarView(profile: profile, size: 68)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(displayName)
                    .font(.title3)
                    .bold()
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text("Pulsar Profile")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.right")
                .font(.subheadline)
                .bold()
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulsarSettingsCardSurface(cornerRadius: 26, interactive: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayName), Pulsar Profile")
        .accessibilityHint("Opens personal information")
    }

    private var displayName: String {
        let trimmed = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Set up your profile" : trimmed
    }
}
