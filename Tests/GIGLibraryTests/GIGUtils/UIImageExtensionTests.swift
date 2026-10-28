import Testing
import UIKit
@testable import GIGLibrary

@MainActor
// Tests use locally-built images and temporary files — none touch `ImageDownloader`'s
// shared static state or the `UIImageView.didFinishLocalGifDecodeForTesting` seam. The `loadGif`
// tests that DO touch that shared state live in `ImageDownloaderTests` (a `.serialized` suite), so
// this suite needs no serialization and cannot race another suite over global state.
@Suite("UIImage+Extension")
struct UIImageExtensionTests {

    @Test("Given valid GIF bytes in a data URL, when using the legacy URL loader, then the non-file input is rejected")
    func legacyGIFRejectsDataURL() {
        let url = "data:image/gif;base64," + budgetGIF(delays: [10]).base64EncodedString()
        #expect(UIImage.gif(url: url) == nil)
    }

    @Test("Given a non-file URL, when using the legacy GIF loader, then it is rejected",
          arguments: ["https://example.invalid/image.gif", "HTTP://example.invalid/image.gif",
                      "ftp://example.invalid/image.gif", "//example.invalid/image.gif",
                      "image.gif"])
    func legacyGIFRejectsNonFileURL(url: String) {
        #expect(UIImage.gif(url: url) == nil)
    }

    @Test("Given a local GIF file, when using the legacy URL loader, then animation and timing are preserved",
          arguments: ["file", "FILE"])
    func legacyGIFLoadsLocalFile(scheme: String) throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + " local image.gif")
        try budgetGIF(delays: [10, 20]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let url = scheme + file.absoluteString.dropFirst("file".count)
        let image = try #require(UIImage.gif(url: url))
        #expect(image.images?.count == 3)
        #expect(abs(image.duration - 0.3) < 0.0001)
    }

    @Test("Given a local GIF at or above the byte limit, when loaded, then both APIs enforce the complete-file budget",
          arguments: [0, 1, 1024 * 1024])
    func localGIFByteBudget(extraBytes: Int) async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        var data = budgetGIF(delays: [10, 20])
        data.append(Data(repeating: 0, count: 20 * 1024 * 1024 + extraBytes - data.count))
        try data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let legacy = UIImage.gif(url: file.absoluteString)
        let asynchronous = await UIImage.decodedGif(fileURL: file)
        if extraBytes > 0 {
            #expect(legacy == nil)
            #expect(asynchronous == nil)
        } else {
            let legacyImage = try #require(legacy)
            let asynchronousImage = try #require(asynchronous)
            #expect(legacyImage.images?.count == 3)
            #expect(asynchronousImage.images?.count == 3)
            #expect(abs(legacyImage.duration - 0.3) < 0.0001)
            #expect(abs(asynchronousImage.duration - 0.3) < 0.0001)
        }
    }

    @Test("Given an opened file that grows beyond the limit, when read, then only limit plus one bytes are consumed")
    func growingFileReadIsBounded() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        try budgetGIF(delays: [10, 20]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let reader = try FileHandle(forReadingFrom: file)
        defer { try? reader.close() }
        let writer = try FileHandle(forWritingTo: file)
        defer { try? writer.close() }
        // Grow the same opened file without allocating its full size in the test process.
        try writer.truncate(atOffset: 200 * 1024 * 1024)

        #expect(try UIImage.readGIFData(from: reader) == nil)
        #expect(try reader.offset() == 20 * 1024 * 1024 + 1)
    }

    @Test("Given a missing local GIF, when loaded, then both APIs return nil")
    func missingLocalGIF() async {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        #expect(UIImage.gif(url: file.absoluteString) == nil)
        let image = await UIImage.decodedGif(fileURL: file)
        #expect(image == nil)
    }

    @Test("Given a GIF over its resource budget, when decoded, then the whole animation is rejected",
          arguments: ["bytes", "count", "dimensions", "memory", "cumulativeMemory", "duration", "expansion"])
    func rejectsGIFOverBudget(kind: String) {
        let data: Data
        switch kind {
        case "bytes": data = Data(repeating: 0, count: 20 * 1024 * 1024 + 1)
        case "count": data = budgetGIF(delays: Array(repeating: 10, count: 201))
        case "dimensions": data = budgetGIF(width: 4097, height: 1, delays: [10])
        case "memory": data = budgetGIF(width: 4096, height: 4096, delays: [10])
        case "cumulativeMemory": data = budgetGIF(width: 2048, height: 2048, delays: [10, 10, 10])
        case "duration": data = budgetGIF(delays: [30000, 30001])
        default: data = budgetGIF(delays: [10, 19999])
        }
        #expect(UIImage.gif(data: data) == nil)
    }

    @Test("Given ordinary unequal GIF delays, when decoded, then animation and duration are preserved")
    func preservesGIFTiming() throws {
        let image = try #require(UIImage.gif(data: budgetGIF(delays: [10, 20])))
        #expect(image.images?.count == 3)
        #expect(abs(image.duration - 0.3) < 0.0001)
    }

    @Test("Given a GIF without delay metadata, when decoded, then it uses the default delay")
    func gifWithoutDelay() throws {
        let image = try #require(UIImage.gif(data: budgetGIF(delays: [10], includeDelay: false)))
        #expect(image.images?.count == 1)
        #expect(abs(image.duration - 0.1) < 0.0001)
    }

    @Test("Given a GIF at the source-frame limit, when decoded, then it stays animated")
    func gifAtFrameLimit() throws {
        let image = try #require(UIImage.gif(data: budgetGIF(delays: Array(repeating: 10, count: 200))))
        #expect(image.images?.count == 200)
        #expect(abs(image.duration - 20) < 0.0001)
    }

    private func budgetGIF(width: UInt16 = 1, height: UInt16 = 1,
                           delays: [UInt16], includeDelay: Bool = true) -> Data {
        // Tiny valid image blocks with independently controlled logical canvas and delays.
        var bytes = Array("GIF89a".utf8)
        bytes += [UInt8(width & 255), UInt8(width >> 8), UInt8(height & 255), UInt8(height >> 8),
                  0x80, 0, 0, 0, 0, 0, 255, 255, 255]
        for delay in delays {
            if includeDelay {
                bytes += [0x21, 0xF9, 4, 1, UInt8(delay & 255), UInt8(delay >> 8), 0, 0]
            }
            bytes += [0x2C, 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, 1, 0x44, 0]
        }
        bytes += [0x3B]
        return Data(bytes)
    }

    // MARK: - imageProportionally guards

    /// Confirms the nil→self wiring end-to-end: when `aspectFillSize` rejects the size, the original
    /// instance is returned and no zero-sized graphics context is created (which would trap with
    /// NSInternalInconsistencyException). The exhaustive degenerate matrix is covered on the pure
    /// helper in `aspectFillSizeRejectsDegenerate`; here `.zero` is the real trigger from a
    /// zero-bounds `UIImageView`, and the infinite case confirms a non-zero degenerate routes the
    /// same way.
    @Test("Given a degenerate target size, when resizing, then the original image is returned unchanged",
          arguments: [
            CGSize.zero,
            CGSize(width: 10, height: CGFloat.infinity)
          ])
    func degenerateTargetReturnsOriginal(target: CGSize) {
        let source = makeImage(size: CGSize(width: 10, height: 10))

        let result = source.imageProportionally(with: target)

        #expect(result === source)
    }

    @Test("Given a zero-sized image, when resizing to a valid target, then the original image is returned unchanged")
    func zeroSourceReturnsOriginal() {
        let source = UIImage()
        #expect(source.size == .zero)

        let result = source.imageProportionally(with: CGSize(width: 20, height: 20))

        // A zero source size would divide to produce a NaN/infinite ratio; the guard returns the
        // original instead.
        #expect(result === source)
    }

    // MARK: - imageProportionally happy path

    @Test("Given a 4x2 image, when resizing to fill 10x10, then it scales by the larger ratio to 20x10")
    func resizesAspectFill() {
        let source = makeImage(size: CGSize(width: 4, height: 2))

        let result = source.imageProportionally(with: CGSize(width: 10, height: 10))

        // Aspect-fill picks the larger ratio (10/2 = 5 over 10/4 = 2.5): 4x2 -> 20x10.
        #expect(result?.size == CGSize(width: 20, height: 10))
    }

    @Test("Given a square image, when resizing to a larger square, then it scales uniformly")
    func resizesSquareUniformly() {
        let source = makeImage(size: CGSize(width: 10, height: 10))

        let result = source.imageProportionally(with: CGSize(width: 30, height: 30))

        #expect(result?.size == CGSize(width: 30, height: 30))
    }

    @Test("Given a large image, when resizing to a smaller target, then it scales down proportionally")
    func resizesDownscale() {
        let source = makeImage(size: CGSize(width: 40, height: 40))

        let result = source.imageProportionally(with: CGSize(width: 10, height: 10))

        // ratio = 10/40 = 0.25 < 1: downscaling works through the same path as upscaling.
        #expect(result?.size == CGSize(width: 10, height: 10))
    }

    @Test("Given a valid image, when resized, then the result adopts the renderer's default screen scale")
    func resultUsesDefaultScale() {
        let source = makeImage(size: CGSize(width: 10, height: 10))

        let result = source.imageProportionally(with: CGSize(width: 20, height: 20))

        // The production code uses `UIGraphicsImageRenderer(size:)` with no explicit format, so the
        // result takes the default screen scale — matching the old `scale: 0.0` behaviour. The
        // source was built at scale 1, so this also confirms the source's own scale is not carried over.
        #expect(result?.scale == UIGraphicsImageRendererFormat.default().scale)
    }

    @Test("Given an extreme aspect ratio, when resized, then no amplified bitmap is allocated",
          arguments: [CGSize(width: 1, height: 4096), CGSize(width: 4096, height: 1)], [CGFloat(1), 2, 3])
    func extremeAspectRatioReturnsOriginal(size: CGSize, scale: CGFloat) throws {
        let original = makeImage(size: size)
        let cgImage = try #require(original.cgImage)
        let source = UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        #expect(source.imageProportionally(with: CGSize(width: 100, height: 100)) === source)
    }

    @Test("Given an oversized finite target, when resized, then the original image is preserved")
    func oversizedTargetReturnsOriginal() {
        let source = makeImage(size: CGSize(width: 10, height: 10))
        #expect(source.imageProportionally(with: CGSize(width: 100000, height: 100000)) === source)
    }

    @Test("Given render dimensions, when checking the budget, then backing scale and rounded pixels are bounded",
          arguments: [CGFloat(1), 2, 3])
    func resizeBudgetIncludesScale(scale: CGFloat) {
        #expect(UIImage.isWithinResizeBudget(size: CGSize(width: 100, height: 200), scale: scale))
        #expect(!UIImage.isWithinResizeBudget(size: CGSize(width: 3000, height: 3000), scale: scale))
        #expect(!UIImage.isWithinResizeBudget(size: CGSize(width: 1, height: 4097), scale: scale))
        #expect(UIImage.isWithinResizeBudget(size: CGSize(width: 2048 / scale, height: 4096 / scale), scale: scale))
        #expect(!UIImage.isWithinResizeBudget(size: CGSize(width: 2048.1 / scale, height: 4096 / scale), scale: scale))
    }

    // MARK: - aspectFillSize (pure size math)

    @Test("Given a finite source and target, when computing the aspect-fill size, then it scales by the larger ratio")
    func aspectFillSizeScalesByLargerRatio() {
        let result = UIImage.aspectFillSize(for: CGSize(width: 4, height: 2),
                                            fitting: CGSize(width: 10, height: 10))

        #expect(result == CGSize(width: 20, height: 10))
    }

    @Test("Given operands whose scaled product overflows to infinity, when computing the aspect-fill size, then it returns nil")
    func aspectFillSizeRejectsOverflow() {
        // Both inputs are finite and positive (they pass the input guard), but
        // heightRatio = 1e200 / 1e-200 = 1e400 overflows to +inf, so newSize is non-finite.
        // This exercises the second guard, which a real UIImage cannot reach (it would need
        // impossible pixel dimensions).
        let result = UIImage.aspectFillSize(for: CGSize(width: 1, height: 1e-200),
                                            fitting: CGSize(width: 1e200, height: 1e200))

        #expect(result == nil)
    }

    @Test("Given a degenerate source or target, when computing the aspect-fill size, then it returns nil",
          arguments: [
            (CGSize(width: 10, height: 10), CGSize.zero),
            (CGSize(width: 10, height: 10), CGSize(width: -1, height: 10)),
            (CGSize(width: 10, height: 10), CGSize(width: CGFloat.infinity, height: 10)),
            (CGSize(width: 10, height: 10), CGSize(width: CGFloat.nan, height: 10)),
            (CGSize.zero, CGSize(width: 10, height: 10)),
            (CGSize(width: CGFloat.infinity, height: 10), CGSize(width: 10, height: 10))
          ])
    func aspectFillSizeRejectsDegenerate(source: CGSize, target: CGSize) {
        #expect(UIImage.aspectFillSize(for: source, fitting: target) == nil)
    }

    // MARK: - Helpers

    /// Builds a solid-colour image of an exact point size at scale 1, so `.size` assertions are
    /// deterministic and independent of the device screen scale.
    private func makeImage(size: CGSize, color: UIColor = .red) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
