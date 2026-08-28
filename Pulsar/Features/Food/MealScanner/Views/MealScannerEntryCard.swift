//
//  MealScannerEntryCard.swift
//  Pulsar
//

import SwiftUI

struct MealScannerEntryCard: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                MealScannerHeroIllustration()
                    .frame(maxWidth: .infinity, minHeight: 104)
                    .offset(y: -2)

                Spacer(minLength: 9)

                Text("3D Meal Scanner")
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(NutritionDesign.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Scan meals with\ndepth accuracy")
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(NutritionDesign.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 26)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 178, alignment: .topLeading)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(NutritionDesign.primaryText)
                    .frame(width: 30, height: 30)
                    .background(Color.black.opacity(0.025), in: .circle)
                    .overlay {
                        Circle()
                            .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                    }
                    .padding(10)
                    .accessibilityHidden(true)
            }
            .nutritionCardSurface()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("3D Meal Scanner")
        .accessibilityHint("Scans meals with camera and depth when available")
    }
}

struct MealScannerCapabilityPill: View {
    var title: String
    var symbolName: String
    var tint: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Label(title, systemImage: symbolName)
            .pulsarTextStyle(.overline)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .foregroundStyle(tint.opacity(colorScheme == .dark ? 0.92 : 0.96))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(colorScheme == .dark ? 0.14 : 0.11), in: .capsule)
    }
}

#Preview {
    MealScannerEntryCard {}
        .frame(width: 180)
        .padding()
        .background(NutritionDesign.pageBackground)
}
