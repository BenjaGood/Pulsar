//
//  PulsarSettingsFooter.swift
//  Pulsar
//

import SwiftUI

struct PulsarSettingsFooter: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 9) {
            Image(wordmarkAssetName)
                .resizable()
                .scaledToFit()
                .frame(width: 118)
                .accessibilityLabel("Pulsar")

            Text(versionLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private var wordmarkAssetName: String {
        colorScheme == .dark ? "PulsarWordmarkDark" : "PulsarWordmark"
    }

    private var versionLine: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String

        return switch (version, build) {
        case let (.some(version), .some(build)):
            "Version \(version) (\(build)) • Built for your health"
        case let (.some(version), .none):
            "Version \(version) • Built for your health"
        default:
            "Built for your health"
        }
    }
}

#Preview("Settings Footer") {
    PulsarSettingsFooter()
        .padding()
        .background(PulsarSettingsBackground())
}
