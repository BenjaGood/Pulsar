//
//  BackgroundSettingsView.swift
//  Pulsar
//

import SwiftUI

struct HomeBackgroundSettingsView: View {
    @ObservedObject var store: HomeBackgroundSettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HelperCard(
                    symbol: "sparkles",
                    title: "Home Background",
                    message: "Automatic mode selects a cinematic wallpaper from local time. Manual modes keep the Home wallpaper fixed.",
                    tint: .indigo
                )

                SettingsSectionCard(title: "Mode") {
                    VStack(spacing: 0) {
                        ForEach(HomeBackgroundMode.allCases) { mode in
                            Button {
                                store.setMode(mode)
                            } label: {
                                HStack(spacing: 14) {
                                    SettingsIcon(symbol: symbol(for: mode), tint: tint(for: mode))

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(mode.title)
                                            .pulsarTextStyle(.bodyEmphasis)
                                            .foregroundStyle(.primary)
                                        Text(subtitle(for: mode))
                                            .pulsarTextStyle(.metadata)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }

                                    Spacer(minLength: 12)

                                    if store.mode == mode {
                                        Image(systemName: "checkmark.circle.fill")
                                            .pulsarTextStyle(.cardTitle)
                                            .foregroundStyle(tint(for: mode))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if mode != HomeBackgroundMode.allCases.last {
                                SettingsDivider()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 30)
        }
        .background(PulsarSectionBackground())
        .navigationTitle("Home Background")
        .navigationBarTitleDisplayMode(.large)
    }

    private func symbol(for mode: HomeBackgroundMode) -> String {
        switch mode {
        case .automatic: "clock.badge.checkmark.fill"
        case .morning: "sunrise.fill"
        case .day: "sun.max.fill"
        case .sunset: "sunset.fill"
        case .night, .minimalDark: "moon.stars.fill"
        }
    }

    private func tint(for mode: HomeBackgroundMode) -> Color {
        switch mode {
        case .automatic: .cyan
        case .morning: .pink
        case .day: .blue
        case .sunset: .orange
        case .night, .minimalDark: .indigo
        }
    }

    private func subtitle(for mode: HomeBackgroundMode) -> String {
        switch mode {
        case .automatic:
            return "5 AM sunrise, 11 AM day, 6 PM sunset, 9 PM night."
        case .morning:
            return "Soft sunrise wallpaper with warm horizon light."
        case .day:
            return "Bright calm daylight wallpaper."
        case .sunset:
            return "Dramatic orange horizon and deep navy sky."
        case .night, .minimalDark:
            return "Deep night wallpaper with subtle stars."
        }
    }
}

#Preview("Background Settings") {
    NavigationStack {
        HomeBackgroundSettingsView(store: HomeBackgroundSettingsStore(defaults: UserDefaults(suiteName: "pulsar.background.preview") ?? .standard))
    }
}
