//
//  BackgroundSettingsView.swift
//  Pulsar
//

import SwiftUI

struct HomeBackgroundSettingsView: View {
    @ObservedObject var store: HomeBackgroundSettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("MODE")
                    .font(.caption)
                    .bold()
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)

                PulsarGlassEffectGroup(spacing: 18) {
                    VStack(spacing: 18) {
                        ForEach(HomeBackgroundMode.allCases) { mode in
                            AppearanceModeCard(
                                mode: mode,
                                isSelected: store.mode == mode
                            ) {
                                store.setMode(mode)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .background(PulsarSettingsBackground())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.large)
        .tint(SettingsMonochromeDesign.primary)
        .preferredColorScheme(.light)
    }
}

#Preview("Appearance Settings") {
    NavigationStack {
        HomeBackgroundSettingsView(
            store: HomeBackgroundSettingsStore(
                defaults: UserDefaults(suiteName: "pulsar.appearance.preview") ?? .standard
            )
        )
    }
}
