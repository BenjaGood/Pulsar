import Foundation
import Vision

nonisolated protocol NutritionLabelOCRServing: Sendable {
    func recognize(imageData: Data) async throws -> NutritionLabelOCRResult
}

actor NutritionLabelOCRService: NutritionLabelOCRServing {
    private let parser: NutritionLabelParser

    init(parser: NutritionLabelParser = NutritionLabelParser()) {
        self.parser = parser
    }

    func recognize(imageData: Data) async throws -> NutritionLabelOCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["es-MX", "es-ES", "en-US"]
        request.minimumTextHeight = 0.012

        let handler = VNImageRequestHandler(data: imageData, options: [:])
        try handler.perform([request])
        let lines = (request.results ?? []).compactMap { observation -> (String, Double)? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return (candidate.string, Double(candidate.confidence))
        }
        return parser.parse(lines: lines)
    }
}
