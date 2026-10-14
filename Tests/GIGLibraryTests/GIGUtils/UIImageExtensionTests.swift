import Testing
import UIKit
@testable import GIGLibrary

@MainActor
// Every test here is pure size math on locally-built images — none touch `ImageDownloader`'s
// shared static state or the `UIImageView.didFinishLocalGifDecodeForTesting` seam. The `loadGif`
// tests that DO touch that shared state live in `ImageDownloaderTests` (a `.serialized` suite), so
// this suite needs no serialization and cannot race another suite over global state.
@Suite("UIImage+Extension")
struct UIImageExtensionTests {

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
