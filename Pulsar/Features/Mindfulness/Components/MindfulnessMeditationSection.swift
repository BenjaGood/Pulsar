//
//  MindfulnessMeditationSection.swift
//  Pulsar
//

import SwiftUI

struct MindfulnessMeditationSection: View {
    var snapshot: PulsarMindfulnessMeditationWeekSnapshot
    var templates: [PulsarMeditationTemplate]
    var onStart: (PulsarMeditationTemplate) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    title
                    Spacer(minLength: 8)
                    weekCount
                }

                VStack(alignment: .leading, spacing: 8) {
                    title
                    weekCount
                }
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(snapshot.days) { day in
                                MindfulnessMeditationWeekDay(day: day, fixedWidth: 58)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    HStack(spacing: 7) {
                        ForEach(snapshot.days) { day in
                            MindfulnessMeditationWeekDay(day: day, fixedWidth: nil)
                        }
                    }
                }
            }
            .padding(16)
            .mindfulnessCardSurface(cornerRadius: 24, shadowOpacity: 0.03)

            PulsarGlassEffectGroup(spacing: 12) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(templates) { template in
                        MindfulnessMeditationTemplateCard(template: template) {
                            onStart(template)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Meditation exercises")
                .pulsarTextStyle(.sectionHeader)
                .foregroundStyle(MindfulnessDesign.primaryText)
                .accessibilityAddTraits(.isHeader)

            Text("Guided sessions")
                .font(.subheadline)
                .foregroundStyle(MindfulnessDesign.secondaryText)
        }
    }

    private var weekCount: some View {
        Text("\(snapshot.meditatedDayCount)/7 days this week")
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(MindfulnessDesign.secondaryText)
    }

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(minimum: 220), spacing: 12, alignment: .top)]
        }

        return [
            GridItem(.flexible(minimum: 140), spacing: 12, alignment: .top),
            GridItem(.flexible(minimum: 140), spacing: 12, alignment: .top)
        ]
    }
}
