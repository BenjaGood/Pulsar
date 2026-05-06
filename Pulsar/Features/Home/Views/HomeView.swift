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
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if viewModel.healthKitStatus != "HealthKit connected" {
                        HealthKitStatusBanner(message: viewModel.healthKitStatus)
                    }
                    cardStack
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

    @ViewBuilder
    private var cardStack: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 16) {
                cards
            }
        } else {
            cards
        }
    }

    private var cards: some View {
        VStack(spacing: 16) {
            NavigationLink {
                SleepDetailsView(viewModel: viewModel.makeSleepDetailsViewModel())
            } label: {
                SleepCard(summary: viewModel.dashboard.sleep)
            }
            .buttonStyle(SleepCardNavigationStyle())
            .simultaneousGesture(TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            })
            NavigationLink {
                RecoveryDetailsView(viewModel: viewModel.makeRecoveryDetailsViewModel())
            } label: {
                RecoveryCard(summary: viewModel.dashboard.recovery)
            }
            .buttonStyle(SleepCardNavigationStyle())
            .simultaneousGesture(TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            })
            NavigationLink {
                StrainDetailsView(viewModel: viewModel.makeStrainDetailsViewModel())
            } label: {
                StrainCard(summary: viewModel.dashboard.strain)
            }
            .buttonStyle(SleepCardNavigationStyle())
            .simultaneousGesture(TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            })
        }
    }
}

private struct SleepCardNavigationStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(.white.opacity(configuration.isPressed ? 0.32 : 0.10), lineWidth: 1)
                    .shadow(color: .indigo.opacity(configuration.isPressed ? 0.24 : 0.0), radius: 18)
            }
            .animation(.smooth(duration: 0.18), value: configuration.isPressed)
    }
}

private struct HealthKitStatusBanner: View {
    var message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.text.square")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SleepCard: View {
    var summary: SleepSummary

    var body: some View {
        PillarCard(title: "Sleep", symbol: "moon.zzz.fill", score: summary.score, confidence: summary.confidence, sources: summary.sourceBadges) {
            MetricGrid(metrics: [
                ("Total Sleep", minutes(summary.totalSleepMinutes)),
                ("Time in Bed", minutes(summary.timeInBedMinutes)),
                ("Efficiency", percent(summary.sleepEfficiency)),
                ("WASO", minutes(summary.wasoMinutes))
            ])
            if !summary.stageBreakdown.isEmpty {
                StageBreakdownView(stages: summary.stageBreakdown)
            }
            NotesView(notes: [summary.confidenceExplanation] + summary.notes)
        }
    }
}

private struct RecoveryCard: View {
    var summary: RecoverySummary

    var body: some View {
        PillarCard(title: "Recovery", symbol: "heart.text.square.fill", score: summary.score, confidence: summary.confidence, sources: summary.sourceBadges) {
            MetricGrid(metrics: [
                ("HRV", percent(summary.hrvReadiness)),
                ("RHR", percent(summary.restingHeartRateReadiness)),
                ("Respiration", percent(summary.respiratoryStability)),
                ("Sleep", percent(summary.sleepContribution))
            ])
            Text(summary.explanation)
                .font(.callout)
                .foregroundStyle(.primary)
            NotesView(notes: summary.notes)
        }
    }
}

private struct StrainCard: View {
    var summary: StrainSummary

    var body: some View {
        PillarCard(title: "Strain", symbol: "figure.run.circle.fill", score: summary.score, confidence: summary.confidence, sources: summary.sourceBadges) {
            MetricGrid(metrics: [
                ("Workout", String(format: "%.0f load", summary.workoutLoad)),
                ("Movement", String(format: "%.0f load", summary.movementLoad)),
                ("Steps", summary.steps.formatted()),
                ("7:28", String(format: "%.2fx", summary.sevenVsTwentyEightRatio))
            ])
            ZoneBars(zones: summary.timeInZones)
            WorkoutLedger(entries: summary.ledger)
            NotesView(notes: summary.notes)
        }
    }
}

private struct PillarCard<Content: View>: View {
    var title: String
    var symbol: String
    var score: Int
    var confidence: ConfidenceGrade
    var sources: [SourceProvenance]
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 36, height: 36)
                    .background(.tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    HStack(spacing: 8) {
                        ConfidenceBadge(grade: confidence)
                        SourceBadges(sources: sources)
                    }
                }
                Spacer()
                ScoreGauge(score: score)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pulsarGlass(cornerRadius: 30)
    }
}

private struct ScoreGauge: View {
    var score: Int

    var body: some View {
        Gauge(value: Double(score), in: 0...100) {
            Text("Score")
        } currentValueLabel: {
            Text(score == 0 ? "--" : "\(score)")
                .font(.title3.weight(.bold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(scoreTint)
        .frame(width: 62, height: 62)
    }

    private var scoreTint: Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .yellow
        case 1..<60: return .orange
        default: return .secondary
        }
    }
}

private struct ConfidenceBadge: View {
    var grade: ConfidenceGrade

    var body: some View {
        Text(grade.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch grade {
        case .high: .green
        case .moderate: .blue
        case .low: .orange
        case .missing: .secondary
        }
    }
}

private struct SourceBadges: View {
    var sources: [SourceProvenance]

    var body: some View {
        if sources.isEmpty {
            Text("No source")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        } else {
            Text(sources.prefix(2).map(\.displayName).joined(separator: ", "))
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MetricGrid: View {
    var metrics: [(String, String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(metrics, id: \.0) { metric in
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(metric.1)
                        .font(.headline.weight(.semibold))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

private struct StageBreakdownView: View {
    var stages: [StageMetric]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stages")
                .font(.headline)
            ForEach(stages) { stage in
                HStack {
                    Text(stage.stage.rawValue)
                    Spacer()
                    Text("\(minutes(stage.minutes)) · \(percent(stage.percentOfSleep))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.subheadline)
            }
        }
    }
}

private struct ZoneBars: View {
    var zones: [TimeInZone]

    var body: some View {
        let total = max(1, zones.reduce(0) { $0 + $1.minutes })
        VStack(alignment: .leading, spacing: 10) {
            Text("Time in Zone")
                .font(.headline)
            HStack(spacing: 5) {
                ForEach(zones) { zone in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color(for: zone.zone))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(8, 44 * zone.minutes / total))
                        .accessibilityLabel("Zone \(zone.zone), \(minutes(zone.minutes))")
                }
            }
            HStack {
                ForEach(zones) { zone in
                    Text("Z\(zone.zone)")
                        .font(.caption2.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func color(for zone: Int) -> Color {
        switch zone {
        case 1: .mint
        case 2: .green
        case 3: .yellow
        case 4: .orange
        default: .red
        }
    }
}

private struct WorkoutLedger: View {
    var entries: [WorkoutLedgerEntry]

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Training Ledger")
                    .font(.headline)
                ForEach(entries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.title)
                                .font(.subheadline.weight(.semibold))
                            Text(entry.start, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(minutes(entry.durationMinutes)) · \(Int(entry.load.rounded()))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct NotesView: View {
    var notes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
    var body: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color.accentColor.opacity(0.12), Color(.secondarySystemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private extension View {
    @ViewBuilder
    func pulsarGlass(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
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
