//
//  ProfileDetailRow.swift
//  Pulsar
//

import SwiftUI

struct ProfileDetailRow<Value: View, Action: View>: View {
    var symbol: String
    var tint: Color
    var label: String
    var subtitle: String? = nil
    @ViewBuilder var value: Value
    @ViewBuilder var action: Action

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        SettingsIcon(symbol: symbol, tint: tint, size: 40)
                        Spacer(minLength: 8)
                        action
                        chevron
                    }

                    rowText
                }
            } else {
                HStack(spacing: 12) {
                    SettingsIcon(symbol: symbol, tint: tint, size: 40)
                    rowText
                    Spacer(minLength: 8)
                    action
                    chevron
                }
            }
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 11 : 5)
        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 76 : 60)
        .contentShape(Rectangle())
    }

    private var rowText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            value

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption)
            .bold()
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}
