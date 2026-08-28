//
//  MealScannerTipsPanel.swift
//  Pulsar
//

import SwiftUI

struct MealScannerTipsPanel: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Scanning tips")
                    .pulsarTextStyle(.sectionTitle)
                    .foregroundStyle(.white)

                Spacer(minLength: 12)

                Button("Close tips", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .mealScannerGlassSurface(cornerRadius: 22, isInteractive: true)
                    .buttonStyle(.plain)
            }

            Label("Keep the entire plate visible.", systemImage: "camera.metering.center.weighted")
            Label("Use soft, even light.", systemImage: "sun.max")
            Label("Move slowly during LiDAR capture.", systemImage: "move.3d")
        }
        .font(.subheadline)
        .foregroundStyle(.white)
        .padding(20)
        .mealScannerGlassSurface(cornerRadius: 30)
        .accessibilityElement(children: .contain)
    }
}
