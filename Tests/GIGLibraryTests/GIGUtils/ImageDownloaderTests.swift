import Testing
import UIKit
@testable import GIGLibrary

@MainActor
@Suite(.serialized)
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
        registerImageResponse(path: "/limit.png")
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
        registerImageResponse(path: "/raise.png")
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
        registerImageResponse(path: "/success.png")

        let view = makeImageViews(count: 1)[0]
        ImageDownloader.shared.download(url: urlString, for: view, placeholder: nil)
        #expect(ImageDownloader.activeDownloads == 1)

        let drained = await waitUntil { ImageDownloader.activeDownloads == 0 }
        #expect(drained)
        #expect(ImageDownloader.images[urlString] != nil)
    }

    @Test("Given a failing response, when it completes, then the slot is released")
    func errorReleasesSlot() async {
        ImageDownloader.resetForTesting()
        MockURLProtocol.respond(path: "/error.png", statusCode: 500, headers: nil, data: nil)
        ImageDownloader.requestProvider = { url in Request.testRequest(baseUrl: url, endpoint: "") }

        let view = makeImageViews(count: 1)[0]
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

        let view = makeImageViews(count: 1)[0]
        ImageDownloader.shared.download(url: "https://example.com/empty.png", for: view, placeholder: nil)

        let drained = await waitUntil { ImageDownloader.activeDownloads == 0 }
        #expect(drained)
    }

    @Test("Given an in-flight download replaced for the same view, when both unwind, then the active count ends at zero")
    func replacingDownloadDoesNotLeakSlots() async {
        ImageDownloader.resetForTesting()
        registerImageResponse(path: "/a.png")
        registerImageResponse(path: "/b.png")

        let view = makeImageViews(count: 1)[0]
        ImageDownloader.shared.download(url: "https://example.com/a.png", for: view, placeholder: nil)
        ImageDownloader.shared.download(url: "https://example.com/b.png", for: view, placeholder: nil)

        let drained = await waitUntil { ImageDownloader.activeDownloads == 0 }
        #expect(drained)
        #expect(ImageDownloader.activeDownloads >= 0)
    }

    // MARK: - Cache hit

    @Test("Given a cached URL, when requested, then no download starts and the cached image is assigned")
    func cachedURLSkipsDownload() {
        ImageDownloader.resetForTesting()
        let urlString = "https://example.com/cached.png"
        let cached = makeImage(.blue)
        ImageDownloader.images[urlString] = cached

        let view = makeImageViews(count: 1)[0]
        ImageDownloader.shared.download(url: urlString, for: view, placeholder: nil)

        #expect(ImageDownloader.activeDownloads == 0)
        #expect(ImageDownloader.stack.isEmpty)
        #expect(view.image === cached)
    }

    // MARK: - Helpers

    /// Registers a mock route returning a valid PNG for `path`, and points the downloader at a
    /// `Request` backed by the mock `URLSession`.
    private func registerImageResponse(path: String) {
        MockURLProtocol.respond(path: path, statusCode: 200, headers: nil, data: makePNGData())
        ImageDownloader.requestProvider = { url in Request.testRequest(baseUrl: url, endpoint: "") }
    }

    private func makeImageViews(count: Int) -> [UIImageView] {
        return (0..<count).map { _ in UIImageView(frame: CGRect(x: 0, y: 0, width: 10, height: 10)) }
    }

    private func makeImage(_ color: UIColor) -> UIImage {
        return UIImage.create(from: color) ?? UIImage()
    }

    private func makePNGData() -> Data {
        return makeImage(.red).pngData() ?? Data()
    }

    /// Polls `condition` on the MainActor until it is true or the timeout elapses. Returns as
    /// soon as the condition holds. The timeout is generous because the success path resizes
    /// images on a `.background` Task, which xctest can throttle heavily.
    private func waitUntil(timeout: Duration = .seconds(15), _ condition: () -> Bool) async -> Bool {
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
    }
}
