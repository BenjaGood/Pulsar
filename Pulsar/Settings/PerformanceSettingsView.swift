//
//  PerformanceSettingsView.swift
//  Pulsar
//

import SwiftUI

struct PerformanceSettingsView: View {
    @ObservedObject var store: ProfileStore
    var onSave: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var draft: UserProfile
    private let calendar = Calendar.current

    init(store: ProfileStore, onSave: (() -> Void)? = nil) {
        self.store = store
        self.onSave = onSave
        _draft = State(initialValue: store.profile)
    }

    var body: some View {
        ScrollView {
            PulsarGlassEffectGroup(spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Performance")
                        .font(.largeTitle)
                        .bold()
                        .foregroundStyle(.primary)
                        .padding(.top, 18)
                        .padding(.bottom, 38)

                    PerformanceHeartMetricsCard(
                        maxHeartRate: maxHeartRateBinding,
                        maxHeartRateSubtitle: maxHeartRateSubtitle,
                        restingHeartRate: restingHeartRateBinding,
                        hrv: hrvBinding
                    )

                    PerformanceTrainingCard(
                        trainingLevel: $draft.trainingLevel,
                        heartRateZoneMethod: $draft.heartRateZoneMethod
                    )
                    .padding(.top, PerformanceSettingsDesign.sectionSpacing)
                }
                .padding(.horizontal, PerformanceSettingsDesign.horizontalPadding)
                .padding(.bottom, 36)
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .background(PulsarSettingsBackground())
        .navigationBarBackButtonHidden()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left", action: dismissPerformance)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass(.clear))
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .tint(.primary)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(action: save) {
                    Text("Save")
                        .bold()
                        .foregroundStyle(
                            hasChanges
                                ? SettingsMonochromeDesign.primary
                                : SettingsMonochromeDesign.disabled
                        )
                        .animation(.easeInOut(duration: 0.2), value: hasChanges)
                }
                .buttonStyle(SettingsOutlineButtonStyle())
                .controlSize(.large)
                .disabled(!hasChanges)
            }
        }
        .tint(SettingsMonochromeDesign.primary)
        .preferredColorScheme(.light)
    }

    private var hasChanges: Bool {
        draft != store.profile
    }

    private var maxHeartRateBinding: Binding<Double> {
        Binding(
            get: {
                draft.manualMaxHeartRate
                    ?? draft.resolvedMaxHeartRate(calendar: calendar)?.value
                    ?? 180
            },
            set: { draft.manualMaxHeartRate = $0 }
        )
    }

    private var restingHeartRateBinding: Binding<Double> {
        Binding(
            get: { draft.restingHeartRateBaselineBPM ?? 55 },
            set: { draft.restingHeartRateBaselineBPM = $0 }
        )
    }

    private var hrvBinding: Binding<Double> {
        Binding(
            get: { draft.hrvBaselineMilliseconds ?? 50 },
            set: { draft.hrvBaselineMilliseconds = $0 }
        )
    }

    private var maxHeartRateSubtitle: String {
        draft.manualMaxHeartRate == nil ? "Estimated until manually updated" : "Manual baseline"
    }

    private func dismissPerformance() {
        dismiss()
    }

    private func save() {
        store.save(draft)
        draft = store.profile
        onSave?()
    }
}

#Preview("Performance") {
    NavigationStack {
        PerformanceSettingsView(store: SettingsPreviewStore.make())
    }
}
