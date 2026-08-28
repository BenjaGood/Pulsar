import Foundation

nonisolated protocol FoodProductRepositoryServing: Sendable {
    func lookup(rawBarcode: String, symbology: BarcodeSymbology) async throws -> FoodProduct?
    func search(query: String, page: Int, pageSize: Int) async throws -> FoodSearchPage
}

nonisolated enum FoodProductRepositoryError: LocalizedError, Equatable, Sendable {
    case notConfigured
    case unauthorized
    case forbidden
    case migrationMissing
    case datasetNotImported
    case networkUnavailable
    case requestTimedOut
    case serverUnavailable
    case decodingFailed
    case notFound
    case duplicateBarcode
    case unknown

    var errorDescription: String? {
        switch self {
        case .notConfigured, .unauthorized, .forbidden, .migrationMissing, .datasetNotImported,
             .decodingFailed, .unknown:
            "Food database temporarily unavailable. Please try again later."
        case .networkUnavailable:
            "You’re offline. Connect to the internet and try again."
        case .requestTimedOut, .serverUnavailable:
            "Couldn’t reach the food database. Please try again."
        case .notFound:
            "Product not found. Scan its nutrition label or enter it manually."
        case .duplicateBarcode:
            "OpenNutrition contains conflicting records for this barcode. Enter the label manually so Pulsar does not guess."
        }
    }

    init(_ error: FoodCommunityServiceError) {
        switch error {
        case .notConfigured: self = .notConfigured
        case .unauthorized, .authenticationFailed, .anonymousSignInsDisabled: self = .unauthorized
        case .forbidden: self = .forbidden
        case .migrationMissing: self = .migrationMissing
        case .datasetNotImported: self = .datasetNotImported
        case .networkUnavailable: self = .networkUnavailable
        case .requestTimedOut: self = .requestTimedOut
        case .serverUnavailable: self = .serverUnavailable
        case .decodingFailed, .invalidResponse: self = .decodingFailed
        case .requestFailed, .unknown: self = .unknown
        }
    }
}

actor FoodProductRepository: FoodProductRepositoryServing {
    private let normalizer: BarcodeNormalizer
    private let database: any FoodDatabaseServing
    private var inFlight: [String: Task<FoodProduct?, Error>] = [:]

    init(normalizer: BarcodeNormalizer = BarcodeNormalizer(), database: any FoodDatabaseServing) {
        self.normalizer = normalizer
        self.database = database
    }

    func lookup(rawBarcode: String, symbology: BarcodeSymbology = .unknown) async throws -> FoodProduct? {
        let normalized = try normalizer.normalize(rawBarcode, symbology: symbology)
        if let existing = inFlight[normalized] { return try await existing.value }
        let task = Task { try await performLookup(normalizedBarcode: normalized) }
        inFlight[normalized] = task
        defer { inFlight[normalized] = nil }
        return try await task.value
    }

    func search(query: String, page: Int = 1, pageSize: Int = 25) async throws -> FoodSearchPage {
        do {
            return try await database.search(query: query, page: page, pageSize: pageSize)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as FoodCommunityServiceError {
            throw FoodProductRepositoryError(error)
        } catch let error as FoodProductRepositoryError {
            throw error
        } catch {
            throw FoodProductRepositoryError.unknown
        }
    }

    private func performLookup(normalizedBarcode: String) async throws -> FoodProduct? {
        do {
            switch try await database.lookup(barcode: normalizedBarcode) {
            case .found(let product): return product
            case .notFound: throw FoodProductRepositoryError.notFound
            case .conflict: throw FoodProductRepositoryError.duplicateBarcode
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as FoodProductRepositoryError {
            throw error
        } catch let error as FoodCommunityServiceError {
            throw FoodProductRepositoryError(error)
        } catch {
            throw FoodProductRepositoryError.unknown
        }
    }

    nonisolated static func live(configuration: FoodCommunityConfiguration = .current()) -> FoodProductRepository {
        let authentication = SupabaseFoodAuthService(configuration: configuration)
        let client = SupabaseFoodRESTClient(configuration: configuration, authentication: authentication)
        return FoodProductRepository(database: PulsarFoodDatabaseService(client: client))
    }
}
