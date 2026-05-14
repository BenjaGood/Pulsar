//
//  InsightsView.swift
//  Pulsar
//

import SwiftUI

struct InsightsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader
                    PlaceholderMetricCard(
                        title: "Breathing",
                        value: "+7%",
                        subtitle: "Mindful minutes trend placeholder",
                        symbol: "figure.mind.and.body"
                    )
                    PlaceholderMetricCard(
                        title: "Consistency",
                        value: "82",
                        subtitle: "Reflection rhythm placeholder",
                        symbol: "sparkles"
                    )
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .pulsarBottomChromeScrollTracking()
            .background(PulsarSectionBackground())
            .premiumScrollHeaderBlur(height: 56)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mindfulness")
                .font(.largeTitle.weight(.semibold))
            Text("Breathing, reflection, and calm recovery patterns will live here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    InsightsView()
}
