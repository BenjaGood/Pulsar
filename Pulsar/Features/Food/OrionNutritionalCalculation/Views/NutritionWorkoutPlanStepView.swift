//
//  NutritionWorkoutPlanStepView.swift
//  Pulsar
//

import SwiftUI

struct NutritionWorkoutPlanStepView: View {
    @Bindable var viewModel: NutritionalCalculationViewModel

    var body: some View {
        VStack(spacing: 16) {
            PulsarNutritionGlassCard(cornerRadius: 28) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Typical day outside workouts")
                        .font(.headline)
                    Picker("Daily activity", selection: $viewModel.input.workoutPlan.dailyActivityLevel) {
                        ForEach(NutritionDailyActivityLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(viewModel.input.workoutPlan.dailyActivityLevel.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            PulsarNutritionGlassCard(cornerRadius: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Routine basis")
                        .font(.headline)
                    ForEach(NutritionWorkoutPlanBasis.allCases) { basis in
                        Button {
                            viewModel.input.workoutPlan.basis = basis
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: viewModel.input.workoutPlan.basis == basis ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(viewModel.input.workoutPlan.basis == basis ? .blue : .secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(basis.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(basis.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let summary = viewModel.input.healthActivity, !summary.observedWorkoutAggregates.isEmpty {
                PulsarNutritionGlassCard(cornerRadius: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("HealthKit suggestion")
                            .font(.headline)
                        Text("Last four completed weeks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(summary.observedWorkoutAggregates, id: \.workoutType) { aggregate in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(aggregate.workoutType.title)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(aggregate.averageSessionsPerWeek.formatted(.number.precision(.fractionLength(1)))) sessions/wk · \(Int(aggregate.medianMinutesPerSession.rounded())) min median")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let intensity = aggregate.observedIntensity {
                                    Text("Observed intensity: \(intensity.title)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button("Use observed routine", systemImage: "arrow.down.doc") {
                            viewModel.importObservedWorkoutPlan()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            PulsarNutritionGlassCard(cornerRadius: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("I train regularly", isOn: $viewModel.input.trainsRegularly)
                    if viewModel.input.trainsRegularly {
                        ForEach(viewModel.input.workoutPlan.sessions) { entry in
                            workoutRow(entry)
                        }
                        Button("Add workout", systemImage: "plus.circle.fill") {
                            viewModel.editingWorkoutEntry = NutritionWorkoutPlanEntry(
                                workoutType: .mixedOther,
                                daysPerWeek: 3,
                                minutesPerSession: 45,
                                intensity: .moderate
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            PulsarNutritionGlassCard(cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Summary")
                        .font(.headline)
                    LabeledContent("Sessions / week", value: "\(viewModel.input.workoutPlan.totalSessionsPerWeek)")
                    LabeledContent("Planned minutes", value: "\(viewModel.input.workoutPlan.totalMinutesPerWeek)")
                    Text(viewModel.input.workoutPlan.workoutMixSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let summary = viewModel.input.healthActivity {
                        Text(planConsistencyMessage(summary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .sheet(item: $viewModel.editingWorkoutEntry) { entry in
            NutritionWorkoutEntryEditor(
                entry: entry,
                onSave: { updated in
                    if viewModel.input.workoutPlan.sessions.contains(where: { $0.id == updated.id }) {
                        viewModel.updateWorkoutEntry(updated)
                    } else {
                        viewModel.addWorkoutEntry(updated)
                    }
                    viewModel.editingWorkoutEntry = nil
                },
                onCancel: {
                    viewModel.editingWorkoutEntry = nil
                }
            )
        }
    }

    private func workoutRow(_ entry: NutritionWorkoutPlanEntry) -> some View {
        Button {
            viewModel.editingWorkoutEntry = entry
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.workoutType.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(entry.accessibilitySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if entry.requiresReview {
                        Text("Confirm duration and intensity")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Button(role: .destructive) {
                    viewModel.deleteWorkoutEntry(id: entry.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.accessibilitySummary)
    }

    private func planConsistencyMessage(_ summary: HealthActivitySummary) -> String {
        if summary.anomalyCodes.contains(.planWorkoutConfirmed) {
            return "HealthKit broadly confirms your planned routine."
        }
        if summary.anomalyCodes.contains(.planWorkoutConflict) {
            return "HealthKit activity differs from your planned routine."
        }
        return "HealthKit workout comparison is limited."
    }
}

private struct NutritionWorkoutEntryEditor: View {
    @State private var entry: NutritionWorkoutPlanEntry
    var onSave: (NutritionWorkoutPlanEntry) -> Void
    var onCancel: () -> Void

    init(
        entry: NutritionWorkoutPlanEntry,
        onSave: @escaping (NutritionWorkoutPlanEntry) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _entry = State(initialValue: entry)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Workout type", selection: $entry.workoutType) {
                    ForEach(NutritionWorkoutType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                Stepper("Days per week: \(entry.daysPerWeek)", value: $entry.daysPerWeek, in: 1...7)
                Stepper("Sessions per day: \(entry.sessionsPerDay)", value: $entry.sessionsPerDay, in: 1...3)
                Stepper("Minutes per session: \(entry.minutesPerSession)", value: $entry.minutesPerSession, in: 5...300, step: 5)
                Picker("Intensity", selection: $entry.intensity) {
                    ForEach(NutritionWorkoutIntensity.allCases) { intensity in
                        Text(intensity.title).tag(intensity)
                    }
                }
                .pickerStyle(.segmented)
            }
            .navigationTitle("Workout entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        entry.requiresReview = false
                        onSave(entry)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
