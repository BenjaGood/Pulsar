import Foundation

struct RecoveryDriver: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case hrv
        case restingHeartRate
        case sleep
        case strain

        var id: String { rawValue }

        var title: String {
            switch self {
            case .hrv:
                "HRV"
            case .restingHeartRate:
                "Resting Heart Rate"
            case .sleep:
                "Sleep"
            case .strain:
                "Strain"
            }
        }

        var systemImage: String {
            switch self {
            case .hrv:
                "waveform.path.ecg"
            case .restingHeartRate:
                "heart.fill"
            case .sleep:
                "moon.zzz.fill"
            case .strain:
                "figure.run"
            }
        }
    }

    var id: String { kind.id }
    var kind: Kind
    var context: String
    var value: String
    var status: String
    var statusSymbol: String
}
