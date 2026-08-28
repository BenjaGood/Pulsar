import SwiftUI

struct FoodBarcodeFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: FoodBarcodeFlowModel

    var addProductAction: (FoodProduct, Double) -> Void
    var manualEntryAction: () -> Void

    init(
        repository: any FoodProductRepositoryServing = FoodProductRepository.live(),
        addProductAction: @escaping (FoodProduct, Double) -> Void,
        manualEntryAction: @escaping () -> Void
    ) {
        _model = State(initialValue: FoodBarcodeFlowModel(repository: repository))
        self.addProductAction = addProductAction
        self.manualEntryAction = manualEntryAction
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                switch model.state {
                case .requestingCamera:
                    ProgressView("Preparing camera…")
                case .scanning:
                    FoodBarcodeScannerScreen(
                        model: model,
                        backAction: dismiss.callAsFunction,
                        manualEntryAction: chooseManualEntry
                    )
                case .loading(let barcode):
                    FoodBarcodeLoadingView(barcode: barcode)
                case .found(let product):
                    FoodProductResultView(
                        product: product,
                        addAction: { multiplier in add(product, multiplier: multiplier) },
                        labelChangedAction: { model.reportLabelChanged(product) }
                    )
                case .notFound(let product):
                    FoodBarcodeNotFoundView(product: product, model: model)
                case .contributing(let product, let type):
                    FoodContributionFlowView(
                        product: product,
                        contributionType: type,
                        useProductAction: { add($0, multiplier: 1) }
                    )
                case .networkUnavailable:
                    ContentUnavailableView {
                        Label("You’re offline", systemImage: "wifi.slash")
                    } description: {
                        Text("Connect to the internet to search Pulsar Community and OpenNutrition.")
                    } actions: {
                        Button("Retry", action: model.retryLookup)
                        Button("Enter Manually", action: chooseManualEntry)
                    }
                case .serviceUnavailable(let message):
                    ContentUnavailableView {
                        Label("Food database unavailable", systemImage: "exclamationmark.icloud")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Retry", action: model.retryLookup)
                        Button("Scan Again", action: model.rescan)
                        Button("Enter Manually", action: chooseManualEntry)
                    }
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn’t scan product", systemImage: "barcode.viewfinder")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again", action: model.rescan)
                        Button("Enter Manually", action: chooseManualEntry)
                    }
                }
            }
            .toolbar {
                if !model.state.isScanning {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close", systemImage: "xmark", action: dismiss.callAsFunction)
                    }
                }
            }
            .toolbar(model.state.isScanning ? .hidden : .visible, for: .navigationBar)
        }
        .task { await model.requestCamera() }
        .onDisappear(perform: model.stop)
        .sensoryFeedback(.success, trigger: model.successfulScanCount)
    }

    private func add(_ product: FoodProduct, multiplier: Double) {
        guard product.pulsarFoodItem() != nil else { return }
        addProductAction(product, multiplier)
        dismiss()
    }

    private func chooseManualEntry() {
        manualEntryAction()
        dismiss()
    }
}

struct FoodBarcodeNotFoundView: View {
    let product: FoodProduct
    let model: FoodBarcodeFlowModel

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                NotFoundAmbientBackground()

                GlassEffectContainer(spacing: 24) {
                    VStack(spacing: 0) {
                    Spacer(minLength: 32)

                    BarcodeNotFoundHero(size: min(proxy.size.width * 0.58, 244))

                    Text("Product not found")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .multilineTextAlignment(.center)
                        .padding(.top, 30)

                    Text("This barcode isn’t in the community catalog yet.\nAdd label photos so it can be reviewed.")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 340)
                        .padding(.top, 14)

                    Spacer(minLength: 48)

                    Button {
                        model.reviewMissingProduct(product)
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 21, weight: .medium))
                                .frame(width: 58, height: 58)
                                .notFoundGlassCircle()

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Contribute product")
                                    .font(.system(.title3, design: .rounded, weight: .semibold))
                                Text("Add label photos")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 18)
                        .frame(maxWidth: .infinity, minHeight: 112)
                        .notFoundGlassRounded(cornerRadius: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Contribute product")
                    .accessibilityHint("Add label photos")

                    Button(action: model.rescan) {
                        HStack(spacing: 14) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 18, weight: .medium))
                                .frame(width: 48, height: 48)
                                .notFoundGlassCircle()
                            Text("Scan again")
                                .font(.system(.title3, design: .rounded, weight: .medium))
                        }
                        .padding(.horizontal, 22)
                        .frame(minWidth: 210, minHeight: 82)
                        .notFoundGlassCapsule()
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 22)
                    .accessibilityLabel("Scan again")

                    Spacer(minLength: max(proxy.safeAreaInsets.bottom + 22, 36))
                }
                        .padding(.horizontal, 28)
                    }
                }
            }
        .ignoresSafeArea(edges: .bottom)
        .accessibilityElement(children: .contain)
    }
}

private struct BarcodeNotFoundHero: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: size * 0.29, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .notFoundGlassCircle()
        .accessibilityLabel("Barcode not found")
    }
}

private struct NotFoundAmbientBackground: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)

            RadialGradient(
                colors: [.black.opacity(0.045), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )

            RadialGradient(
                colors: [.white.opacity(0.9), .clear],
                center: .bottomTrailing,
                startRadius: 50,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

private extension View {
    @ViewBuilder
    func notFoundGlassCircle() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: .circle)
        } else {
            background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.28), lineWidth: 1))
        }
    }

    @ViewBuilder
    func notFoundGlassCapsule() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: .capsule)
        } else {
            background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 1))
        }
    }

    @ViewBuilder
    func notFoundGlassRounded(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius, style: .continuous))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.28), lineWidth: 1)
                )
        }
    }
}

private extension FoodBarcodeFlowState {
    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }
}

private struct FoodBarcodeLoadingView: View {
    var barcode: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Checking community and OpenNutrition…").font(.headline)
            Text(barcode).font(.footnote).monospaced().foregroundStyle(.secondary)
            Text("Then Pulsar checks the active OpenNutrition dataset.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}
