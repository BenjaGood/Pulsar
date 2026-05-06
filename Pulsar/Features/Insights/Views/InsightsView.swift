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
                        title: "Trend",
                        value: "+7%",
                        subtitle: "Recovery trend placeholder",
                        symbol: "chart.line.uptrend.xyaxis"
                    )
                    PlaceholderMetricCard(
                        title: "Consistency",
                        value: "82",
                        subtitle: "Sleep timing placeholder",
                        symbol: "calendar.badge.clock"
                    )
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .background(PulsarSectionBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Understand patterns")
                .font(.largeTitle.weight(.semibold))
            Text("Longitudinal sleep, recovery, strain, and nutrition patterns will live here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

#Preview {
    InsightsView()
}
