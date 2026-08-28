import SwiftUI

struct StrainDetailsLoadingView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(StrainDetailsDesign.strainOrange)

            Text("Loading Strain")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .strainCardSurface()
        .accessibilityElement(children: .combine)
    }
}
