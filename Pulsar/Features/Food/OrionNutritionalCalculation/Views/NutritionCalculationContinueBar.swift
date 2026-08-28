//
//  NutritionCalculationContinueBar.swift
//  Pulsar
//

import SwiftUI

struct NutritionCalculationContinueBar: View {
    var title: String
    var isDisabled: Bool
    var showsTrailingChevron = false
    var usesNeutralBackdrop = false
    var emphasizesPrimaryAction = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Label(title, systemImage: "sparkles")
                    .labelStyle(.titleAndIcon)
                    .pulsarTextStyle(.buttonTitle)
                    .foregroundStyle(.white)

                if showsTrailingChevron {
                    HStack {
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.82))
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 22)
                }
            }
            .frame(maxWidth: .infinity, minHeight: emphasizesPrimaryAction ? 62 : 56)
            .contentShape(.capsule)
            .nutritionCalculationGlassSurface(
                cornerRadius: emphasizesPrimaryAction ? 31 : 28,
                isInteractive: true,
                fillColor: emphasizesPrimaryAction
                    ? .black
                    : Color(red: 0.055, green: 0.065, blue: 0.075),
                fillOpacity: 0.98,
                borderColor: .white,
                borderOpacity: emphasizesPrimaryAction ? 0.09 : 0.12,
                borderWidth: 0.65,
                shadowOpacity: emphasizesPrimaryAction ? 0.085 : 0.13,
                shadowRadius: emphasizesPrimaryAction ? 12 : 14,
                shadowY: emphasizesPrimaryAction ? 6 : 7
            )
        }
        .buttonStyle(NutritionCalculationPressButtonStyle(pressedScale: 0.985))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.58 : 1)
        .padding(
            .horizontal,
            emphasizesPrimaryAction ? 28 : NutritionCalculationDesign.screenHorizontalPadding
        )
        .padding(.top, emphasizesPrimaryAction ? 12 : 10)
        .padding(.bottom, emphasizesPrimaryAction ? 10 : 8)
        .background {
            if usesNeutralBackdrop {
                LinearGradient(
                    colors: [.white.opacity(0), .white.opacity(0.97)],
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color(red: 0.985, green: 0.985, blue: 0.976).opacity(0.96)
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()
            }
        }
    }
}
