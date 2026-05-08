//
//  PulsarRootView.swift
//  Pulsar
//

import SwiftUI

struct PulsarRootView: View {
    @State private var selectedTab: PulsarTab = .home
    @StateObject private var homeViewModel = HomeViewModel()
    @StateObject private var runCoordinator = PulsarRunCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(viewModel: homeViewModel)
                .tabItem { Label(PulsarTab.home.title, systemImage: PulsarTab.home.symbol) }
                .tag(PulsarTab.home)
                .accessibilityLabel(PulsarTab.home.title)

            FitnessView()
                .environmentObject(runCoordinator)
                .tabItem { Label(PulsarTab.fitness.title, systemImage: PulsarTab.fitness.symbol) }
                .tag(PulsarTab.fitness)
                .accessibilityLabel(PulsarTab.fitness.title)

            FoodView()
                .tabItem { Label(PulsarTab.food.title, systemImage: PulsarTab.food.symbol) }
                .tag(PulsarTab.food)
                .accessibilityLabel(PulsarTab.food.title)

            InsightsView()
                .tabItem { Label(PulsarTab.insights.title, systemImage: PulsarTab.insights.symbol) }
                .tag(PulsarTab.insights)
                .accessibilityLabel(PulsarTab.insights.title)
        }
        .tint(.accentColor)
        .pulsarTabBarAppearance()
        .task { await homeViewModel.requestInitialAppEntrySync() }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await homeViewModel.appDidBecomeActive() }
        }
    }
}

private enum PulsarTab: Hashable {
    case home
    case fitness
    case food
    case insights

    var title: String {
        switch self {
        case .home: "Home"
        case .fitness: "Fitness"
        case .food: "Food"
        case .insights: "Insights"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .fitness: "figure.run"
        case .food: "fork.knife"
        case .insights: "chart.line.uptrend.xyaxis"
        }
    }
}

#Preview {
    PulsarRootView()
}
