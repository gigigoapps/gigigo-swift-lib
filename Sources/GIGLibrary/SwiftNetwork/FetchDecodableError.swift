import Foundation

public enum FetchDecodableError: Error {
    case requestFailed(status: ResponseStatus, statusCode: Int, underlying: NSError?)
    case emptyResponseBody(statusCode: Int)
    case decodingFailed(underlying: Error)
}
