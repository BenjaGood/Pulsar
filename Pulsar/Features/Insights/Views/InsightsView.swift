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
            .safeAreaPadding(.bottom, 16)
            .scrollContentBackground(.hidden)
            .navigationTitle("Mindfulness")
            .toolbarTitleDisplayMode(.large)
        }
        .background(PulsarSectionBackground())
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

#Preview {
    InsightsView()
}
