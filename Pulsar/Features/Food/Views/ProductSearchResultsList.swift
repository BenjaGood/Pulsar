import SwiftUI

struct ProductSearchQueryField: View {
    @Binding var searchText: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.blue)
                .accessibilityHidden(true)
            TextField("Search products or brands", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill", action: clearSearch)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            .white.opacity(0.84),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private func clearSearch() {
        searchText = ""
    }
}

struct ProductSearchResultsList: View {
    let state: FoodSearchState
    let items: [ProductSearchDisplayItem]
    let canLoadMore: Bool
    let isLoadingNextPage: Bool
    let paginationError: FoodProductRepositoryError?
    let paginationTriggerID: UUID?
    let nextPage: Int
    let retry: () -> Void
    let loadMore: () async -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            switch state {
            case .idle:
                ProductSearchHintView()
            case .loading:
                ForEach(0..<4, id: \.self) { _ in
                    ProductSearchSkeleton()
                }
            case .noResults:
                ContentUnavailableView(
                    "No products found",
                    systemImage: "magnifyingglass",
                    description: Text("Try a brand, product name, or barcode.")
                )
            case .failed(let error):
                ContentUnavailableView {
                    Label("Search unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Retry", action: retry)
                }
            case .results:
                ForEach(items) { item in
                    NavigationLink(value: ProductSearchRoute(productID: item.id)) {
                        ProductSearchRow(item: item)
                            .equatable()
                    }
                    .buttonStyle(.plain)

                    if canLoadMore,
                       paginationError == nil,
                       item.id == paginationTriggerID {
                        ProductSearchPaginationTrigger(page: nextPage, load: loadMore)
                    }
                }

                if isLoadingNextPage {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Loading more products")
                } else if let paginationError {
                    ProductSearchPaginationRetry(error: paginationError, retry: loadMore)
                }
            }
        }
    }
}

private struct ProductSearchHintView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.blue)
            Text("Search the community catalog")
                .font(.headline)
            Text("Results prioritize branded products with nutrition and serving information.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}

private struct ProductSearchSkeleton: View {
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12)
                .fill(.gray.opacity(0.14))
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.gray.opacity(0.14))
                    .frame(width: 190, height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(.gray.opacity(0.10))
                    .frame(width: 120, height: 12)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .white.opacity(0.72),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .redacted(reason: .placeholder)
    }
}

private struct ProductSearchRow: View, Equatable {
    let item: ProductSearchDisplayItem

    var body: some View {
        HStack(spacing: 14) {
            ProductVisualImage(
                url: item.thumbnailURL,
                descriptor: item.visualDescriptor,
                size: 64,
                isDetailed: false
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .foregroundStyle(PackagedProductStyle.ink)
                    .lineLimit(2)
                if let brand = item.brand, !brand.isEmpty {
                    Text(brand)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(item.metadataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(
            .white.opacity(0.78),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens product details")
    }

}

private struct ProductSearchPaginationTrigger: View {
    let page: Int
    let load: () async -> Void

    var body: some View {
        Color.clear
            .frame(height: 1)
            .accessibilityHidden(true)
            .task(id: page) {
                await load()
            }
    }
}

private struct ProductSearchPaginationRetry: View {
    let error: FoodProductRepositoryError
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(error.localizedDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try loading more", systemImage: "arrow.clockwise") {
                Task { await retry() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
