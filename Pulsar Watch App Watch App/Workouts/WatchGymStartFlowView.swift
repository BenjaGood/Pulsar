//
//  WatchGymStartFlowView.swift
//  Pulsar Watch App Watch App
//

import SwiftUI
import WatchKit

struct WatchGymEntryView: View {
    @ObservedObject var syncStore: PulsarWatchConnectivitySyncStore
    @State private var isShowingOptions = false

    var body: some View {
        ZStack {
            if let activeState {
                WatchActiveGymWorkoutView(syncStore: syncStore, state: activeState)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else if isShowingOptions {
                WatchGymOptionsView(syncStore: syncStore)
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                WatchWorkoutHeartbeatIntroView(title: "Gym", tint: Color(red: 0.72, green: 0.66, blue: 1.00)) {
                    withAnimation(.smooth(duration: 0.34)) {
                        isShowingOptions = true
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.smooth(duration: 0.34), value: activeState?.sessionId)
        .animation(.smooth(duration: 0.34), value: isShowingOptions)
        .onAppear {
            syncStore.sendGymAction(.requestState())
            syncStore.sendGymAction(.requestSavedRoutines())
        }
    }

    private var activeState: ActiveGymWorkoutState? {
        guard let state = syncStore.activeGymState,
              syncStore.isRoutableActiveGymState(state) else { return nil }
        return state
    }
}

struct WatchGymOptionsView: View {
    @ObservedObject var syncStore: PulsarWatchConnectivitySyncStore
    @Environment(\.dismiss) private var dismiss
    @State private var isStartingFreeWorkout = false

    var body: some View {
        ZStack {
            WatchGymStartBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header

                    Button {
                        guard !isStartingFreeWorkout else { return }
                        isStartingFreeWorkout = true
                        Task {
                            await WatchGymSessionManager.shared.startFreeWorkoutFromWatch()
                            isStartingFreeWorkout = false
                        }
                    } label: {
                        WatchGymStartOptionCard(
                            symbolName: "plus.circle.fill",
                            title: "Start Free Workout",
                            subtitle: "Open strength session",
                            tint: Color(red: 0.66, green: 1.0, blue: 0.78),
                            trailingSymbol: isStartingFreeWorkout ? "hourglass" : "bolt.fill"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isStartingFreeWorkout)

                    NavigationLink {
                        WatchSavedRoutineListView(syncStore: syncStore)
                    } label: {
                        WatchGymStartOptionCard(
                            symbolName: "list.bullet.rectangle.portrait.fill",
                            title: "Saved Routines",
                            subtitle: savedRoutinesSubtitle,
                            tint: Color(red: 0.72, green: 0.66, blue: 1.0),
                            trailingSymbol: "chevron.right"
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        WKInterfaceDevice.current().play(.click)
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .pulsarTextStyle(.captionEmphasis)
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(.white.opacity(0.08), in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            syncStore.sendGymAction(.requestSavedRoutines())
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Gym")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(.white)
            Text("Start fast or mirror an iPhone routine.")
                .pulsarTextStyle(.overline)
                .foregroundStyle(.white.opacity(0.60))
                .lineLimit(2)
        }
        .padding(.horizontal, 2)
    }

    private var savedRoutinesSubtitle: String {
        let count = syncStore.savedGymRoutines.count
        if count == 0 { return "My routines" }
        return count == 1 ? "1 routine synced" : "\(count) routines synced"
    }
}

struct WatchSavedRoutineListView: View {
    @ObservedObject var syncStore: PulsarWatchConnectivitySyncStore
    @Environment(\.dismiss) private var dismiss
    @State private var startingRoutineID: UUID?

    var body: some View {
        ZStack {
            WatchGymStartBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header

                    if syncStore.savedGymRoutines.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(syncStore.savedGymRoutines) { routine in
                                Button {
                                    guard startingRoutineID == nil else { return }
                                    startingRoutineID = routine.routineId
                                    Task {
                                        await WatchGymSessionManager.shared.startRoutineFromWatch(routine)
                                        startingRoutineID = nil
                                        dismiss()
                                    }
                                } label: {
                                    WatchSavedRoutineCard(
                                        routine: routine,
                                        isStarting: startingRoutineID == routine.routineId
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(startingRoutineID != nil)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    syncStore.sendGymAction(.requestSavedRoutines())
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh saved routines")
            }
        }
        .onAppear {
            syncStore.sendGymAction(.requestSavedRoutines())
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Saved Routines")
                .pulsarTextStyle(.cardTitle)
                .foregroundStyle(.white)
            Text("Synced from iPhone")
                .pulsarTextStyle(.overline)
                .foregroundStyle(.white.opacity(0.60))
        }
        .padding(.horizontal, 2)
    }

    private var emptyState: some View {
        WatchGymStartGlassCard {
            VStack(spacing: 7) {
                Image(systemName: "iphone.gen3")
                    .pulsarTextStyle(.sectionHeader)
                    .foregroundStyle(Color(red: 0.72, green: 0.66, blue: 1.0))
                Text("No saved routines")
                    .pulsarTextStyle(.cardTitle)
                    .foregroundStyle(.white)
                Text("Create one on iPhone")
                    .pulsarTextStyle(.overline)
                    .foregroundStyle(.white.opacity(0.58))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }
}

private struct WatchSavedRoutineCard: View {
    let routine: WatchGymRoutinePlan
    let isStarting: Bool

    var body: some View {
        WatchGymStartGlassCard {
            HStack(spacing: 9) {
                Text(routine.emoji)
                    .pulsarTextStyle(.sectionHeader)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.09), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                    Text(routineMeta)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: isStarting ? "hourglass" : "play.fill")
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(Color(red: 0.66, green: 1.0, blue: 0.78))
            }
        }
    }

    private var routineMeta: String {
        let exerciseText = routine.exerciseCount == 1 ? "1 exercise" : "\(routine.exerciseCount) exercises"
        if routine.mainMuscleGroups.isEmpty {
            return exerciseText
        }
        return "\(exerciseText) / \(routine.subtitle)"
    }
}

private struct WatchGymStartOptionCard: View {
    let symbolName: String
    let title: String
    let subtitle: String
    let tint: Color
    let trailingSymbol: String

    var body: some View {
        WatchGymStartGlassCard {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                    Image(systemName: symbolName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: trailingSymbol)
                    .pulsarTextStyle(.captionEmphasis)
                    .foregroundStyle(tint.opacity(0.86))
            }
        }
    }
}

private struct WatchGymStartGlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color(red: 0.72, green: 0.66, blue: 1.0).opacity(0.11),
                                Color.black.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.13), lineWidth: 1)
            }
    }
}

private struct WatchGymStartBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.04, blue: 0.10),
                    Color(red: 0.02, green: 0.02, blue: 0.05),
                    Color(red: 0.22, green: 0.12, blue: 0.38).opacity(0.55)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 0.72, green: 0.66, blue: 1.0).opacity(0.24), .clear],
                center: .topTrailing,
                startRadius: 4,
                endRadius: 120
            )
        }
        .ignoresSafeArea()
    }
}

#Preview {
    WatchGymEntryView(syncStore: .shared)
}
