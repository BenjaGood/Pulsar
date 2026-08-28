//
//  RecoveryDetailsView.swift
//  Pulsar
//

import SwiftUI

struct RecoveryDetailsView: View {
    @StateObject private var viewModel: RecoveryDetailsViewModel
    @ObservedObject private var bottomChromeLayoutStore: PulsarBottomChromeLayoutStore

    init(
        viewModel: RecoveryDetailsViewModel,
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
                    RecoveryDetailsLoadingView()
                case .permissionRequired:
                    RecoveryDetailsStateView(
                        symbol: "heart.text.square",
                        title: "Health Permission Required",
                        message: "Grant HealthKit HRV, resting heart rate, sleep, and activity permissions to view real recovery details."
                    )
                case .noData:
                    RecoveryDetailsStateView(
                        symbol: "waveform.path.ecg",
                        title: "No Recovery Data Available",
                        message: "Recovery details appear after HealthKit records HRV, resting heart rate, sleep, or strain signals for this day."
                    )
                case .error(let message):
                    RecoveryDetailsStateView(
                        symbol: "exclamationmark.triangle",
                        title: "Could Not Load Recovery",
                        message: message
                    )
                case .loaded:
                    RecoveryDetailsLoadedContent(viewModel: viewModel)
                }
            }
            .padding(.horizontal, RecoveryDetailsDesign.pagePadding)
            .padding(.top, RecoveryDetailsDesign.topPadding)
            .padding(.bottom, RecoveryDetailsDesign.bottomPadding)
        }
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .pulsarBottomChromeScrollContainer(layoutStore: bottomChromeLayoutStore)
        .ignoresSafeArea(edges: .bottom)
        .background(RecoveryDetailsBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .pulsarScrollAwareInlineTitle("Recovery")
        .refreshable { await viewModel.load() }
        .task { await viewModel.loadIfNeeded() }
    }
}
