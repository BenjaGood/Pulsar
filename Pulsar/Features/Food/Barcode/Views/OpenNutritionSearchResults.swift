import SwiftUI

struct OpenNutritionSearchResults: View {
    var model: FoodSearchModel
    var selectAction: (FoodProduct) -> Void

    var body: some View {
        if model.state != .idle {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("OpenNutrition")
                        .pulsarTextStyle(.captionEmphasis)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.state == .loading { ProgressView().controlSize(.small) }
                }

                ForEach(model.products) { product in
                    Button {
                        selectAction(product)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: product.foodType == .restaurant ? "fork.knife" : "carrot.fill")
                                .frame(width: 24)
                                .foregroundStyle(.green)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(product.name).foregroundStyle(.primary)
                                Text(resultSubtitle(product)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "plus.circle").foregroundStyle(.green).accessibilityHidden(true)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(product.name) from OpenNutrition")
                }

                if model.canLoadMore {
                    Button("More OpenNutrition results", systemImage: "chevron.down") {
                        Task { await model.loadMore() }
                    }
                    .buttonStyle(.bordered)
                }
                switch model.state {
                case .noResults:
                    ContentUnavailableView(
                        "No OpenNutrition results",
                        systemImage: "magnifyingglass",
                        description: Text("Try another name, scan a product barcode, or enter the food manually.")
                    )
                case .failed(let error):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error.localizedDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Retry", systemImage: "arrow.clockwise") {
                            Task { await model.retry() }
                        }
                        .buttonStyle(.bordered)
                    }
                default:
                    EmptyView()
                }
                Link("Nutrition data from OpenNutrition", destination: URL(string: "https://www.opennutrition.app")!)
                    .font(.footnote)
            }
        }
    }

    private func resultSubtitle(_ product: FoodProduct) -> String {
        let kind = product.foodType?.rawValue.capitalized ?? "Food"
        return [kind, product.serving?.displayText].compactMap { $0 }.joined(separator: " · ")
    }
}
