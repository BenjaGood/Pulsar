//
//  MindfulnessHistoryHeader.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessHistoryHeader: View {
    var month: Date
    var onClose: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))

        layout {
            VStack(alignment: .leading, spacing: 3) {
                Text("Mood History")
                    .pulsarTextStyle(.displayLarge)
                    .foregroundStyle(MindfulnessDesign.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text(month, format: .dateTime.month(.wide).year())
                    .font(.title3)
                    .foregroundStyle(MindfulnessDesign.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Close", systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(MindfulnessDesign.primaryText)
                .frame(
                    width: MindfulnessDesign.historyControlSize,
                    height: MindfulnessDesign.historyControlSize
                )
                .mindfulnessCardSurface(
                    cornerRadius: MindfulnessDesign.historyControlSize / 2,
                    isInteractive: true,
                    shadowOpacity: 0.025
                )
                .buttonStyle(.plain)
                .accessibilityHint("Closes mood history")
                .frame(
                    maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
                    alignment: .trailing
                )
        }
    }
}
