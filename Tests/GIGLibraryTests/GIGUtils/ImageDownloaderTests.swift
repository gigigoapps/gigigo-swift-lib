import Testing
import UIKit
@testable import GIGLibrary

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ImageDownloaderTests {

    // MARK: - Configuration

    @Test("Given a reset downloader, then the default max concurrent downloads is 6")
    func defaultMaxIsSix() {
        ImageDownloader.resetForTesting()

        #expect(ImageDownloaderConfiguration.maxConcurrentDownloads == 6)
    }

    @Test("Given a value below 1, when setting the max, then it is clamped to 1")
    func clampsToMinimumOne() {
        ImageDownloader.resetForTesting()

        ImageDownloaderConfiguration.maxConcurrentDownloads = 0
        #expect(ImageDownloaderConfiguration.maxConcurrentDownloads == 1)

        ImageDownloaderConfiguration.maxConcurrentDownloads = -5
        #expect(ImageDownloaderConfiguration.maxConcurrentDownloads == 1)
    }

    @Test("Given a reset downloader, then the default max cached images is 100")
    func defaultMaxCachedImagesIsHundred() {
        ImageDownloader.resetForTesting()

        #expect(ImageDownloaderConfiguration.maxCachedImages == ImageDownloaderConfiguration.defaultMaxCachedImages)
    }

    @Test("Given a value for max cached images, when set, then it is stored and negatives clamp to 0")
    func maxCachedImagesStoresAndClamps() {
        ImageDownloader.resetForTesting()

        ImageDownloaderConfiguration.maxCachedImages = 50
        #expect(ImageDownloaderConfiguration.maxCachedImages == 50)

        ImageDownloaderConfiguration.maxCachedImages = -10
        #expect(ImageDownloaderConfiguration.maxCachedImages == 0)

        // Restore the default so later tests observe the standard cache limit.
        ImageDownloader.resetForTesting()
    }

    // MARK: - Concurrency limit

    @Test("Given a max of 2, when 5 downloads are requested in one tick, then only 2 are active and 3 stay queued")
    func concurrencyLimitIsRespected() async {
        ImageDownloader.resetForTesting()
        useFailFastRequests()
        ImageDownloaderConfiguration.maxConcurrentDownloads = 2

        let views = makeImageViews(count: 5)
        for view in views {
            ImageDownloader.shared.download(url: "https://example.com/limit.png", for: view, placeholder: nil)
        }

        // Deterministic: `activeDownloads` is incremented synchronously inside `pump()`,
        // and nothing is decremented until a fetch completes (which can't happen until we await).
        #expect(ImageDownloader.activeDownloads == 2)
        #expect(ImageDownloader.stack.count == 3)

        // Drain everything so the shared state is clean for the next test.
        let drained = await waitUntil { ImageDownloader.activeDownloads == 0 && ImageDownloader.stack.isEmpty }
        #expect(drained)
    }

    @Test("Given a backlog with the limit reached, when the limit is raised, then queued downloads start immediately")
    func raisingLimitDrainsBacklog() async {
        ImageDownloader.resetForTesting()
        useFailFastRequests()
        ImageDownloaderConfiguration.maxConcurrentDownloads = 1

        let views = makeImageViews(count: 3)
        for view in views {
            ImageDownloader.shared.download(url: "https://example.com/raise.png", for: view, placeholder: nil)
        }
        #expect(ImageDownloader.activeDownloads == 1)
        #expect(ImageDownloader.stack.count == 2)

        ImageDownloaderConfiguration.maxConcurrentDownloads = 3
        #expect(ImageDownloader.activeDownloads == 3)
        #expect(ImageDownloader.stack.isEmpty)

        let drained = await waitUntil { ImageDownloader.activeDownloads == 0 }
        #expect(drained)
    }

    // MARK: - Slot release

    @Test("Given a successful download, when it completes, then the slot is released and the image is cached")
    func successReleasesSlotAndCaches() async {
        ImageDownloader.resetForTesting()
        let urlString = "https://example.com/success.png"
        // Inject a PNG response directly instead of going through URLSession, whose stalls under CI
        // load (NSURLError -1001) made this test flaky. The success path (decode → resize → cache)
        // still runs for real. The Response's `url` is only nominal — the cache key is the caller's
        // original URL string (`PendingDownload.url`), independent of the Response's own `url`, so
        // any valid response URL works. See `ImageDownloader.fetchProvider`.
        ImageDownloader.fetchProvider = { _ in
            makeImageResponse(body: makePNGData(), url: URL(fileURLWithPath: "/success.png"))
        }

        let view = makeImageView()
        ImageDownloader.shared.download(url: urlString, for: view, placeholder: nil)
        #expect(ImageDownloader.activeDownloads == 1)

        // The slot is freed as soon as the (mocked) network finishes; the image is cached after the
        // resize completes on the cooperative pool. Await the cache write deterministically instead
        // of polling: under CI load the `.utility` resize task can be scheduled late, which used to
        // exhaust `waitUntil`'s deadline and flake. See `awaitCache`.
        await awaitCache(of: urlString)
        #expect(ImageDownloader.images.object(forKey: urlString as NSString) != nil)
        #expect(ImageDownloader.activeDownloads == 0)
    }

    @Test("Given a failing response, when it completes, then the slot is released")
    func errorReleasesSlot() async {
        ImageDownloader.resetForTesting()
        MockURLProtocol.respond(path: "/error.png", statusCode: 500, headers: nil, data: nil)
        ImageDownloader.requestProvider = { url in Request.testRequest(baseUrl: url, endpoint: "") }

        let view = makeImageView()
        ImageDownloader.shared.download(url: "https://example.com/error.png", for: view, placeholder: nil)
        #expect(ImageDownloader.activeDownloads == 1)

        let drained = await waitUntil { ImageDownloader.activeDownloads == 0 }
        #expect(drained)
    }

    @Test("Given a 200 response with a body that is not an image, when handled, then the slot is released")
    func undecodableBodyReleasesSlot() async {
        ImageDownloader.resetForTesting()
        MockURLProtocol.respond(path: "/empty.png", statusCode: 200, headers: nil, data: nil)
        ImageDownloader.requestProvider = { url in Request.testRequest(baseUrl: url, endpoint: "") }

        let view = makeImageView()
        ImageDownloader.shared.download(url: "https://example.com/empty.png", for: view, placeholder: nil)

        let drained = await waitUntil { ImageDownloader.activeDownloads == 0 }
        #expect(drained)
    }

    @Test("Given a failed download, when it finishes, then its queue entry is cleared (no leak)")
    func failedDownloadClearsQueueEntry() async {
        ImageDownloader.resetForTesting()
        useFailFastRequests()

        let view = makeImageView()
        ImageDownloader.shared.download(url: "https://example.com/fail-clear.png", for: view, placeholder: nil)

        let drained = await waitUntil { ImageDownloader.activeDownloads == 0 }
        #expect(drained)
        #expect(ImageDownloader.queue[view] == nil)
    }

    @Test("Given an in-flight download replaced for the same view, when both unwind, then the active count ends at zero")
    func replacingDownloadDoesNotLeakSlots() async {
        ImageDownloader.resetForTesting()
        useFailFastRequests()

        let view = makeImageView()
        ImageDownloader.shared.download(url: "https://example.com/a.png", for: view, placeholder: nil)
        ImageDownloader.shared.download(url: "https://example.com/b.png", for: view, placeholder: nil)

        let drained = await waitUntil { ImageDownloader.activeDownloads == 0 }
        #expect(drained)
    }

    @Test("Given a view re-requested while still queued, when slots free up, then it is only started once")
    func requeuingQueuedViewDoesNotDuplicate() async {
        ImageDownloader.resetForTesting()
        useFailFastRequests()
        ImageDownloaderConfiguration.maxConcurrentDownloads = 1

        let busy = makeImageView()      // takes the only slot
        let queued = makeImageView()    // will wait in the stack

        ImageDownloader.shared.download(url: "https://example.com/dup.png", for: busy, placeholder: nil)
        ImageDownloader.shared.download(url: "https://example.com/dup.png", for: queued, placeholder: nil)
        #expect(ImageDownloader.stack.count == 1)

        // Re-request the still-queued view: it must not be enqueued twice.
        ImageDownloader.shared.download(url: "https://example.com/dup.png", for: queued, placeholder: nil)
        #expect(ImageDownloader.stack.count == 1)

        // Draining never pushes the in-flight count above the limit of 1.
        var maxObserved = ImageDownloader.activeDownloads
        let drained = await waitUntil {
            maxObserved = max(maxObserved, ImageDownloader.activeDownloads)
            return ImageDownloader.activeDownloads == 0 && ImageDownloader.stack.isEmpty
        }
        #expect(drained)
        #expect(maxObserved == 1)
    }

    @Test("Given a view reused before its task runs, when the task runs, then the stale request never hits the network")
    func reusedBeforeStartDoesNotFetch() async {
        ImageDownloader.resetForTesting()
        let networkHits = RequestCounter()
        MockURLProtocol.respond(path: "/race.png", statusCode: 200, headers: nil, data: makePNGData()) { _ in
            networkHits.increment()
        }
        ImageDownloader.requestProvider = { url in Request.testRequest(baseUrl: url, endpoint: "") }

        // Two synchronous requests on the same view (same URL), before either task gets to run.
        let view = makeImageView()
        ImageDownloader.shared.download(url: "https://example.com/race.png", for: view, placeholder: nil)
        ImageDownloader.shared.download(url: "https://example.com/race.png", for: view, placeholder: nil)

        let drained = await waitUntil { ImageDownloader.activeDownloads == 0 }
        #expect(drained)
        // Only the current (second) request reaches the network; the replaced one is dropped by
        // the identity guard in `startDownload` before it can fetch and occupy a slot.
        #expect(networkHits.value == 1)
    }

    @Test("Given an animated GIF response, when downloaded, then the cached image stays animated (resize must not flatten it)")
    func gifDownloadStaysAnimated() async {
        ImageDownloader.resetForTesting()
        let urlString = "https://example.com/anim.gif"
        // Minimal 1x1 GIF89a — decodes to an animated UIImage (`images != nil`). The resize step
        // would flatten it to a single static frame if it weren't skipped for animated images.
        let gifData = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7") ?? Data()
        ImageDownloader.fetchProvider = { _ in
            makeImageResponse(body: gifData, url: URL(string: urlString) ?? URL(fileURLWithPath: "/anim.gif"))
        }

        let view = makeImageView()
        ImageDownloader.shared.download(url: urlString, for: view, placeholder: nil)

        await awaitCache(of: urlString)
        #expect(ImageDownloader.images.object(forKey: urlString as NSString) != nil)
        #expect(ImageDownloader.images.object(forKey: urlString as NSString)?.images != nil)
        #expect(ImageDownloader.activeDownloads == 0)
    }

    // MARK: - loadGif(urlString:) routing

    @Test("Given loadGif(urlString:), when called, then it routes through the managed download path")
    func loadGifURLStringRoutesThroughImageDownloader() async {
        ImageDownloader.resetForTesting()
        useFailFastRequests()

        let view = makeImageView()
        view.loadGif(urlString: "https://example.com/animation.gif")

        // A managed download is registered for the view (async/cancellable path), rather than the
        // old synchronous `Data(contentsOf:)` on a background thread. Checked before draining: this
        // is `@MainActor` so `download()` enqueues synchronously (before any `await`), and the
        // fail-fast request clears the entry once it unwinds, so the entry only exists pre-drain.
        #expect(ImageDownloader.queue[view] != nil)

        let drained = await waitUntil { ImageDownloader.activeDownloads == 0 }
        #expect(drained)
    }

    @Test("Given loadGif(urlString:) called twice on a reused view, when both resolve, then the view shows the last URL and only it is cached")
    func loadGifURLStringReusedViewShowsLastImage() async {
        ImageDownloader.resetForTesting()
        let firstURL = "https://example.com/first.gif"
        let secondURL = "https://example.com/second.gif"
        // Both requests would decode to a valid image; which one paints is decided by the view
        // identity guard, not by which finishes first. See `ImageDownloader.fetchProvider`.
        ImageDownloader.fetchProvider = { _ in
            makeImageResponse(body: makePNGData(), url: URL(fileURLWithPath: "/reused.png"))
        }

        // Simulates a reused cell: two GIF loads in quick succession on the same view.
        let view = makeImageView()
        view.loadGif(urlString: firstURL)
        view.loadGif(urlString: secondURL)

        // Await the last URL's cache write deterministically.
        await awaitCache(of: secondURL)

        // Observable outcome: the last-requested URL is the one that completes, caches, and paints;
        // the replaced first request is dropped by the identity guard before it can fetch, so it
        // never populates the cache. `handleResponse` paints and caches the SAME decoded instance,
        // so the view showing exactly the second URL's image is asserted by identity.
        let cachedSecond = ImageDownloader.images.object(forKey: secondURL as NSString)
        #expect(cachedSecond != nil)
        #expect(ImageDownloader.images.object(forKey: firstURL as NSString) == nil)
        #expect(view.image === cachedSecond)

        let drained = await waitUntil { ImageDownloader.activeDownloads == 0 }
        #expect(drained)
    }

    // MARK: - loadGif cross-invalidation (mixed name:/urlString: usage on a reused view)

    @Test("Given a view mid-remote-load, when it is reused for loadGif(name:), then the pending remote download is cancelled")
    func loadGifNameCancelsPendingRemoteDownload() async {
        ImageDownloader.resetForTesting()
        useFailFastRequests()

        let view = makeImageView()
        view.loadGif(urlString: "https://example.com/reused-then-name.gif")
        // Registered synchronously before any await, same reasoning as the routing test above.
        #expect(ImageDownloader.queue[view] != nil)

        // Reusing the view for a bundled GIF must cancel the still-pending remote download (Codex
        // P2): otherwise it could complete afterward and paint over the bundled result.
        view.loadGif(name: "___missing_resource_that_does_not_exist___")
        #expect(ImageDownloader.queue[view] == nil)

        let drained = await waitUntil { ImageDownloader.activeDownloads == 0 }
        #expect(drained)
    }

    @Test("Given a view mid-local-decode, when reused for loadGif(urlString:) with a remote URL, then the remote result wins")
    func loadGifURLStringRemoteInvalidatesPendingLocalDecode() async throws {
        ImageDownloader.resetForTesting()
        let remoteURL = "https://example.com/remote-after-local.gif"
        ImageDownloader.fetchProvider = { _ in
            makeImageResponse(body: makePNGData(), url: URL(fileURLWithPath: "/remote-after-local.png"))
        }

        // A real local GIF so the local decode would actually succeed if it were allowed to apply.
        let gifData = try #require(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        try gifData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Simulates a reused cell: a local-file GIF load immediately superseded by a remote one.
        let view = makeImageView()
        view.loadGif(urlString: tempURL.absoluteString)
        view.loadGif(urlString: remoteURL)

        await awaitCache(of: remoteURL)

        // The remote load must win (Codex P2): the local decode's generation was bumped stale
        // before it could resolve, so it cannot overwrite the remote result even if it finishes late.
        let cachedRemote = ImageDownloader.images.object(forKey: remoteURL as NSString)
        #expect(cachedRemote != nil)
        #expect(view.image === cachedRemote)

        let drained = await waitUntil { ImageDownloader.activeDownloads == 0 }
        #expect(drained)
    }

    // MARK: - loadGif local decode (name: / local file://)

    @Test("Given loadGif(name:) with a missing resource, when the decode fails, then the existing image is preserved")
    func loadGifNameMissingPreservesImage() async {
        ImageDownloader.resetForTesting()
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

    @Test("Given a view mid-local-GIF-decode, when reused for image(from:), then the stale local decode does not paint over image(from:)")
    func imageFromInvalidatesPendingLocalGifDecode() async throws {
        ImageDownloader.resetForTesting()
        useFailFastRequests()

        // A real local GIF so the local decode actually produces an image and WOULD paint if it were
        // still considered current — a nil decode could otherwise mask the bug. The `file://` branch
        // of `loadGif(urlString:)` shares the exact `gifLoadGeneration` guard as `loadGif(name:)`
        // (both go through `loadGifLocally`), and unlike a bundled resource it can be decoded from
        // the test bundle, so it faithfully exercises the `name:` → `image(from:)` reuse scenario.
        let gifData = try #require(Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"))
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
        try gifData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // A non-animated marker so the assertion can tell image(from:)'s result apart from the GIF.
        let placeholder = makeImage(.blue)

        let view = makeImageView()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            UIImageView.didFinishLocalGifDecodeForTesting = {
                UIImageView.didFinishLocalGifDecodeForTesting = nil
                continuation.resume()
            }
            // Simulates a reused cell mixing the GIF and remote-image APIs:
            // 1. Start a local GIF decode (captures the current generation).
            view.loadGif(urlString: tempURL.absoluteString)
            // 2. Reuse the same view for image(from:). These two calls run synchronously with no
            //    suspension point before the await below, so the local decode's `@MainActor` task
            //    cannot interleave — image(from:)'s (synchronous) generation bump is guaranteed to
            //    land first. The fail-fast request never paints, so `placeholder` is the last thing
            //    image(from:) writes to the view.
            view.image(from: "https://example.com/reused-then-remote.png", placeholder: placeholder)
        }

        // With the generation bump now in image(from:), the local decode is stale by the time it
        // resolves and must NOT overwrite image(from:)'s result: the marker placeholder stays and
        // the view is never left showing the animated GIF.
        #expect(view.image === placeholder)
        #expect(view.image?.images == nil)

        let drained = await waitUntil { ImageDownloader.activeDownloads == 0 }
        #expect(drained)
    }

    // MARK: - Cache hit

    @Test("Given a cached URL, when requested, then no download starts and the cached image is assigned")
    func cachedURLSkipsDownload() {
        ImageDownloader.resetForTesting()
        let urlString = "https://example.com/cached.png"
        let cached = makeImage(.blue)
        ImageDownloader.images.setObject(cached, forKey: urlString as NSString)

        let view = makeImageView()
        ImageDownloader.shared.download(url: urlString, for: view, placeholder: nil)

        #expect(ImageDownloader.activeDownloads == 0)
        #expect(ImageDownloader.stack.isEmpty)
        #expect(view.image === cached)
    }

    // MARK: - Memory warning

    @Test("Given a cached image, when a memory warning is posted, then the cache is purged")
    func memoryWarningPurgesCache() async {
        ImageDownloader.resetForTesting()
        // Touch `shared` so the singleton's memory-warning observer is registered (it is installed
        // in `ImageDownloader`'s private init). `resetForTesting` already accesses `shared` via the
        // `maxConcurrentDownloads` setter, but assert it explicitly to make the dependency obvious.
        _ = ImageDownloader.shared

        let urlString = "https://example.com/memory-warning.png"
        let cached = makeImage(.blue)
        ImageDownloader.images.setObject(cached, forKey: urlString as NSString)
        #expect(ImageDownloader.images.object(forKey: urlString as NSString) != nil)

        // The observer clears the cache on the main queue and then hops through a `Task { @MainActor }`,
        // so the purge is asynchronous — poll until the entry is gone rather than asserting inline.
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)

        let purged = await waitUntil { ImageDownloader.images.object(forKey: urlString as NSString) == nil }
        #expect(purged)
    }

    // MARK: - Helpers

    /// Points the downloader at requests that fail fast in `preChecks` (reachability off), so each
    /// download finishes immediately via the error path WITHOUT touching `URLSession` or the resize.
    /// Use for tests that only assert the slot counter / queue: the mechanics of `pump`/the counter
    /// are exercised identically, but draining is deterministic and independent of the network and
    /// the cooperative thread pool (avoids occasional URLSession stalls under load).
    private func useFailFastRequests() {
        ImageDownloader.requestProvider = { url in
            Request.testRequest(baseUrl: url, endpoint: "", reachable: false)
        }
    }

    private func makeImageView() -> UIImageView {
        return UIImageView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    private func makeImageViews(count: Int) -> [UIImageView] {
        return (0..<count).map { _ in makeImageView() }
    }

    private func makeImage(_ color: UIColor) -> UIImage {
        return UIImage.create(from: color) ?? UIImage()
    }

    /// Builds a solid-colour, non-animated image of an exact point size at scale 1, so `.size`
    /// assertions are deterministic and `.images == nil` distinguishes it from a decoded GIF.
    private func makeImage(size: CGSize, color: UIColor = .red) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makePNGData() -> Data {
        return makeImage(.red).pngData() ?? Data()
    }

    /// Awaits the success-path cache write for `cacheKey` deterministically. `download(...)` is
    /// fire-and-forget, so we install the DEBUG cache hook and suspend until the resize → cache step
    /// fires it. Unlike `waitUntil`, this carries no deadline: when the `.utility` resize task is
    /// scheduled late under CI load it simply waits for the real signal instead of racing a timeout
    /// and flaking. The `.timeLimit` suite trait is the backstop against a genuine hang.
    ///
    /// Safe to install the hook here (rather than before `download`): the caller is `@MainActor`, so
    /// the unstructured download `Task` and its detached resize cannot run until this function
    /// suspends at the `await` below — the signal can never fire before the hook is in place.
    private func awaitCache(of cacheKey: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ImageDownloader.didCacheImageForTesting = { written in
                guard written == cacheKey else { return }
                ImageDownloader.didCacheImageForTesting = nil
                continuation.resume()
            }
        }
    }

    /// Polls `condition` on the MainActor until it is true or the timeout elapses. Returns as soon
    /// as the condition holds, so warm runs finish in milliseconds. The timeout is generous because
    /// the first test that chains async hops pays a one-time concurrency-runtime/simulator warm-up
    /// (observed up to ~12s cold); later async tests then run in milliseconds.
    private func waitUntil(timeout: Duration = .seconds(30), _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }
}

// MARK: - Test support

extension ImageDownloader {
    /// Resets all shared state and configuration to defaults so each test starts clean.
    /// Lives in the test target — it is intentionally not part of the production code.
    static func resetForTesting() {
        queue = [:]
        stack = []
        images.removeAllObjects()
        images.countLimit = ImageDownloaderConfiguration.defaultMaxCachedImages
        activeDownloads = 0
        maxConcurrentDownloads = 6  // setter clamps and pumps (a no-op while the stack is empty)
        requestProvider = { url in Request(method: .get, baseUrl: url, endpoint: "", bodyParams: nil) }
        fetchProvider = { request in await request.fetch() }
        didCacheImageForTesting = nil
    }
}

/// Thread-safe counter for assertions driven from `MockURLProtocol` handlers, which run off the
/// main actor.
private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
