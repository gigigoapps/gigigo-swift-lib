//
//  ImageDownloaderConfiguration.swift
//  GIGLibrary
//
//  Copyright © 2026 Gigigo SL. All rights reserved.
//

import UIKit

/// Public configuration for the library's image downloader.
///
/// Typically set once at app startup, but safe to change at runtime:
/// ```swift
/// ImageDownloaderConfiguration.maxConcurrentDownloads = 4
/// ```
@MainActor
public enum ImageDownloaderConfiguration {

    /// Maximum number of images downloaded concurrently.
    ///
    /// Values below `1` are clamped to `1`. Defaults to `6`. Raising the limit at runtime
    /// starts queued downloads immediately; lowering it only affects future downloads —
    /// those already in flight run to completion.
    public static var maxConcurrentDownloads: Int {
        get { ImageDownloader.maxConcurrentDownloads }
        set { ImageDownloader.maxConcurrentDownloads = newValue }
    }

    /// Default upper bound on the number of images kept in the in-memory cache. Applied to the
    /// `NSCache` when it is first created; `NSCache` still evicts earlier under memory pressure.
    static let defaultMaxCachedImages = 100

    /// Maximum number of images kept in the in-memory cache.
    ///
    /// Backed by `NSCache.countLimit`, which is **best-effort**: the cache may briefly exceed this
    /// count before it evicts. A value of `0` means "no count limit" (eviction then happens only
    /// under memory pressure). Defaults to `defaultMaxCachedImages`. Negative values are clamped to `0`.
    public static var maxCachedImages: Int {
        get { ImageDownloader.images.countLimit }
        set { ImageDownloader.images.countLimit = max(0, newValue) }
    }
}
