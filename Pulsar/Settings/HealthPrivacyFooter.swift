//
//  HealthPrivacyFooter.swift
//  Pulsar
//

import SwiftUI

struct HealthPrivacyFooter: View {
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 46

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                lockIcon
                privacyMessage
                    .frame(maxWidth: 250, alignment: .leading)
            }

            VStack(spacing: 10) {
                lockIcon
                privacyMessage
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: HealthSettingsDesign.privacyFooterMaximumWidth)
        .accessibilityElement(children: .combine)
    }

    private var lockIcon: some View {
        Image(systemName: "lock.fill")
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(width: iconSize, height: iconSize)
            .background(SettingsMonochromeDesign.surface, in: Circle())
            .overlay {
                Circle()
                    .stroke(SettingsMonochromeDesign.border, lineWidth: 0.75)
            }
            .shadow(color: SettingsMonochromeDesign.shadow, radius: 10, y: 5)
            .accessibilityHidden(true)
    }

    private var privacyMessage: some View {
        Text("Your data is private and secure.\nPulsar never writes to Apple Health.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
