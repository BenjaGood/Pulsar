//
//  GymSettingsUnitOptionRow.swift
//  Pulsar
//

import SwiftUI

struct GymSettingsUnitOptionRow: View {
    var title: String
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            GymSettingsSelectionIndicator(isSelected: isSelected)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(minHeight: 64)
        .accessibilityElement(children: .combine)
    }
}
