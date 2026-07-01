//
//  UIImageExtension.swift
//  GiGLibrary
//
//  Created by Sergio López on 11/10/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import UIKit
import ImageIO

public extension UIImageView {
    
    func image(from urlString: String, placeholder: UIImage?) {
        ImageDownloader.shared.download(url: urlString, for: self, placeholder: placeholder)
    }
    
    /// Loads a GIF bundled with the app by resource name, decoding it off the main actor.
    ///
    /// Decoding runs on a background executor so a large/multi-frame GIF cannot block the UI, and
    /// the result is only applied if this call is still the most recent `loadGif(name:)` for the
    /// view — a reused cell that fires two loads in a row shows the LAST one requested, not
    /// whichever finishes decoding last (see `gifLoadGeneration`). A decode failure leaves the
    /// current image untouched instead of blanking it.
    func loadGif(name: String) {
        let generation = beginGifLoad()
        // Unstructured Task: this is a synchronous UIKit entry point (not an async context), so the
        // off-main `decodedGif` must be bridged here. The generation guard drops a stale result if
        // the view is reused before the decode finishes.
        Task { @MainActor in
            let image = await UIImage.decodedGif(name: name)
            if self.gifLoadGeneration == generation, let image {
                self.image = image
            }
            #if DEBUG
            UIImageView.didFinishLoadGifNameForTesting?()
            #endif
        }
    }

    /// Loads a remote GIF through `ImageDownloader`, reusing its managed download path: async and
    /// cancellable network I/O (no synchronous `Data(contentsOf:)` on a background thread), a
    /// bounded concurrency limit, an in-memory cache, and the view-identity guard that makes a
    /// reused cell show the last URL requested. The current image is passed as the placeholder so a
    /// failed load leaves it untouched rather than blanking the view.
    ///
    /// The response is decoded as an animated GIF when the URL ends in `.gif` or its bytes carry a
    /// GIF signature (see `Response.image`), so a GIF served from an extensionless URL still animates.
    func loadGif(urlString: String) {
        ImageDownloader.shared.download(url: urlString, for: self, placeholder: self.image)
    }
}

// MARK: - loadGif(name:) view identity

private extension UIImageView {

    /// Monotonic per-view counter identifying the most recent `loadGif(name:)` request, stored as an
    /// associated object. Compared on completion so a stale decode (the view was reused) is dropped.
    /// The 1-byte allocation is only ever used for its stable address as the association key and is
    /// intentionally never freed — it lives for the process lifetime, like a `static` sentinel.
    private static let gifLoadGenerationKey = UnsafeRawPointer(UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1))

    var gifLoadGeneration: Int {
        (objc_getAssociatedObject(self, UIImageView.gifLoadGenerationKey) as? Int) ?? 0
    }

    /// Bumps the generation for this view and returns the new value, marking any in-flight
    /// `loadGif(name:)` decode as stale.
    func beginGifLoad() -> Int {
        let next = gifLoadGeneration &+ 1
        objc_setAssociatedObject(self, UIImageView.gifLoadGenerationKey, next, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return next
    }
}

#if DEBUG
extension UIImageView {
    /// DEBUG-only seam fired on the MainActor after a `loadGif(name:)` decode completes (whether or
    /// not the image was applied), so tests can await the real completion instead of sleeping. `nil`
    /// by default and absent from release builds. Mirrors `ImageDownloader.didCacheImageForTesting`.
    static var didFinishLoadGifNameForTesting: (@MainActor () -> Void)?
}
#endif

extension UIImage {
    
    public class func create(from color: UIColor) -> UIImage? {
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        return UIGraphicsImageRenderer(bounds: rect).image { _ in
            color.setFill()
            UIRectFill(rect)
        }
    }
    
    public class func gif(data: Data) -> UIImage? {
        // Create source from data
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            LogWarn("Source for the image does not exist")
            return nil
        }
        
        return UIImage.animatedImageWithSource(source)
    }
    
    /// Loads a GIF from a URL string by reading its bytes synchronously with `Data(contentsOf:)`.
    ///
    /// - Warning: For a **remote** URL this performs blocking network I/O with no timeout,
    ///   cancellation, or concurrency limit — which the library forbids for downloads. Use
    ///   `UIImageView.loadGif(urlString:)` (managed, async, cancellable) for remote GIFs, or
    ///   `gif(data:)` once you already hold the bytes. Kept only for loading a local `file://` URL.
    @available(*, deprecated, message: "For remote URLs use UIImageView.loadGif(urlString:) (async, cancellable); for bytes you already hold use gif(data:). This does blocking network I/O.")
    public class func gif(url: String) -> UIImage? {
        // Validate URL
        guard let bundleURL = URL(string: url) else {
            LogWarn("This image named \"\(url)\" does not exist")
            return nil
        }

        // Validate data
        guard let imageData = try? Data(contentsOf: bundleURL) else {
            LogWarn("Cannot turn image named \"\(url)\" into NSData")
            return nil
        }

        return gif(data: imageData)
    }
    
    public class func gif(name: String) -> UIImage? {
        // Check for existance of gif
        guard let bundleURL = Bundle.main
            .url(forResource: name, withExtension: "gif") else {
            LogWarn("This image named \"\(name)\" does not exist")
            return nil
        }

        // Validate data
        guard let imageData = try? Data(contentsOf: bundleURL) else {
            LogWarn("Cannot turn image named \"\(name)\" into NSData")
            return nil
        }

        return gif(data: imageData)
    }

    /// Decodes a bundled GIF by name off the main actor. `@concurrent` forces the (potentially heavy,
    /// multi-frame) decode onto a background executor instead of the caller's actor, and the
    /// `sending` result lets the freshly-created, non-`Sendable` `UIImage` cross back to the
    /// `@MainActor` caller in `UIImageView.loadGif(name:)`.
    @concurrent
    static func decodedGif(name: String) async -> sending UIImage? {
        UIImage.gif(name: name)
    }
    
    public func imageProportionally(with size: CGSize) -> UIImage? {
        // If the target/source sizes are degenerate (e.g. a zero-bounds `UIImageView` in
        // `ImageDownloader.handleResponse`), `aspectFillSize` returns nil and the original image is
        // returned unchanged — `UIGraphicsImageRenderer` would otherwise trap with
        // `NSInternalInconsistencyException` on a non-finite/zero-sized context.
        guard let newSize = UIImage.aspectFillSize(for: self.size, fitting: size) else {
            return self
        }
        // `UIGraphicsImageRenderer` replaces the deprecated UIGraphics* context API. It does not
        // require the main actor (the `ImageDownloader` caller runs the resize on a detached task),
        // and its default format uses the device screen scale, matching the previous `scale: 0.0`.
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Computes the aspect-fill size that scales `source` to cover `target`, or `nil` when the
    /// result cannot be drawn safely. Extracted as a pure, side-effect-free function so the guard
    /// logic is unit-testable without a real graphics context.
    ///
    /// Returns nil when either size is non-positive, NaN or infinite, or when the scaled result
    /// overflows to a non-finite value. `> 0` already rejects zero, negatives and NaN
    /// (`NaN > 0` is `false`); the `.isFinite` checks additionally reject infinities. The final
    /// check on `newSize` catches the overflow case the input guards cannot: a finite but very
    /// large operand multiplied by the ratio can still reach infinity.
    static func aspectFillSize(for source: CGSize, fitting target: CGSize) -> CGSize? {
        guard target.width > 0, target.width.isFinite,
              target.height > 0, target.height.isFinite,
              source.width > 0, source.width.isFinite,
              source.height > 0, source.height.isFinite else {
            return nil
        }
        let widthRatio = target.width / source.width
        let heightRatio = target.height / source.height
        // Aspect-fill: scale by the larger ratio so the image covers the target size.
        let ratio = max(widthRatio, heightRatio)
        let newSize = CGSize(width: source.width * ratio, height: source.height * ratio)
        guard newSize.width.isFinite, newSize.height.isFinite,
              newSize.width > 0, newSize.height > 0 else {
            return nil
        }
        return newSize
    }

    // MARK: - Private Helpers
    
    internal class func delayForImageAtIndex(_ index: Int, source: CGImageSource) -> Double {
        var delay = 0.1
        // Get dictionaries
        let cfProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
        let gifPropertiesPointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(capacity: 0)
        if CFDictionaryGetValueIfPresent(
            cfProperties,
            Unmanaged.passUnretained(kCGImagePropertyGIFDictionary).toOpaque(),
            gifPropertiesPointer
        ) == false {
            return delay
        }
        let gifProperties: CFDictionary = unsafeBitCast(gifPropertiesPointer.pointee, to: CFDictionary.self)
        // Get delay time
        var delayObject: AnyObject = unsafeBitCast(
            CFDictionaryGetValue(
                gifProperties,
                Unmanaged.passUnretained(kCGImagePropertyGIFUnclampedDelayTime).toOpaque()),
            to: AnyObject.self)
        if delayObject.doubleValue == 0 {
            delayObject = unsafeBitCast(CFDictionaryGetValue(
                gifProperties,
                Unmanaged.passUnretained(kCGImagePropertyGIFDelayTime).toOpaque()),
                                        to: AnyObject.self)
        }
        delay = delayObject as? Double ?? 0
        if delay < 0.1 {
            delay = 0.1 // Make sure they're not too fast
        }
        return delay
    }
    
    internal class func gcdForPair(_ aVar: Int?, _ bVar: Int?) -> Int {
        // If either is nil, return the other (or 0 if both are nil)
        guard var a = aVar else { return bVar ?? 0 }
        guard var b = bVar else { return a }
        // Swap so a >= b for modulo
        if a < b {
            swap(&a, &b)
        }
        // Get greatest common divisor (Euclidean algorithm)
        while b != 0 {
            let rest = a % b
            a = b
            b = rest
        }
        return a
    }
    
    internal class func gcdForArray(_ array: [Int]) -> Int {
        if array.isEmpty {
            return 1
        }
        var gcd = array[0]
        for val in array {
            gcd = UIImage.gcdForPair(val, gcd)
        }
        return gcd
    }
    
    internal class func animatedImageWithSource(_ source: CGImageSource) -> UIImage? {
        let count = CGImageSourceGetCount(source)
        var images = [CGImage]()
        var delays = [Int]()
        // Fill arrays. Keep `images` and `delays` aligned: a frame that fails to decode is skipped
        // entirely instead of appending a delay without an image. Otherwise a partially corrupt GIF
        // desyncs the arrays and the frame loop below traps on `images[i]` out of range — a path now
        // reachable from untrusted network data via `Response.image()`.
        for i in 0..<count {
            // Add image
            guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            images.append(image)
            // At it's delay in cs
            let delaySeconds = UIImage.delayForImageAtIndex(Int(i),
                                                            source: source)
            delays.append(Int(delaySeconds * 1000.0)) // Seconds to ms
        }
        guard !images.isEmpty else { return nil }
        // Calculate full duration
        let duration: Int = {
            var sum = 0

            for val: Int in delays {
                sum += val
            }

            return sum
        }()
        // Get frames
        let gcd = gcdForArray(delays)
        var frames = [UIImage]()
        var frame: UIImage
        var frameCount: Int
        for i in 0..<images.count {
            frame = UIImage(cgImage: images[i])
            frameCount = Int(delays[i] / gcd)

            for _ in 0..<frameCount {
                frames.append(frame)
            }
        }
        return UIImage.animatedImage(
            with: frames,
            duration: Double(duration) / 1000.0)
    }
    
    
    
}
