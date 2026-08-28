//
//  NutritionMealsEditorHeader.swift
//  Pulsar
//

import SwiftUI

struct NutritionMealsEditorHeader: View {
    var onDone: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 31
    @ScaledMetric(relativeTo: .headline) private var actionSlotWidth: CGFloat = 78
    @ScaledMetric(relativeTo: .headline) private var actionVisualWidth: CGFloat = 72
    @ScaledMetric(relativeTo: .headline) private var actionVisualHeight: CGFloat = 38

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: actionSlotWidth, height: 44)
                    .accessibilityHidden(true)

                Spacer(minLength: 8)
                title
                Spacer(minLength: 8)
                doneButton
            }

            VStack(spacing: 10) {
                title

                HStack {
                    Spacer(minLength: 0)
                    doneButton
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 54)
    }

    private var title: some View {
        Text("Meals")
            .font(.system(size: titleSize, weight: .regular, design: .serif))
            .foregroundStyle(NutritionDesign.primaryText)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityAddTraits(.isHeader)
    }

    private var doneButton: some View {
        Button(action: onDone) {
            Text("Done")
                .pulsarTextStyle(.label)
                .frame(width: actionVisualWidth, height: actionVisualHeight)
                .nutritionMealsEditorGlassSurface(
                    cornerRadius: actionVisualHeight / 2,
                    isInteractive: true,
                    fillOpacity: 0.24,
                    borderOpacity: 0.035,
                    shadowOpacity: 0.012,
                    shadowRadius: 4,
                    shadowY: 2
                )
        }
            .frame(width: actionSlotWidth, height: 44)
            .buttonStyle(NutritionMealsPressButtonStyle())
    }
}
