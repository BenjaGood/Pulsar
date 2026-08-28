//
//  SleepDetailsView.swift
//  Pulsar
//

import SwiftUI

struct SleepDetailsView: View {
    @StateObject private var viewModel: SleepDetailsViewModel

    init(viewModel: SleepDetailsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            Group {
                switch viewModel.state {
                case .loading:
                    SleepDetailsLoadingView()
                case .permissionRequired:
                    SleepDetailsStateView(
                        symbol: "heart.text.square",
                        title: "Health Permission Required",
                        message: "Grant HealthKit sleep permission to view your real sleep details. Pulsar never fills this screen with demo sleep data."
                    )
                case .noData:
                    SleepDetailsStateView(
                        symbol: "moon.zzz",
                        title: "No Sleep Data Available",
                        message: "Wear Apple Watch to sleep or allow a compatible HealthKit source to write sleep-analysis samples."
                    )
                case .error(let message):
                    SleepDetailsStateView(
                        symbol: "exclamationmark.triangle",
                        title: "Could Not Load Sleep",
                        message: message
                    )
                case .loaded:
                    SleepDetailsLoadedContent(viewModel: viewModel)
                }
            }
            .padding(.horizontal, SleepDetailsDesign.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(SleepDetailsBackground())
        .navigationBarTitleDisplayMode(.inline)
        .pulsarScrollAwareInlineTitle("Sleep")
        .refreshable { await viewModel.load() }
        .task { await viewModel.loadIfNeeded() }
    }
}

#Preview("Sleep Details") {
    NavigationStack {
        SleepDetailsView(
            viewModel: SleepDetailsViewModel(
                initialSummary: MockHealthData.sleepSummary,
                profile: MockHealthData.profile,
                wakeUpDate: MockHealthData.calendar.date(
                    from: DateComponents(year: 2026, month: 5, day: 3)
                )!,
                provider: SleepDetailsPreviewProvider(summary: MockHealthData.sleepSummary),
                calendar: MockHealthData.calendar
            )
        )
    }
}
