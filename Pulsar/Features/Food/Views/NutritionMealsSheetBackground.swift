//
//  NutritionMealsSheetBackground.swift
//  Pulsar
//

import SwiftUI

struct NutritionMealsSheetBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if #available(iOS 26.0, *) {
            warmWhite
                .opacity(reduceTransparency ? 1 : 0.90)
                .glassEffect(
                    .clear.tint(.white.opacity(0.08)),
                    in: .rect(
                        cornerRadius: NutritionMealsEditorDesign.sheetCornerRadius,
                        style: .continuous
                    )
                )
                .ignoresSafeArea()
        } else {
            warmWhite
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
        }
    }

    private var warmWhite: LinearGradient {
        LinearGradient(
            colors: [
                .white,
                Color(red: 0.985, green: 0.985, blue: 0.976)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
