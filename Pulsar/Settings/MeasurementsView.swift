//
//  MeasurementsView.swift
//  Pulsar
//

import SwiftUI

struct MeasurementsView: View {
    @ObservedObject var store: ProfileStore
    var onSave: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var draft: UserProfile
    @State private var saveFeedbackSequence = 0
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 34

    init(store: ProfileStore, onSave: (() -> Void)? = nil) {
        self.store = store
        self.onSave = onSave
        _draft = State(initialValue: store.profile)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MeasurementsDesign.sectionSpacing) {
                Text("Measurements")
                    .font(.system(size: titleSize, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .padding(.top, 2)

                VStack(spacing: 12) {
                    MeasurementEditorCard(
                        heightCentimeters: heightBinding,
                        weightKilograms: weightBinding,
                        units: draft.preferredUnits
                    )

                    MeasurementUnitSelector(selection: $draft.preferredUnits)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("SOURCES")
                        .font(.footnote)
                        .bold()
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)

                    MeasurementSourcesCard(
                        bodyMassSource: $draft.bodyMassSource,
                        heightSource: $draft.heightSource,
                        lastUpdated: draft.lastUpdated
                    )
                }

                if let bmiValue {
                    let bmiStatus = MeasurementBMIStatus(value: bmiValue)

                    NavigationLink {
                        MeasurementBMIDetailView(
                            value: bmiValue,
                            status: bmiStatus
                        )
                    } label: {
                        MeasurementBMICard(
                            value: bmiValue,
                            status: bmiStatus
                        )
                    }
                    .buttonStyle(MeasurementPressButtonStyle(pressedScale: 0.985))
                }
            }
            .padding(.horizontal, MeasurementsDesign.horizontalPadding)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .background(MeasurementsDesign.background.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left", action: dismissMeasurements)
                    .profileActionControl(tint: .black, controlSize: .regular)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Save", action: save)
                    .font(.subheadline.bold())
                    .foregroundStyle(hasChanges ? Color.white : Color.secondary)
                    .padding(.horizontal, 3)
                    .buttonStyle(
                        .glass(
                            .regular.tint(
                                hasChanges
                                    ? Color.black
                                    : Color.gray.opacity(0.1)
                            )
                        )
                    )
                    .buttonBorderShape(.capsule)
                    .controlSize(.regular)
                    .opacity(hasChanges ? 1 : 0.82)
                    .disabled(!hasChanges)
                    .animation(.easeInOut(duration: 0.2), value: hasChanges)
            }
        }
        .tint(MeasurementsDesign.accent)
        .preferredColorScheme(.light)
        .sensoryFeedback(.success, trigger: saveFeedbackSequence)
    }

    private var hasChanges: Bool {
        draft != store.profile
    }

    private var heightBinding: Binding<Double> {
        Binding(
            get: { draft.heightCentimeters ?? draft.healthKitHeightCentimeters ?? 175 },
            set: { draft.heightCentimeters = $0 }
        )
    }

    private var weightBinding: Binding<Double> {
        Binding(
            get: { draft.weightKilograms ?? draft.healthKitWeightKilograms ?? 72 },
            set: { draft.weightKilograms = $0 }
        )
    }

    private var bmiValue: Double? {
        guard let height = draft.resolvedHeightCentimeters,
              let weight = draft.resolvedWeightKilograms,
              height > 0 else {
            return nil
        }

        return weight / pow(height / 100, 2)
    }

    private func save() {
        store.save(draft)
        draft = store.profile
        saveFeedbackSequence += 1
        onSave?()
    }

    private func dismissMeasurements() {
        dismiss()
    }
}

#Preview("Measurements") {
    NavigationStack {
        MeasurementsView(store: SettingsPreviewStore.make())
    }
}
