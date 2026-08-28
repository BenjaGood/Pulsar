import SwiftUI

struct ProductCategoryGlyph: View {
    let category: ProductVisualCategory
    let size: CGFloat

    var body: some View {
        Group {
            switch category {
            case .bakery:
                Image(systemName: "birthday.cake.fill")
                    .font(.system(size: size * 0.82, weight: .medium))
            case .yogurt:
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: size * 0.82, weight: .medium))
            case .snack:
                Image(systemName: "bag.fill")
                    .font(.system(size: size * 0.82, weight: .medium))
            case .proteinBar:
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.16)
                        .strokeBorder(lineWidth: max(1.5, size * 0.07))
                        .frame(width: size, height: size * 0.48)
                    HStack(spacing: size * 0.10) {
                        Capsule().frame(width: max(1.5, size * 0.05), height: size * 0.30)
                        Capsule().frame(width: max(1.5, size * 0.05), height: size * 0.30)
                    }
                }
            case .drink:
                Image(systemName: "waterbottle.fill")
                    .font(.system(size: size * 0.86, weight: .medium))
            case .cereal:
                ProductBowlGlyphShape()
                    .stroke(
                        style: StrokeStyle(
                            lineWidth: max(1.5, size * 0.07),
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
            case .milk:
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: size * 0.10)
                        .strokeBorder(lineWidth: max(1.5, size * 0.07))
                        .frame(width: size * 0.64, height: size * 0.78)
                        .offset(y: size * 0.18)
                    Image(systemName: "chevron.compact.up")
                        .font(.system(size: size * 0.58, weight: .bold))
                }
            case .cheese:
                ZStack {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: size * 0.92, weight: .medium))
                    Circle().fill(.white.opacity(0.72)).frame(width: size * 0.12)
                        .offset(x: -size * 0.16, y: size * 0.12)
                    Circle().fill(.white.opacity(0.72)).frame(width: size * 0.09)
                        .offset(x: size * 0.14, y: size * 0.20)
                }
            case .frozen:
                Image(systemName: "snowflake")
                    .font(.system(size: size * 0.88, weight: .medium))
            case .candy:
                HStack(spacing: size * 0.03) {
                    Image(systemName: "chevron.left")
                    Capsule().frame(width: size * 0.52, height: size * 0.40)
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: size * 0.32, weight: .bold))
            case .unknown:
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: size * 0.80, weight: .medium))
            }
        }
        .foregroundStyle(category.tint)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
