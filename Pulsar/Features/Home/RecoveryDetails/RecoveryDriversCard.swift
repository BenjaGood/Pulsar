import SwiftUI

struct RecoveryDriversCard: View {
    var drivers: [RecoveryDriver]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Recovery Drivers")
                    .pulsarTextStyle(.sectionHeader)
                    .accessibilityAddTraits(.isHeader)

                Text("What’s impacting your recovery today")
                    .pulsarTextStyle(.metadata)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(drivers) { driver in
                    RecoveryDriverRow(driver: driver)

                    if driver.id != drivers.last?.id {
                        Divider()
                            .overlay(.primary.opacity(0.04))
                            .padding(.leading, 42)
                    }
                }
            }
        }
        .padding(RecoveryDetailsDesign.cardPadding)
        .recoveryCardSurface()
    }
}
