import SwiftUI

private enum FoodReviewField: Hashable {
    case productName
    case brand
    case contains
    case packageQuantity
    case packageUnit
    case servingQuantity
    case servingUnit
    case servingWeight
    case servingsPerContainer
    case ingredients
    case nutrient(FoodNutrientKey)
}

struct FoodContributionFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: FoodContributionDraftModel
    @State private var cameraStep: FoodContributionCaptureStep?
    @State private var isEditingNutrition = false
    @State private var successfulSubmissionCount = 0
    @FocusState private var focusedField: FoodReviewField?

    var useProductAction: (FoodProduct) -> Void

    init(
        product: FoodProduct,
        contributionType: FoodContributionType,
        useProductAction: @escaping (FoodProduct) -> Void
    ) {
        _model = State(initialValue: FoodContributionDraftModel(product: product, contributionType: contributionType))
        self.useProductAction = useProductAction
    }

    var body: some View {
        @Bindable var model = model
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FoodContributionBackButton(action: dismiss.callAsFunction)
                        .padding(.top, 2)

                    if model.step == .review {
                        FoodContributionHeader(step: model.step)
                            .padding(.top, 18)
                        FoodContributionReviewForm(
                            model: model,
                            isEditingNutrition: $isEditingNutrition,
                            focusedField: $focusedField
                        )
                            .padding(.top, 18)
                        if model.submissionStatus == .pendingReview {
                            Label("Submitted for community review", systemImage: "clock.badge.checkmark")
                                .foregroundStyle(.secondary)
                                .padding(.top, 18)
                        }
                        FoodSaveProductButton(
                            title: model.isSubmitting ? "Saving…" : model.submissionStatus == .failed ? "Retry submission" : "Save Product",
                            isDisabled: !model.canSubmit || model.submissionStatus == .pendingReview,
                            action: submit
                        )
                        .disabled(!model.canSubmit || model.submissionStatus == .pendingReview)
                        .padding(.top, 20)
                        if let message = model.blockingValidationMessage, !model.isSubmitting {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                                .padding(.top, 8)
                        }
                    } else {
                        FoodContributionHeader(step: model.step)
                            .padding(.top, 22)
                        FoodEvidenceCaptureSurface(
                            step: model.step,
                            height: min(360, max(320, proxy.size.width - 72)),
                            captureAction: captureCurrentStep
                        )
                        .padding(.top, 28)

                        if model.step == .front {
                            FoodManualEntryRow(action: model.enterManualEntry)
                                .padding(.top, 16)
                        } else if model.step == .ingredients {
                            Button("Skip ingredients for now", systemImage: "arrow.right") {
                                model.step = .review
                            }
                            .buttonStyle(.glass)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                        }

                        if model.isRecognizing {
                            Label("Reading this label on your device…", systemImage: "text.viewfinder")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 18)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom + 24, 40))
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background {
                Color.white
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = nil }
            }
            .onChange(of: focusedField) { _, field in
                guard let field else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    scrollProxy.scrollTo(field, anchor: .center)
                }
            }
            }
        }
        .background(Color.white.ignoresSafeArea())
        .presentationBackground(.white)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    focusedField = nil
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 17, weight: .semibold))
                }
                .accessibilityLabel("Done")
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: model.step)
        .sensoryFeedback(.success, trigger: successfulSubmissionCount)
        .fullScreenCover(item: $cameraStep) { step in
            FoodEvidenceCameraView(
                captureAction: { data in finishCapture(data, step: step) },
                cancelAction: cancelCapture
            )
            .ignoresSafeArea()
        }
        .alert("Couldn’t complete the submission", isPresented: errorBinding) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Please try again.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private func captureCurrentStep() {
        cameraStep = model.step
    }

    private func finishCapture(_ data: Data, step: FoodContributionCaptureStep) {
        cameraStep = nil
        Task { await model.captured(data, for: step) }
    }

    private func cancelCapture() {
        cameraStep = nil
    }

    private func submit() {
        Task {
            do {
                let product = try await model.submit()
                successfulSubmissionCount += 1
                useProductAction(product)
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }
}

private struct FoodContributionBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.interactive(), in: Circle())
        .clipShape(Circle())
        .accessibilityLabel("Back")
    }
}

private struct FoodContributionHeader: View {
    var step: FoodContributionCaptureStep

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(step.title)
                .font(.system(size: 30, weight: .bold, design: .default))
                .foregroundStyle(.black)
            Text(step.guidance)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.secondary)
            FoodContributionProgress(step: step)
                .padding(.top, 22)
        }
    }
}

private struct FoodContributionProgress: View {
    let step: FoodContributionCaptureStep

    private var progress: CGFloat {
        switch step {
        case .front: 1 / 3
        case .nutrition: 2 / 3
        case .ingredients, .review: 1
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.09))
                Capsule()
                    .fill(Color.black)
                    .frame(width: proxy.size.width * progress)
                    .animation(.easeInOut(duration: 0.28), value: progress)
            }
        }
        .frame(height: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Contribution progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

private struct FoodEvidenceCaptureSurface: View {
    var step: FoodContributionCaptureStep
    var height: CGFloat
    var captureAction: () -> Void

    var body: some View {
        Button(action: captureAction) {
            VStack(spacing: 17) {
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 58, height: 58)
                    .glassEffect(.clear, in: Circle())
                    .accessibilityHidden(true)

                Image(systemName: "camera")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(.primary)
                    .frame(width: 112, height: 112)
                    .glassEffect(.clear.interactive(), in: Circle())

                Text("Tap to capture")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 30, style: .continuous))
        .contentShape(.rect(cornerRadius: 32))
        .accessibilityLabel("Capture \(step.title)")
        .accessibilityHint("Opens the camera")
    }

    private var symbol: String {
        switch step {
        case .front: "shippingbox"
        case .nutrition: "list.bullet.rectangle"
        case .ingredients: "text.alignleft"
        case .review: "checkmark.seal"
        }
    }
}

private struct FoodManualEntryRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 20, weight: .medium))
                Text("Enter manually instead")
                    .font(.system(size: 17, weight: .medium))
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 66)
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.interactive(), in: .capsule)
        .accessibilityLabel("Enter manually instead")
        .accessibilityHint("Skip photo capture and enter the product details")
    }
}

private struct FoodContributionReviewForm: View {
    @Bindable var model: FoodContributionDraftModel
    @Binding var isEditingNutrition: Bool
    @FocusState.Binding var focusedField: FoodReviewField?

    var body: some View {
        VStack(spacing: 16) {
            FoodReviewGlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    FoodReviewSectionTitle(title: "Product")

                    FoodReviewTextField(label: "Product name", text: $model.name, focusField: .productName, focusedField: $focusedField)
                    FoodReviewTextField(label: "Brand", text: $model.brand, focusField: .brand, focusedField: $focusedField)
                    FoodReviewTextField(label: "Contains", text: $model.allergensText, focusField: .contains, focusedField: $focusedField)

                    HStack(spacing: 10) {
                        FoodReviewNumberField(label: "Package", value: $model.packageQuantity, focusField: .packageQuantity, focusedField: $focusedField)
                        FoodReviewUnitField(label: "Unit", value: $model.packageUnit, focusField: .packageUnit, focusedField: $focusedField)
                    }

                    HStack(spacing: 10) {
                        FoodReviewNumberField(label: "Serving size", value: $model.servingQuantity, focusField: .servingQuantity, focusedField: $focusedField)
                        FoodReviewUnitField(label: "Unit", value: $model.servingUnit, focusField: .servingUnit, focusedField: $focusedField)
                    }

                    FoodReviewNumberField(label: "Serving weight (\(model.servingWeightUnit))", value: $model.servingWeight, focusField: .servingWeight, focusedField: $focusedField)

                    FoodReviewNumberField(label: "Servings per container", value: $model.servingsPerContainer, focusField: .servingsPerContainer, focusedField: $focusedField)
                    FoodReviewTextField(label: "Ingredients", text: $model.ingredients, axis: .vertical, focusField: .ingredients, focusedField: $focusedField)
                        .lineLimit(2...5)
                }
            }

            FoodReviewGlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            FoodReviewSectionTitle(title: "Nutrition")
                            Text("Missing values stay blank—not zero.")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditingNutrition.toggle()
                            }
                        } label: {
                            Label(isEditingNutrition ? "Done" : "Edit manually", systemImage: isEditingNutrition ? "checkmark" : "pencil")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.clear.interactive(), in: Capsule())
                        .accessibilityLabel(isEditingNutrition ? "Finish editing nutrition" : "Edit nutrition manually")
                    }

                    FoodNutritionBasisMenu(model: model)

                    if isEditingNutrition {
                        FoodNutritionEditor(model: model, focusedField: $focusedField)
                    } else {
                        FoodNutritionFacts(model: model)
                    }
                }
            }

            if model.evidence.front != nil || model.evidence.nutrition != nil || model.evidence.ingredients != nil {
                FoodEvidenceReviewGrid(evidence: model.evidence)
            }
        }
    }
}

private struct FoodReviewGlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.clear, in: .rect(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.black.opacity(0.06), lineWidth: 0.7)
            }
    }
}

private struct FoodReviewSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 25, weight: .regular, design: .serif))
            .foregroundStyle(.primary)
    }
}

private struct FoodReviewTextField: View {
    let label: String
    @Binding var text: String
    var axis: Axis = .horizontal
    let focusField: FoodReviewField
    @FocusState.Binding var focusedField: FoodReviewField?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if axis == .vertical {
                TextField("—", text: $text, axis: axis)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(2...5)
                    .focused($focusedField, equals: focusField)
            } else {
                TextField("—", text: $text, axis: axis)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .focused($focusedField, equals: focusField)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 18, style: .continuous))
        .id(focusField)
    }
}

private struct FoodReviewNumberField: View {
    let label: String
    @Binding var value: Double?
    let focusField: FoodReviewField
    @FocusState.Binding var focusedField: FoodReviewField?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            TextField("—", value: $value, format: .number.precision(.fractionLength(0...3)))
                .font(.system(size: 17))
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: focusField)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 18, style: .continuous))
        .id(focusField)
    }
}

private struct FoodReviewUnitField: View {
    let label: String
    @Binding var value: String
    let focusField: FoodReviewField
    @FocusState.Binding var focusedField: FoodReviewField?

    private let commonUnits = ["serving", "piece", "pieces", "slice", "slices", "g", "grams", "oz", "ml", "cup", "tbsp", "tsp", "package", "container"]

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                TextField("unit", text: $value)
                    .font(.system(size: 17))
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: focusField)
            }
            Menu {
                ForEach(commonUnits, id: \.self) { unit in
                    Button(unit) { value = unit }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel("Choose \(label.lowercased())")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.clear.interactive(), in: .rect(cornerRadius: 18, style: .continuous))
        .id(focusField)
    }
}

private struct FoodNutritionBasisMenu: View {
    @Bindable var model: FoodContributionDraftModel

    var body: some View {
        Menu {
            ForEach(model.availableBases, id: \.self) { option in
                Button(option.title) { model.basis = option }
            }
        } label: {
            HStack(spacing: 6) {
                Text(model.basis.title)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.interactive(), in: Capsule())
        .accessibilityLabel("Nutrition basis")
    }
}

private struct FoodNutritionFacts: View {
    @Bindable var model: FoodContributionDraftModel

    private let columns: [[FoodNutrientKey]] = [
        [.protein, .fat, .saturatedFat, .transFat, .carbohydrates, .fiber, .sugars, .addedSugars],
        [.sodium, .salt, .cholesterol, .calcium, .iron, .potassium, .vitaminD]
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nutrition Facts")
                .font(.system(size: 28, weight: .black, design: .serif))
            Text("\(formatted(model.servingsPerContainer)) servings per container")
                .font(.system(size: 12, weight: .medium))
                .padding(.top, 2)
            if model.basis != .perServing {
                Text("Values per \(model.basis == .per100Milliliters ? "100 ml" : "100 g")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            Divider().overlay(.black).padding(.vertical, 6)

            Text("Serving size")
                .font(.system(size: 13, weight: .bold))
            Text(servingDescription)
                .font(.system(size: 16, weight: .bold))
            Divider().overlay(.black).padding(.vertical, 6)

            HStack(alignment: .lastTextBaseline) {
                Text("Calories")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Text(nutrientValue(for: .energyKcal))
                    .font(.system(size: 29, weight: .black))
                Text("kcal")
                    .font(.system(size: 13, weight: .medium))
            }
            Divider().overlay(.black).padding(.vertical, 5)

            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    VStack(spacing: 0) {
                        ForEach(column, id: \.self) { key in
                            FoodNutritionFactRow(
                                key: key,
                                value: nutrientValue(for: key),
                                isIndented: key == .saturatedFat || key == .transFat || key == .fiber || key == .sugars || key == .addedSugars || key == .salt
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.45), in: .rect(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.black, lineWidth: 1.5)
        }
    }

    private var servingDescription: String {
        guard let amount = model.servingQuantity else { return "—" }
        let base = "\(formatted(amount)) \(model.servingUnit)"
        guard let weight = model.servingWeight else { return base }
        guard let unit = ProductServingUnit.normalized(model.servingUnit), !unit.isMass, !unit.isVolume else { return base }
        return "\(base) (\(formatted(weight)) \(model.servingWeightUnit))"
    }

    private func nutrientValue(for key: FoodNutrientKey) -> String {
        guard let amount = model.nutrientAmount(for: key) else {
            return "— \(key.canonicalUnit)"
        }
        return "\(formatted(amount)) \(key.canonicalUnit)"
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...3)))
    }
}

private struct FoodNutritionFactRow: View {
    let key: FoodNutrientKey
    let value: String
    let isIndented: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(key.title)
                .font(.system(size: 11, weight: isIndented ? .regular : .bold))
                .padding(.leading, isIndented ? 8 : 0)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Spacer(minLength: 2)
            Text(value)
                .font(.system(size: 11, weight: isIndented ? .regular : .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.vertical, 3)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.black.opacity(0.18)).frame(height: 0.5)
        }
    }
}

private struct FoodNutritionEditor: View {
    @Bindable var model: FoodContributionDraftModel
    @FocusState.Binding var focusedField: FoodReviewField?

    var body: some View {
        VStack(spacing: 0) {
            ForEach($model.nutrients) { $nutrient in
                HStack(spacing: 8) {
                    Text(nutrient.key.title)
                        .font(.system(size: 14, weight: .medium))
                    Spacer(minLength: 8)
                    TextField("—", value: $nutrient.amount, format: .number.precision(.fractionLength(0...3)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 86)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .glassEffect(.clear.interactive(), in: Capsule())
                        .focused($focusedField, equals: .nutrient(nutrient.key))
                    Text(nutrient.key.canonicalUnit)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .leading)
                }
                .padding(.vertical, 6)
                .id(FoodReviewField.nutrient(nutrient.key))
                Divider().overlay(.black.opacity(0.12))
            }
        }
    }
}

private struct FoodSaveProductButton: View {
    let title: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(labelColor)
                    .frame(maxWidth: .infinity)

                HStack {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(labelColor)
                        .frame(width: 28, height: 28)
                    Spacer(minLength: 12)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(chevronColor)
                        .frame(width: 28, height: 28)
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 62)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .glassEffect(
            isDisabled
                ? .regular.tint(.black.opacity(0.64))
                : .regular.tint(.black.opacity(0.90)).interactive(),
            in: .capsule
        )
        .accessibilityLabel(title)
    }

    private var labelColor: Color {
        isDisabled ? .white.opacity(0.64) : .white
    }

    private var chevronColor: Color {
        isDisabled ? .white.opacity(0.48) : .white.opacity(0.72)
    }
}

private struct FoodEvidenceReviewGrid: View {
    var evidence: FoodEvidenceImages

    var body: some View {
        FoodReviewGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                FoodReviewSectionTitle(title: "Captured Labels")
                Text("Used on this device for extraction only")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, -8)
                HStack(spacing: 8) {
                    FoodEvidenceThumbnail(title: "Front", data: evidence.front)
                    FoodEvidenceThumbnail(title: "Nutrition", data: evidence.nutrition)
                    FoodEvidenceThumbnail(title: "Ingredients", data: evidence.ingredients)
                }
            }
        }
    }
}

private struct FoodEvidenceThumbnail: View {
    var title: String
    var data: Data?

    var body: some View {
        VStack(spacing: 6) {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
            Label(title, systemImage: "camera")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(.white.opacity(0.28), in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.black.opacity(0.06), lineWidth: 0.7)
        }
        .clipShape(.rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
