//
//  ImageDownloader.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo on 3/11/16.
//  Copyright © 2016 Gigigo SL. All rights reserved.
//

import UIKit

@MainActor
struct ImageDownloader {

    static let shared = ImageDownloader()
    static var queue: [UIImageView: Request] = [:]
    static var stack: [UIImageView] = []
    static var images: [String: UIImage] = [:]

    /// Number of downloads currently in flight: a `fetch()` has been started and has not yet
    /// reached a terminal handler. Views still waiting in `stack` are NOT counted.
    /// Kept `internal` (not `private`) so tests can assert that the limit is respected.
    static var activeDownloads = 0

    #if DEBUG
    /// Seam used only by DEBUG builds so tests can inject a `Request` backed by a mocked
    /// `URLSession`/reachability. It does not exist in release builds — see `loadImage(url:in:)`.
    static var requestProvider: (_ url: String) -> Request = { url in
        Request(method: .get, baseUrl: url, endpoint: "", bodyParams: nil)
    }

    /// Seam used only by DEBUG builds so tests can supply a `Response` directly instead of letting
    /// the request hit `URLSession`. The real `URLSession` can stall under CI load (surfacing as
    /// `-1001` timeouts), which made the success-path test flaky; injecting a `Response` carrying
    /// the image bytes keeps that test deterministic while still exercising the real decode → resize
    /// → cache. It does not exist in release builds — see `startDownload(for:)`.
    static var fetchProvider: (_ request: Request) async -> Response = { request in
        await request.fetch()
    }
    #endif

    /// Backing store for `maxConcurrentDownloads`, always clamped to a minimum of 1.
    private static var storedMaxConcurrentDownloads = 6

    /// Maximum number of images downloaded concurrently. Minimum 1; defaults to 6.
    static var maxConcurrentDownloads: Int {
        get { ImageDownloader.storedMaxConcurrentDownloads }
        set {
            // A value of 0 (or less) would stall the pump forever, so clamp to >= 1.
            ImageDownloader.storedMaxConcurrentDownloads = max(1, newValue)
            // Raising the limit at runtime should immediately drain any queued work.
            ImageDownloader.shared.pump()
        }
    }

    // MARK: - Initializers

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                ImageDownloader.images = [:]
                ImageDownloader.stack = []
                ImageDownloader.queue = [:]
                // Intentionally do NOT reset `activeDownloads`: the in-flight fetches keep running
                // and decrement it themselves as they unwind. Zeroing it here would let new
                // requests start a full batch on top of the still-running ones, briefly doubling
                // the configured concurrency precisely under memory pressure.
            }
        }
    }

    // MARK: - Public methods

    func download(url: String, for view: UIImageView, placeholder: UIImage?) {
        if let request = ImageDownloader.queue[view] {
            request.cancel()
            ImageDownloader.queue.removeValue(forKey: view)
            // Do NOT touch `activeDownloads` here. If the request was already in flight, its
            // `fetch()` will unwind through `handleResponse` and release the slot there; if it
            // was still pending in `stack`, it was never counted and `pump()` skips its entry.
        }
        if let image = ImageDownloader.images[url] {
            view.image = image
        } else {
            view.image = placeholder
            self.loadImage(url: url, in: view)
        }
    }

    // MARK: - Private Helpers

    private func loadImage(url: String, in view: UIImageView) {
        #if DEBUG
        let request = ImageDownloader.requestProvider(url)
        #else
        let request = Request(method: .get, baseUrl: url, endpoint: "", bodyParams: nil)
        #endif
        ImageDownloader.queue[view] = request
        // Drop any stale pending entry for this view before re-enqueuing it, so a view that was
        // re-requested while still queued (e.g. a reused cell) is never started more than once.
        ImageDownloader.stack.removeAll { $0 === view }
        ImageDownloader.stack.append(view)
        self.pump()
    }

    /// Starts as many downloads as the configured limit allows, draining the pending `stack`.
    /// This is the single place that decides whether more work may begin.
    private func pump() {
        while ImageDownloader.activeDownloads < ImageDownloader.maxConcurrentDownloads,
              let view = ImageDownloader.stack.popLast() {
            // Skip stale entries whose request was cancelled or replaced while still queued.
            guard ImageDownloader.queue[view] != nil else { continue }
            self.startDownload(for: view)
        }
    }

    /// The single place that increments `activeDownloads` and launches a fetch.
    private func startDownload(for view: UIImageView) {
        guard let request = ImageDownloader.queue[view] else { return }
        ImageDownloader.activeDownloads += 1
        // Unstructured Task is required here: `fetch()` is `@concurrent` (it runs off the
        // MainActor) and must be bridged from this MainActor-isolated flow, which is driven by
        // synchronous UIKit callbacks rather than an async context.
        Task { @MainActor in
            // The view may have been reused (or purged) between reserving the slot above and this
            // task getting to run. `Request.cancel()` from `download(...)` is a no-op until
            // `fetch()` installs its in-flight canceller, so if this request is no longer the
            // current one for the view, release the slot here instead of letting a discarded
            // download occupy it (and hit the network) until it finishes.
            guard ImageDownloader.queue[view] === request else {
                self.finishDownload()
                return
            }
            #if DEBUG
            let response = await ImageDownloader.fetchProvider(request)
            #else
            let response = await request.fetch()
            #endif
            self.handleResponse(response, view: view, request: request)
        }
    }

    /// The single place that decrements `activeDownloads`. Always pumps afterwards so a freed
    /// slot is immediately reused by the next pending download.
    private func finishDownload() {
        ImageDownloader.activeDownloads = max(0, ImageDownloader.activeDownloads - 1)
        self.pump()
    }

    /// Removes `view`'s queue entry only if it still holds THIS exact request, compared by object
    /// identity (not URL). A stale completion must never evict a newer request's entry for the same
    /// reused view — even when both target the same URL.
    private func clearQueueEntry(for view: UIImageView, ifCurrent request: Request) {
        if ImageDownloader.queue[view] === request {
            ImageDownloader.queue.removeValue(forKey: view)
        }
    }

    private func handleResponse(_ response: Response, view: UIImageView, request: Request) {
        switch response.status {
        case .success:
            guard let image = try? response.image() else {
                LogWarn("While downloading the image, the body was empty or the image type was not recognized.")
                self.clearQueueEntry(for: view, ifCurrent: request)
                self.finishDownload()
                return
            }
            let width = view.width() * UIScreen.main.scale
            let height = view.height() * UIScreen.main.scale
            let targetSize = CGSize(width: width, height: height)
            // The network download finished: release the slot now so the next one can start.
            // Resizing is CPU work; it must not keep a download slot occupied, and a low-priority
            // resize must never gate the concurrency counter.
            self.finishDownload()
            Task.detached(priority: .utility) {
                var finalImage = image
                if let resized = image.imageProportionally(with: targetSize) {
                    finalImage = resized
                }
                await MainActor.run {
                    // Compare by object identity: only the still-current request for this view may
                    // apply its image, cache it, and clear its entry. This way a stale resize (the
                    // view was reused, even for the same URL) never paints over the newer request,
                    // and a completion whose entry was purged by a memory warning does NOT refill
                    // the cache the app was trying to free.
                    guard ImageDownloader.queue[view] === request else { return }
                    self.setAnimated(image: finalImage, in: view)
                    ImageDownloader.images[request.baseURL] = finalImage
                    ImageDownloader.queue.removeValue(forKey: view)
                }
            }
        default:
            LogError(response.error)
            self.clearQueueEntry(for: view, ifCurrent: request)
            self.finishDownload()
        }
    }

    private func setAnimated(image: UIImage?, in view: UIImageView) {
        UIView.transition(
            with: view,
            duration: 0.4,
            options: .transitionCrossDissolve,
            animations: {
                view.image = image
            },
            completion: nil
        )
    }

}
