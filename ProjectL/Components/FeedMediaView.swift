import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FeedMediaGallery: View {
    let images: [PostMedia]
    let gif: PostMedia?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(images) { image in
                StaticPostMediaView(media: image)
            }
            if let gif {
                AnimatedGIFView(media: gif)
                    .frame(height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

struct StaticPostMediaView: View {
    let media: PostMedia

    var body: some View {
        Color.clear
            .frame(height: 210)
            .overlay {
                GeometryReader { geometry in
                    mediaContent
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityIdentifier("clubFeed-image")
    }

    private var mediaContent: some View {
        Group {
            if let assetName = media.assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else if media.data != nil || media.remoteURL != nil {
                DownsampledPhoto(data: media.data, url: media.remoteURL,
                    cacheKey: media.id.uuidString, maximumPixels: 1200)
            } else {
                ZStack {
                    Color.oliveSoft
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(Color.olive)
                }
            }
        }
    }
}

struct DownsampledPhoto: View {
    let data: Data?
    let url: URL?
    let cacheKey: String
    let maximumPixels: Int
    var fit = false
    @State private var image: UIImage?
    @State private var failed = false
    private var key: String { cacheKey + ":" + String(maximumPixels) + ":" + (url?.absoluteString ?? "local") }
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: fit ? .fit : .fill)
            } else if failed {
                Image(systemName: "photo.badge.exclamationmark").foregroundStyle(Color.olive)
            } else { ProgressView().tint(Color.olive) }
        }
        .task(id: key) {
            image = nil
            failed = false
            do {
                let decoded = try await ThumbnailLoader.load(data: data, url: url, key: key, pixels: maximumPixels)
                try Task.checkCancellation()
                image = decoded
            } catch is CancellationError {
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}

@MainActor
enum ThumbnailLoader {
    static func clear() { cache.removeAllObjects() }
    static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 24 * 1024 * 1024
        cache.countLimit = 60
        return cache
    }()
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 20
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
    static func download(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              data.count <= CommunityMediaStorage.maximumFileSize else { throw URLError(.badServerResponse) }
        return data
    }

    static func load(data: Data?, url: URL?, key: String, pixels: Int) async throws -> UIImage {
        if let cached = cache.object(forKey: key as NSString) { return cached }
        let bytes: Data
        if let data { bytes = data }
        else if let url {
            bytes = try await download(from: url)
        } else { throw URLError(.badURL) }
        let image = try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixels,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
            return UIImage(cgImage: cg)
        }.value
        try Task.checkCancellation()
        cache.setObject(image, forKey: key as NSString,
            cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0))
        return image
    }
}

// MAINTENANCE-POINT: FEED-GIF-001
private struct AnimatedGIFView: View {
    let media: PostMedia

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var state: MediaState = .loading

    private enum MediaState {
        case loading
        case still(UIImage)
        case animation(GIFAnimation, startedAt: Date)
        case failed
    }

    private struct LoadKey: Equatable {
        let id: UUID
        let remoteURL: URL?
        let pixels: Int
        let firstFrameOnly: Bool
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let pixels = Int(min(1_200, max(size.width, size.height) * displayScale).rounded(.up))
            let key = LoadKey(id: media.id, remoteURL: media.remoteURL,
                pixels: pixels, firstFrameOnly: reduceMotion)

            content
                .frame(width: size.width, height: size.height)
                .task(id: key) {
                    guard pixels > 0 else { return }
                    state = .loading
                    do {
                        let next = try await load(key)
                        try Task.checkCancellation()
                        state = next
                    } catch {
                        if !Task.isCancelled { state = .failed }
                    }
                }
        }
        .onDisappear { state = .loading }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            ProgressView().tint(Color.olive)
        case .still(let image):
            display(Image(uiImage: image))
        case .animation(let animation, let startedAt):
            if reduceMotion || animation.frames.count == 1 {
                if let first = animation.frames.first {
                    display(Image(first.image, scale: 1, label: Text("GIF")))
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    if let frame = animation.frame(at: timeline.date.timeIntervalSince(startedAt)) {
                        display(Image(frame.image, scale: 1, label: Text("GIF")))
                    }
                }
            }
        case .failed:
            Image(systemName: "photo.badge.exclamationmark")
                .foregroundStyle(Color.olive)
        }
    }

    private func display(_ image: Image) -> some View {
        image.resizable()
            .scaledToFit()
            .accessibilityLabel(Text("GIF"))
            .accessibilityIdentifier("clubFeed-gif")
    }

    private func load(_ key: LoadKey) async throws -> MediaState {
        let bytes: Data
        if let data = media.data {
            bytes = data
        } else if let url = key.remoteURL {
            bytes = try await ThumbnailLoader.download(from: url)
        } else if let name = media.assetName {
            if let asset = NSDataAsset(name: name) {
                bytes = asset.data
            } else if let url = Bundle.main.url(forResource: name, withExtension: "gif") {
                bytes = try Data(contentsOf: url, options: .mappedIfSafe)
            } else if let image = UIImage(named: name) {
                return .still(image)
            } else {
                throw URLError(.fileDoesNotExist)
            }
        } else {
            throw URLError(.badURL)
        }

        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) {
            GIFAnimation.decode(bytes, maximumPixels: key.pixels, firstFrameOnly: key.firstFrameOnly)
        }
        let animation = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
        guard let animation else { throw URLError(.cannotDecodeContentData) }
        return .animation(animation, startedAt: Date())
    }
}

struct GIFAnimation {
    struct Frame {
        let image: CGImage
        let duration: TimeInterval
    }

    static let maximumFrameCount = 60
    static let minimumFrameDuration = 0.02
    private static let defaultFrameDuration = 0.1
    private static let decodedByteBudget = 24 * 1_024 * 1_024
    private static let maximumCanvasPixels = 16 * 1_024 * 1_024

    let frames: [Frame]
    private let duration: TimeInterval
    private let repeatCount: Int?

    static func decode(_ data: Data, maximumPixels: Int, firstFrameOnly: Bool = false) -> Self? {
        guard maximumPixels > 0, data.count <= CommunityMediaStorage.maximumFileSize,
              let source = CGImageSourceCreateWithData(data as CFData,
                    [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetType(source) == UTType.gif.identifier as CFString,
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any],
              let width = gif[kCGImagePropertyGIFCanvasPixelWidth] as? Int, width > 0,
              let height = gif[kCGImagePropertyGIFCanvasPixelHeight] as? Int, height > 0,
              width <= maximumCanvasPixels / height else { return nil }

        let count = min(CGImageSourceGetCount(source), firstFrameOnly ? 1 : maximumFrameCount)
        guard count > 0 else { return nil }
        // Size the thumbnails to fit the frame budget even for square images.
        let budgetPixels = Int(Double(decodedByteBudget / count / 4).squareRoot())
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maximumPixels, budgetPixels),
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        var frames: [Frame] = []
        var remainingBytes = decodedByteBudget
        for index in 0..<count {
            guard !Task.isCancelled,
                  let image = CGImageSourceCreateThumbnailAtIndex(source, index, options) else { return nil }
            let cost = image.bytesPerRow * image.height
            guard cost <= remainingBytes else { break }
            remainingBytes -= cost
            frames.append(Frame(image: image, duration: frameDuration(source, index: index)))
        }
        guard !frames.isEmpty else { return nil }
        return Self(frames: frames, duration: frames.reduce(0) { $0 + $1.duration },
            repeatCount: gif[kCGImagePropertyGIFLoopCount] as? Int)
    }

    private static func frameDuration(_ source: CGImageSource, index: Int) -> TimeInterval {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let delay = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
            ?? gif?[kCGImagePropertyGIFDelayTime] as? TimeInterval
        guard let delay, delay.isFinite, delay > 0 else { return defaultFrameDuration }
        return max(minimumFrameDuration, delay)
    }

    func frame(at elapsed: TimeInterval) -> Frame? {
        let elapsed = max(0, elapsed)
        if repeatCount != 0, elapsed >= duration * (Double(repeatCount ?? 0) + 1) {
            return frames.last
        }

        var remaining = elapsed.truncatingRemainder(dividingBy: duration)
        for frame in frames {
            if remaining < frame.duration { return frame }
            remaining -= frame.duration
        }
        return frames.last
    }
}
