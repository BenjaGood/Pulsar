//
//  PulsarRunHistoryView.swift
//  Pulsar
//

import SwiftUI

struct PulsarRunHistoryView: View {
    @ObservedObject var coordinator: PulsarRunCoordinator
    var workoutKind: PulsarOutdoorWorkoutKind = .running
    @State private var runs: [PulsarRunSummary] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView("Loading \(workoutKind.actionName)s")
                } else if runs.isEmpty {
                    ContentUnavailableView(
                        "No \(workoutKind.shortName)s Yet",
                        systemImage: "\(workoutKind.systemImageName).circle",
                        description: Text("Start an outdoor \(workoutKind.actionName) and Pulsar will build your training log here.")
                    )
                } else {
                    ForEach(runs) { run in
                        NavigationLink {
                            PulsarRunSummaryView(summary: run)
                        } label: {
                            RunHistoryRow(run: run)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(PulsarSectionBackground())
            .navigationTitle("Training Log")
        }
        .task {
            runs = await coordinator.history(for: workoutKind)
            isLoading = false
        }
    }
}

private struct RunHistoryRow: View {
    var run: PulsarRunSummary

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(run.workoutKind.accentColor.opacity(0.14))
                Image(systemName: run.workoutKind.systemImageName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(run.workoutKind.accentColor)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(run.startedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.headline.weight(.bold))
                Text("\(PulsarRunFormatters.distance(run.distanceMeters)) · \(PulsarRunFormatters.duration(run.movingTime)) · \(PulsarRunFormatters.paceOrSpeed(workoutKind: run.workoutKind, paceSecondsPerKilometer: run.averagePaceSecondsPerKilometer, speedMetersPerSecond: run.averageSpeedMetersPerSecond))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(run.source == .appleWatch ? "Watch" : "iPhone")
                .font(.caption2.weight(.black))
                .foregroundStyle(run.workoutKind.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(run.workoutKind.accentColor.opacity(0.11), in: Capsule())
        }
        .padding(.vertical, 6)
    }
}
