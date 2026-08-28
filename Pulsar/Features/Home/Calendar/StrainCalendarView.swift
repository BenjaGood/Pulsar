//
//  StrainCalendarView.swift
//  Pulsar
//

import SwiftUI

struct StrainCalendarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel: StrainCalendarViewModel
    @State private var monthTransitionDirection = 1
    @Namespace private var selectionNamespace

    private let onDateSelected: (Date) -> Void

    @MainActor
    init(
        selectedDate: Date = Date(),
        records: [DailyStrainRecord] = [],
        onDateSelected: @escaping (Date) -> Void = { _ in }
    ) {
        let lifecycleStore = AppLifecycleStore()
        _viewModel = StateObject(
            wrappedValue: StrainCalendarViewModel(
                selectedDate: selectedDate,
                records: records,
                firstLaunchDate: lifecycleStore.firstLaunchDate,
                firstStrainSyncDate: lifecycleStore.firstStrainSyncDate
            )
        )
        self.onDateSelected = onDateSelected
    }

    @MainActor
    init(
        viewModel: StrainCalendarViewModel,
        onDateSelected: @escaping (Date) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onDateSelected = onDateSelected
    }

    var body: some View {
        ScrollView {
            VStack(spacing: StrainCalendarDesign.sectionSpacing) {
                StrainCalendarMonthHeader(
                    title: viewModel.monthTitle,
                    savedDayCount: viewModel.records.count,
                    canGoToPreviousMonth: viewModel.canGoToPreviousMonth,
                    canGoToNextMonth: viewModel.canGoToNextMonth,
                    onPreviousMonth: showPreviousMonth,
                    onNextMonth: showNextMonth
                )

                ZStack {
                    StrainCalendarGrid(
                        viewModel: viewModel,
                        selectionNamespace: selectionNamespace,
                        onSelectDate: selectDate
                    )
                    .id(viewModel.displayedMonth)
                    .transition(monthTransition)
                }

                StrainCalendarSummary(
                    date: viewModel.selectedDate,
                    record: viewModel.selectedRecord
                )
            }
            .padding(.horizontal, StrainCalendarDesign.screenMargin)
            .padding(.top, StrainCalendarDesign.topSpacing)
            .padding(.bottom, StrainCalendarDesign.bottomSpacing)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.white.opacity(0.86).ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: viewModel.selectedDate)
    }

    private var monthTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let insertionEdge: Edge = monthTransitionDirection > 0 ? .trailing : .leading
        let removalEdge: Edge = monthTransitionDirection > 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private var navigationAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.16) : .smooth(duration: 0.34)
    }

    private var selectionAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.14) : .spring(response: 0.38, dampingFraction: 0.86)
    }

    private func showPreviousMonth() {
        monthTransitionDirection = -1
        withAnimation(navigationAnimation) {
            viewModel.goToPreviousMonth()
        }
    }

    private func showNextMonth() {
        monthTransitionDirection = 1
        withAnimation(navigationAnimation) {
            viewModel.goToNextMonth()
        }
    }

    private func selectDate(_ date: Date) {
        guard viewModel.isDateSelectable(date) else { return }
        withAnimation(selectionAnimation) {
            viewModel.selectDate(date)
        }
        onDateSelected(date)
    }
}

#Preview("Minimal Calendar", traits: .fixedLayout(width: 430, height: 860)) {
    let calendar = Calendar.current
    let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: 25)) ?? .now
    let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)) ?? date
    let records = MockStrainCalendarData.previewRecords(around: date, calendar: calendar)

    StrainCalendarView(
        viewModel: StrainCalendarViewModel(
            selectedDate: date,
            records: records,
            firstLaunchDate: start,
            today: date,
            calendar: calendar
        )
    )
    .preferredColorScheme(.light)
}
