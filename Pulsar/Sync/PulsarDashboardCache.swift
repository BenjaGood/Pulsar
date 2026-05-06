import Foundation

struct PulsarDashboardCache {
    private let defaults: UserDefaults
    private let cacheKey = "pulsar.dashboard.cache.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadDashboard(for day: Date, calendar: Calendar = .current) -> HomeDashboard? {
        guard let data = defaults.data(forKey: cacheKey),
              let dashboard = try? decoder.decode(HomeDashboard.self, from: data) else { return nil }

        let dashboardDate = dashboard.strain.date ?? dashboard.recovery.date ?? dashboard.generatedAt
        return calendar.isDate(dashboardDate, inSameDayAs: day) ? dashboard : nil
    }

    func save(_ dashboard: HomeDashboard) {
        guard let data = try? encoder.encode(dashboard) else { return }
        defaults.set(data, forKey: cacheKey)
    }
}
