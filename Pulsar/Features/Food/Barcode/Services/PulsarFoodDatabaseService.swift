import Foundation

nonisolated enum FoodDatabaseLookupResult: Sendable, Equatable {
    case found(FoodProduct)
    case notFound
    case conflict
}

nonisolated struct FoodSearchPage: Sendable, Equatable {
    var products: [FoodProduct]
    var page: Int
    var pageSize: Int
    var totalCount: Int

    var hasMore: Bool { products.count + ((page - 1) * pageSize) < totalCount }
}

nonisolated protocol FoodDatabaseServing: Sendable {
    func lookup(barcode: String) async throws -> FoodDatabaseLookupResult
    func search(query: String, page: Int, pageSize: Int) async throws -> FoodSearchPage
}

actor PulsarFoodDatabaseService: FoodDatabaseServing {
    private let client: SupabaseFoodRESTClient
    private var hasVerifiedDataset = false

    init(client: SupabaseFoodRESTClient) {
        self.client = client
    }

    func lookup(barcode: String) async throws -> FoodDatabaseLookupResult {
        let requestID = UUID()
        let startedAt = Date.now
        let endpoint = "/rest/v1/rpc/lookup_food_by_barcode"
        do {
            let body = try JSONEncoder.supabase.encode(BarcodeLookupRequest(barcode: barcode))
            let (data, response) = try await client.request(
                path: endpoint,
                method: "POST",
                body: body,
                authenticated: false
            )
            let row: LookupRow
            do {
                guard let decoded = try JSONDecoder.supabase.decode([LookupRow].self, from: data).first else {
                    throw FoodCommunityServiceError.decodingFailed
                }
                row = decoded
            } catch let error as FoodCommunityServiceError {
                throw error
            } catch {
                throw FoodCommunityServiceError.decodingFailed
            }
            let result: FoodDatabaseLookupResult
            switch row.status {
            case "found":
                guard let product = row.product?.domainProduct else {
                    throw FoodCommunityServiceError.decodingFailed
                }
                result = .found(product)
            case "conflict": result = .conflict
            case "not_found": result = .notFound
            case "dataset_not_imported": throw FoodCommunityServiceError.datasetNotImported
            default: throw FoodCommunityServiceError.decodingFailed
            }
            FoodDatabaseTrace.finish(
                requestID: requestID, lookupType: "barcode", normalizedInput: barcode,
                repositoryStage: "supabase_exact_lookup", endpoint: endpoint,
                httpStatus: response.statusCode, resultCount: result.resultCount,
                startedAt: startedAt, error: nil
            )
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as FoodCommunityServiceError {
            FoodDatabaseTrace.finish(
                requestID: requestID, lookupType: "barcode", normalizedInput: barcode,
                repositoryStage: "supabase_exact_lookup", endpoint: endpoint,
                httpStatus: error.httpStatus, resultCount: nil, startedAt: startedAt, error: error
            )
            throw error
        } catch {
            let mapped = FoodCommunityServiceError.unknown
            FoodDatabaseTrace.finish(
                requestID: requestID, lookupType: "barcode", normalizedInput: barcode,
                repositoryStage: "supabase_exact_lookup", endpoint: endpoint,
                httpStatus: nil, resultCount: nil, startedAt: startedAt, error: mapped
            )
            throw mapped
        }
    }

    func search(query: String, page: Int, pageSize: Int) async throws -> FoodSearchPage {
        let requestID = UUID()
        let startedAt = Date.now
        var endpoint = "/rest/v1/rpc/food_database_status"
        do {
            if !hasVerifiedDataset {
                try await ensureDatasetIsImported(endpoint: endpoint)
                hasVerifiedDataset = true
            }
            endpoint = "/rest/v1/rpc/search_food_products"
            let request = SearchRequest(query: query, page: page, pageSize: pageSize)
            let body = try JSONEncoder.supabase.encode(request)
            let (data, response) = try await client.request(
                path: endpoint,
                method: "POST",
                body: body,
                authenticated: false
            )
            let rows: [SearchRow]
            do {
                rows = try JSONDecoder.supabase.decode([SearchRow].self, from: data)
            } catch {
                throw FoodCommunityServiceError.decodingFailed
            }
            let result = FoodSearchPage(
                products: rows.map(\.product.domainProduct),
                page: max(page, 1),
                pageSize: pageSize,
                totalCount: rows.first?.totalCount ?? 0
            )
            FoodDatabaseTrace.finish(
                requestID: requestID, lookupType: "text_search", normalizedInput: query,
                repositoryStage: "supabase_search", endpoint: "/rest/v1/rpc/search_food_products",
                httpStatus: response.statusCode, resultCount: result.products.count,
                startedAt: startedAt, error: nil
            )
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as FoodCommunityServiceError {
            FoodDatabaseTrace.finish(
                requestID: requestID, lookupType: "text_search", normalizedInput: query,
                repositoryStage: endpoint.contains("status") ? "dataset_readiness" : "supabase_search",
                endpoint: endpoint, httpStatus: error.httpStatus, resultCount: nil,
                startedAt: startedAt, error: error
            )
            throw error
        } catch {
            let mapped = FoodCommunityServiceError.unknown
            FoodDatabaseTrace.finish(
                requestID: requestID, lookupType: "text_search", normalizedInput: query,
                repositoryStage: "supabase_search", endpoint: endpoint, httpStatus: nil,
                resultCount: nil, startedAt: startedAt, error: mapped
            )
            throw mapped
        }
    }

    private func ensureDatasetIsImported(endpoint: String) async throws {
        let body = Data("{}".utf8)
        let (data, _) = try await client.request(
            path: endpoint, method: "POST", body: body, authenticated: false
        )
        let status: DatabaseStatusRow
        do {
            guard let decoded = try JSONDecoder.supabase.decode([DatabaseStatusRow].self, from: data).first else {
                throw FoodCommunityServiceError.decodingFailed
            }
            status = decoded
        } catch let error as FoodCommunityServiceError {
            throw error
        } catch {
            throw FoodCommunityServiceError.decodingFailed
        }
        guard status.status == "ready", status.productCount > 0 else {
            throw FoodCommunityServiceError.datasetNotImported
        }
    }
}

nonisolated private extension FoodDatabaseLookupResult {
    var resultCount: Int {
        switch self {
        case .found: 1
        case .notFound, .conflict: 0
        }
    }
}

nonisolated private struct BarcodeLookupRequest: Encodable {
    var barcode: String
    enum CodingKeys: String, CodingKey { case barcode = "p_barcode" }
}

nonisolated private struct SearchRequest: Encodable {
    var query: String
    var page: Int
    var pageSize: Int
    enum CodingKeys: String, CodingKey {
        case query = "p_query"
        case page = "p_page"
        case pageSize = "p_page_size"
    }
}

nonisolated private struct LookupRow: Decodable {
    var status: String
    var product: ProductRow?
}

nonisolated private struct SearchRow: Decodable {
    var product: ProductRow
    var rank: Double
    var totalCount: Int
}

nonisolated private struct DatabaseStatusRow: Decodable {
    var status: String
    var datasetVersion: String?
    var productCount: Int
    var barcodeCount: Int
}

nonisolated struct ProductPayload: Codable, Sendable {
    var id: UUID?
    var barcode: String?
    var name: String
    var genericName: String?
    var brand: String?
    var countryCode: String?
    var packageQuantity: Double?
    var packageUnit: String?
    var servingQuantity: Double?
    var servingUnit: String?
    var servingGrams: Double?
    var servingMilliliters: Double?
    var servingsPerContainer: Double?
    var servingIsEstimated: Bool?
    var frontImageURL: URL?
    var nutritionImageURL: URL?
    var ingredientsImageURL: URL?
    var ingredients: String?
    var allergens: [String]
    var source: FoodProductSource
    var sourceProductID: String?
    var sourceUpdatedAt: Date?
    var verificationStatus: FoodVerificationStatus
    var rawSourcePayload: String?

    init(product: FoodProduct) {
        id = product.id
        barcode = product.barcode
        name = product.name
        genericName = product.genericName
        brand = product.brand
        countryCode = product.countryCode
        packageQuantity = product.packageQuantity
        packageUnit = product.packageUnit
        servingQuantity = product.serving?.quantity
        servingUnit = product.serving?.unit
        servingGrams = product.serving?.gramWeight
        servingMilliliters = product.serving?.milliliterVolume
        servingsPerContainer = product.servingsPerContainer
        servingIsEstimated = product.servingIsEstimated
        frontImageURL = product.frontImageURL
        nutritionImageURL = product.nutritionImageURL
        ingredientsImageURL = product.ingredientsImageURL
        ingredients = product.ingredients
        allergens = product.allergens
        source = product.source
        sourceProductID = product.sourceProductID
        sourceUpdatedAt = product.sourceUpdatedAt
        verificationStatus = product.verificationStatus
        rawSourcePayload = product.sourcePayload.flatMap { String(data: $0, encoding: .utf8) }
    }
}

nonisolated struct NutrientPayload: Codable, Sendable {
    var nutrientKey: FoodNutrientKey
    var amount: Double
    var unit: String
    var basis: FoodNutrientBasis
    var confidence: Double?

    init(_ nutrient: FoodNutrient) {
        nutrientKey = nutrient.key
        amount = nutrient.amount
        unit = nutrient.unit
        basis = nutrient.basis
        confidence = nutrient.confidence
    }
}

nonisolated private struct ProductRow: Decodable {
    var id: UUID
    var barcode: String?
    var originalBarcode: String?
    var name: String
    var genericName: String?
    var brand: String?
    var countryCode: String?
    var packageQuantity: Double?
    var packageUnit: String?
    var servingQuantity: Double?
    var servingUnit: String?
    var servingGrams: Double?
    var servingMilliliters: Double?
    var servingsPerContainer: Double?
    var servingIsEstimated: Bool?
    var frontImageURL: URL?
    var nutritionImageURL: URL?
    var ingredientsImageURL: URL?
    var ingredients: String?
    var allergens: [String]?
    var source: FoodProductSource
    var sourceProductID: String?
    var sourceDatasetVersion: String?
    var sourceURL: URL?
    var sourceReferences: [FoodSourceReference]?
    var provenanceClass: FoodProvenanceClass?
    var sourceConfidence: Double?
    var isAIEstimated: Bool?
    var foodType: OpenNutritionFoodType?
    var alternateNames: [String]?
    var sourceUpdatedAt: Date?
    var verificationStatus: FoodVerificationStatus
    var verificationCount: Int?
    var verifiedAt: Date?
    var createdAt: Date?
    var updatedAt: Date?
    var nutrients: [NutrientRow]?
    var foodProductNutrients: [NutrientRow]?

    var domainProduct: FoodProduct {
        let allNutrients = nutrients ?? foodProductNutrients ?? []
        let inferredServing = servingIsEstimated ?? (servingGrams == nil && servingMilliliters == nil)
        let resolvedServing: FoodServing? = if inferredServing {
            FoodServing(quantity: 100, unit: "g", gramWeight: 100)
        } else if let servingQuantity {
            FoodServing(
                quantity: servingQuantity,
                unit: servingUnit ?? "serving",
                gramWeight: servingGrams,
                milliliterVolume: servingMilliliters
            )
        } else {
            FoodServing(
                quantity: servingGrams ?? servingMilliliters ?? 100,
                unit: servingGrams != nil ? "g" : "ml",
                gramWeight: servingGrams,
                milliliterVolume: servingMilliliters
            )
        }
        return FoodProduct(
            id: id, barcode: barcode, originalBarcode: originalBarcode, name: name,
            genericName: genericName, brand: brand, countryCode: countryCode,
            packageQuantity: packageQuantity, packageUnit: packageUnit, serving: resolvedServing,
            servingsPerContainer: servingsPerContainer,
            servingIsEstimated: inferredServing,
            frontImageURL: frontImageURL,
            nutritionImageURL: nutritionImageURL, ingredientsImageURL: ingredientsImageURL,
            ingredients: ingredients, allergens: allergens ?? [], source: source,
            sourceProductID: sourceProductID, sourceDatasetVersion: sourceDatasetVersion,
            sourceURL: sourceURL, sourceReferences: sourceReferences ?? [],
            provenanceClass: provenanceClass, sourceConfidence: sourceConfidence,
            isAIEstimated: isAIEstimated, foodType: foodType,
            alternateNames: alternateNames ?? [], sourceUpdatedAt: sourceUpdatedAt,
            verificationStatus: verificationStatus, verificationCount: verificationCount ?? 0,
            verifiedAt: verifiedAt, nutrients: allNutrients.map(\.domainNutrient),
            sourcePayload: nil, createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

nonisolated private struct NutrientRow: Decodable {
    var id: UUID?
    var nutrientKey: FoodNutrientKey
    var amount: Double
    var unit: String
    var basis: FoodNutrientBasis
    var confidence: Double?

    var domainNutrient: FoodNutrient {
        FoodNutrient(id: id ?? UUID(), key: nutrientKey, amount: amount, unit: unit, basis: basis, confidence: confidence)
    }
}

extension JSONEncoder {
    nonisolated static var supabase: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    nonisolated static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
