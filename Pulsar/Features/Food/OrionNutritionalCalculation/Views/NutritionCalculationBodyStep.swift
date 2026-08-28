//
//  NutritionCalculationBodyStep.swift
//  Pulsar
//

import SwiftUI

struct NutritionCalculationBodyStep: View {
    @Bindable var viewModel: NutritionalCalculationViewModel

    @FocusState private var focusedField: NutritionCalculationBodyField?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: NutritionCalculationDesign.rowSpacing) {
                NutritionCalculationSymbolBadge(
                    symbolName: "info",
                    size: 40,
                    symbolSize: 14
                )

                Text("These values are automatically filled from your Pulsar profile whenever available. Review them before Orion calculates your personalized nutrition targets.")
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(NutritionDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 14)

            separator

            NutritionCalculationEditableRow(
                title: "Age",
                symbolName: "calendar",
                isActive: focusedField == .age
            ) {
                HStack(spacing: 5) {
                    TextField("Age", value: $viewModel.input.age, format: .number)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .pulsarTextStyle(.bodyEmphasis)
                        .monospacedDigit()
                        .frame(minWidth: 44, idealWidth: 50, maxWidth: 70)
                        .focused($focusedField, equals: .age)
                        .accessibilityLabel("Age in years")

                    unit("years")
                    editIndicator
                }
            }

            separator

            NutritionCalculationEditableRow(
                title: "Height",
                symbolName: "ruler",
                isActive: focusedField == .height
            ) {
                HStack(spacing: 5) {
                    TextField(
                        "Height",
                        value: $viewModel.input.heightCentimeters,
                        format: .number.precision(.fractionLength(0...1))
                    )
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .pulsarTextStyle(.bodyEmphasis)
                    .monospacedDigit()
                    .frame(minWidth: 56, idealWidth: 64, maxWidth: 90)
                    .focused($focusedField, equals: .height)
                    .accessibilityLabel("Height in centimeters")

                    unit("cm")
                    editIndicator
                }
            }

            separator

            NutritionCalculationEditableRow(
                title: "Weight",
                symbolName: "scalemass",
                isActive: focusedField == .weight
            ) {
                HStack(spacing: 5) {
                    TextField(
                        "Weight",
                        value: $viewModel.input.weightKilograms,
                        format: .number.precision(.fractionLength(0...1))
                    )
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .pulsarTextStyle(.bodyEmphasis)
                    .monospacedDigit()
                    .frame(minWidth: 56, idealWidth: 64, maxWidth: 90)
                    .focused($focusedField, equals: .weight)
                    .accessibilityLabel("Weight in kilograms")

                    unit("kg")
                    editIndicator
                }
            }

            separator

            NutritionCalculationEditableRow(
                title: "Body fat",
                symbolName: "percent",
                isActive: focusedField == .bodyFat
            ) {
                HStack(spacing: 5) {
                    TextField(
                        "Optional",
                        value: $viewModel.input.bodyFatPercentage,
                        format: .number.precision(.fractionLength(0...1))
                    )
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .pulsarTextStyle(.bodyEmphasis)
                    .monospacedDigit()
                    .frame(minWidth: 72, idealWidth: 82, maxWidth: 120)
                    .focused($focusedField, equals: .bodyFat)
                    .accessibilityLabel("Optional body fat percentage")

                    unit("%")
                    editIndicator
                }
            }

            separator

            NutritionCalculationEditableRow(
                title: "Gender",
                symbolName: "person",
                isActive: false
            ) {
                Menu {
                    ForEach(BiologicalSex.allCases) { sex in
                        Button {
                            select(sex)
                        } label: {
                            if viewModel.input.biologicalSex == sex {
                                Label(sex.rawValue, systemImage: "checkmark")
                            } else {
                                Text(sex.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text(viewModel.input.biologicalSex.rawValue)
                            .pulsarTextStyle(.bodyEmphasis)
                            .foregroundStyle(NutritionDesign.primaryText)

                        Image(systemName: "chevron.down")
                            .pulsarTextStyle(.caption)
                            .foregroundStyle(NutritionDesign.tertiaryText)
                    }
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(NutritionCalculationPressButtonStyle(pressedScale: 0.985))
                .accessibilityLabel("Gender")
                .accessibilityValue(viewModel.input.biologicalSex.rawValue)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nutritionCalculationGlassSurface(
            cornerRadius: NutritionCalculationDesign.cardCornerRadius,
            fillOpacity: 0.60,
            borderOpacity: 0.028,
            shadowOpacity: 0.022,
            shadowRadius: 10,
            shadowY: 5
        )
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done", action: dismissKeyboard)
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(NutritionDesign.separator.opacity(0.42))
            .frame(height: 0.35)
            .padding(.leading, NutritionCalculationDesign.separatorInset)
    }

    private func unit(_ title: String) -> some View {
        Text(title)
            .pulsarTextStyle(.metadata)
            .foregroundStyle(NutritionDesign.secondaryText)
    }

    private var editIndicator: some View {
        Image(systemName: "pencil")
            .pulsarTextStyle(.caption)
            .foregroundStyle(NutritionDesign.tertiaryText.opacity(0.72))
            .accessibilityHidden(true)
    }

    private func select(_ sex: BiologicalSex) {
        withAnimation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.30, dampingFraction: 0.88)
        ) {
            viewModel.input.biologicalSex = sex
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
    }
}

#Preview("Confirm Body Info") {
    let viewModel: NutritionalCalculationViewModel = {
        let model = NutritionalCalculationViewModel(
            profile: .empty,
            latestBodyCheckIn: nil
        )
        model.input.age = 24
        model.input.heightCentimeters = 180
        model.input.weightKilograms = 100
        model.input.bodyFatPercentage = nil
        model.input.biologicalSex = .male
        return model
    }()

    ZStack {
        NutritionDesign.pageBackground
            .ignoresSafeArea()

        ScrollView {
            PulsarGlassEffectGroup(spacing: 22) {
                VStack(spacing: 18) {
                    NutritionCalculationScreenHeader(
                        title: "Confirm body info",
                        canMoveBack: true,
                        onBack: {},
                        onClose: {}
                    )

                    NutritionCalculationFlowHeader(
                        currentStep: 2,
                        totalSteps: 7,
                        progress: 2.0 / 7.0
                    )

                    NutritionCalculationBodyStep(viewModel: viewModel)
                }
            }
            .padding(.horizontal, NutritionCalculationDesign.screenHorizontalPadding)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
    .safeAreaInset(edge: .bottom) {
        NutritionCalculationContinueBar(
            title: "Continue",
            isDisabled: false,
            action: {}
        )
    }
    .pulsarFitnessMonochromeAppearance()
}
