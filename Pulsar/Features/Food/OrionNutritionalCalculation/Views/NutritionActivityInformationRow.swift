//
//  NutritionActivityInformationRow.swift
//  Pulsar
//

import SwiftUI

struct NutritionActivityInformationRow: View {
    var message: String
    var density: NutritionActivityLayoutDensity = .regular

    var body: some View {
        Label(message, systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(NutritionDesign.secondaryText)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, density.informationVerticalPadding)
            .background(.black.opacity(0.018), in: .rect(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(.black.opacity(0.035), lineWidth: 0.5)
            }
    }
}
