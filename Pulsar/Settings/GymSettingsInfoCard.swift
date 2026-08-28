//
//  GymSettingsInfoCard.swift
//  Pulsar
//

import SwiftUI

struct GymSettingsInfoCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 18) {
                    icon
                    copy
                }
            } else {
                HStack(alignment: .center, spacing: 20) {
                    icon
                    copy
                }
            }
        }
        .padding(GymSettingsDesign.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gymSettingsCardSurface()
        .accessibilityElement(children: .combine)
    }

    private var icon: some View {
        Image(systemName: "dumbbell.fill")
            .font(.largeTitle)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(SettingsMonochromeDesign.primary)
            .frame(width: 84, height: 84)
            .background(GymSettingsDesign.iconGradient, in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(SettingsMonochromeDesign.border, lineWidth: 0.75)
            }
            .accessibilityHidden(true)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lifting Units")
                .font(.title3)
                .bold()
                .foregroundStyle(.primary)

            Text("Gym weights can use pounds or kilograms without changing body weight, distance, or other app measurements.")
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
