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
        // still runs for real. The Response's `url` is only nominal — the cache key is
        // `request.baseURL` — so any valid URL works. See `ImageDownloader.fetchProvider`.
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
        #expect(ImageDownloader.images[urlString] != nil)
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
        #expect(ImageDownloader.images[urlString] != nil)
        #expect(ImageDownloader.images[urlString]?.images != nil)
        #expect(ImageDownloader.activeDownloads == 0)
    }

    // MARK: - Cache hit

    @Test("Given a cached URL, when requested, then no download starts and the cached image is assigned")
    func cachedURLSkipsDownload() {
        ImageDownloader.resetForTesting()
        let urlString = "https://example.com/cached.png"
        let cached = makeImage(.blue)
        ImageDownloader.images[urlString] = cached

        let view = makeImageView()
        ImageDownloader.shared.download(url: urlString, for: view, placeholder: nil)

        #expect(ImageDownloader.activeDownloads == 0)
        #expect(ImageDownloader.stack.isEmpty)
        #expect(view.image === cached)
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
        images = [:]
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
