//
//  StrainCalendarDayCell.swift
//  Pulsar
//

import SwiftUI

struct StrainCalendarDayCell: View {
    let date: Date
    let strainScore: Int?
    let isToday: Bool
    let isSelected: Bool
    let isSelectable: Bool
    let isInDisplayedMonth: Bool
    let calendar: Calendar
    let selectionNamespace: Namespace.ID
    let onSelect: (Date) -> Void

    var body: some View {
        Button {
            onSelect(date)
        } label: {
            ZStack {
                StrainCalendarRing(
                    score: strainScore ?? 0,
                    size: 30,
                    progressLineWidth: 2.2
                )

                Text("\(calendar.component(.day, from: date))")
                    .font(.callout)
                    .bold(isSelected || isToday)
                    .monospacedDigit()
                    .foregroundStyle(textStyle)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(!isSelectable)
        .opacity(dayOpacity)
        .contentShape(.rect(cornerRadius: 14))
        .background(
            isSelected && isSelectable ? Color.white.opacity(0.36) : .clear,
            in: .rect(cornerRadius: 14)
        )
        .glassEffect(
            isSelected && isSelectable ? .clear.interactive() : .identity,
            in: .rect(cornerRadius: 14)
        )
        .glassEffectID(
            isSelected && isSelectable ? "selected-calendar-day" : nil,
            in: selectionNamespace
        )
        .glassEffectTransition(.matchedGeometry)
        .shadow(
            color: .black.opacity(isSelected && isSelectable ? 0.06 : 0),
            radius: 7,
            y: 3
        )
        .zIndex(isSelected ? 1 : 0)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var textStyle: HierarchicalShapeStyle {
        isSelectable && isInDisplayedMonth ? .primary : .secondary
    }

    private var dayOpacity: Double {
        if !isSelectable { return 0.28 }
        if !isInDisplayedMonth { return 0.42 }
        return 1
    }

    private var accessibilityLabel: String {
        guard isSelectable else {
            return "\(date.formatted(date: .long, time: .omitted)), unavailable"
        }

        var parts = [date.formatted(date: .long, time: .omitted)]
        if isSelected { parts.append("selected") }
        if isToday { parts.append("today") }
        if let strainScore, strainScore > 0 {
            parts.append("strain \(strainScore)")
        } else {
            parts.append("no strain recorded")
        }
        return parts.joined(separator: ", ")
    }
}
