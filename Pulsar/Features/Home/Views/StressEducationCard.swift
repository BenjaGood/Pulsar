//
//  StressEducationCard.swift
//  Pulsar
//

import SwiftUI

struct StressEducationCard: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(Color(red: 0.46, green: 0.64, blue: 0.92))
                Text("About Stress")
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(primaryText)
            }

            Text("Stress is an estimate of physiological load based on available wearable signals.")
            Text("It can be influenced by exercise, sleep, caffeine, illness, heat, and emotional stress.")
            Text("Pulsar is not a medical device.")
        }
        .pulsarTextStyle(.label)
        .foregroundStyle(secondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(cardBorder)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white.opacity(0.94) : Color(red: 0.08, green: 0.10, blue: 0.15)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? .white.opacity(0.66) : Color(red: 0.35, green: 0.39, blue: 0.47)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.66))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.74), lineWidth: 1)
    }
}
