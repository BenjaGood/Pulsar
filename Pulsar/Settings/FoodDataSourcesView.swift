import SwiftUI

struct FoodDataSourcesView: View {
    private let openNutritionURL = URL(string: "https://www.opennutrition.app")!
    private let odblURL = URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!
    private let openFoodFactsURL = URL(string: "https://world.openfoodfacts.org")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Food Data Sources").font(.largeTitle).bold()
                Text("Pulsar identifies the source and verification state of food records. Community-verified records take priority over imported data.")
                    .foregroundStyle(.secondary)

                SettingsSectionCard(title: "OpenNutrition") {
                    sourceRow(
                        title: "Nutrition data from OpenNutrition",
                        subtitle: "Primary imported food database",
                        destination: openNutritionURL
                    )
                    SettingsDivider()
                    sourceRow(title: "Open Database License 1.0", subtitle: "Database license", destination: odblURL)
                    SettingsDivider()
                    sourceRow(
                        title: "Modified Database Contents License",
                        subtitle: "Exact terms are included with each OpenNutrition release",
                        destination: openNutritionURL
                    )
                }

                SettingsSectionCard(
                    title: "Attribution",
                    footer: "When an imported record explicitly identifies Open Food Facts as an origin, Pulsar also shows that attribution on the product. The current OpenNutrition 2025.1 release does not expose such record-level references."
                ) {
                    sourceRow(
                        title: "(c) Open Food Facts contributors",
                        subtitle: "Conditional upstream attribution",
                        destination: openFoodFactsURL
                    )
                }

                Text("User-private foods, food logs, account information, and evidence-image paths are not part of the shared OpenNutrition-derived database export.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(PulsarSettingsBackground())
        .navigationTitle("Food Data")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sourceRow(title: String, subtitle: String, destination: URL) -> some View {
        Link(destination: destination) {
            SettingsNavigationRow(
                title: title,
                subtitle: subtitle,
                symbol: "arrow.up.right.square",
                tint: .black
            )
        }
        .buttonStyle(.plain)
    }
}
