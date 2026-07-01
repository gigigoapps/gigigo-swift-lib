import Testing
import UIKit
@testable import GIGLibrary

@MainActor
// Serialized: `loadGifNameMissingPreservesImage` installs the global `UIImageView`
// `didFinishLocalGifDecodeForTesting` seam and consumes it via a `CheckedContinuation`. Parallel
// tests touching that shared static could resume the continuation twice (a trap), so the suite runs
// serially — same rationale as `ImageDownloaderTests`.
@Suite("UIImage+Extension", .serialized)
struct UIImageExtensionTests {

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

    // MARK: - loadGif(name:) failure handling

    @Test("Given loadGif(name:) with a missing resource, when the decode fails, then the existing image is preserved")
    func loadGifNameMissingPreservesImage() async {
        let view = UIImageView()
        let existing = makeImage(size: CGSize(width: 4, height: 4))
        view.image = existing

        // Await the real decode-completion signal instead of sleeping, so the assertion runs AFTER
        // the (nil) decode was handled — proving the image was preserved because the failed decode
        // was skipped, not merely because the background task had not run yet. Installing the hook
        // before `loadGif` is safe: this is `@MainActor`, so the load's `@MainActor` task cannot run
        // until we suspend at the continuation below.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            UIImageView.didFinishLocalGifDecodeForTesting = {
                UIImageView.didFinishLocalGifDecodeForTesting = nil
                continuation.resume()
            }
            view.loadGif(name: "___missing_resource_that_does_not_exist___")
        }

        // A failed decode must not blank the view (C050): the previous image stays untouched.
        #expect(view.image === existing)
    }

    // MARK: - loadGif(urlString:) local file handling

    @Test("Given loadGif(urlString:) with a local file:// URL, when the file has valid GIF data, then it decodes locally without going through ImageDownloader")
    func loadGifURLStringLocalFileDecodesWithoutImageDownloader() async throws {
        ImageDownloader.resetForTesting()
        let gifData = try #require(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        try gifData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let view = makeImageView()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            UIImageView.didFinishLocalGifDecodeForTesting = {
                UIImageView.didFinishLocalGifDecodeForTesting = nil
                continuation.resume()
            }
            view.loadGif(urlString: tempURL.absoluteString)
        }

        // A `file://` URL must never touch ImageDownloader's network path (no reachability
        // precheck, no queue entry) — otherwise a purely local read would fail offline (Codex P2).
        #expect(ImageDownloader.queue[view] == nil)
        #expect(view.image?.images != nil)
    }

    // MARK: - Helpers

    private func makeImageView() -> UIImageView {
        return UIImageView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
    }

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
