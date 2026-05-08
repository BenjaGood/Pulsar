//
//  HomeView.swift
//  Pulsar
//

import SwiftUI
import UIKit

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @State private var isShowingProfile = false
    @State private var isShowingCalendar = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if viewModel.healthKitStatus != "HealthKit connected" {
                        HealthKitStatusBanner(message: viewModel.healthKitStatus)
                    }
                    metricOrbStack
                    stressSection
                    healthMonitorSection
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .background(PulsarBackground())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingProfile) {
                PulsarSettingsView(store: viewModel.profileStore) {
                    viewModel.refreshProfileFromStore()
                }
            }
            .sheet(isPresented: $isShowingCalendar) {
                StrainCalendarView(selectedDate: viewModel.selectedDate, records: viewModel.strainRecords) { date in
                    Task { await viewModel.selectDate(date) }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .refreshable { await viewModel.load() }
            .safeAreaInset(edge: .top) {
                PulsarSyncStatusPill()
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
            }
        }
    }

    private var header: some View {
        HomeHeaderView(profile: viewModel.dashboard.profile, date: viewModel.selectedDate) {
            isShowingCalendar = true
        } onProfileTapped: {
            isShowingProfile = true
        }
    }

    private var metricOrbStack: some View {
        metricOrbLayout
    }

    private var stressSection: some View {
        NavigationLink {
            StressDetailView(summary: viewModel.dashboard.stress)
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
            return "Current \(summary.score) · Target \(suggestedStrainTargetRange.displayText)"
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
}

private struct HealthKitStatusBanner: View {
    var message: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.text.square")
                .foregroundStyle(.orange.opacity(0.95))
            Text(message)
                .font(.footnote.weight(.semibold))
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
                    .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
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

#Preview("Home - Polish Values") {
    HomePolishPreview()
}

#if DEBUG
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
