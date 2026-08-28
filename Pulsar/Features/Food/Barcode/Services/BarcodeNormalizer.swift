import Foundation

nonisolated enum BarcodeSymbology: String, Sendable {
    case upcA
    case upcE
    case ean8
    case ean13
    case gtin14
    case unknown
}

nonisolated enum BarcodeNormalizationError: LocalizedError, Equatable {
    case nonNumeric
    case unsupportedLength
    case invalidCheckDigit

    var errorDescription: String? {
        switch self {
        case .nonNumeric: "Barcodes can contain digits only."
        case .unsupportedLength: "This barcode format is not supported."
        case .invalidCheckDigit: "The barcode check digit is invalid."
        }
    }
}

nonisolated struct BarcodeNormalizer: Sendable {
    func normalize(_ rawValue: String, symbology: BarcodeSymbology = .unknown) throws -> String {
        let digits = rawValue.filter(\.isNumber)
        guard digits.count == rawValue.filter({ !$0.isWhitespace && $0 != "-" }).count else {
            throw BarcodeNormalizationError.nonNumeric
        }

        let expanded: String
        if symbology == .upcE {
            expanded = try expandUPCE(digits)
        } else {
            expanded = digits
        }

        guard [8, 12, 13, 14].contains(expanded.count) else {
            throw BarcodeNormalizationError.unsupportedLength
        }
        guard hasValidCheckDigit(expanded) else {
            throw BarcodeNormalizationError.invalidCheckDigit
        }
        return String(repeating: "0", count: 14 - expanded.count) + expanded
    }

    func hasValidCheckDigit(_ digits: String) -> Bool {
        guard digits.count >= 2,
              let supplied = digits.last?.wholeNumberValue else { return false }
        let payload = digits.dropLast().reversed()
        let sum = payload.enumerated().reduce(0) { partial, element in
            let weight = element.offset.isMultiple(of: 2) ? 3 : 1
            return partial + (element.element.wholeNumberValue ?? 0) * weight
        }
        return (10 - sum % 10) % 10 == supplied
    }

    private func expandUPCE(_ digits: String) throws -> String {
        guard digits.count == 8 else { throw BarcodeNormalizationError.unsupportedLength }
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == 8, values[0] == 0 || values[0] == 1 else {
            throw BarcodeNormalizationError.unsupportedLength
        }

        let numberSystem = values[0]
        let data = Array(values[1...6])
        let check = values[7]
        let payload: [Int]
        switch data[5] {
        case 0, 1, 2:
            payload = [numberSystem, data[0], data[1], data[5], 0, 0, 0, 0, data[2], data[3], data[4]]
        case 3:
            payload = [numberSystem, data[0], data[1], data[2], 0, 0, 0, 0, 0, data[3], data[4]]
        case 4:
            payload = [numberSystem, data[0], data[1], data[2], data[3], 0, 0, 0, 0, 0, data[4]]
        default:
            payload = [numberSystem, data[0], data[1], data[2], data[3], data[4], 0, 0, 0, 0, data[5]]
        }
        let expanded = payload.map(String.init).joined() + String(check)
        guard hasValidCheckDigit(expanded) else { throw BarcodeNormalizationError.invalidCheckDigit }
        return expanded
    }
}
