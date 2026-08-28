import Foundation

struct PulsarDashboardCache {
    private let defaults: UserDefaults
    private let cacheKey = "pulsar.dashboard.cache.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileCache: PulsarSyncPayloadFileCache

    init(
        defaults: UserDefaults = .standard,
        fileCache: PulsarSyncPayloadFileCache = .shared
    ) {
        self.defaults = defaults
        self.fileCache = fileCache
    }

    func loadDashboard(for day: Date, calendar: Calendar = .current) -> HomeDashboard? {
        let data = fileCache.migrateLegacyData(
            from: defaults,
            key: cacheKey,
            to: .dashboard,
            validating: { (try? JSONDecoder().decode(HomeDashboard.self, from: $0)) != nil }
        )
        guard let data,
              let dashboard = try? decoder.decode(HomeDashboard.self, from: data) else { return nil }

        let dashboardDate = dashboard.strain.date ?? dashboard.recovery.date ?? dashboard.generatedAt
        return calendar.isDate(dashboardDate, inSameDayAs: day) ? dashboard : nil
    }

    func save(_ dashboard: HomeDashboard) {
        guard let data = try? encoder.encode(dashboard) else { return }
        let revision = DispatchTime.now().uptimeNanoseconds
        Task {
            _ = await fileCache.saveEncodedData(data, for: .dashboard, revision: revision)
        }
    }
}
