import SwiftUI
import WidgetKit

@main
struct PulsarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PulsarMainMetricsWidget()
        PulsarStressWidget()
        if #available(iOSApplicationExtension 16.1, *) {
            PulsarGymLiveActivityWidget()
        }
    }
}

struct PulsarMainMetricsWidget: Widget {
    let kind: String = PulsarWidgetKind.mainMetrics

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulsarWidgetProvider()) { entry in
            PulsarMainMetricsWidgetView(entry: entry)
        }
        .configurationDisplayName("Pulsar Metrics")
        .description("Sleep, Recovery, and Strain in a polished at-a-glance view.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PulsarStressWidget: Widget {
    let kind: String = PulsarWidgetKind.stress

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulsarWidgetProvider()) { entry in
            PulsarStressWidgetView(entry: entry)
        }
        .configurationDisplayName("Pulsar Stress")
        .description("See your latest stress score and status without opening the app.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
