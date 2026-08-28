//
//  OrionNutritionalCalculationFlowView.swift
//  Pulsar
//

import SwiftUI

struct OrionNutritionalCalculationFlowView: View {
    @ObservedObject private var nutritionStore: PulsarNutritionStore
    @State private var viewModel: NutritionalCalculationViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        nutritionStore: PulsarNutritionStore,
        profile: UserProfile,
        latestBodyCheckIn: PulsarBodyCheckIn?
    ) {
        self.nutritionStore = nutritionStore
        _viewModel = State(
            wrappedValue: NutritionalCalculationViewModel(
                profile: profile,
                latestBodyCheckIn: latestBodyCheckIn,
                previousTargetCalories: nutritionStore.latestNutritionalCalculation?.result.energy.targetCalories
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white
                    .ignoresSafeArea()

                if viewModel.step != .activity {
                    NutritionDesign.pageBackground
                        .ignoresSafeArea()
                }

                if viewModel.step == .activity {
                    NutritionCalculationActivityScreen(
                        viewModel: viewModel,
                        onClose: dismiss.callAsFunction
                    )
                } else {
                    ScrollView {
                        PulsarGlassEffectGroup(spacing: 22) {
                            VStack(spacing: 18) {
                                NutritionCalculationScreenHeader(
                                    title: viewModel.step.title,
                                    canMoveBack: viewModel.canMoveBack,
                                    onBack: viewModel.moveBack,
                                    onClose: dismiss.callAsFunction
                                )

                                NutritionCalculationFlowHeader(
                                    currentStep: viewModel.step.rawValue + 1,
                                    totalSteps: NutritionalCalculationViewModel.Step.allCases.count,
                                    progress: viewModel.progress
                                )

                                stepContent
                                    .id(viewModel.step)
                                    .transition(
                                        .opacity.combined(
                                            with: .scale(scale: reduceMotion ? 1 : 0.985)
                                        )
                                    )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 24)
                        .animation(stepAnimation, value: viewModel.step)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDismissesKeyboard(.interactively)
                }

                if viewModel.isGenerating {
                    calculationOverlay
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if viewModel.step != .results {
                    NutritionCalculationContinueBar(
                        title: viewModel.step == .preferences ? "Calculate targets" : "Continue",
                        isDisabled: viewModel.isGenerating,
                        showsTrailingChevron: false,
                        usesNeutralBackdrop: viewModel.step == .activity,
                        emphasizesPrimaryAction: viewModel.step == .activity,
                        action: viewModel.moveForward
                    )
                }
            }
            .task(id: viewModel.step) {
                if viewModel.step == .activity {
                    await viewModel.loadActivityIfNeeded()
                }
            }
        }
        .pulsarFitnessMonochromeAppearance()
        .presentationCornerRadius(38)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch viewModel.step {
        case .introduction:
            NutritionCalculationIntroductionStep()
        case .body:
            NutritionCalculationBodyStep(viewModel: viewModel)
        case .activity:
            NutritionCalculationActivityStep(viewModel: viewModel)
        case .workoutPlan:
            NutritionWorkoutPlanStepView(viewModel: viewModel)
        case .goal:
            NutritionCalculationGoalStep(viewModel: viewModel)
        case .preferences:
            NutritionCalculationPreferencesStep(viewModel: viewModel)
        case .results:
            if let result = viewModel.result {
                NutritionCalculationResultsStep(
                    viewModel: viewModel,
                    result: result,
                    onSave: saveTargets
                )
            }
        }

        if let errorMessage = viewModel.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .pulsarTextStyle(.captionEmphasis)
                .foregroundStyle(
                    viewModel.step == .activity
                        ? NutritionDesign.primaryText
                        : Color.orange
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    viewModel.step == .activity
                        ? Color.black.opacity(0.045)
                        : Color.orange.opacity(0.12),
                    in: .rect(cornerRadius: 16)
                )
                .accessibilityIdentifier("nutrition-calculation-error")
        }
    }

    private var calculationOverlay: some View {
        VStack(spacing: 14) {
            OrionAnimatedLogo(size: 82)
            ProgressView()
                .controlSize(.large)
                .tint(NutritionDesign.primaryText)
            Text("Calculating locally…")
                .pulsarTextStyle(.bodyEmphasis)
            Text("Orion AI is not used to choose your numbers.")
                .pulsarTextStyle(.metadata)
                .foregroundStyle(NutritionDesign.secondaryText)
        }
        .padding(28)
        .nutritionCalculationGlassSurface(
            cornerRadius: 28,
            fillOpacity: 0.74,
            borderOpacity: 0.035,
            shadowOpacity: 0.055,
            shadowRadius: 18,
            shadowY: 9
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Calculating nutrition targets locally")
    }

    private var stepAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.14)
            : .spring(response: 0.42, dampingFraction: 0.90)
    }

    private func saveTargets() {
        guard let calculation = viewModel.savedCalculation() else { return }
        nutritionStore.applyCalculatedTargets(calculation)
        dismiss()
    }
}

private struct NutritionCalculationGoalStep: View {
    @Bindable var viewModel: NutritionalCalculationViewModel

    var body: some View {
        VStack(spacing: 12) {
            ForEach(NutritionCalculationGoal.allCases) { goal in
                Button {
                    viewModel.input.goal = goal
                } label: {
                    PulsarNutritionGlassCard(cornerRadius: 20, padding: 14) {
                        HStack(spacing: 14) {
                            Image(systemName: goal.symbolName)
                                .font(.title2)
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(goal.title).font(.headline)
                                Text(goal.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Image(systemName: viewModel.input.goal == goal ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(viewModel.input.goal == goal ? .green : .secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(viewModel.input.goal == goal ? .isSelected : [])
            }

            PulsarNutritionGlassCard(cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Desired pace", selection: $viewModel.input.pace) {
                        ForEach(NutritionGoalPace.allCases) { pace in
                            Text(pace.title).tag(pace)
                        }
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("Target weight") {
                        HStack(spacing: 5) {
                            TextField("Optional", value: $viewModel.input.targetWeightKilograms, format: .number.precision(.fractionLength(0...1)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 100)
                            Text("kg").foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent("Target date") {
                        DatePicker(
                            "Optional",
                            selection: Binding(
                                get: { viewModel.input.targetDate ?? .now.addingTimeInterval(86_400 * 90) },
                                set: { viewModel.input.targetDate = $0 }
                            ),
                            displayedComponents: .date
                        )
                        .labelsHidden()
                    }
                }
            }
        }
    }
}

private struct NutritionCalculationPreferencesStep: View {
    @Bindable var viewModel: NutritionalCalculationViewModel

    var body: some View {
        VStack(spacing: 16) {
            PulsarNutritionGlassCard(cornerRadius: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Dietary preference", selection: $viewModel.input.dietaryPreference) {
                        ForEach(NutritionDietaryPreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Allergies or exclusions")
                            .font(.subheadline.weight(.medium))
                        TextField("Optional; e.g. peanuts, lactose", text: $viewModel.input.exclusions, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.roundedBorder)
                    }

                    if viewModel.input.biologicalSex == .female {
                        Picker("Life stage", selection: $viewModel.input.lifeStage) {
                            ForEach(NutritionLifeStage.allCases) { stage in
                                Text(stage.title).tag(stage)
                            }
                        }
                    }
                }
            }

            PulsarNutritionGlassCard(cornerRadius: 22) {
                Toggle(isOn: $viewModel.input.medicalAcknowledgementAccepted) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Informational guidance")
                            .font(.headline)
                        Text("I understand this is not diagnosis, treatment, or a substitute for a registered dietitian or clinician.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct NutritionCalculationResultsStep: View {
    @Bindable var viewModel: NutritionalCalculationViewModel
    var result: NutritionalCalculationResult
    var onSave: () -> Void
    @State private var confirmedLargeChange = false

    var body: some View {
        VStack(spacing: 16) {
            if result.energy.requiresUserConfirmation, !confirmedLargeChange {
                targetChangeCard
            }

            PulsarNutritionGlassCard(cornerRadius: 28) {
                VStack(spacing: 14) {
                    Text("Daily calorie target")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.secondary)
                    Text("\(Int(result.energy.targetCalories))")
                        .font(.largeTitle.scaled(by: 1.45))
                        .bold()
                        .monospacedDigit()
                    Text("\(Int(result.energy.targetRange.lowerBound))–\(Int(result.energy.targetRange.upperBound)) cal practical range")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label("\(result.confidence.title) confidence", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 10) {
                ForEach(result.macros) { macro in
                    macroCard(macro)
                }
            }

            PulsarNutritionGlassCard(cornerRadius: 24) {
                DisclosureGroup("How Pulsar calculated this") {
                    VStack(alignment: .leading, spacing: 10) {
                        resultMetric("BMR", "\(Int(result.energy.basalMetabolicRate)) cal")
                        resultMetric("Maintenance", "\(Int(result.energy.maintenanceCalories)) cal")
                        resultMetric("Modeled maintenance", "\(Int(result.energy.modeledMaintenanceCalories)) cal")
                        resultMetric("Formula", result.energy.formula.title)
                        resultMetric("BMI", "\(result.bodyMassIndex.formatted()) · \(result.bodyMassIndexCategory)")
                        ForEach(result.energy.primaryDrivers, id: \.self) { driver in
                            Text(driver)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(result.energy.rationale)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("BMI is a population screening measure, not a diagnosis or direct body-composition measurement.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)
                }

                Divider().padding(.vertical, 10)

                DisclosureGroup("Fiber, hydration & micronutrients") {
                    VStack(alignment: .leading, spacing: 10) {
                        resultMetric("Fiber", "\(Int(result.fiberGrams)) g")
                        resultMetric("Hydration", "\(Int(result.hydrationMilliliters)) ml")
                        ForEach(result.micronutrients) { item in
                            resultMetric(item.nutrient, "\(item.amount.formatted()) \(item.unit)")
                        }
                    }
                    .padding(.top, 12)
                }
            }

            PulsarNutritionGlassCard(cornerRadius: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("Allow an optional Orion explanation", isOn: $viewModel.allowsOrionExplanation)
                    Text("Only aggregated activity, confirmed inputs, and these validated results are sent through Pulsar's secure backend. Orion cannot change the numbers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let explanation = viewModel.explanation {
                        Divider()
                        Text(explanation.summary).font(.subheadline)
                        ForEach(explanation.practicalRecommendations, id: \.self) { recommendation in
                            Label(recommendation, systemImage: "sparkles")
                                .font(.caption)
                        }
                        Text(explanation.safetyNote)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if viewModel.allowsOrionExplanation {
                        Button {
                            Task { await viewModel.requestExplanation() }
                        } label: {
                            if viewModel.isLoadingExplanation {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Label("Ask Orion to explain", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isLoadingExplanation)
                    }
                }
            }

            ForEach(result.limitations, id: \.self) { limitation in
                Label(limitation, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: onSave) {
                Label("Save targets", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(result.energy.requiresUserConfirmation && !confirmedLargeChange)

            Button("Recalculate", systemImage: "arrow.clockwise") {
                viewModel.moveBack()
            }
            .buttonStyle(.bordered)
        }
    }

    private var targetChangeCard: some View {
        PulsarNutritionGlassCard(cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Confirm target change")
                    .font(.headline)
                if let previous = result.energy.previousTargetCalories {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Previous")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(Int(previous)) cal")
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Proposed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(Int(result.energy.targetCalories)) cal")
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                }
                ForEach(result.energy.confirmationReasons, id: \.self) { reason in
                    Label(reason, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Confirm new target") {
                    confirmedLargeChange = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func macroCard(_ macro: MacroRecommendation) -> some View {
        VStack(spacing: 7) {
            Image(systemName: macro.kind == .protein ? "leaf.fill" : (macro.kind == .carbohydrates ? "bolt.fill" : "drop.fill"))
                .foregroundStyle(macro.kind == .protein ? .green : (macro.kind == .carbohydrates ? .cyan : .purple))
            Text("\(Int(macro.grams))g")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(macro.kind.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.thinMaterial, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private func resultMetric(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
            .font(.caption)
    }
}

#Preview {
    OrionNutritionalCalculationFlowView(
        nutritionStore: PulsarNutritionStore(),
        profile: .empty,
        latestBodyCheckIn: nil
    )
}
