//
//  StressDetailView.swift
//  Pulsar
//

import SwiftUI

struct StressDetailView: View {
    var summary: StressSummary
    var selectedDate: Date? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StressDetailsDesign.sectionSpacing) {
                StressDetailsHeader(dateSubtitle: dateSubtitle)
                StressHeroCard(summary: summary)
                StressMetricsCard(summary: summary)
                StressTimelineChartView(samples: summary.dailySamples, summary: summary)
                StressSignalsCard(signals: summary.signals)
                StressInsightsSection(summary: summary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerRelativeFrame(.horizontal) { length, _ in
                max(0, length - StressDetailsDesign.pagePadding * 2)
            }
            .padding(.horizontal, StressDetailsDesign.pagePadding)
            .padding(.top, StressDetailsDesign.topPadding)
            .padding(.bottom, StressDetailsDesign.bottomPadding)
        }
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .background(StressDetailsBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarRole(.editor)
        .pulsarScrollAwareInlineTitle("Stress")
    }

    private var dateSubtitle: String {
        let date = selectedDate ?? summary.date ?? summary.queryStart ?? .now
        let calendar = Calendar.current

        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

#Preview("Stress Detail - Full Day") {
    NavigationStack {
        StressDetailView(
            summary: MockHealthData.stressDetailSummary,
            selectedDate: MockHealthData.stressDetailSummary.date
        )
    }
}

#Preview("Stress Detail - Missing") {
    NavigationStack {
        StressDetailView(summary: .missing)
    }
}
