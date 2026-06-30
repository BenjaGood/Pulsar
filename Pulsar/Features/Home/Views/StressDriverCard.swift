//
//  StressDriverCard.swift
//  Pulsar
//

import SwiftUI

struct StressDriverCard: View {
    var driver: StressDriver

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(colorScheme == .dark ? 0.16 : 0.10), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(driver.title)
                    .pulsarTextStyle(.label)
                    .foregroundStyle(primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(driver.detail)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(tint.opacity(colorScheme == .dark ? 0.12 : 0.16), lineWidth: 1)
        )
    }

    private var icon: String {
        switch driver.severity {
        case .supportive:
            return "leaf.fill"
        case .neutral:
            return "waveform.path.ecg"
        case .elevated:
            return "arrow.up.heart.fill"
        case .high:
            return "exclamationmark.circle.fill"
        }
    }

    private var tint: Color {
        switch driver.severity {
        case .supportive:
            return Color(red: 0.25, green: 0.80, blue: 0.58)
        case .neutral:
            return Color(red: 0.46, green: 0.64, blue: 0.92)
        case .elevated:
            return Color(red: 0.95, green: 0.68, blue: 0.25)
        case .high:
            return Color(red: 1.00, green: 0.36, blue: 0.36)
        }
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.94) : Color(red: 0.08, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.62) : Color(red: 0.35, green: 0.39, blue: 0.47)
    }

    private var rowBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.66)
    }
}
