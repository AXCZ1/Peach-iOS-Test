#if canImport(AVFoundation)
import AVFoundation
import ImageIO
import XCTest
@testable import PeachTestCore

@MainActor
final class OriginalVideoFrameTests: XCTestCase {
    func testNativeFrameResolutionAndPersistentRangePlayback() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let movie = root.appendingPathComponent("fixture.mp4")
        try await writeVideo(to: movie)
        let fixture = RangeFixture(data: try Data(contentsOf: movie))
        let origin = URL(string: "https://peach.example.com/")!
        let cache = MediaDiskCache(root: root.appendingPathComponent("cache"))
        let first = try await PreviewRangeSource.open(origin: origin, identity: "fixture", cache: cache, fetch: fixture.fetch)
        let firstLoader = CachedPreviewAsset(source: first)
        defer { firstLoader.cancel() }
        let frame = try await OriginalVideoFrame.capture(asset: firstLoader.asset, seconds: 0.1, hls: false)
        XCTAssertEqual(frame.width, 1280)
        XCTAssertEqual(frame.height, 720)
        let data = try OriginalVideoFrame.png(frame)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let roundTrip = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        XCTAssertEqual(roundTrip.width, frame.width)
        XCTAssertEqual(roundTrip.height, frame.height)

        let afterFirst = await fixture.payloadRequests
        XCTAssertGreaterThan(afterFirst, 0)
        let reopened = MediaDiskCache(root: root.appendingPathComponent("cache"))
        let second = try await PreviewRangeSource.open(origin: origin, identity: "fixture", cache: reopened, fetch: fixture.fetch)
        let secondLoader = CachedPreviewAsset(source: second)
        defer { secondLoader.cancel() }
        let secondFrame = try await OriginalVideoFrame.capture(asset: secondLoader.asset, seconds: 0.1, hls: false)
        XCTAssertEqual(secondFrame.width, 1280)
        let afterSecond = await fixture.payloadRequests
        XCTAssertEqual(afterSecond, afterFirst, "Reopening the same source should only issue the one-byte validation probe")
    }

    private func writeVideo(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
                                                                           AVVideoWidthKey: 1280, AVVideoHeightKey: 720])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1280, kCVPixelBufferHeightKey as String: 720
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? PeachAPIError(message: "Could not start test video") }
        writer.startSession(atSourceTime: .zero)
        let pool = try XCTUnwrap(adaptor.pixelBufferPool)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer), kCVReturnSuccess)
        let pixel = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixel, [])
        if let bytes = CVPixelBufferGetBaseAddress(pixel) { memset(bytes, 127, CVPixelBufferGetDataSize(pixel)) }
        CVPixelBufferUnlockBaseAddress(pixel, [])
        for index in 0..<12 {
            let deadline = ContinuousClock.now + .seconds(3)
            while !input.isReadyForMoreMediaData, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            guard input.isReadyForMoreMediaData,
                  adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(index), timescale: 30)) else {
                throw writer.error ?? PeachAPIError(message: "Could not write test video frame")
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? PeachAPIError(message: "Could not finish test video") }
    }
}

private actor RangeFixture {
    let data: Data
    private(set) var payloadRequests = 0
    init(data: Data) { self.data = data }

    func fetch(_ range: ClosedRange<Int64>, _ validator: String?) async throws -> PreviewRangeReply {
        if range != 0...0 { payloadRequests += 1 }
        let end = min(range.upperBound, Int64(data.count) - 1)
        let response = try XCTUnwrap(HTTPByteRange("bytes \(range.lowerBound)-\(end)/\(data.count)"))
        return PreviewRangeReply(range: response, validator: "\"test-fixture\"",
                                 data: data.subdata(in: Int(range.lowerBound)..<Int(end + 1)))
    }
}
#endif
