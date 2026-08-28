//
//  MeasurementSourceRowLabel.swift
//  Pulsar
//

import SwiftUI

struct MeasurementSourceRowLabel: View {
    var source: ProfileValueSource
    var caption: String
    var symbol: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        sourceIcon
                        Spacer(minLength: 12)
                        accessories
                    }

                    sourceText
                }
            } else {
                HStack(spacing: 12) {
                    sourceIcon
                    sourceText
                    Spacer(minLength: 8)
                    accessories
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var sourceIcon: some View {
        Image(systemName: symbol)
            .font(.body)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(SettingsMonochromeDesign.primary)
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
    }

    private var sourceText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.rawValue)
                .font(.body.bold())
                .foregroundStyle(.primary)

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var accessories: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.body)
                .foregroundStyle(SettingsMonochromeDesign.primary)

            Image(systemName: "chevron.right")
                .font(.caption)
                .bold()
                .foregroundStyle(.tertiary)
        }
        .accessibilityHidden(true)
    }
}
