//
//  NutritionMealsEditorCard.swift
//  Pulsar
//

import SwiftUI

struct NutritionMealsEditorCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var categories: [PulsarMealCategory]
    var entryCount: (PulsarMealCategory) -> Int
    @Binding var draggingCategoryID: UUID?
    var onEdit: (PulsarMealCategory) -> Void
    var onDelete: (PulsarMealCategory) -> Void
    var onAdd: () -> Void
    var onMove: (IndexSet, Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                NutritionMealCategoryEditorRow(
                    category: category,
                    entryCount: entryCount(category),
                    position: index,
                    categoryCount: categories.count,
                    categories: categories,
                    draggingCategoryID: $draggingCategoryID,
                    onEdit: { onEdit(category) },
                    onDelete: { onDelete(category) },
                    onMove: onMove
                )

                separator
            }

            Button(action: onAdd) {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .regular))
                        .frame(
                            width: NutritionMealsEditorDesign.roundControlHitSize,
                            height: NutritionMealsEditorDesign.roundControlHitSize
                        )
                        .background { addControlSurface }

                    Text("Add meal category")
                        .pulsarTextStyle(.label)

                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(NutritionMealsPressButtonStyle())
            .frame(minHeight: NutritionMealsEditorDesign.actionRowMinimumHeight)
        }
        .padding(.horizontal, NutritionMealsEditorDesign.cardHorizontalPadding)
        .padding(.vertical, NutritionMealsEditorDesign.cardVerticalPadding)
        .frame(maxWidth: .infinity)
        .nutritionMealsEditorGlassSurface(
            cornerRadius: NutritionMealsEditorDesign.cardCornerRadius,
            fillOpacity: 0.54,
            borderOpacity: 0.026,
            borderWidth: 0.45,
            shadowOpacity: 0.016,
            shadowRadius: 8,
            shadowY: 4
        )
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.42, dampingFraction: 0.90),
            value: categories
        )
    }

    private var separator: some View {
        Rectangle()
            .fill(NutritionDesign.separator.opacity(0.42))
            .frame(height: 0.35)
            .padding(.leading, NutritionMealsEditorDesign.separatorLeadingInset)
            .padding(.trailing, 8)
    }

    private var addControlSurface: some View {
        Color.clear
            .frame(
                width: NutritionMealsEditorDesign.roundControlVisualSize,
                height: NutritionMealsEditorDesign.roundControlVisualSize
            )
            .nutritionMealsEditorGlassSurface(
                cornerRadius: NutritionMealsEditorDesign.roundControlVisualSize / 2,
                isInteractive: true,
                fillOpacity: 0.26,
                borderOpacity: 0.04,
                shadowOpacity: 0.012,
                shadowRadius: 4,
                shadowY: 2
            )
    }
}
