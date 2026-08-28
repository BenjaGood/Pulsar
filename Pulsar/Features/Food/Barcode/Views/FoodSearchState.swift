import Foundation

enum FoodSearchState: Equatable {
    case idle
    case loading
    case results
    case noResults
    case failed(FoodProductRepositoryError)
}
