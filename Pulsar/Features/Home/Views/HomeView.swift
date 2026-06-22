//
//  HomeView.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @StateObject private var measurementSourceManager = MeasurementSourceManager()
    @ObservedObject private var backgroundSettings: HomeBackgroundSettingsStore
    @State private var isShowingProfile = false
    @State private var isShowingCalendar = false
    @State private var isShowingMeasurementSource = false
    @State private var lastReportedScrollOffset: CGFloat = 0
    #if DEBUG
    @State private var lastHomeRenderDiagnosticSignature = ""
    #endif
    private let onScrollOffsetChange: (CGFloat) -> Void
    @ObservedObject private var bottomChromeLayoutStore: PulsarBottomChromeLayoutStore

    init(
        viewModel: HomeViewModel,
        backgroundSettings: HomeBackgroundSettingsStore = HomeBackgroundSettingsStore(),
        bottomChromeLayoutStore: PulsarBottomChromeLayoutStore = PulsarBottomChromeLayoutStore(),
        onScrollOffsetChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self._backgroundSettings = ObservedObject(wrappedValue: backgroundSettings)
        self._bottomChromeLayoutStore = ObservedObject(wrappedValue: bottomChromeLayoutStore)
        self.onScrollOffsetChange = onScrollOffsetChange
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { timeline in
            let backgroundStyle = backgroundSettings.mode.resolvedStyle(for: timeline.date)
            let appearance = HomeAdaptiveAppearance(style: backgroundStyle)

            homeContent(backgroundStyle: backgroundStyle)
                .environment(\.homeAdaptiveAppearance, appearance)
                .preferredColorScheme(appearance.preferredColorScheme)
        }
    }

    private func homeContent(backgroundStyle: HomeBackgroundStyle) -> some View {
        NavigationStack {
            GeometryReader { _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HomeHeaderView(
                            profile: viewModel.dashboard.profile,
                            activeDevice: measurementSourceManager.activeDevice,
                            date: viewModel.selectedDate,
                            onTodayTapped: { isShowingCalendar = true },
                            onProfileTapped: { isShowingProfile = true },
                            onDeviceTapped: { isShowingMeasurementSource = true }
                        )

                        if !viewModel.healthKitStatus.hasPrefix("HealthKit connected") {
                            HealthKitStatusBanner(message: viewModel.healthKitStatus)
                        }

                        metricGlassCardStack
                        stressSection
                        sourceSummaryCards
                        healthMonitorSection
                        PulsarBottomChromeSpacer(layoutStore: bottomChromeLayoutStore)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, geometry.contentOffset.y + geometry.contentInsets.top)
                } action: { _, offset in
                    reportHomeScrollOffset(offset)
                }
                .pulsarBottomChromeScrollContainer(layoutStore: bottomChromeLayoutStore)
                .background(StaticTimeBackgroundView(style: backgroundStyle))
                .scrollContentBackground(.hidden)
                .ignoresSafeArea(edges: .bottom)
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $isShowingProfile) {
                    PulsarSettingsView(store: viewModel.profileStore, backgroundSettingsStore: backgroundSettings) {
                        viewModel.refreshProfileFromStore()
                    } onHealthAuthorizationUpdated: {
                        Task { await viewModel.load() }
                    }
                }
                .sheet(isPresented: $isShowingCalendar) {
                    StrainCalendarView(selectedDate: viewModel.selectedDate, records: viewModel.strainRecords) { date in
                        Task { await viewModel.selectDate(date) }
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $isShowingMeasurementSource) {
                    MeasurementSourceSheet(manager: measurementSourceManager) {
                        await viewModel.load()
                    } onDismiss: {
                        isShowingMeasurementSource = false
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
                .ouraDebugReportSheet(viewModel: viewModel)
                .refreshable { await viewModel.load() }
                .onAppear {
                    logHomeRenderedStateIfNeeded()
                }
                .onDisappear {
                    reportHomeScrollOffset(0)
                }
                .onChange(of: viewModel.selectedDate) { _, _ in
                    logHomeRenderedStateIfNeeded()
                }
                .onChange(of: viewModel.dashboard) { _, _ in
                    logHomeRenderedStateIfNeeded()
                }
                .background(Color.clear)
                .toolbarBackground(.hidden, for: .navigationBar)
            }
        }
    }

    private func reportHomeScrollOffset(_ offset: CGFloat) {
        let normalizedOffset = max(0, offset)
        guard abs(lastReportedScrollOffset - normalizedOffset) > 0.5 else { return }
        lastReportedScrollOffset = normalizedOffset
        onScrollOffsetChange(normalizedOffset)
    }

    private var metricGlassCardStack: some View {
        metricGlassCardLayout
    }

    private var homeNavigationTitle: String {
        if Calendar.current.isDateInToday(viewModel.selectedDate) { return "Today" }
        if Calendar.current.isDateInYesterday(viewModel.selectedDate) { return "Yesterday" }
        return viewModel.selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var stressSection: some View {
        NavigationLink {
            StressDetailView(summary: viewModel.dashboard.stress, selectedDate: viewModel.selectedDate)
        } label: {
            StressHomeMeterView(summary: viewModel.dashboard.stress)
        }
        .buttonStyle(StressHomeMeterButtonStyle(glowColor: stressGaugeTint(for: viewModel.dashboard.stress.score)))
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        })
        .accessibilityHint("Open Stress details")
    }

    private var healthMonitorSection: some View {
        HealthMonitorGlassSection(summary: viewModel.dashboard.healthMonitor)
    }

    private var sourceSummaryCards: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 8
            let minimumInlineWidth: CGFloat = 132
            let cardWidth = max(118, (proxy.size.width - spacing * 2) / 3)

            if proxy.size.width < minimumInlineWidth * 3 + spacing * 2 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: spacing) {
                        ForEach(sourceCardContents) { item in
                            sourceCardButton(item: item, width: 132)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            } else {
                HStack(spacing: spacing) {
                    ForEach(sourceCardContents) { item in
                        sourceCardButton(item: item, width: cardWidth)
                    }
                }
                .frame(width: proxy.size.width, alignment: .center)
            }
        }
        .frame(height: 64)
    }

    private func sourceCardButton(item: HomeSourceCardContent, width: CGFloat) -> some View {
        Button {
            isShowingMeasurementSource = true
        } label: {
            HomeSourceGlassCard(item: item)
                .frame(width: width, height: 64)
        }
        .buttonStyle(HomeSourceGlassButtonStyle(glowColor: item.tint))
        .accessibilityLabel("\(item.title), \(item.subtitle)")
        .accessibilityHint("Open measurement sources")
    }

    private var metricGlassCardLayout: some View {
        GeometryReader { proxy in
            if proxy.size.width < 334 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        sleepMetricCard
                            .frame(width: 112, height: 238)
                        recoveryMetricCard
                            .frame(width: 112, height: 238)
                        strainMetricCard
                            .frame(width: 112, height: 238)
                    }
                    .padding(.horizontal, 1)
                }
                .frame(width: proxy.size.width, height: 238, alignment: .leading)
            } else {
                let spacing: CGFloat = 8
                let cardWidth = max(104, (proxy.size.width - spacing * 2) / 3)
                let cardHeight = CGFloat(238)

                HStack(alignment: .top, spacing: spacing) {
                    sleepMetricCard
                        .frame(width: cardWidth, height: cardHeight)
                    recoveryMetricCard
                        .frame(width: cardWidth, height: cardHeight)
                    strainMetricCard
                        .frame(width: cardWidth, height: cardHeight)
                }
                .frame(width: proxy.size.width, alignment: .center)
            }
        }
        .frame(height: 238)
    }

    private var sleepMetricCard: some View {
        metricGlassCardLink(
            title: "Sleep",
            value: viewModel.dashboard.sleep.score,
            status: sleepStatus(for: viewModel.dashboard.sleep),
            description: sleepSupportiveDescription(for: viewModel.dashboard.sleep),
            icon: "moon.zzz",
            metric: .sleep,
            destination: SleepDetailsView(viewModel: viewModel.makeSleepDetailsViewModel())
        )
    }

    private var recoveryMetricCard: some View {
        metricGlassCardLink(
            title: "Recovery",
            value: viewModel.dashboard.recovery.score,
            status: recoveryStatus(for: viewModel.dashboard.recovery),
            description: recoverySupportiveDescription(for: viewModel.dashboard.recovery),
            icon: "leaf.fill",
            metric: .recovery,
            destination: RecoveryDetailsView(viewModel: viewModel.makeRecoveryDetailsViewModel())
        )
    }

    private var strainMetricCard: some View {
        metricGlassCardLink(
            title: "Strain",
            value: viewModel.dashboard.strain.score,
            status: strainStatus(for: viewModel.dashboard.strain),
            description: strainSupportiveDescription(for: viewModel.dashboard.strain),
            icon: "figure.run",
            metric: .strain,
            showsZeroValue: hasCurrentStrainValue(viewModel.dashboard.strain),
            destination: StrainDetailsView(viewModel: viewModel.makeStrainDetailsViewModel())
        )
    }

    private func metricGlassCardLink<Destination: View>(
        title: String,
        value: Int,
        status: String,
        description: String,
        icon: String,
        metric: PulsarMetricRingKind,
        showsZeroValue: Bool = false,
        destination: Destination
    ) -> some View {
        let tint = PulsarMetricRingTheme.tint(for: metric)

        return NavigationLink {
            destination
        } label: {
            PremiumGlassMetricCard(
                title: title,
                score: value,
                status: status,
                description: description,
                icon: icon,
                metric: metric,
                showsZeroValue: showsZeroValue
            )
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .buttonStyle(PulsarMetricCircleButtonStyle(glowColor: tint))
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        })
        .accessibilityLabel("\(title) \(value == 0 && !showsZeroValue ? "unavailable" : "\(value)"), \(status)")
        .accessibilityHint("Open \(title) details")
    }

    private var suggestedStrainTargetRange: PulsarSharedStrainTargetRange? {
        viewModel.recommendedStrainTargetRange()
    }

    private func sleepStatus(for summary: SleepSummary) -> String {
        guard summary.score > 0 else { return "Unavailable" }
        switch summary.score {
        case 85...100:
            return "Optimal"
        case 70..<85:
            return "Good"
        case 50..<70:
            return "Fair"
        default:
            return "Low"
        }
    }

    private func sleepSupportiveDescription(for summary: SleepSummary) -> String {
        guard summary.score > 0 else {
            if summary.confidenceExplanation == SleepSummary.permissionRequired.confidenceExplanation {
                return "Health access needed"
            }
            return "Awaiting sleep"
        }

        if summary.score >= 70 {
            return "You slept well last night."
        }

        let sleepText = minutes(summary.totalSleepMinutes)
        return "\(sleepText) logged last night."
    }

    private func recoveryStatus(for summary: RecoverySummary) -> String {
        guard summary.score > 0 else {
            return "Unavailable"
        }

        switch summary.score {
        case 85...100:
            return "Excellent"
        case 70..<85:
            return "Good"
        case 50..<70:
            return "Moderate"
        default:
            return "Low"
        }
    }

    private func recoverySupportiveDescription(for summary: RecoverySummary) -> String {
        guard summary.score > 0 else {
            return "Awaiting recent biometrics."
        }

        switch summary.score {
        case 85...100:
            return "Your body is ready for more."
        case 70..<85:
            return "Your body is recovering well."
        case 50..<70:
            return "Keep today balanced and steady."
        default:
            return "Prioritize rest and easier effort."
        }
    }

    private func strainStatus(for summary: StrainSummary) -> String {
        guard hasCurrentStrainValue(summary) else { return "Unavailable" }
        switch summary.score {
        case 0..<40:
            return "Light"
        case 40..<70:
            return "Moderate"
        case 70..<88:
            return "High"
        default:
            return "Peak"
        }
    }

    private func strainSupportiveDescription(for summary: StrainSummary) -> String {
        guard hasCurrentStrainValue(summary) else {
            return "Awaiting load"
        }

        if let suggestedStrainTargetRange {
            if Double(summary.score) <= Double(suggestedStrainTargetRange.upperBound) {
                return "Training load is in a good range."
            }
            return "Above today's guard \(suggestedStrainTargetRange.displayText)."
        }
        if summary.workoutMinutes > 0 {
            return "\(minutes(summary.workoutMinutes)) training logged."
        }
        if summary.steps > 0 {
            return "\(summary.steps.formatted()) steps so far."
        }
        return "Current load is \(summary.score)."
    }

    private func hasCurrentStrainValue(_ summary: StrainSummary) -> Bool {
        summary.lastUpdated != nil || summary.confidence != .missing || summary.score > 0 || summary.steps > 0 || summary.workoutMinutes > 0 || summary.exerciseMinutes > 0 || (summary.activeEnergyKilocalories ?? 0) > 0
    }

    private var sourceCardContents: [HomeSourceCardContent] {
        [
            HomeSourceCardContent(
                title: "Recovery",
                subtitle: sourceCardSubtitle(
                    sources: viewModel.dashboard.recovery.sourceBadges,
                    category: .sleepRecovery,
                    emptyText: "No source"
                ),
                symbol: "chart.bar.fill",
                tint: Color(red: 0.45, green: 0.91, blue: 0.42)
            ),
            HomeSourceCardContent(
                title: "Steps",
                subtitle: sourceCardSubtitle(
                    sources: viewModel.dashboard.strain.sourceBadges,
                    category: .activitySteps,
                    emptyText: viewModel.dashboard.strain.steps > 0 ? "\(viewModel.dashboard.strain.steps.formatted()) steps" : "No source"
                ),
                symbol: "shoeprints.fill",
                tint: Color(red: 0.45, green: 0.58, blue: 1.00)
            ),
            HomeSourceCardContent(
                title: "Workouts",
                subtitle: workoutSourceSubtitle,
                symbol: "figure.run",
                tint: Color(red: 0.58, green: 0.42, blue: 1.00)
            )
        ]
    }

    private func sourceCardSubtitle(sources: [SourceProvenance], category: HealthSourcePriorityCategory, emptyText: String) -> String {
        guard let source = compactSourceName(sources) else { return emptyText }
        let resolved = measurementSourceManager.resolvedSource(for: category)
        let suffix = resolved.isFallback ? " fallback" : ""
        return "from \(source)\(suffix)"
    }

    private var workoutSourceSubtitle: String {
        if let workoutSource = viewModel.dashboard.strain.workouts.compactMap(\.sourceName).first(where: { !$0.isEmpty }) {
            return "from \(compactDisplayName(workoutSource))"
        }
        if compactSourceName(viewModel.dashboard.strain.sourceBadges) != nil {
            return sourceCardSubtitle(sources: viewModel.dashboard.strain.sourceBadges, category: .workoutsActivity, emptyText: "This week")
        }
        let workoutCount = viewModel.dashboard.strain.workouts.count
        if workoutCount == 1 { return "1 today" }
        if workoutCount > 1 { return "\(workoutCount) today" }
        return "This week"
    }

    private func compactSourceName(_ sources: [SourceProvenance]) -> String? {
        guard let first = sources.first else { return nil }
        return compactDisplayName(first.displayName)
    }

    private func compactDisplayName(_ displayName: String) -> String {
        if displayName.localizedCaseInsensitiveContains("oura") {
            return "Oura"
        }
        if displayName.localizedCaseInsensitiveContains("watch") {
            return "Apple Watch"
        }
        return displayName
    }

    private func logHomeRenderedStateIfNeeded() {
        #if DEBUG
        let sleep = viewModel.dashboard.sleep
        let signature = viewModel.homeRenderDiagnosticSignature(uiRenderedSleepMinutes: sleep.totalSleepMinutes)
        guard signature != lastHomeRenderDiagnosticSignature else { return }
        lastHomeRenderDiagnosticSignature = signature
        viewModel.logHomeRenderedState(uiRenderedSleepMinutes: sleep.totalSleepMinutes)
        #endif
    }
}

private struct HomeSourceCardContent: Identifiable {
    var id: String { title }
    var title: String
    var subtitle: String
    var symbol: String
    var tint: Color
}

private struct HomeSourceGlassCard: View {
    var item: HomeSourceCardContent

    @Environment(\.homeAdaptiveAppearance) private var appearance

    var body: some View {
        PremiumGlassContainer(cornerRadius: 26, tint: item.tint.opacity(0.72), isInteractive: true) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(item.tint.opacity(0.08))
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [item.tint.opacity(0.18), .clear],
                                center: .center,
                                startRadius: 2,
                                endRadius: 30
                            )
                        )
                    Image(systemName: item.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(item.tint)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(appearance.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    Text(item.subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(appearance.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(appearance.tertiaryText)
                    .frame(width: 12, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

private struct HomeSourceGlassButtonStyle: ButtonStyle {
    var glowColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.984 : 1)
            .brightness(configuration.isPressed ? 0.035 : 0)
            .shadow(color: glowColor.opacity(configuration.isPressed ? 0.16 : 0), radius: 12, y: 6)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

private struct HealthKitStatusBanner: View {
    var message: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.text.square")
                .foregroundStyle(.orange.opacity(0.95))
            Text(message)
                .pulsarTextStyle(.caption)
                .foregroundStyle(colorScheme == .dark ? .white.opacity(0.92) : .primary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.22),
                            Color.white.opacity(colorScheme == .dark ? 0.06 : 0.42),
                            Color.orange.opacity(colorScheme == .dark ? 0.10 : 0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.06), lineWidth: 1)
        }
    }
}

private extension View {
    @ViewBuilder
    func ouraDebugReportSheet(viewModel: HomeViewModel) -> some View {
        #if DEBUG
        self.sheet(
            item: Binding(
                get: { viewModel.latestOuraDebugReport },
                set: { value in
                    if value == nil {
                        viewModel.dismissOuraDebugReport()
                    }
                }
            )
        ) { report in
            OuraDebugReportSheet(report: report)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        #else
        self
        #endif
    }
}

#if DEBUG
private struct OuraDebugReportSheet: View {
    var report: OuraSyncDebugReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    let availableRows = report.providedRows.filter { $0.isAvailable && $0.title != "Profile" }
                    if !availableRows.isEmpty {
                        debugSection(title: "Available Oura Data", rows: availableRows)
                    }
                    debugSection(title: "Mapped Pulsar Metrics", rows: report.mappedRows)
                    endpointSection
                    debugSection(title: "Oura Day Values", rows: report.providedRows)
                    debugSection(title: "Canonical Samples", rows: report.canonicalSampleRows)
                }
                .padding(18)
            }
            .background(PulsarBackground())
            .navigationTitle("Oura Debug")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Refresh \(report.reason)", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                .font(.headline.weight(.semibold))
            Text(report.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Date \(report.dateKey)")
                Text("Window \(report.windowStartKey) to \(report.windowEndKey)")
                Text("Scopes \(report.scopes.isEmpty ? "none" : report.scopes.joined(separator: ", "))")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var endpointSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Oura Endpoints")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(report.endpointRows, id: \.path) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle()
                            .fill(statusTint(row.status))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(row.title): \(row.sampleCount)")
                                .font(.caption.weight(.semibold))
                            Text(endpointDetail(row))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
            }
            .padding(13)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func debugSection(title: String, rows: [OuraDebugValueRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(title)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows, id: \.title) { row in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: row.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(row.isAvailable ? .green : .orange)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.caption.weight(.semibold))
                            Text(row.detail)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(13)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }

    private func endpointDetail(_ row: OuraEndpointDebugRow) -> String {
        if let detail = row.detail, !detail.isEmpty {
            return "\(row.status.displayText) · \(detail)"
        }
        return row.status.displayText
    }

    private func statusTint(_ status: OuraEndpointDebugStatus) -> Color {
        switch status {
        case .succeeded:
            return .green
        case .skipped:
            return .gray
        case .unavailable:
            return .orange
        case .failed:
            return .red
        }
    }
}
#endif

struct AvatarView: View {
    var profile: UserProfile
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .fill(.tint.opacity(0.12))
            if let data = profile.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if let initials {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.primary)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
    }

    private var initials: String? {
        let parts = profile.name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? nil : String(letters).uppercased()
    }
}

private struct PulsarBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: backgroundColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var backgroundColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.06, green: 0.08, blue: 0.14),
                Color(red: 0.03, green: 0.05, blue: 0.10),
                Color(red: 0.01, green: 0.02, blue: 0.05)
            ]
        }

        return [
            Color(.systemBackground),
            Color(red: 0.95, green: 0.97, blue: 1.00),
            Color(.secondarySystemBackground)
        ]
    }
}

private func minutes(_ value: Double) -> String {
    if value <= 0 { return "--" }
    let hours = Int(value) / 60
    let minutes = Int(value.rounded()) % 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
}

private func percent(_ value: Double) -> String {
    if value <= 0 { return "--" }
    return "\(Int((value * 100).rounded()))%"
}

#Preview {
    HomeView(viewModel: HomeViewModel())
}

#if DEBUG
#Preview("Home - Polish Values") {
    HomePolishPreview()
}

@MainActor
private struct HomePolishPreview: View {
    @StateObject private var viewModel: HomeViewModel
    @StateObject private var backgroundSettings: HomeBackgroundSettingsStore

    init() {
        let viewModel = HomeViewModel()
        viewModel.usePreviewDashboard(MockHealthData.homePolishPreviewDashboard)
        _viewModel = StateObject(wrappedValue: viewModel)

        let defaults = UserDefaults(suiteName: "pulsar.home.polish.preview") ?? .standard
        let backgroundSettings = HomeBackgroundSettingsStore(defaults: defaults)
        backgroundSettings.setMode(.sunset)
        _backgroundSettings = StateObject(wrappedValue: backgroundSettings)
    }

    var body: some View {
        HomeView(viewModel: viewModel, backgroundSettings: backgroundSettings)
    }
}
#endif
