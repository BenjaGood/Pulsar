//
//  MindfulnessHistoryChevronButton.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessHistoryChevronButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.body)
            .foregroundStyle(MindfulnessDesign.primaryText)
            .frame(
                width: MindfulnessDesign.historyControlSize,
                height: MindfulnessDesign.historyControlSize
            )
            .mindfulnessCardSurface(
                cornerRadius: 18,
                isInteractive: true,
                shadowOpacity: 0.018
            )
            .buttonStyle(.plain)
    }
}
