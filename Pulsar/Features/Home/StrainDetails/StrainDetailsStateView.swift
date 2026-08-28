import SwiftUI

struct StrainDetailsStateView: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: symbol,
            description: Text(message)
        )
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(20)
        .strainCardSurface()
    }
}
