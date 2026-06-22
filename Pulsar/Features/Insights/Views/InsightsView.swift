//
//  InsightsView.swift
//  Pulsar
//

import SwiftUI

struct InsightsView: View {
    @ObservedObject private var homeViewModel: HomeViewModel
    @ObservedObject private var mindfulnessStore: PulsarMindfulnessStore
    @ObservedObject private var mindfulnessRouter: PulsarMindfulnessRouter
    @ObservedObject private var bottomChromeLayoutStore: PulsarBottomChromeLayoutStore

    init(
        homeViewModel: HomeViewModel,
        mindfulnessStore: PulsarMindfulnessStore,
        mindfulnessRouter: PulsarMindfulnessRouter,
        bottomChromeLayoutStore: PulsarBottomChromeLayoutStore = PulsarBottomChromeLayoutStore()
    ) {
        self.homeViewModel = homeViewModel
        self.mindfulnessStore = mindfulnessStore
        self.mindfulnessRouter = mindfulnessRouter
        self._bottomChromeLayoutStore = ObservedObject(wrappedValue: bottomChromeLayoutStore)
    }

    var body: some View {
        MindfulnessView(
            homeViewModel: homeViewModel,
            store: mindfulnessStore,
            router: mindfulnessRouter,
            bottomChromeLayoutStore: bottomChromeLayoutStore
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
