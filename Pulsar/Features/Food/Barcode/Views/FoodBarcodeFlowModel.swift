import AVFoundation
import Foundation
import Observation

enum FoodBarcodeFlowState {
    case requestingCamera
    case scanning
    case loading(String)
    case found(FoodProduct)
    case notFound(FoodProduct)
    case contributing(FoodProduct, FoodContributionType)
    case networkUnavailable(String)
    case serviceUnavailable(String)
    case failed(String)
}

@MainActor
@Observable
final class FoodBarcodeFlowModel {
    private(set) var state: FoodBarcodeFlowState = .requestingCamera
    private(set) var successfulScanCount = 0
    var isTorchEnabled = false
    private(set) var isTorchAvailable = false

    private let repository: any FoodProductRepositoryServing
    private var lookupTask: Task<Void, Never>?
    private var lastScan: (code: String, symbology: BarcodeSymbology)?

    init(
        repository: any FoodProductRepositoryServing,
        initialState: FoodBarcodeFlowState = .requestingCamera
    ) {
        self.repository = repository
        state = initialState
    }

    func requestCamera() async {
        guard AVCaptureDevice.default(for: .video) != nil else {
            state = .failed("Barcode scanning is not available on this device.")
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let allowed: Bool
        switch status {
        case .authorized:
            allowed = true
        case .notDetermined:
            allowed = await AVCaptureDevice.requestAccess(for: .video)
        default:
            allowed = false
        }
        state = allowed ? .scanning : .failed("Camera access is required to scan a barcode. You can enable it in Settings or enter food manually.")
    }

    func received(code: String, symbology: BarcodeSymbology) {
        guard case .scanning = state else { return }
        isTorchEnabled = false
        successfulScanCount += 1
        lastScan = (code, symbology)
        state = .loading(code)
        lookupTask?.cancel()
        lookupTask = Task {
            do {
                if let product = try await repository.lookup(rawBarcode: code, symbology: symbology) {
                    state = product.isComplete ? .found(product) : .contributing(product, .nutritionUpdate)
                } else {
                    state = .notFound(missingProduct(code: code, symbology: symbology))
                }
            } catch is CancellationError {
                return
            } catch FoodProductRepositoryError.notFound {
                state = .notFound(missingProduct(code: code, symbology: symbology))
            } catch FoodProductRepositoryError.networkUnavailable {
                state = .networkUnavailable(code)
            } catch let error as FoodProductRepositoryError {
                state = .serviceUnavailable(error.localizedDescription)
            } catch {
                state = .serviceUnavailable(FoodProductRepositoryError.unknown.localizedDescription)
            }
        }
    }

    func scannerUnavailable(_ message: String) {
        state = .failed(message)
    }

    func rescan() {
        lookupTask?.cancel()
        isTorchEnabled = false
        state = .scanning
    }

    func retryLookup() {
        guard let lastScan else {
            rescan()
            return
        }
        state = .scanning
        received(code: lastScan.code, symbology: lastScan.symbology)
    }

    func reviewMissingProduct(_ product: FoodProduct) {
        state = .contributing(product, .newProduct)
    }

    func toggleTorch() {
        guard isTorchAvailable else { return }
        isTorchEnabled.toggle()
    }

    func stop() {
        lookupTask?.cancel()
        isTorchEnabled = false
    }

    func setTorchAvailability(_ isAvailable: Bool) {
        isTorchAvailable = isAvailable
        if !isAvailable {
            isTorchEnabled = false
        }
    }

    func reportLabelChanged(_ product: FoodProduct) {
        state = .contributing(product, .labelChanged)
    }

    private func missingProduct(code: String, symbology: BarcodeSymbology) -> FoodProduct {
        let normalized = (try? BarcodeNormalizer().normalize(code, symbology: symbology)) ?? code
        return FoodProduct(
            barcode: normalized,
            originalBarcode: code,
            name: "",
            source: .manual,
            verificationStatus: .communitySubmitted,
            nutrients: []
        )
    }
}
