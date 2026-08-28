import SwiftUI
import UIKit

struct ProductVisualImage: View {
    @Environment(\.displayScale) private var displayScale
    let url: URL?
    let descriptor: ProductVisualDescriptor
    let size: CGFloat
    let isDetailed: Bool
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            ProductVisualPlaceholder(
                descriptor: descriptor,
                size: size,
                isDetailed: isDetailed
            )

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(isDetailed ? 10 : 4)
                    .frame(width: size, height: size)
                    .background(.white.opacity(0.82))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: isDetailed ? size * 0.20 : size * 0.22))
        .task(id: loadIdentifier) {
            let loadedImage = await ProductImageCache.shared.image(
                for: url,
                pixelSize: size * displayScale
            )
            guard !Task.isCancelled else { return }
            image = loadedImage
        }
        .accessibilityHidden(true)
    }

    private var loadIdentifier: String {
        "\(url?.absoluteString ?? "placeholder")#\(Int((size * displayScale).rounded(.up)))"
    }
}
