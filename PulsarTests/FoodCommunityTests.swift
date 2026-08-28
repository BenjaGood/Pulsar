import XCTest
@testable import Pulsar

final class FoodCommunityTests: XCTestCase {
    func testUPCAEANAndGTINNormalizeToGTIN14() throws {
        let normalizer = BarcodeNormalizer()
        // OpenNutrition 2025.1 fd_4PhO6yibzOp5: Dave's Killer Bread.
        XCTAssertEqual(try normalizer.normalize("013764027053", symbology: .upcA), "00013764027053")
        XCTAssertEqual(try normalizer.normalize("0013764027053", symbology: .ean13), "00013764027053")
        XCTAssertEqual(try normalizer.normalize("00013764027053", symbology: .gtin14), "00013764027053")
        // OpenNutrition 2025.1 fd_cQ05pEiqbMP7: Vitamin D Whole Milk by Lala.
        XCTAssertEqual(try normalizer.normalize("0815473015037", symbology: .ean13), "00815473015037")
        XCTAssertEqual(try normalizer.normalize("96385074", symbology: .ean8), "00000096385074")
        XCTAssertEqual(try normalizer.normalize("04252614", symbology: .upcE), "00042100005264")
    }

    func testBarcodeRejectsInvalidContentAndCheckDigit() {
        let normalizer = BarcodeNormalizer()
        XCTAssertThrowsError(try normalizer.normalize("75010A5300075"))
        XCTAssertThrowsError(try normalizer.normalize("7501055300074"))
        XCTAssertThrowsError(try normalizer.normalize("12345"))
    }

    func testExplicitZeroIsPreservedWhileAbsentNutrientIsNil() {
        let product = completeDomainProduct(status: .imported, source: .openNutrition)
        XCTAssertEqual(product.nutrient(for: .transFat)?.amount, 0)
        XCTAssertNil(product.nutrient(for: .vitaminD))
    }

    func testServingScalingSupportsPerServingPer100GramAndPerPackage() {
        let perServing = FoodProduct(
            barcode: "00012345678905", name: "Serving fixture",
            serving: FoodServing(quantity: 1, unit: "bar", gramWeight: 25),
            source: .manual, verificationStatus: .communitySubmitted,
            nutrients: [FoodNutrient(key: .protein, amount: 8, basis: .perServing)]
        )
        XCTAssertEqual(perServing.nutrientAmount(.protein, servingMultiplier: 2.5), 20)

        let per100Grams = FoodProduct(
            name: "100 g fixture", serving: FoodServing(quantity: 30, unit: "g", gramWeight: 30),
            source: .openNutrition, verificationStatus: .imported,
            nutrients: [FoodNutrient(key: .protein, amount: 10, basis: .per100Grams)]
        )
        XCTAssertEqual(per100Grams.nutrientAmount(.protein, servingMultiplier: 2), 6)

        let perPackage = FoodProduct(
            barcode: "00012345678905", name: "Package fixture", packageQuantity: 120,
            packageUnit: "g", serving: FoodServing(quantity: 1, unit: "serving", gramWeight: 30),
            source: .manual, verificationStatus: .communitySubmitted,
            nutrients: [FoodNutrient(key: .protein, amount: 24, basis: .perPackage)]
        )
        XCTAssertEqual(perPackage.nutrientAmount(.protein, servingMultiplier: 1), 6)
    }

    func testSpanishOCRParsesServingBasisUnitsAndExplicitZero() {
        let result = NutritionLabelParser().parse(lines: [
            ("Tamaño de porción 30 g", 0.99), ("Porciones por envase 5", 0.95),
            ("Contenido energético 120 kcal", 0.97), ("Proteínas 3 g", 0.94),
            ("Carbohidratos 18 g", 0.93), ("Grasas totales 4.5 g", 0.91),
            ("Grasas trans 0 g", 0.88), ("Sodio 150 mg", 0.92)
        ])
        XCTAssertEqual(result.basis, .perServing)
        XCTAssertEqual(result.serving?.gramWeight, 30)
        XCTAssertEqual(result.nutrients.first(where: { $0.key == .transFat })?.amount, 0)
    }

    func testPackageTextParserExtractsFrontProposalAndIngredientsWithoutRewritingContent() {
        let parser = FoodPackageTextParser()
        let proposal = parser.frontProposal(from: "LALA\nLeche Entera\n1 L")
        XCTAssertEqual(proposal.name, "LALA")
        XCTAssertEqual(proposal.brand, "Leche Entera")

        XCTAssertEqual(
            parser.ingredientsText(from: "Ingredientes: leche entera, vitamina D.\nContiene leche."),
            "leche entera, vitamina D. Contiene leche."
        )
        XCTAssertNil(parser.ingredientsText(from: "Nutrition Facts\nCalories 120"))
    }

    @MainActor
    func testFrontAndIngredientsEvidenceAreOptionalButNutritionEvidenceIsRequired() {
        let draft = FoodContributionDraftModel(
            product: completeDomainProduct(status: .communitySubmitted, source: .labelOCR),
            contributionType: .newProduct,
            ocr: NoopNutritionLabelOCR(),
            contributions: RetryOnceContributionMock()
        )
        XCTAssertFalse(draft.canReview)
        draft.evidence.nutrition = Data([2])
        XCTAssertTrue(draft.canReview)
    }

    @MainActor
    func testManualContributionPathJumpsToReviewWithoutPhotosAndPreservesBarcode() {
        let product = completeDomainProduct(status: .communitySubmitted, source: .manual, barcode: "00013764027053")
        let draft = FoodContributionDraftModel(
            product: product,
            contributionType: .newProduct,
            ocr: NoopNutritionLabelOCR(),
            contributions: RetryOnceContributionMock()
        )

        draft.enterManualEntry()

        XCTAssertEqual(draft.step, .review)
        XCTAssertEqual(draft.inputMode, .manual)
        XCTAssertTrue(draft.canReview)
        XCTAssertEqual(draft.confirmedProduct().barcode, "00013764027053")
    }

    func testRepositoryUsesSingleDatabaseBoundaryAndCoalescesLookups() async throws {
        let imported = completeDomainProduct(
            status: .imported, source: .openNutrition, barcode: "00013764027053"
        )
        let database = FoodDatabaseMock(result: .found(imported), delay: .milliseconds(100))
        let repository = FoodProductRepository(database: database)

        async let first = repository.lookup(rawBarcode: "013764027053", symbology: .upcA)
        async let second = repository.lookup(rawBarcode: "0013764027053", symbology: .ean13)
        let results = try await (first, second)

        XCTAssertEqual(results.0?.source, .openNutrition)
        XCTAssertEqual(results.1?.source, .openNutrition)
        let lookupCount = await database.lookupCount
        XCTAssertEqual(lookupCount, 1)
    }

    func testBarcodeConflictNeverChoosesAnImportedRecord() async {
        let repository = FoodProductRepository(database: FoodDatabaseMock(result: .conflict))
        do {
            _ = try await repository.lookup(rawBarcode: "0013764027053", symbology: .ean13)
            XCTFail("Expected an explicit conflict")
        } catch FoodProductRepositoryError.duplicateBarcode {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConfigurationRejectsMissingAndPlaceholderValues() {
        let missing = FoodCommunityConfiguration(
            supabaseURL: nil, supabaseAnonKey: nil
        )
        XCTAssertEqual(missing.validationIssue, .missingURL)

        let placeholder = FoodCommunityConfiguration(
            supabaseURL: URL(string: "https://your-project.supabase.co"),
            supabaseAnonKey: "your_public_anon_key_placeholder"
        )
        XCTAssertNotNil(placeholder.validationIssue)

        let valid = FoodCommunityConfiguration(
            supabaseURL: URL(string: "https://pulsar-food.supabase.co"),
            supabaseAnonKey: String(repeating: "a", count: 40)
        )
        XCTAssertNil(valid.validationIssue)
    }

    func testSupabasePublishableKeyIsNotTreatedAsBearerJWT() {
        XCTAssertFalse(SupabaseFoodRESTClient.isLegacyJWTAPIKey("sb_publishable_public-client-key"))
        XCTAssertTrue(SupabaseFoodRESTClient.isLegacyJWTAPIKey("eyJheader.payload.signature"))
    }

    @MainActor
    func testContributionRetryReusesDraftAndReachesPendingReview() async throws {
        let contribution = RetryOnceContributionMock()
        let draft = FoodContributionDraftModel(
            product: completeDomainProduct(status: .communitySubmitted, source: .labelOCR),
            contributionType: .newProduct,
            ocr: NoopNutritionLabelOCR(),
            contributions: contribution
        )
        draft.evidence = FoodEvidenceImages(front: Data([1]), nutrition: Data([2]), ingredients: Data([3]))

        do {
            _ = try await draft.submit()
            XCTFail("The first upload should fail")
        } catch {
            XCTAssertEqual(draft.submissionStatus, .failed)
        }

        _ = try await draft.submit()
        XCTAssertEqual(draft.submissionStatus, .pendingReview)
        XCTAssertNil(draft.evidence.front)
        XCTAssertNil(draft.evidence.nutrition)
        XCTAssertNil(draft.evidence.ingredients)
        let submissions = await contribution.submissions
        XCTAssertEqual(submissions.count, 2)
        XCTAssertEqual(submissions[0].submissionID, submissions[1].submissionID)
    }

    func testRepositoryDoesNotClassifyConfigurationOrServerFailuresAsOffline() async {
        let cases: [(FoodCommunityServiceError, FoodProductRepositoryError)] = [
            (FoodCommunityServiceError.notConfigured, FoodProductRepositoryError.notConfigured),
            (.unauthorized, .unauthorized),
            (.forbidden, .forbidden),
            (.migrationMissing, .migrationMissing),
            (.datasetNotImported, .datasetNotImported),
            (.requestTimedOut, .requestTimedOut),
            (.serverUnavailable(503), .serverUnavailable),
            (.decodingFailed, .decodingFailed),
            (.networkUnavailable, .networkUnavailable),
        ]
        for (serviceError, expected) in cases {
            let repository = FoodProductRepository(
                database: FoodDatabaseMock(result: .notFound, lookupError: serviceError)
            )
            do {
                _ = try await repository.lookup(rawBarcode: "0013764027053", symbology: .ean13)
                XCTFail("Expected \(expected)")
            } catch let actual as FoodProductRepositoryError {
                XCTAssertEqual(actual, expected)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    @MainActor
    func testSearchDistinguishesNoResultsFromRecoverableFailures() async {
        let emptyModel = FoodSearchModel(
            repository: FoodProductRepository(database: FoodDatabaseMock(result: .notFound))
        )
        await emptyModel.search("Lala")
        XCTAssertEqual(emptyModel.state, .noResults)

        let failedModel = FoodSearchModel(repository: FoodProductRepository(database: FoodDatabaseMock(
            result: .notFound, searchError: .datasetNotImported
        )))
        await failedModel.search("Lala")
        XCTAssertEqual(failedModel.state, .failed(.datasetNotImported))
    }

    @MainActor
    func testBarcodeFlowSeparatesNotFoundNetworkAndOnlineServerErrors() async {
        let notFound = FoodBarcodeFlowModel(
            repository: FoodProductRepository(database: FoodDatabaseMock(result: .notFound)),
            initialState: .scanning
        )
        // Valid EAN-13 verified absent from the OpenNutrition 2025.1 TSV.
        notFound.received(code: "9999999999994", symbology: .ean13)
        await waitForLookup(notFound)
        guard case .notFound(let draft) = notFound.state else {
            return XCTFail("Expected not-found contribution flow")
        }
        XCTAssertEqual(draft.barcode, "09999999999994")

        let network = FoodBarcodeFlowModel(
            repository: FoodProductRepository(database: FoodDatabaseMock(
                result: .notFound, lookupError: .networkUnavailable
            )), initialState: .scanning
        )
        network.received(code: "0013764027053", symbology: .ean13)
        await waitForLookup(network)
        guard case .networkUnavailable = network.state else {
            return XCTFail("Expected the genuine offline state")
        }

        let server = FoodBarcodeFlowModel(
            repository: FoodProductRepository(database: FoodDatabaseMock(
                result: .notFound, lookupError: .serverUnavailable(503)
            )), initialState: .scanning
        )
        server.received(code: "0013764027053", symbology: .ean13)
        await waitForLookup(server)
        guard case .serviceUnavailable = server.state else {
            return XCTFail("An online server failure must not be displayed as offline")
        }
    }

    @MainActor
    func testScannerIgnoresRepeatedCallbacksWhileLookupIsActive() async {
        let product = completeDomainProduct(
            status: .imported, source: .openNutrition, barcode: "00013764027053"
        )
        let database = FoodDatabaseMock(result: .found(product), delay: .milliseconds(80))
        let model = FoodBarcodeFlowModel(
            repository: FoodProductRepository(database: database), initialState: .scanning
        )
        model.received(code: "0013764027053", symbology: .ean13)
        model.received(code: "0013764027053", symbology: .ean13)
        await waitForLookup(model)
        let lookupCount = await database.lookupCount
        XCTAssertEqual(lookupCount, 1)
        XCTAssertEqual(model.successfulScanCount, 1)
    }

    func testRepositoryExposesPaginatedTextSearch() async throws {
        let product = completeDomainProduct(status: .communityVerified, source: .pulsarCommunity)
        let page = FoodSearchPage(products: [product], page: 2, pageSize: 8, totalCount: 20)
        let database = FoodDatabaseMock(result: .notFound, searchPage: page)
        let repository = FoodProductRepository(database: database)
        let result = try await repository.search(query: "café", page: 2, pageSize: 8)
        XCTAssertEqual(result.products.first?.name, "Repository fixture")
        XCTAssertTrue(result.hasMore)
    }

    func testSourceAwareAttributionAndUnknownAIEstimationDisclosure() throws {
        let sourceJSON = #"{"id":123,"database":"Open Food Facts","url":"https://world.openfoodfacts.org/product/123"}"#
        let reference = try JSONDecoder().decode(FoodSourceReference.self, from: Data(sourceJSON.utf8))
        var product = completeDomainProduct(status: .imported, source: .openNutrition)
        product.sourceReferences = [reference]
        XCTAssertTrue(product.requiresOpenNutritionAttribution)
        XCTAssertTrue(product.requiresOpenFoodFactsAttribution)
        XCTAssertNotNil(product.estimationDisclosure)

        product.isAIEstimated = true
        XCTAssertEqual(product.estimationDisclosure, "OpenNutrition marks this record as estimated.")
    }

    func testScannedProductFeedsExistingNutritionTotals() throws {
        let now = Date(timeIntervalSince1970: 1_786_500_000)
        let store = PulsarNutritionStore(
            provider: FoodCommunityNutritionProvider(), calendar: Calendar(identifier: .gregorian),
            nowProvider: { now }
        )
        let food = try XCTUnwrap(completeDomainProduct(status: .communityVerified, source: .pulsarCommunity).pulsarFoodItem())
        let entry = store.logFood(food, servingMultiplier: 2, mealMoment: .lunch, loggedAt: now)
        XCTAssertEqual(entry.nutrition.calories, 240, accuracy: 0.001)
        XCTAssertEqual(store.dashboard.totals.carbohydrates, 36, accuracy: 0.001)
    }

    private func completeDomainProduct(
        status: FoodVerificationStatus,
        source: FoodProductSource,
        barcode: String = "00013764027053"
    ) -> FoodProduct {
        FoodProduct(
            barcode: barcode, name: "Repository fixture",
            serving: FoodServing(quantity: 1, unit: "serving", gramWeight: 30), source: source,
            sourceProductID: "fd_fixture", sourceDatasetVersion: source == .openNutrition ? "2025.1" : nil,
            verificationStatus: status,
            nutrients: [
                FoodNutrient(key: .energyKcal, amount: 120, basis: .perServing),
                FoodNutrient(key: .protein, amount: 3, basis: .perServing),
                FoodNutrient(key: .carbohydrates, amount: 18, basis: .perServing),
                FoodNutrient(key: .fat, amount: 4, basis: .perServing),
                FoodNutrient(key: .transFat, amount: 0, basis: .perServing)
            ]
        )
    }

    @MainActor
    private func waitForLookup(_ model: FoodBarcodeFlowModel) async {
        for _ in 0..<100 {
            if case .loading = model.state {
                try? await Task.sleep(for: .milliseconds(10))
            } else {
                return
            }
        }
        XCTFail("Barcode lookup did not finish")
    }
}

private struct FoodCommunityNutritionProvider: PulsarNutritionProviding {
    func loadState() -> PulsarNutritionState { .empty }
    func saveState(_ state: PulsarNutritionState) throws {}
    func recoveryContext(for date: Date) -> PulsarNutritionRecoveryContext { .mock }
    func searchableFoods() -> [PulsarFoodItem] { [] }
}

private struct NoopNutritionLabelOCR: NutritionLabelOCRServing {
    func recognize(imageData: Data) async throws -> NutritionLabelOCRResult {
        NutritionLabelOCRResult(
            recognizedText: "",
            serving: nil,
            servingsPerContainer: nil,
            basis: .perServing,
            nutrients: [],
            uncertainFields: []
        )
    }
}

private actor RetryOnceContributionMock: FoodContributionServing {
    struct Submission: Sendable {
        let submissionID: UUID
    }

    private(set) var submissions: [Submission] = []

    func submit(
        submissionID: UUID,
        product: FoodProduct,
        type: FoodContributionType
    ) async throws -> FoodContribution {
        submissions.append(Submission(submissionID: submissionID))
        if submissions.count == 1 {
            throw FoodCommunityServiceError.networkUnavailable
        }
        return FoodContribution(
            id: submissionID,
            productID: nil,
            barcode: product.barcode ?? "00013764027053",
            submittedBy: nil,
            contributionType: type,
            proposedProduct: product,
            frontImagePath: nil,
            nutritionImagePath: nil,
            ingredientsImagePath: nil,
            status: .pending,
            createdAt: .now
        )
    }
}

private actor FoodDatabaseMock: FoodDatabaseServing {
    let result: FoodDatabaseLookupResult
    let searchPage: FoodSearchPage
    let delay: Duration?
    let lookupError: FoodCommunityServiceError?
    let searchError: FoodCommunityServiceError?
    private(set) var lookupCount = 0

    init(
        result: FoodDatabaseLookupResult,
        searchPage: FoodSearchPage = FoodSearchPage(products: [], page: 1, pageSize: 8, totalCount: 0),
        delay: Duration? = nil,
        lookupError: FoodCommunityServiceError? = nil,
        searchError: FoodCommunityServiceError? = nil
    ) {
        self.result = result
        self.searchPage = searchPage
        self.delay = delay
        self.lookupError = lookupError
        self.searchError = searchError
    }

    func lookup(barcode: String) async throws -> FoodDatabaseLookupResult {
        lookupCount += 1
        if let delay { try await Task.sleep(for: delay) }
        if let lookupError { throw lookupError }
        return result
    }

    func search(query: String, page: Int, pageSize: Int) async throws -> FoodSearchPage {
        if let searchError { throw searchError }
        return searchPage
    }
}
