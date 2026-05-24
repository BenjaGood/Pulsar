//
//  InsightsView.swift
//  Pulsar
//

import SwiftUI

struct InsightsView: View {
    @ObservedObject private var homeViewModel: HomeViewModel
    @ObservedObject private var mindfulnessStore: PulsarMindfulnessStore
    @ObservedObject private var mindfulnessRouter: PulsarMindfulnessRouter

    init(
        homeViewModel: HomeViewModel,
        mindfulnessStore: PulsarMindfulnessStore,
        mindfulnessRouter: PulsarMindfulnessRouter
    ) {
        self.homeViewModel = homeViewModel
        self.mindfulnessStore = mindfulnessStore
        self.mindfulnessRouter = mindfulnessRouter
    }

    var body: some View {
        MindfulnessView(
            homeViewModel: homeViewModel,
            store: mindfulnessStore,
            router: mindfulnessRouter
        )
    }
}

#Preview {
    InsightsView(
        homeViewModel: HomeViewModel(),
        mindfulnessStore: PulsarMindfulnessStore(),
        mindfulnessRouter: PulsarMindfulnessRouter()
    )
}
