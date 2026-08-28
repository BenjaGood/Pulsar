import Foundation
import Observation

@MainActor
@Observable
final class FoodSearchModel {
    private(set) var products: [FoodProduct] = []
    private(set) var displayItems: [ProductSearchDisplayItem] = []
    private(set) var state: FoodSearchState = .idle
    private(set) var canLoadMore = false
    private(set) var isLoadingNextPage = false
    private(set) var paginationError: FoodProductRepositoryError?
    private(set) var paginationTriggerID: UUID?

    private let repository: any FoodProductRepositoryServing
    private let displayItemBuilder = ProductSearchDisplayItemBuilder()
    private var query = ""
    private var page = 0
    private var generation = 0
    private var loadedProductIDs: Set<UUID> = []
    private var activeRequest: ProductSearchRequest?
    private let pageSize = 25

    var nextPage: Int { page + 1 }

    init(repository: any FoodProductRepositoryServing) {
        self.repository = repository
    }

    func search(_ rawQuery: String) async {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            generation += 1
            query = ""
            page = 0
            products = []
            displayItems = []
            loadedProductIDs = []
            canLoadMore = false
            isLoadingNextPage = false
            paginationError = nil
            paginationTriggerID = nil
            activeRequest = nil
            state = .idle
            return
        }
        generation += 1
        let currentGeneration = generation
        query = trimmed
        page = 0
        products = []
        displayItems = []
        loadedProductIDs = []
        canLoadMore = false
        isLoadingNextPage = false
        paginationError = nil
        paginationTriggerID = nil
        state = .loading
        await load(
            query: trimmed,
            page: 1,
            replacing: true,
            generation: currentGeneration
        )
    }

    func loadMore() async {
        guard canLoadMore,
              state == .results,
              !isLoadingNextPage,
              activeRequest == nil else { return }
        await load(
            query: query,
            page: nextPage,
            replacing: false,
            generation: generation
        )
    }

    func retry() async {
        guard !query.isEmpty else { return }
        generation += 1
        page = 0
        products = []
        displayItems = []
        loadedProductIDs = []
        canLoadMore = false
        isLoadingNextPage = false
        paginationError = nil
        paginationTriggerID = nil
        state = .loading
        await load(query: query, page: 1, replacing: true, generation: generation)
    }

    private func load(
        query requestedQuery: String,
        page requestedPage: Int,
        replacing: Bool,
        generation requestedGeneration: Int
    ) async {
        let request = ProductSearchRequest(generation: requestedGeneration, page: requestedPage)
        activeRequest = request
        if !replacing {
            isLoadingNextPage = true
            paginationError = nil
        }
        defer {
            if activeRequest == request {
                activeRequest = nil
                if !replacing { isLoadingNextPage = false }
            }
        }

        do {
            let result = try await repository.search(
                query: requestedQuery,
                page: requestedPage,
                pageSize: pageSize
            )
            guard !Task.isCancelled, generation == requestedGeneration else { return }

            let preparedPage = await displayItemBuilder.prepare(
                result.products,
                excluding: replacing ? [] : loadedProductIDs
            )
            guard !Task.isCancelled, generation == requestedGeneration else { return }

            if replacing {
                products = preparedPage.products
                displayItems = preparedPage.displayItems
                loadedProductIDs = preparedPage.productIDs
            } else {
                products.append(contentsOf: preparedPage.products)
                displayItems.append(contentsOf: preparedPage.displayItems)
                loadedProductIDs.formUnion(preparedPage.productIDs)
            }
            page = requestedPage
            canLoadMore = result.hasMore && !result.products.isEmpty
            paginationTriggerID = canLoadMore
                ? displayItems[max(displayItems.count - 5, 0)].id
                : nil
            state = products.isEmpty ? .noResults : .results
        } catch is CancellationError {
            if generation == requestedGeneration {
                state = products.isEmpty ? .idle : .results
            }
            return
        } catch let error as FoodProductRepositoryError {
            guard generation == requestedGeneration else { return }
            handle(error: error, replacing: replacing)
        } catch {
            guard generation == requestedGeneration else { return }
            handle(error: .unknown, replacing: replacing)
        }
    }

    private func handle(error: FoodProductRepositoryError, replacing: Bool) {
        if replacing {
            products = []
            displayItems = []
            loadedProductIDs = []
            canLoadMore = false
            paginationTriggerID = nil
            state = .failed(error)
        } else {
            paginationError = error
            state = .results
        }
    }
}

nonisolated struct ProductSearchDisplayItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let brand: String?
    let servingText: String?
    let calorieText: String?
    let metadataText: String
    let thumbnailURL: URL?
    let visualDescriptor: ProductVisualDescriptor

    init(product: FoodProduct) {
        id = product.id
        name = product.name
        brand = product.brand
        servingText = product.serving?.displayText
        let resolvedCalorieText = product.nutrientAmount(.energyKcal, servingMultiplier: 1).map {
            "\($0.formatted(.number.precision(.fractionLength(0...1)))) kcal"
        }
        calorieText = resolvedCalorieText
        metadataText = [servingText, resolvedCalorieText]
            .compactMap { $0 }
            .joined(separator: " • ")
        thumbnailURL = product.frontImageURL
        visualDescriptor = ProductVisualDescriptor(product: product)
    }
}

nonisolated private struct ProductSearchRequest: Equatable {
    let generation: Int
    let page: Int
}

nonisolated private struct PreparedProductSearchPage: Sendable {
    let products: [FoodProduct]
    let displayItems: [ProductSearchDisplayItem]
    let productIDs: Set<UUID>
}

private actor ProductSearchDisplayItemBuilder {
    func prepare(
        _ products: [FoodProduct],
        excluding existingIDs: Set<UUID>
    ) -> PreparedProductSearchPage {
        var seenIDs = existingIDs
        var preparedProducts: [FoodProduct] = []
        var preparedItems: [ProductSearchDisplayItem] = []
        preparedProducts.reserveCapacity(products.count)
        preparedItems.reserveCapacity(products.count)

        for product in products where seenIDs.insert(product.id).inserted {
            guard !Task.isCancelled else { break }
            preparedProducts.append(product)
            preparedItems.append(ProductSearchDisplayItem(product: product))
        }

        return PreparedProductSearchPage(
            products: preparedProducts,
            displayItems: preparedItems,
            productIDs: Set(preparedProducts.map(\.id))
        )
    }
}
