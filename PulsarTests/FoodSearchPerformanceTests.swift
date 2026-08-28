import XCTest
@testable import Pulsar

@MainActor
final class FoodSearchPerformanceTests: XCTestCase {
    func testAddProductMenuUsesDistinctTypedRoutes() {
        XCTAssertNotEqual(PackagedProductRoute.search, .scanner)
    }

    func testProductSearchNavigationUsesDedicatedRouteInsteadOfRawUUID() {
        let productID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!

        let route = ProductSearchRoute(productID: productID)

        XCTAssertEqual(route.productID, productID)
    }

    func testInitialSearchUsesTwentyFiveItemsAndPreparesStableDisplayRows() async throws {
        let firstPage = makePage(page: 1, range: 0..<25, totalCount: 50)
        let repository = PaginatedFoodSearchRepository(pages: ["Yoplait": [1: firstPage]])
        let model = FoodSearchModel(repository: repository)

        await model.search("Yoplait")

        XCTAssertEqual(model.state, .results)
        XCTAssertEqual(model.products.count, 25)
        XCTAssertEqual(model.displayItems.count, 25)
        XCTAssertEqual(model.displayItems.map(\.id), model.products.map(\.id))
        XCTAssertEqual(model.paginationTriggerID, model.displayItems[20].id)
        XCTAssertTrue(model.canLoadMore)
        let requests = await repository.requests
        XCTAssertEqual(requests, [.init(query: "Yoplait", page: 1, pageSize: 25)])
    }

    func testPaginationKeepsExistingRowsVisibleAndCoalescesDuplicateRequests() async throws {
        let firstPage = makePage(page: 1, range: 0..<25, totalCount: 50)
        let secondPage = makePage(page: 2, range: 25..<50, totalCount: 50)
        let repository = PaginatedFoodSearchRepository(
            pages: ["Yoplait": [1: firstPage, 2: secondPage]],
            delays: [.init(query: "Yoplait", page: 2): .milliseconds(120)]
        )
        let model = FoodSearchModel(repository: repository)
        await model.search("Yoplait")
        let originalIDs = model.displayItems.map(\.id)

        let firstLoad = Task { await model.loadMore() }
        await waitForRequest(page: 2, repository: repository)
        let duplicateLoad = Task { await model.loadMore() }

        XCTAssertEqual(model.state, .results)
        XCTAssertTrue(model.isLoadingNextPage)
        XCTAssertEqual(model.displayItems.map(\.id), originalIDs)

        await firstLoad.value
        await duplicateLoad.value

        XCTAssertEqual(model.state, .results)
        XCTAssertFalse(model.isLoadingNextPage)
        XCTAssertEqual(model.displayItems.count, 50)
        XCTAssertEqual(Array(model.displayItems.prefix(25).map(\.id)), originalIDs)
        XCTAssertFalse(model.canLoadMore)
        let pageTwoRequests = await repository.requests.filter { $0.page == 2 }
        XCTAssertEqual(pageTwoRequests.count, 1)
    }

    func testPaginationDeduplicatesStableProductIDsWithoutRemappingPreviousRows() async {
        let firstPage = makePage(page: 1, range: 0..<25, totalCount: 49)
        var secondProducts = Array(firstPage.products.suffix(1))
        secondProducts.append(contentsOf: makeProducts(in: 25..<49))
        let secondPage = FoodSearchPage(
            products: secondProducts,
            page: 2,
            pageSize: 25,
            totalCount: 49
        )
        let repository = PaginatedFoodSearchRepository(
            pages: ["Yoplait": [1: firstPage, 2: secondPage]]
        )
        let model = FoodSearchModel(repository: repository)
        await model.search("Yoplait")
        let firstPageItems = model.displayItems

        await model.loadMore()

        XCTAssertEqual(model.displayItems.count, 49)
        XCTAssertEqual(Array(model.displayItems.prefix(25)), firstPageItems)
        XCTAssertEqual(Set(model.displayItems.map(\.id)).count, 49)
    }

    func testOlderSearchResponseCannotReplaceNewerResults() async {
        let oldPage = makePage(page: 1, range: 0..<2, totalCount: 2, namePrefix: "Old")
        let newPage = makePage(page: 1, range: 100..<102, totalCount: 2, namePrefix: "New")
        let repository = PaginatedFoodSearchRepository(
            pages: ["old": [1: oldPage], "new": [1: newPage]],
            delays: [
                .init(query: "old", page: 1): .milliseconds(180),
                .init(query: "new", page: 1): .milliseconds(10)
            ]
        )
        let model = FoodSearchModel(repository: repository)

        let oldSearch = Task { await model.search("old") }
        await waitForRequest(query: "old", page: 1, repository: repository)
        let newSearch = Task { await model.search("new") }
        await newSearch.value
        await oldSearch.value

        XCTAssertEqual(model.state, .results)
        XCTAssertTrue(model.displayItems.allSatisfy { $0.name.hasPrefix("New") })
    }

    func testPaginationFailureDoesNotDestroyVisibleRows() async {
        let firstPage = makePage(page: 1, range: 0..<25, totalCount: 50)
        let repository = PaginatedFoodSearchRepository(
            pages: ["Yoplait": [1: firstPage]],
            failures: [.init(query: "Yoplait", page: 2): .serverUnavailable]
        )
        let model = FoodSearchModel(repository: repository)
        await model.search("Yoplait")
        let visibleItems = model.displayItems

        await model.loadMore()

        XCTAssertEqual(model.state, .results)
        XCTAssertEqual(model.displayItems, visibleItems)
        XCTAssertEqual(model.paginationError, .serverUnavailable)
        XCTAssertFalse(model.isLoadingNextPage)
        XCTAssertTrue(model.canLoadMore)
    }

    private func waitForRequest(
        query: String? = nil,
        page: Int,
        repository: PaginatedFoodSearchRepository
    ) async {
        for _ in 0..<100 {
            let hasRequest = await repository.requests.contains {
                $0.page == page && (query == nil || $0.query == query)
            }
            if hasRequest { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for search page \(page)")
    }

    private func makePage(
        page: Int,
        range: Range<Int>,
        totalCount: Int,
        namePrefix: String = "Yoplait"
    ) -> FoodSearchPage {
        FoodSearchPage(
            products: makeProducts(in: range, namePrefix: namePrefix),
            page: page,
            pageSize: 25,
            totalCount: totalCount
        )
    }

    private func makeProducts(
        in range: Range<Int>,
        namePrefix: String = "Yoplait"
    ) -> [FoodProduct] {
        range.map { index in
            FoodProduct(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                name: "\(namePrefix) product \(index)",
                brand: "Yoplait",
                serving: FoodServing(quantity: 1, unit: "container", gramWeight: 150),
                source: .openNutrition,
                verificationStatus: .imported,
                nutrients: [
                    FoodNutrient(key: .energyKcal, amount: 150 + Double(index), basis: .perServing)
                ]
            )
        }
    }
}

private actor PaginatedFoodSearchRepository: FoodProductRepositoryServing {
    struct Request: Equatable, Hashable, Sendable {
        let query: String
        let page: Int
        let pageSize: Int

        init(query: String, page: Int, pageSize: Int = 25) {
            self.query = query
            self.page = page
            self.pageSize = pageSize
        }
    }

    struct PageKey: Hashable, Sendable {
        let query: String
        let page: Int
    }

    private let pages: [String: [Int: FoodSearchPage]]
    private let delays: [PageKey: Duration]
    private let failures: [PageKey: FoodProductRepositoryError]
    private(set) var requests: [Request] = []

    init(
        pages: [String: [Int: FoodSearchPage]],
        delays: [PageKey: Duration] = [:],
        failures: [PageKey: FoodProductRepositoryError] = [:]
    ) {
        self.pages = pages
        self.delays = delays
        self.failures = failures
    }

    func lookup(rawBarcode: String, symbology: BarcodeSymbology) async throws -> FoodProduct? {
        nil
    }

    func search(query: String, page: Int, pageSize: Int) async throws -> FoodSearchPage {
        requests.append(Request(query: query, page: page, pageSize: pageSize))
        let key = PageKey(query: query, page: page)
        if let delay = delays[key] {
            try await Task.sleep(for: delay)
        }
        if let failure = failures[key] {
            throw failure
        }
        return pages[query]?[page] ?? FoodSearchPage(
            products: [],
            page: page,
            pageSize: pageSize,
            totalCount: 0
        )
    }
}
