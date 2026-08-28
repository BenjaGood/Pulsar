//
//  NutritionMealCategoryEditorRow.swift
//  Pulsar
//

import SwiftUI
import UniformTypeIdentifiers

struct NutritionMealCategoryEditorRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var category: PulsarMealCategory
    var entryCount: Int
    var position: Int
    var categoryCount: Int
    var categories: [PulsarMealCategory]
    @Binding var draggingCategoryID: UUID?
    var onEdit: () -> Void
    var onDelete: () -> Void
    var onMove: (IndexSet, Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button("Delete \(category.name)", systemImage: "minus", action: onDelete)
                .labelStyle(.iconOnly)
                .font(.system(size: 16, weight: .regular))
                .frame(
                    width: NutritionMealsEditorDesign.roundControlHitSize,
                    height: NutritionMealsEditorDesign.roundControlHitSize
                )
                .background { roundControlSurface }
                .buttonStyle(NutritionMealsPressButtonStyle(flashesRed: true))

            Button(action: onEdit) {
                HStack(spacing: 12) {
                    Image(systemName: category.symbolName)
                        .font(.system(size: 19, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(category.tint.opacity(0.88))
                        .frame(
                            width: NutritionMealsEditorDesign.mealIconSize,
                            height: NutritionMealsEditorDesign.mealIconSize
                        )
                        .background(category.tint.opacity(0.095), in: .circle)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(category.name)
                            .pulsarTextStyle(.label)
                            .foregroundStyle(NutritionDesign.primaryText)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.78)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("\(entryCount) today • \(category.baseMoment.title)")
                            .pulsarTextStyle(.caption)
                            .foregroundStyle(NutritionDesign.tertiaryText.opacity(0.82))
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.78)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(category.name)")
            .accessibilityValue("\(entryCount) today")

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .ultraLight))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(NutritionDesign.tertiaryText.opacity(0.34))
                .frame(width: 32, height: 44)
                .contentShape(.rect)
                .onDrag(beginDragging)
                .accessibilityLabel("Position for \(category.name)")
                .accessibilityValue("\(position + 1) of \(categoryCount)")
                .accessibilityHint("Drag to change the meal category order")
                .accessibilityAdjustableAction(adjustPosition)
        }
        .frame(maxWidth: .infinity, minHeight: NutritionMealsEditorDesign.rowMinimumHeight)
        .opacity(draggingCategoryID == category.id ? 0.70 : 1)
        .scaleEffect(draggingCategoryID == category.id && !reduceMotion ? 0.985 : 1)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.34, dampingFraction: 0.88),
            value: draggingCategoryID
        )
        .onDrop(
            of: [UTType.text],
            delegate: NutritionMealCategoryDropDelegate(
                destinationCategory: category,
                categories: categories,
                draggingCategoryID: $draggingCategoryID,
                onMove: onMove,
                reduceMotion: reduceMotion
            )
        )
    }

    private var roundControlSurface: some View {
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

    private func beginDragging() -> NSItemProvider {
        draggingCategoryID = category.id
        return NSItemProvider(object: category.id.uuidString as NSString)
    }

    private func adjustPosition(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment where position < categoryCount - 1:
            onMove(IndexSet(integer: position), position + 2)
        case .decrement where position > 0:
            onMove(IndexSet(integer: position), position - 1)
        default:
            break
        }
    }
}
