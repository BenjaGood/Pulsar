//
//  HomeView.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @StateObject private var measurementSourceManager = MeasurementSourceManager()
    @State private var isShowingProfile = false
    @State private var isShowingCalendar = false
    @State private var isShowingMeasurementSource = false
    #if DEBUG
    @State private var lastHomeRenderDiagnosticSignature = ""
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !viewModel.healthKitStatus.hasPrefix("HealthKit connected") {
                        HealthKitStatusBanner(message: viewModel.healthKitStatus)
                    }
                    metricOrbStack
                    sourceContextStrip
                    stressSection
                    healthMonitorSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .safeAreaPadding(.bottom, 16)
            .scrollContentBackground(.hidden)
            .navigationTitle(homeNavigationTitle)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingMeasurementSource = true
                    } label: {
                        MeasurementDeviceIconView(type: measurementSourceManager.activeDevice.type, size: 22)
                    }
                    .accessibilityLabel("Measurement Source")
                    .accessibilityHint("Choose which device powers your health metrics")
                }

                ToolbarItem(placement: .principal) {
                    Button {
                        isShowingCalendar = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(homeNavigationTitle)
                                .pulsarTextStyle(.cardTitle)
                            Image(systemName: "chevron.down")
                                .pulsarTextStyle(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open calendar")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingProfile = true
                    } label: {
                        AvatarView(profile: viewModel.dashboard.profile, size: 28)
                    }
                    .accessibilityLabel("Open Profile")
                }
            }
            .sheet(isPresented: $isShowingProfile) {
                PulsarSettingsView(store: viewModel.profileStore) {
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
            .onChange(of: viewModel.selectedDate) { _, _ in
                logHomeRenderedStateIfNeeded()
            }
            .onChange(of: viewModel.dashboard) { _, _ in
                logHomeRenderedStateIfNeeded()
            }
        }
        .background(PulsarBackground())
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var metricOrbStack: some View {
        metricOrbLayout
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
        .buttonStyle(StressHomeMeterButtonStyle(glowColor: viewModel.dashboard.stress.level?.stressTint(colorScheme: .dark) ?? .blue.opacity(0.6)))
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        })
        .accessibilityHint("Open Stress details")
    }

    private var healthMonitorSection: some View {
        HealthMonitorSection(summary: viewModel.dashboard.healthMonitor)
    }

    @ViewBuilder
    private var sourceContextStrip: some View {
        let labels = sourceContextLabels
        if !labels.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(labels, id: \.self) { label in
                        Text(label)
                            .pulsarTextStyle(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var metricOrbLayout: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = proxy.size.width < 340 ? 8 : 10
            let cardWidth = max(78, (proxy.size.width - spacing * 2) / 3)

            HStack(alignment: .top, spacing: spacing) {
                sleepMetricOrb
                    .frame(width: cardWidth, height: 168)
                recoveryMetricOrb
                    .frame(width: cardWidth, height: 168)
                strainMetricOrb
                    .frame(width: cardWidth, height: 168)
            }
            .frame(width: proxy.size.width, alignment: .center)
        }
        .frame(height: 168)
    }

    private var sleepMetricOrb: some View {
        metricOrbLink(
            title: "Sleep",
            value: viewModel.dashboard.sleep.score,
            description: sleepDescription(for: viewModel.dashboard.sleep),
            icon: "moon.zzz.fill",
            metric: .sleep,
            destination: SleepDetailsView(viewModel: viewModel.makeSleepDetailsViewModel())
        )
    }

    private var recoveryMetricOrb: some View {
        metricOrbLink(
            title: "Recovery",
            value: viewModel.dashboard.recovery.score,
            description: recoveryDescription(for: viewModel.dashboard.recovery),
            icon: "heart.text.square.fill",
            metric: .recovery,
            destination: RecoveryDetailsView(viewModel: viewModel.makeRecoveryDetailsViewModel())
        )
    }

    private var strainMetricOrb: some View {
        metricOrbLink(
            title: "Strain",
            value: viewModel.dashboard.strain.score,
            description: strainDescription(for: viewModel.dashboard.strain),
            icon: "figure.run.circle.fill",
            metric: .strain,
            targetValue: suggestedStrainTargetRange.map { Double($0.upperBound) },
            targetRange: suggestedStrainTargetRange.map { Double($0.lowerBound)...Double($0.upperBound) },
            targetLabel: "Target range",
            showsZeroValue: hasCurrentStrainValue(viewModel.dashboard.strain),
            destination: StrainDetailsView(viewModel: viewModel.makeStrainDetailsViewModel())
        )
    }

    private func metricOrbLink<Destination: View>(
        title: String,
        value: Int,
        description: String,
        icon: String,
        metric: PulsarMetricRingKind,
        targetValue: Double? = nil,
        targetRange: ClosedRange<Double>? = nil,
        targetLabel: String? = nil,
        showsZeroValue: Bool = false,
        destination: Destination
    ) -> some View {
        let colorState = MetricOrbColorState(score: Double(value))
        let tint = PulsarMetricRingTheme.tint(for: metric)
        let targetAccessibility = targetRange.map { ", \(targetLabel?.lowercased() ?? "target range") \(Int($0.lowerBound.rounded())) to \(Int($0.upperBound.rounded()))" } ?? targetValue.map { ", \(targetLabel?.lowercased() ?? "target") \(Int($0.rounded()))" } ?? ""

        return NavigationLink {
            destination
        } label: {
            PulsarMetricCircle(
                title: title,
                value: Double(value),
                description: description,
                icon: icon,
                metric: metric,
                colorState: colorState,
                targetValue: targetValue,
                targetRange: targetRange,
                targetLabel: targetLabel,
                showsZeroValue: showsZeroValue
            )
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .buttonStyle(PulsarMetricCircleButtonStyle(glowColor: tint))
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        })
        .accessibilityLabel("\(title) \(value == 0 && !showsZeroValue ? "unavailable" : "\(value)")\(targetAccessibility)")
        .accessibilityHint("Open \(title) details")
    }

    private var suggestedStrainTargetRange: PulsarSharedStrainTargetRange? {
        viewModel.recommendedStrainTargetRange()
    }

    private func sleepDescription(for summary: SleepSummary) -> String {
        guard summary.score > 0 else {
            if summary.confidenceExplanation == SleepSummary.permissionRequired.confidenceExplanation {
                return "Health access needed"
            }
            return "Awaiting sleep"
        }

        let sleepText = minutes(summary.totalSleepMinutes)
        return "\(sleepText) sleep"
    }

    private func recoveryDescription(for summary: RecoverySummary) -> String {
        guard summary.score > 0 else {
            return "Build baseline"
        }

        return summary.status.label
    }

    private func strainDescription(for summary: StrainSummary) -> String {
        guard hasCurrentStrainValue(summary) else {
            return "Awaiting load"
        }

        if let suggestedStrainTargetRange {
            return "Current \(summary.score) · Guard \(suggestedStrainTargetRange.displayText)"
        }
        if summary.workoutMinutes > 0 {
            return "\(minutes(summary.workoutMinutes)) training"
        }
        if summary.steps > 0 {
            return "\(summary.steps.formatted()) steps"
        }
        return "Current \(summary.score)"
    }

    private func hasCurrentStrainValue(_ summary: StrainSummary) -> Bool {
        summary.lastUpdated != nil || summary.confidence != .missing || summary.score > 0 || summary.steps > 0 || summary.workoutMinutes > 0 || summary.exerciseMinutes > 0 || (summary.activeEnergyKilocalories ?? 0) > 0
    }

    private var sourceContextLabels: [String] {
        var labels: [String] = []
        if let source = compactSourceName(viewModel.dashboard.sleep.sourceBadges) {
            labels.append(sourceLabel(prefix: "Sleep data", source: source, category: .sleepRecovery))
        }
        if let source = compactSourceName(viewModel.dashboard.recovery.sourceBadges) {
            labels.append(sourceLabel(prefix: "Recovery", source: source, category: .sleepRecovery))
        }
        if let source = compactSourceName(viewModel.dashboard.strain.sourceBadges) {
            labels.append(sourceLabel(prefix: "Steps", source: source, category: .activitySteps))
            labels.append(sourceLabel(prefix: "Workout data", source: source, category: .workoutsActivity))
        }
        if let hrv = viewModel.dashboard.healthMonitor.metrics.first(where: { $0.kind == .hrv }),
           let source = compactSourceName(hrv.sourceBadges) {
            labels.append(sourceLabel(prefix: "HRV", source: source, category: .heartMetrics))
        }
        return Array(labels.prefix(4))
    }

    private func sourceLabel(prefix: String, source: String, category: HealthSourcePriorityCategory) -> String {
        let resolved = measurementSourceManager.resolvedSource(for: category)
        let fallback = resolved.isFallback ? " · Using fallback source" : ""
        return "\(prefix) from \(source)\(fallback)"
    }

    private func compactSourceName(_ sources: [SourceProvenance]) -> String? {
        guard let first = sources.first else { return nil }
        if first.displayName.localizedCaseInsensitiveContains("oura") {
            return "Oura"
        }
        if first.displayName.localizedCaseInsensitiveContains("watch") {
            return "Apple Watch"
        }
        return first.displayName
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

    init() {
        let viewModel = HomeViewModel()
        viewModel.usePreviewDashboard(MockHealthData.homePolishPreviewDashboard)
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        HomeView(viewModel: viewModel)
    }
}
#endif
