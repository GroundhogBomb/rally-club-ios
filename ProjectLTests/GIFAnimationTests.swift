import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ProjectL

struct GIFAnimationTests {
    @Test func decodesFramesAtDisplaySize() throws {
        let data = try makeGIF(delays: [0.15, 0.3, 0.45])
        let animation = try #require(GIFAnimation.decode(data, maximumPixels: 8))
        #expect(animation.frames.count == 3)
        #expect(animation.frames.allSatisfy { max($0.image.width, $0.image.height) == 8 })

        let reducedMotion = try #require(GIFAnimation.decode(data, maximumPixels: 8, firstFrameOnly: true))
        #expect(reducedMotion.frames.count == 1)
    }

    @Test func clampsShortDelaysAndHandlesZeroDelay() throws {
        let data = try makeGIF(delays: [0.01, 0, 0.25])
        let animation = try #require(GIFAnimation.decode(data, maximumPixels: 16))
        #expect(animation.frames.map(\.duration) == [0.02, 0.1, 0.25])
    }

    @Test func limitsTheNumberOfDecodedFrames() throws {
        let data = try makeGIF(delays: Array(repeating: 0.15, count: GIFAnimation.maximumFrameCount + 2))
        let animation = try #require(GIFAnimation.decode(data, maximumPixels: 16))
        #expect(animation.frames.count == GIFAnimation.maximumFrameCount)
    }

    @Test func invalidDataFailsToDecode() {
        #expect(GIFAnimation.decode(Data([0x47, 0x49, 0x46]), maximumPixels: 16) == nil)
    }

    private func makeGIF(delays: [TimeInterval]) throws -> Data {
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            output, UTType.gif.identifier as CFString, delays.count, nil
        ))
        let context = try #require(CGContext(
            data: nil, width: 16, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))

        for (index, delay) in delays.enumerated() {
            context.setFillColor(red: index.isMultiple(of: 2) ? 1 : 0, green: 0, blue: 0.5, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 8))
            let frame = try #require(context.makeImage())
            CGImageDestinationAddImage(destination, frame, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: delay]
            ] as CFDictionary)
        }
        try #require(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
