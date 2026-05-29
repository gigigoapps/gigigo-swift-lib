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
}
