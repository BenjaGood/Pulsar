//
//  MindfulnessWeeklyOverviewCard.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessWeeklyOverviewCard: View {
    var snapshot: PulsarMindfulnessWeekSnapshot
    var onViewMore: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    title
                    Spacer(minLength: 8)
                    viewMoreButton
                }

                VStack(alignment: .leading, spacing: 12) {
                    title
                    viewMoreButton
                }
            }

            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        weekdays
                    }
                    .padding(.horizontal, 1)
                }
                .scrollIndicators(.hidden)
            } else {
                HStack(spacing: 0) {
                    weekdays
                }
            }
        }
        .padding(MindfulnessDesign.cardPadding)
        .mindfulnessCardSurface()
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mood at a glance")
                .pulsarTextStyle(.sectionHeader)
                .foregroundStyle(MindfulnessDesign.primaryText)
                .accessibilityAddTraits(.isHeader)

            Text("This week")
                .font(.subheadline)
                .foregroundStyle(MindfulnessDesign.secondaryText)
        }
    }

    private var viewMoreButton: some View {
        Button("View more", action: onViewMore)
            .font(.subheadline)
            .foregroundStyle(MindfulnessDesign.primaryText)
            .padding(.horizontal, 15)
            .frame(minHeight: 44)
            .mindfulnessCardSurface(
                cornerRadius: 22,
                isInteractive: true,
                shadowOpacity: 0.02
            )
            .buttonStyle(.plain)
            .accessibilityHint("Opens the full monthly mood calendar")
    }

    @ViewBuilder
    private var weekdays: some View {
        ForEach(snapshot.days) { day in
            MindfulnessWeekdayMoodIndicator(day: day)
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 58 : nil)
        }
    }
}
