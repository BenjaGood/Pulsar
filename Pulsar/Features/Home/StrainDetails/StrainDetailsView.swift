//
//  StrainDetailsView.swift
//  Pulsar
//

import SwiftUI

struct StrainDetailsView: View {
    @StateObject private var viewModel: StrainDetailsViewModel
    @ObservedObject private var bottomChromeLayoutStore: PulsarBottomChromeLayoutStore

    init(
        viewModel: StrainDetailsViewModel,
        bottomChromeLayoutStore: PulsarBottomChromeLayoutStore
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _bottomChromeLayoutStore = ObservedObject(wrappedValue: bottomChromeLayoutStore)
    }

    var body: some View {
        ScrollView {
            Group {
                switch viewModel.state {
                case .loading:
                    StrainDetailsLoadingView()
                case .permissionRequired:
                    StrainDetailsStateView(
                        symbol: "heart.text.square",
                        title: "Health Permission Required",
                        message: "Grant HealthKit activity, workout, and heart-rate permissions to view real strain details."
                    )
                case .noData:
                    StrainDetailsStateView(
                        symbol: "figure.walk",
                        title: "No Strain Data Available",
                        message: "Strain details appear after HealthKit records workouts, movement, calories, or heart-rate samples for this day."
                    )
                case .error(let message):
                    StrainDetailsStateView(
                        symbol: "exclamationmark.triangle",
                        title: "Could Not Load Strain",
                        message: message
                    )
                case .loaded:
                    StrainDetailsLoadedContent(viewModel: viewModel)
                }
            }
            .padding(.horizontal, StrainDetailsDesign.pagePadding)
            .padding(.top, StrainDetailsDesign.topPadding)
            .padding(.bottom, StrainDetailsDesign.bottomPadding)
        }
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .pulsarBottomChromeScrollContainer(layoutStore: bottomChromeLayoutStore)
        .ignoresSafeArea(edges: .bottom)
        .background(StrainDetailsBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .pulsarScrollAwareInlineTitle("Strain")
        .refreshable { await viewModel.load() }
        .task { await viewModel.loadIfNeeded() }
    }
}
