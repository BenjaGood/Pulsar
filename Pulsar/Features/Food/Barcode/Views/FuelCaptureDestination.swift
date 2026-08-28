import Foundation

enum FuelCaptureDestination: String, Identifiable {
    case barcodeScanner

    var id: String { rawValue }
}

enum FuelCaptureFocus: Hashable {
    case search
    case foodName
}
