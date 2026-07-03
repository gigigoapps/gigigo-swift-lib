import Testing
import UIKit
@testable import GIGLibrary

@Suite("QRGenerator")
struct QRGeneratorTests {

    // MARK: - generate(_:) -> UIImage?

    @Test("Given a non-empty string, when generating a QR image, then a non-empty image is returned")
    func generatesImageForNonEmptyString() throws {
        let image = try #require(QR.generate("hello"))

        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test("Given an empty string, when generating a QR image, then a non-empty image is still returned")
    func generatesImageForEmptyString() throws {
        // Fixes the current contract: the CIQRCodeGenerator filter encodes empty data into a valid
        // (minimal) symbol, so the API returns a real image rather than nil for the empty string.
        let image = try #require(QR.generate(""))

        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    // MARK: - generate(_:onView:)

    @MainActor
    @Test("Given a view with a valid frame, when generating onto it, then the view receives an image")
    func drawsOntoViewWithValidFrame() {
        let view = UIImageView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))

        QR.generate("hello", onView: view)

        #expect(view.image != nil)
    }

    @MainActor
    @Test("Given a zero-sized view, when generating onto it, then it does not crash and leaves the image unset")
    func zeroSizedViewDoesNotCrash() {
        // A `.zero` frame cannot back a bitmap context. This fixes the contract that the degenerate
        // case is a silent no-op (guarded explicitly in `generate(_:onView:)`) rather than a crash.
        let view = UIImageView(frame: .zero)

        QR.generate("hello", onView: view)

        #expect(view.image == nil)
    }
}
