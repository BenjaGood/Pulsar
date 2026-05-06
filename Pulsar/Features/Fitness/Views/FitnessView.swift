//
//  FitnessView.swift
//  Pulsar
//

import SwiftUI

struct FitnessView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader
                    PlaceholderMetricCard(
                        title: "Training Load",
                        value: "42",
                        subtitle: "Moderate work planned for today",
                        symbol: "figure.run"
                    )
                    PlaceholderMetricCard(
                        title: "Workouts",
                        value: "3",
                        subtitle: "This week",
                        symbol: "dumbbell.fill"
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
            Text("Move with intent")
                .font(.largeTitle.weight(.semibold))
            Text("Workouts, zones, and weekly training context will live here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

#Preview {
    FitnessView()
}
