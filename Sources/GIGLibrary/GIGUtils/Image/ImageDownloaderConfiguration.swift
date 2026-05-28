//
//  ImageDownloaderConfiguration.swift
//  GIGLibrary
//
//  Copyright © 2026 Gigigo SL. All rights reserved.
//

import UIKit

/// Public configuration for the library's image downloader.
///
/// Configure it once during app startup, e.g.:
/// ```swift
/// ImageDownloaderConfiguration.maxConcurrentDownloads = 4
/// ```
@MainActor
public enum ImageDownloaderConfiguration {

    /// Maximum number of images downloaded concurrently.
    ///
    /// Values below `1` are clamped to `1`. Defaults to `6`. Raising the limit at runtime
    /// immediately starts any downloads that were waiting in the queue.
    public static var maxConcurrentDownloads: Int {
        get { ImageDownloader.maxConcurrentDownloads }
        set { ImageDownloader.maxConcurrentDownloads = newValue }
    }
}
