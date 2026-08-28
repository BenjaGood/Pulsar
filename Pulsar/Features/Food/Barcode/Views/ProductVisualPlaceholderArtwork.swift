import SwiftUI

struct ProductVisualPlaceholderArtwork: View {
    let descriptor: ProductVisualDescriptor
    let size: CGFloat
    let isDetailed: Bool

    var body: some View {
        let cornerRadius = isDetailed ? size * 0.20 : size * 0.22
        let tint = descriptor.category.tint

        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.white.opacity(isDetailed ? 0.48 : 0.78))

            LinearGradient(
                colors: [tint.opacity(isDetailed ? 0.16 : 0.12), tint.opacity(0.025), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(tint.opacity(isDetailed ? 0.09 : 0.065))
                .frame(width: size * 0.76, height: size * 0.76)
                .offset(x: -size * 0.24, y: -size * 0.24)

            if let monogram = descriptor.brandMonogram {
                Text(monogram)
                    .font(.system(size: size * 0.43, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint.opacity(isDetailed ? 0.13 : 0.11))
                    .offset(x: size * 0.23, y: size * 0.23)
                    .accessibilityHidden(true)
            }

            ProductCategoryGlyph(
                category: descriptor.category,
                size: size * (isDetailed ? 0.40 : 0.38)
            )
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.96), tint.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(
            color: tint.opacity(isDetailed ? 0.08 : 0),
            radius: isDetailed ? 16 : 0,
            y: isDetailed ? 8 : 0
        )
    }
}
