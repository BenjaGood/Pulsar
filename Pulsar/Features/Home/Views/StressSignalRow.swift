//
//  StressSignalRow.swift
//  Pulsar
//

import SwiftUI

struct StressSignalRow: View {
    var signal: StressSignal

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(colorScheme == .dark ? 0.15 : 0.10), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(signal.title)
                    .pulsarTextStyle(.label)
                    .foregroundStyle(primaryText)
                if let baseline = signal.baseline {
                    Text(baseline)
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.80)
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 4) {
                Text(signal.value)
                    .pulsarTextStyle(.label)
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(statusText)
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(secondaryText)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var icon: String {
        switch signal.availability {
        case .available:
            return "checkmark.circle.fill"
        case .limited:
            return "circle.lefthalf.filled"
        case .unavailable:
            return "minus.circle.fill"
        }
    }

    private var statusText: String {
        switch signal.availability {
        case .available:
            return "Available"
        case .limited:
            return "Limited"
        case .unavailable:
            return "Missing"
        }
    }

    private var tint: Color {
        switch signal.availability {
        case .available:
            return Color(red: 0.25, green: 0.78, blue: 0.56)
        case .limited:
            return Color(red: 0.92, green: 0.66, blue: 0.24)
        case .unavailable:
            return Color(red: 0.55, green: 0.59, blue: 0.66)
        }
    }

    private var valueColor: Color {
        signal.availability == .unavailable ? secondaryText : primaryText
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.94) : Color(red: 0.08, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.58) : Color(red: 0.38, green: 0.42, blue: 0.50)
    }

    private var rowBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.62)
    }
}
