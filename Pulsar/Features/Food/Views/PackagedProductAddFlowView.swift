import SwiftUI

struct PackagedProductAddFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store: PulsarNutritionStore
    @State private var showHistoryInfo = false
    let initialMoment: PulsarNutritionMealMoment
    let initialCategoryID: UUID?

    init(
        store: PulsarNutritionStore,
        initialMoment: PulsarNutritionMealMoment,
        initialCategoryID: UUID?
    ) {
        self.store = store
        self.initialMoment = initialMoment
        self.initialCategoryID = initialCategoryID
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PackagedProductAmbientBackground()
                ScrollView {
                    VStack(spacing: 28) {
                        HStack {
                            PackagedProductCircleButton(systemName: "xmark") { dismiss() }
                            Spacer()
                            PackagedProductCircleButton(systemName: "clock.arrow.circlepath") { showHistoryInfo = true }
                                .accessibilityLabel("Product history")
                        }

                        VStack(spacing: 8) {
                            Text("Add Product")
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .foregroundStyle(PackagedProductStyle.ink)
                            Text("Search or scan a product")
                                .font(.title3)
                                .foregroundStyle(PackagedProductStyle.secondary)
                        }
                        .padding(.top, 10)

                        VStack(spacing: 14) {
                            NavigationLink(value: PackagedProductRoute.search) {
                                PackagedProductActionCard(
                                    title: "Search Product",
                                    subtitle: "Find any product",
                                    systemName: "magnifyingglass",
                                    tint: .blue
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink(value: PackagedProductRoute.scanner) {
                                PackagedProductActionCard(
                                    title: "Scan Barcode",
                                    subtitle: "Scan product barcode",
                                    systemName: "viewfinder",
                                    tint: .green
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer(minLength: 90)

                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Your data is private")
                                    .font(.subheadline.weight(.semibold))
                                Text("Only community submissions are shared")
                                    .font(.footnote)
                                    .foregroundStyle(PackagedProductStyle.secondary)
                            }
                        } icon: {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.blue)
                                .padding(10)
                                .background(.blue.opacity(0.10), in: Circle())
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.78), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.9), lineWidth: 1))
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PackagedProductRoute.self) { route in
                switch route {
                case .search:
                    PackagedProductSearchView(
                        store: store,
                        initialMoment: initialMoment,
                        initialCategoryID: initialCategoryID
                    )
                case .scanner:
                    PackagedProductScannerView(
                        store: store,
                        initialMoment: initialMoment,
                        initialCategoryID: initialCategoryID
                    )
                }
            }
        }
        .presentationBackground(.white)
        .alert("Product history", isPresented: $showHistoryInfo) {
            Button("Done", role: .cancel) { }
        } message: {
            Text("Recent products are kept on this device. Community submissions are the only data shared with the food catalog.")
        }
    }
}

enum PackagedProductStyle {
    static let ink = Color(red: 0.055, green: 0.09, blue: 0.16)
    static let secondary = Color(red: 0.36, green: 0.41, blue: 0.52)
    static let surface = Color.white.opacity(0.82)
}

private struct PackagedProductAmbientBackground: View {
    var body: some View {
        ZStack {
            Color.white
            RadialGradient(colors: [.blue.opacity(0.12), .clear], center: .topLeading, startRadius: 20, endRadius: 430)
            RadialGradient(colors: [.green.opacity(0.09), .clear], center: .bottomTrailing, startRadius: 30, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

private struct PackagedProductCircleButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(PackagedProductStyle.ink)
                .frame(width: 54, height: 54)
                .background(.white.opacity(0.78), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private struct PackagedProductActionCard: View {
    let title: String
    let subtitle: String
    let systemName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: systemName)
                .font(.system(size: 29, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 70, height: 70)
                .background(tint.opacity(0.10), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.title3.weight(.semibold)).foregroundStyle(tint)
                Text(subtitle).font(.body).foregroundStyle(PackagedProductStyle.ink.opacity(0.82))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.headline.weight(.semibold))
                .foregroundStyle(PackagedProductStyle.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(PackagedProductStyle.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.95), lineWidth: 1))
        .shadow(color: .blue.opacity(0.07), radius: 22, y: 10)
    }
}

struct PackagedProductSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store: PulsarNutritionStore
    @State private var searchText = ""
    @State private var model: FoodSearchModel
    let initialMoment: PulsarNutritionMealMoment
    let initialCategoryID: UUID?

    init(store: PulsarNutritionStore, initialMoment: PulsarNutritionMealMoment, initialCategoryID: UUID?) {
        self.store = store
        self.initialMoment = initialMoment
        self.initialCategoryID = initialCategoryID
        _model = State(initialValue: FoodSearchModel(repository: FoodProductRepository.live()))
    }

    var body: some View {
        ZStack {
            PackagedProductAmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ProductSearchQueryField(searchText: $searchText)
                    ProductSearchResultsList(
                        state: model.state,
                        items: model.displayItems,
                        canLoadMore: model.canLoadMore,
                        isLoadingNextPage: model.isLoadingNextPage,
                        paginationError: model.paginationError,
                        paginationTriggerID: model.paginationTriggerID,
                        nextPage: model.nextPage,
                        retry: retrySearch,
                        loadMore: loadMoreResults
                    )
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Search Product")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ProductSearchRoute.self) { route in
            if let product = model.products.first(where: { $0.id == route.productID }) {
                PackagedProductDetailView(product: product, store: store, initialMoment: initialMoment, initialCategoryID: initialCategoryID)
            }
        }
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await model.search(searchText)
        }
    }

    private func retrySearch() {
        Task { await model.retry() }
    }

    private func loadMoreResults() async {
        await model.loadMore()
    }
}

struct PackagedProductScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store: PulsarNutritionStore
    @State private var model: FoodBarcodeFlowModel
    let initialMoment: PulsarNutritionMealMoment
    let initialCategoryID: UUID?

    init(store: PulsarNutritionStore, initialMoment: PulsarNutritionMealMoment, initialCategoryID: UUID?) {
        self.store = store
        self.initialMoment = initialMoment
        self.initialCategoryID = initialCategoryID
        _model = State(initialValue: FoodBarcodeFlowModel(repository: FoodProductRepository.live()))
    }

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.state {
            case .requestingCamera:
                ProgressView("Preparing camera…").tint(.blue)
            case .scanning:
                FoodBarcodeScannerScreen(
                    model: model,
                    backAction: dismiss.callAsFunction,
                    manualEntryAction: dismiss.callAsFunction
                )
            case .loading(let barcode):
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("Checking the product catalog…").font(.headline)
                    Text(barcode).font(.footnote.monospaced()).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .found(let product):
                PackagedProductDetailView(product: product, store: store, initialMoment: initialMoment, initialCategoryID: initialCategoryID)
            case .notFound(let product):
                MissingProductView(product: product, model: model)
            case .contributing(let product, let type):
                FoodContributionFlowView(product: product, contributionType: type, useProductAction: { _ in dismiss() })
            case .networkUnavailable:
                ScannerErrorView(title: "You’re offline", message: "Connect to the internet to check community products.", retry: model.retryLookup, rescan: model.rescan)
            case .serviceUnavailable(let message), .failed(let message):
                ScannerErrorView(title: "Couldn’t scan product", message: message, retry: model.retryLookup, rescan: model.rescan)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.requestCamera() }
        .onDisappear(perform: model.stop)
        .sensoryFeedback(.success, trigger: model.successfulScanCount)
    }
}

private struct MissingProductView: View {
    let product: FoodProduct
    let model: FoodBarcodeFlowModel

    var body: some View {
        FoodBarcodeNotFoundView(product: product, model: model)
    }
}

private struct ScannerErrorView: View {
    let title: String
    let message: String
    let retry: () -> Void
    let rescan: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "barcode.viewfinder")
        } description: { Text(message) } actions: {
            Button("Retry", action: retry)
            Button("Scan again", action: rescan)
        }
    }
}

struct PackagedProductDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let product: FoodProduct
    @ObservedObject var store: PulsarNutritionStore
    let initialMoment: PulsarNutritionMealMoment
    let initialCategoryID: UUID?
    private let visualDescriptor: ProductVisualDescriptor
    @State private var servingModel: ProductServingModel?
    @State private var isFavorite = false

    init(
        product: FoodProduct,
        store: PulsarNutritionStore,
        initialMoment: PulsarNutritionMealMoment,
        initialCategoryID: UUID?
    ) {
        self.product = product
        _store = ObservedObject(wrappedValue: store)
        self.initialMoment = initialMoment
        self.initialCategoryID = initialCategoryID
        visualDescriptor = ProductVisualDescriptor(product: product)
        _servingModel = State(initialValue: ProductServingModel(product: product))
    }

    var body: some View {
        ZStack {
            PackagedProductAmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    identity
                    if let servingModel {
                        CompactProductServingControl(model: servingModel)
                        if let calculation = servingModel.calculation {
                            macroSummary(calculation)
                            nutritionFacts(calculation)
                        } else {
                            calculationUnavailable
                        }
                    } else {
                        calculationUnavailable
                    }
                    productInformation
                    attribution
                    Button(action: addProduct) {
                        Label("Add Product", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(servingModel?.calculation?.isComplete != true)
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Favorite", systemImage: isFavorite ? "heart.fill" : "heart") { isFavorite.toggle() }
                    .tint(isFavorite ? .pink : PackagedProductStyle.ink)
                ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") }
            }
        }
    }

    private var identity: some View {
        HStack(alignment: .center, spacing: 18) {
            ProductVisualImage(
                url: product.frontImageURL,
                descriptor: visualDescriptor,
                size: 128,
                isDetailed: true
            )
            VStack(alignment: .leading, spacing: 6) {
                Text(product.name).font(.title2.bold()).foregroundStyle(PackagedProductStyle.ink)
                if let brand = product.brand, !brand.isEmpty { Text(brand).font(.headline).foregroundStyle(.secondary) }
                if product.verificationStatus.isTrusted {
                    Label("Verified Product", systemImage: "checkmark.seal.fill").font(.subheadline).foregroundStyle(.green)
                }
            }
        }
    }

    private func macroSummary(_ calculation: ProductNutritionCalculation) -> some View {
        HStack(spacing: 0) {
            MacroValue(title: "Calories", value: calculation.amount(for: .energyKcal), unit: "kcal", tint: .blue)
            MacroValue(title: "Carbs", value: calculation.amount(for: .carbohydrates), unit: "g", tint: .green)
            MacroValue(title: "Protein", value: calculation.amount(for: .protein), unit: "g", tint: .orange)
            MacroValue(title: "Fat", value: calculation.amount(for: .fat), unit: "g", tint: .pink)
        }
        .packagedProductCard()
    }

    private func nutritionFacts(_ calculation: ProductNutritionCalculation) -> some View {
        let rows = nutrientRows(for: calculation)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Nutrition Facts").font(.headline)
                Spacer()
                Text(calculation.measurement.servingText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
                .padding(.bottom, 8)
            ForEach(rows, id: \.key) { row in
                HStack {
                    Text(row.key.title).padding(.leading, row.indented ? 18 : 0)
                        .foregroundStyle(row.indented ? .secondary : PackagedProductStyle.ink)
                    Spacer()
                    Text(format(row.key, calculation: calculation)).monospacedDigit()
                }
                .font(row.indented ? .subheadline : .subheadline.weight(.medium))
                .padding(.vertical, 8)
                if row.key != rows.last?.key { Divider() }
            }
        }
        .packagedProductCard()
    }

    private var calculationUnavailable: some View {
        ContentUnavailableView(
            "Nutrition unavailable",
            systemImage: "exclamationmark.triangle",
            description: Text("This product does not include a reliable serving conversion for its nutrition basis.")
        )
        .packagedProductCard()
    }

    private var productInformation: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Product Information").font(.headline).padding(.bottom, 8)
            infoRow("Brand", product.brand)
            infoRow("Category", product.foodType?.rawValue.capitalized)
            infoRow("Barcode", product.barcode)
            infoRow("Serving", product.serving?.displayText)
            infoRow("Package", packageText)
        }
        .packagedProductCard()
    }

    private var attribution: some View {
        Text("Source: \(product.source.title)")
            .font(.footnote).foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    private var shareText: String { "\(product.name)\(product.brand.map { " by \($0)" } ?? "") — \(product.source.title)" }
    private var packageText: String? {
        guard let quantity = product.packageQuantity else { return product.packageUnit }
        return "\(quantity.formatted(.number.precision(.fractionLength(0...2)))) \(product.packageUnit ?? "")".trimmingCharacters(in: .whitespaces)
    }
    private func nutrientRows(for calculation: ProductNutritionCalculation) -> [(key: FoodNutrientKey, indented: Bool)] {
        let keys: [(FoodNutrientKey, Bool)] = [(.energyKcal, false), (.fat, false), (.saturatedFat, true), (.transFat, true), (.carbohydrates, false), (.fiber, true), (.sugars, true), (.addedSugars, true), (.protein, false), (.sodium, false), (.salt, true), (.cholesterol, false), (.potassium, false), (.calcium, false), (.iron, false), (.vitaminD, false)]
        return keys.compactMap { calculation.amount(for: $0.0) == nil ? nil : (key: $0.0, indented: $0.1) }
    }
    private func format(_ key: FoodNutrientKey, calculation: ProductNutritionCalculation) -> String {
        guard let value = calculation.amount(for: key) else { return "—" }
        return "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(key.canonicalUnit)"
    }
    @ViewBuilder private func infoRow(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) }.font(.subheadline).padding(.vertical, 7)
            Divider()
        }
    }
    private func addProduct() {
        guard let calculation = servingModel?.calculation,
              let food = calculation.foodItem(for: product) else { return }
        store.logFood(food, servingMultiplier: 1, mealMoment: initialMoment, categoryID: initialCategoryID, source: .barcodeScanner)
        dismiss()
    }
}

private struct MacroValue: View {
    let title: String
    let value: Double?
    let unit: String
    let tint: Color
    var body: some View {
        VStack(spacing: 3) {
            Text(value.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—")
                .font(.title3.weight(.semibold)).foregroundStyle(PackagedProductStyle.ink)
            Text(unit).font(.caption).foregroundStyle(.secondary)
            Circle().fill(tint).frame(width: 7, height: 7).padding(.top, 3)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension View {
    func packagedProductCard() -> some View {
        padding(16)
            .background(.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.95), lineWidth: 1))
            .shadow(color: .blue.opacity(0.05), radius: 16, y: 7)
    }
}
