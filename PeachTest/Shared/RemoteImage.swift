import SwiftUI
import UIKit

@MainActor
final class PeachImageCache {
    static let shared = PeachImageCache()
    private let cache = NSCache<NSURL, UIImage>()
    private var tasks: [URL: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 180
        cache.totalCostLimit = 90 * 1024 * 1024
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let task = tasks[url] { return await task.value }
        let task = Task<UIImage?, Never> {
            do {
                var request = URLRequest(url: url)
                request.setValue("image/*", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 30
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
                guard let image = UIImage(data: data) else { return nil }
                return image
            } catch {
                return nil
            }
        }
        tasks[url] = task
        let image = await task.value
        tasks[url] = nil
        if let image {
            cache.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * 4))
        }
        return image
    }
}

struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.07))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                Image(systemName: "film")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .clipped()
        .task(id: url) {
            image = nil
            guard let url else { return }
            let loaded = await PeachImageCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}
