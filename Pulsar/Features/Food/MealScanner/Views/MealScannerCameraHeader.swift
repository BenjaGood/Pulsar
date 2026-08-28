//
//  MealScannerCameraHeader.swift
//  Pulsar
//

import SwiftUI

struct MealScannerCameraHeader: View {
    var currentStep: Int
    var onClose: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 13) {
                Text("3D Meal Scanner")
                    .pulsarTextStyle(.displayMedium)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.62), radius: 6, y: 2)
                    .multilineTextAlignment(.center)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.68)

                VStack(spacing: 10) {
                    Text("STEP \(currentStep) OF 3")
                        .font(.footnote)
                        .tracking(3.4)
                        .foregroundStyle(.white.opacity(0.60))
                        .shadow(color: .black.opacity(0.56), radius: 4, y: 1)

                    HStack(spacing: 6) {
                        ForEach(1...3, id: \.self) { step in
                            Capsule()
                                .fill(.white.opacity(step <= currentStep ? 0.88 : 0.18))
                                .frame(width: 18, height: 3)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 56)
            .padding(.top, dynamicTypeSize.isAccessibilitySize ? 60 : 14)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityElement(children: .combine)

            Button("Close meal scanner", systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.52), radius: 3, y: 1)
                .frame(width: 46, height: 46)
                .mealScannerGlassSurface(cornerRadius: 23, isInteractive: true)
                .buttonStyle(.plain)
                .accessibilityHint("Dismisses the scanner")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

#Preview("Meal scanner header", traits: .fixedLayout(width: 430, height: 220)) {
    ZStack {
        Color.black
        MealScannerCameraHeader(currentStep: 1, onClose: {})
    }
    .preferredColorScheme(.dark)
}
