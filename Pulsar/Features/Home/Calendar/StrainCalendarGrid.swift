//
//  StrainCalendarGrid.swift
//  Pulsar
//

import SwiftUI

struct StrainCalendarGrid: View {
    @ObservedObject var viewModel: StrainCalendarViewModel
    let selectionNamespace: Namespace.ID
    let onSelectDate: (Date) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 7
    )

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(viewModel.weekdaySymbols, id: \.self) { weekday in
                        Text(weekday.uppercased())
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(viewModel.monthDays) { day in
                        StrainCalendarDayCell(
                            date: day.date,
                            strainScore: viewModel.record(for: day.date)?.strainScore,
                            isToday: viewModel.isToday(day.date),
                            isSelected: viewModel.isSelected(day.date),
                            isSelectable: viewModel.isDateSelectable(day.date),
                            isInDisplayedMonth: day.isInDisplayedMonth,
                            calendar: viewModel.calendar,
                            selectionNamespace: selectionNamespace,
                            onSelect: onSelectDate
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .dynamicTypeSize(...DynamicTypeSize.large)
        .strainCalendarSurface(cornerRadius: StrainCalendarDesign.calendarCornerRadius)
        .padding(.horizontal, 10)
    }
}
