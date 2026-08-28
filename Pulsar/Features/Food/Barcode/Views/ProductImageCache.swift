import ImageIO
import UIKit

actor ProductImageCache {
    static let shared = ProductImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: [String: InFlightRequest] = [:]

    init() {
        cache.countLimit = 250
        cache.totalCostLimit = 48 * 1_024 * 1_024
    }

    func image(for url: URL?, pixelSize: CGFloat) async -> UIImage? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }

        let key = "\(url.absoluteString)#\(Int(pixelSize.rounded(.up)))"
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        let waiterID = UUID()
        let task: Task<UIImage?, Never>
        if var request = inFlight[key] {
            request.waiterIDs.insert(waiterID)
            inFlight[key] = request
            task = request.task
        } else {
            task = Task.detached(priority: .utility) {
                await Self.downloadImage(from: url, pixelSize: pixelSize)
            }
            inFlight[key] = InFlightRequest(task: task, waiterIDs: [waiterID])
        }

        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { await self.cancelWaiter(waiterID, key: key) }
        }

        finishWaiter(waiterID, key: key, image: result)
        return Task.isCancelled ? nil : result
    }

    private func finishWaiter(_ waiterID: UUID, key: String, image: UIImage?) {
        guard var request = inFlight[key] else { return }
        request.waiterIDs.remove(waiterID)
        if let image {
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
            cache.setObject(image, forKey: key as NSString, cost: cost)
        }
        if request.waiterIDs.isEmpty || image != nil {
            inFlight[key] = nil
        } else {
            inFlight[key] = request
        }
    }

    private func cancelWaiter(_ waiterID: UUID, key: String) {
        guard var request = inFlight[key] else { return }
        request.waiterIDs.remove(waiterID)
        if request.waiterIDs.isEmpty {
            request.task.cancel()
            inFlight[key] = nil
        } else {
            inFlight[key] = request
        }
    }

    nonisolated private static func downloadImage(
        from url: URL,
        pixelSize: CGFloat
    ) async -> UIImage? {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 20
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled,
                  let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode,
                  let source = CGImageSourceCreateWithData(
                    data as CFData,
                    [kCGImageSourceShouldCache: false] as CFDictionary
                  ) else {
                return nil
            }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: max(pixelSize, 96),
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            ) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }

    private struct InFlightRequest {
        let task: Task<UIImage?, Never>
        var waiterIDs: Set<UUID>
    }
}
