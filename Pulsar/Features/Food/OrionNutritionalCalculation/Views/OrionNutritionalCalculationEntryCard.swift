//
//  OrionNutritionalCalculationEntryCard.swift
//  Pulsar
//

import SwiftUI

struct OrionNutritionalCalculationEntryCard: View {
    var latestCalculation: SavedNutritionalCalculation?
    var action: () -> Void

    @State private var isActivating = false
    @State private var activationTask: Task<Void, Never>?

    var body: some View {
        Button(action: activate) {
            VStack(alignment: .leading, spacing: 0) {
                OrionAnimatedLogo(size: 104)
                    .frame(maxWidth: .infinity, minHeight: 104)
                    .offset(y: -2)
                    .accessibilityHidden(true)

                Spacer(minLength: 9)

                Text("Orion Calculation")
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(NutritionDesign.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Advanced nutrition insights")
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
        .accessibilityLabel("Orion Calculation")
        .accessibilityHint(
            latestCalculation == nil
                ? "Creates personalized nutrition targets"
                : "Reviews or recalculates saved nutrition targets"
        )
        .onDisappear(perform: cancelActivation)
    }

    private func activate() {
        guard !isActivating else { return }

        isActivating = true
        activationTask?.cancel()
        activationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }

            action()
            isActivating = false
            activationTask = nil
        }
    }

    private func cancelActivation() {
        activationTask?.cancel()
        activationTask = nil
        isActivating = false
    }
}

#Preview {
    OrionNutritionalCalculationEntryCard(latestCalculation: nil) {}
        .frame(width: 180)
        .padding()
        .background(NutritionDesign.pageBackground)
}
