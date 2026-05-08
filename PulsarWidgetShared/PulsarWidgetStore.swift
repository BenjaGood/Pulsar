import Foundation

struct PulsarWidgetStore {
    static let appGroupIdentifier = "group.aetherial.Pulsar"

    private enum Keys {
        static let snapshot = "pulsar.widgets.snapshot.v1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: Self.appGroupIdentifier) ?? .standard
    }

    func loadSnapshot() -> PulsarWidgetSnapshot {
        guard let data = defaults.data(forKey: Keys.snapshot),
              let snapshot = try? decoder.decode(PulsarWidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    @discardableResult
    func save(_ snapshot: PulsarWidgetSnapshot) -> Bool {
        let current = loadSnapshot()
        guard current != snapshot else { return false }
        guard let data = try? encoder.encode(snapshot) else { return false }
        defaults.set(data, forKey: Keys.snapshot)
        return true
    }
}
