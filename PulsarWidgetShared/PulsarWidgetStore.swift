import Foundation

struct PulsarWidgetStore {
    static let appGroupIdentifier = "group.aetherial.Pulsar"

    private enum Keys {
        static let snapshot = "pulsar.widgets.snapshot.v1"
    }

    private let defaults: UserDefaults?
    private let snapshotURL: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        self.snapshotURL = defaults == nil
            ? FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)?
                .appending(path: "PulsarWidgets", directoryHint: .isDirectory)
                .appending(path: "snapshot-v1.json", directoryHint: .notDirectory)
            : nil
    }

    func loadSnapshot() -> PulsarWidgetSnapshot {
        let data = defaults?.data(forKey: Keys.snapshot)
            ?? snapshotURL.flatMap { try? Data(contentsOf: $0) }
        guard let data,
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
        if let defaults {
            defaults.set(data, forKey: Keys.snapshot)
            return true
        }
        guard let snapshotURL else { return false }
        do {
            try FileManager.default.createDirectory(
                at: snapshotURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: snapshotURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch {
            return false
        }
    }
}
