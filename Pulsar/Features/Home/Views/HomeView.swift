//
//  HomeView.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var measurementSourceManager = MeasurementSourceManager()
    @ObservedObject private var backgroundSettings: HomeBackgroundSettingsStore
    @State private var isShowingProfile = false
    @State private var isShowingCalendar = false
    @State private var isShowingMeasurementSource = false
    #if DEBUG
    @State private var lastHomeRenderDiagnosticSignature = ""
    #endif
    @ObservedObject private var bottomChromeLayoutStore: PulsarBottomChromeLayoutStore

    init(
        viewModel: HomeViewModel,
        backgroundSettings: HomeBackgroundSettingsStore = HomeBackgroundSettingsStore(),
        bottomChromeLayoutStore: PulsarBottomChromeLayoutStore = PulsarBottomChromeLayoutStore()
    ) {
        self.viewModel = viewModel
        self._backgroundSettings = ObservedObject(wrappedValue: backgroundSettings)
        self._bottomChromeLayoutStore = ObservedObject(wrappedValue: bottomChromeLayoutStore)
    }

    var body: some View {
        PulsarPerformanceSignposts.measureTabDestinationBody(.home) {
            homeContent
                .environment(\.homeAdaptiveAppearance, .premium)
                .preferredColorScheme(.light)
        }
    }

    private var homeContent: some View {
        NavigationStack {
            PulsarScreenScaffold(
                layoutStore: bottomChromeLayoutStore,
                header: homeHeaderConfiguration,
                horizontalPadding: HomePremiumDesign.Layout.screenMargin,
                topPadding: HomePremiumDesign.Layout.headerTopPadding,
                spacing: HomePremiumDesign.Layout.sectionSpacing,
                onRefresh: {
                    await viewModel.load()
                },
                background: {
                    HomePremiumDesign.background
                },
                expandedHeader: {
                    HomeHeaderView(
                        profile: viewModel.dashboard.profile,
                        activeDevice: measurementSourceManager.activeDevice,
                        date: viewModel.selectedDate,
                        canGoPrevious: viewModel.canSelectPreviousDay,
                        canGoNext: viewModel.canSelectNextDay,
                        onPreviousDay: selectPreviousDay,
                        onNextDay: selectNextDay,
                        onTodayTapped: { isShowingCalendar = true },
                        onProfileTapped: { isShowingProfile = true },
                        onDeviceTapped: { isShowingMeasurementSource = true }
                    )
                },
                content: {
                    Group {
                        if viewModel.showsSavedDailyDataConfirmation {
                            HealthKitStatusBanner(message: HomeViewModel.savedDailyDataBannerMessage)
                                .transition(savedDailyDataBannerTransition)
                        } else if HomeViewModel.showsPersistentHealthKitStatusBanner(
                            healthKitStatus: viewModel.healthKitStatus
                        ) {
                            HealthKitStatusBanner(message: viewModel.healthKitStatus)
                        }
                    }
                    .animation(savedDailyDataBannerAnimation, value: viewModel.showsSavedDailyDataConfirmation)

                    metricGlassCardStack
                    stressSection
                    healthMonitorSection
                }
            )
            .toolbar(.hidden, for: .navigationBar)
            .blur(radius: isShowingCalendar ? 1.5 : 0)
            .animation(.easeOut(duration: 0.2), value: isShowingCalendar)
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
                .presentationCornerRadius(38)
                .presentationBackground(.regularMaterial)
                .presentationContentInteraction(.scrolls)
                .presentationSizing(.page)
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
            .onAppear {
                viewModel.setDashboardVisible(true)
                PulsarPerformanceSignposts.markTabDestinationAppeared(.home)
                PulsarPerformanceSignposts.markTabDestinationUseful(.home, cacheState: .notApplicable)
                PulsarPerformanceSignposts.markHomeUseful()
                logHomeRenderedStateIfNeeded()
            }
            .onDisappear {
                viewModel.setDashboardVisible(false)
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

    private func selectPreviousDay() {
        Task { await viewModel.selectAdjacentDay(offset: -1) }
    }

    private func selectNextDay() {
        Task { await viewModel.selectAdjacentDay(offset: 1) }
    }

    private var savedDailyDataBannerTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6))
    }

    private var savedDailyDataBannerAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .smooth(duration: 0.28)
    }

    private var metricGlassCardStack: some View {
        PulsarGlassEffectGroup(spacing: HomePremiumDesign.Layout.cardSpacing) {
            metricGlassCardLayout
        }
    }

    private var homeNavigationTitle: String {
        HomeDateLabel.title(for: viewModel.selectedDate)
    }

    private var homeHeaderConfiguration: PulsarScreenHeaderConfiguration {
        PulsarScreenHeaderConfiguration(
            title: homeNavigationTitle,
            titleAccessibilityLabel: "Open calendar, \(homeNavigationTitle)",
            titleAction: { isShowingCalendar = true },
            leading: .systemImage(
                "line.3.horizontal",
                accessibilityLabel: "Measurement source",
                action: { isShowingMeasurementSource = true }
            ),
            trailing: [
                .custom(accessibilityLabel: "Open profile", action: { isShowingProfile = true }) {
                    AvatarView(profile: viewModel.dashboard.profile, size: 32)
                        .frame(width: 44, height: 44)
                }
            ]
        )
    }

    private var stressSection: some View {
        NavigationLink {
            StressDetailView(summary: viewModel.dashboard.stress, selectedDate: viewModel.selectedDate)
        } label: {
            StressHomeMeterView(summary: viewModel.dashboard.stress)
        }
        .buttonStyle(StressHomeMeterButtonStyle(glowColor: HomePremiumDesign.stressTeal))
        .frame(maxWidth: .infinity)
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        })
        .accessibilityHint("Open Stress details")
    }

    private var healthMonitorSection: some View {
        HealthMonitorGlassSection(summary: viewModel.dashboard.healthMonitor)
    }

    private var metricGlassCardLayout: some View {
        GeometryReader { proxy in
            if usesScrollableMetricCards || proxy.size.width < 318 {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: HomePremiumDesign.Layout.cardSpacing) {
                        sleepMetricCard
                            .frame(width: compactMetricCardWidth, height: metricCardHeight)
                        recoveryMetricCard
                            .frame(width: compactMetricCardWidth, height: metricCardHeight)
                        strainMetricCard
                            .frame(width: compactMetricCardWidth, height: metricCardHeight)
                    }
                    .padding(.horizontal, 1)
                }
                .scrollIndicators(.hidden)
                .frame(width: proxy.size.width, height: metricCardHeight, alignment: .leading)
            } else {
                let spacing = HomePremiumDesign.Layout.cardSpacing
                let cardWidth = (proxy.size.width - spacing * 2) / 3

                HStack(alignment: .top, spacing: spacing) {
                    sleepMetricCard
                        .frame(width: cardWidth, height: metricCardHeight)
                    recoveryMetricCard
                        .frame(width: cardWidth, height: metricCardHeight)
                    strainMetricCard
                        .frame(width: cardWidth, height: metricCardHeight)
                }
                .frame(width: proxy.size.width, alignment: .center)
            }
        }
        .frame(height: metricCardHeight)
    }

    private var metricCardHeight: CGFloat {
        if dynamicTypeSize.isAccessibilitySize { return 344 }
        if dynamicTypeSize > .large { return 278 }
        return 246
    }

    private var compactMetricCardWidth: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 178 : 146
    }

    private var usesScrollableMetricCards: Bool {
        dynamicTypeSize > .large
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
            destination: RecoveryDetailsView(
                viewModel: viewModel.makeRecoveryDetailsViewModel(),
                bottomChromeLayoutStore: bottomChromeLayoutStore
            )
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
            destination: StrainDetailsView(
                viewModel: viewModel.makeStrainDetailsViewModel(),
                bottomChromeLayoutStore: bottomChromeLayoutStore
            )
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
            .contentShape(.rect(cornerRadius: HomePremiumDesign.Radius.metricCard))
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

private struct HealthKitStatusBanner: View {
    var message: String
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.text.square")
                .foregroundStyle(HomePremiumDesign.tertiaryText)

            Text(message)
                .foregroundStyle(HomePremiumDesign.secondaryText)

            Spacer(minLength: 8)

            Image(systemName: "checkmark.shield")
                .foregroundStyle(HomePremiumDesign.tertiaryText)
                .accessibilityHidden(true)
        }
        .pulsarTextStyle(.caption)
        .symbolRenderingMode(.monochrome)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .modifier(HealthKitStatusBannerGlass(reduceTransparency: reduceTransparency))
    }
}

private struct HealthKitStatusBannerGlass: ViewModifier {
    var reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(HomePremiumDesign.surface, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(HomePremiumDesign.border, lineWidth: 0.5)
                }
        } else if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.16), lineWidth: 0.5)
                }
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
                .pulsarTextStyle(.cardTitle)
            Text(report.summary)
                .pulsarTextStyle(.label)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Date \(report.dateKey)")
                Text("Window \(report.windowStartKey) to \(report.windowEndKey)")
                Text("Scopes \(report.scopes.isEmpty ? "none" : report.scopes.joined(separator: ", "))")
            }
            .pulsarTextStyle(.captionEmphasis)
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
                                .pulsarTextStyle(.captionEmphasis)
                            Text(endpointDetail(row))
                                .pulsarTextStyle(.overline)
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
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(row.isAvailable ? .green : .orange)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .pulsarTextStyle(.captionEmphasis)
                            Text(row.detail)
                                .pulsarTextStyle(.overline)
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
            .pulsarTextStyle(.captionEmphasis)
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

#Preview("Home - Compact 375×667", traits: .fixedLayout(width: 375, height: 667)) {
    HomePolishPreview()
}

#Preview("Home - Standard 393×852", traits: .fixedLayout(width: 393, height: 852)) {
    HomePolishPreview()
}

#Preview("Home - Pro Max 430×932", traits: .fixedLayout(width: 430, height: 932)) {
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
        _backgroundSettings = StateObject(wrappedValue: backgroundSettings)
    }

    var body: some View {
        HomeView(viewModel: viewModel, backgroundSettings: backgroundSettings)
    }
}
#endif
