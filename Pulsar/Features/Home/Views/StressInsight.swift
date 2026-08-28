import Foundation

struct StressInsight: Identifiable, Equatable {
    var id: String
    var symbol: String
    var title: String
    var description: String
    var tone: StressInsightTone
}
