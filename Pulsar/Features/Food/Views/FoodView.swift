//
//  FoodView.swift
//  Pulsar
//

import SwiftUI

struct FoodView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader
                    PlaceholderMetricCard(
                        title: "Energy",
                        value: "2,180",
                        subtitle: "Calories logged placeholder",
                        symbol: "leaf.circle.fill"
                    )
                    PlaceholderMetricCard(
                        title: "Protein",
                        value: "128g",
                        subtitle: "Daily target placeholder",
                        symbol: "takeoutbag.and.cup.and.straw.fill"
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
            Text("Fuel simply")
                .font(.largeTitle.weight(.semibold))
            Text("Nutrition logging, recovery fueling, and habits will live here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    FoodView()
}
