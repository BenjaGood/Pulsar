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
            .safeAreaPadding(.bottom, 16)
            .scrollContentBackground(.hidden)
            .navigationTitle("Food")
            .toolbarTitleDisplayMode(.large)
        }
        .background(PulsarSectionBackground())
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

#Preview {
    FoodView()
}
