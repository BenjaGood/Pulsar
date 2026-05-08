import Foundation
import WidgetKit

struct PulsarWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: PulsarWidgetSnapshot
}

struct PulsarWidgetProvider: TimelineProvider {
    private let store = PulsarWidgetStore()

    func placeholder(in context: Context) -> PulsarWidgetEntry {
        PulsarWidgetEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (PulsarWidgetEntry) -> Void) {
        let snapshot = context.isPreview ? PulsarWidgetSnapshot.preview : store.loadSnapshot()
        completion(PulsarWidgetEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulsarWidgetEntry>) -> Void) {
        let snapshot = store.loadSnapshot()
        let entry = PulsarWidgetEntry(date: .now, snapshot: snapshot)
        let refreshDate = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }
}
