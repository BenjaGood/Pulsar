import SwiftUI

struct PulsarSyncStatusPill: View {
    @ObservedObject var center: PulsarSyncBannerCenter = .shared

    var body: some View {
        PulsarSyncStatusPillContent(state: center.state)
    }
}
