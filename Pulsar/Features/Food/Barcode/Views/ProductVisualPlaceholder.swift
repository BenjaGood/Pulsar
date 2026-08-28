import SwiftUI

struct ProductVisualPlaceholder: View {
    let descriptor: ProductVisualDescriptor
    let size: CGFloat
    let isDetailed: Bool

    @ViewBuilder
    var body: some View {
        if isDetailed {
            ProductVisualPlaceholderArtwork(
                descriptor: descriptor,
                size: size,
                isDetailed: true
            )
            .glassEffect(
                .regular.tint(descriptor.category.tint.opacity(0.06)),
                in: .rect(cornerRadius: size * 0.20)
            )
        } else {
            ProductVisualPlaceholderArtwork(
                descriptor: descriptor,
                size: size,
                isDetailed: false
            )
        }
    }
}

#Preview("Product placeholders") {
    VStack(spacing: 24) {
        ProductVisualPlaceholder(
            descriptor: ProductVisualDescriptor(name: "Yoplait Cocoa Puffs", brand: "Yoplait"),
            size: 128,
            isDetailed: true
        )

        HStack(spacing: 14) {
            ProductVisualPlaceholder(
                descriptor: ProductVisualDescriptor(name: "Bimbo White Bread", brand: "Bimbo"),
                size: 64,
                isDetailed: false
            )
            ProductVisualPlaceholder(
                descriptor: ProductVisualDescriptor(name: "Frozen Yogurt", brand: "Yoplait"),
                size: 64,
                isDetailed: false
            )
            ProductVisualPlaceholder(
                descriptor: ProductVisualDescriptor(name: "Protein Bar", brand: "Kirkland"),
                size: 64,
                isDetailed: false
            )
        }
    }
    .padding(32)
    .background(Color.white)
}
