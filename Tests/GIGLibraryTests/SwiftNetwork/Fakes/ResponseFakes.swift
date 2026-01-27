import Foundation

extension HTTPURLResponse {
    static func fake(url: URL, statusCode: Int = 200, headers: [String: String]? = nil) -> HTTPURLResponse {
        return HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
    }
}
