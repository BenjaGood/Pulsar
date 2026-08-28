//
//  StrainCalendarMonthHeader.swift
//  Pulsar
//

import SwiftUI

struct StrainCalendarMonthHeader: View {
    let title: String
    let savedDayCount: Int
    let canGoToPreviousMonth: Bool
    let canGoToNextMonth: Bool
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            HStack(alignment: .center, spacing: 18) {
                monthButton(
                    title: "Previous month",
                    systemImage: "chevron.left",
                    isEnabled: canGoToPreviousMonth,
                    action: onPreviousMonth
                )

                VStack(spacing: 4) {
                    Text(title)
                        .pulsarTextStyle(.displayLarge)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .contentTransition(.numericText())

                    Text("\(savedDayCount) saved days")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)

                monthButton(
                    title: "Next month",
                    systemImage: "chevron.right",
                    isEnabled: canGoToNextMonth,
                    action: onNextMonth
                )
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.bottom, 8)
    }

    private func monthButton(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .font(.headline)
            .frame(minWidth: 44, minHeight: 44)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.32)
    }
}
