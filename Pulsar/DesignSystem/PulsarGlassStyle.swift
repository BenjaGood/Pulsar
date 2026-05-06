//
//  PulsarGlassStyle.swift
//  Pulsar
//

import SwiftUI

extension View {
    @ViewBuilder
    func pulsarLiquidGlass(cornerRadius: CGFloat = 28) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
        }
    }

    func pulsarTabBarAppearance() -> some View {
        self
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
    }
}

struct PulsarSectionBackground: View {
    var body: some View {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
    }
}

struct PlaceholderMetricCard: View {
    var title: String
    var value: String
    var subtitle: String
    var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(.tint)
                    .frame(width: 34, height: 34)
                    .background(.tint.opacity(0.12), in: Circle())
                Spacer()
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(value)
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulsarLiquidGlass()
    }
}

#Preview("Metric Card") {
    PlaceholderMetricCard(title: "Sleep", value: "86", subtitle: "Strong night", symbol: "moon.zzz.fill")
        .padding()
        .background(PulsarSectionBackground())
}
