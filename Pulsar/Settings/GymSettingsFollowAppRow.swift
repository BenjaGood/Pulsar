//
//  GymSettingsFollowAppRow.swift
//  Pulsar
//

import SwiftUI

struct GymSettingsFollowAppRow: View {
    var resolvedUnit: PulsarWeightUnit
    var isSelected: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        icon
                        Spacer(minLength: 12)
                        badge
                    }

                    copy
                }
            } else {
                HStack(spacing: 14) {
                    icon
                    copy
                    Spacer(minLength: 12)
                    badge
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(minHeight: 82)
        .accessibilityElement(children: .combine)
    }

    private var icon: some View {
        Image(systemName: "scalemass.fill")
            .font(.title3)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(SettingsMonochromeDesign.primary)
            .frame(width: 48, height: 48)
            .accessibilityHidden(true)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Follow App Units")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Currently resolves to \(resolvedUnit.displayName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var badge: some View {
        Text(resolvedUnit.displayName)
            .font(.subheadline)
            .bold()
            .foregroundStyle(SettingsMonochromeDesign.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                SettingsMonochromeDesign.subtleFill,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(SettingsMonochromeDesign.border, lineWidth: 0.75)
            }
    }
}
