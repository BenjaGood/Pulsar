//
//  MindfulnessPremiumHeader.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessPremiumHeader: View {
    var streakDays: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let headerLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))

        headerLayout {
            layout {
                Image(systemName: "camera.macro")
                    .font(.title.weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(MindfulnessDesign.primaryText)
                    .frame(width: 52, height: 52)
                    .background {
                        Color.clear
                            .mindfulnessCardSurface(cornerRadius: 26, shadowOpacity: 0.03)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Mindfulness")
                        .pulsarTextStyle(.displayLarge)
                        .foregroundStyle(MindfulnessDesign.primaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)

                    Text("Understand your mind.")
                        .pulsarTextStyle(.label)
                        .foregroundStyle(MindfulnessDesign.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Mindfulness. Understand your mind.")
            .accessibilityAddTraits(.isHeader)

            MindfulnessStreakStatusCapsule(dayCount: streakDays)
        }
    }
}
