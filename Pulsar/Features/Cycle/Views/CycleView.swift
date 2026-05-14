//
//  CycleView.swift
//  Pulsar
//

import SwiftUI

struct CycleView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    heroCard
                    featureCards
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .pulsarBottomChromeScrollTracking()
            .background(CycleModuleBackground())
            .premiumScrollHeaderBlur(height: 56)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "moonphase.waxing.crescent")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.pink)
                .frame(width: 54, height: 54)
                .background(
                    LinearGradient(
                        colors: [
                            Color.pink.opacity(0.20),
                            Color.teal.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Cycle")
                    .font(.largeTitle.weight(.semibold))
                Text("Track your cycle, symptoms, phases, and wellness trends.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.teal)
                    .frame(width: 44, height: 44)
                    .background(Color.teal.opacity(0.13), in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text("Cycle Overview")
                        .font(.title3.weight(.semibold))
                    Text("A calm home for phase-aware check-ins, upcoming predictions, and patterns that connect with recovery.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()
                .overlay(.white.opacity(0.2))

            HStack(spacing: 10) {
                CycleHeroMetric(title: "Status", value: "Preview")
                CycleHeroMetric(title: "Privacy", value: "Personal")
                CycleHeroMetric(title: "Trends", value: "Planned")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulsarLiquidGlass(cornerRadius: 30)
    }

    private var featureCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coming Next")
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 2)

            CycleFeatureCard(
                symbol: "calendar",
                title: "Cycle Overview",
                subtitle: "See the current phase, recent logs, and cycle rhythm in one quiet dashboard."
            )

            CycleFeatureCard(
                symbol: "heart.text.square",
                title: "Symptoms",
                subtitle: "Capture symptoms, mood, energy, and body signals without clutter."
            )

            CycleFeatureCard(
                symbol: "sparkles",
                title: "Predictions",
                subtitle: "Prepare for upcoming phases with gentle forecasts and wellness context."
            )
        }
    }
}

private struct CycleHeroMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct CycleFeatureCard: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.pink)
                .frame(width: 42, height: 42)
                .background(Color.pink.opacity(0.11), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulsarLiquidGlass(cornerRadius: 26)
    }
}

private struct CycleModuleBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            PulsarSectionBackground()

            LinearGradient(
                colors: backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    private var backgroundColors: [Color] {
        if colorScheme == .dark {
            [
                Color.pink.opacity(0.16),
                Color.black.opacity(0.0),
                Color.teal.opacity(0.10)
            ]
        } else {
            [
                Color.pink.opacity(0.12),
                Color.white.opacity(0.0),
                Color.teal.opacity(0.10)
            ]
        }
    }
}

#Preview {
    CycleView()
}
