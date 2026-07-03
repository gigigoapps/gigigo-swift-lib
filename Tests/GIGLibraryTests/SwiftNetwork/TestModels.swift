import Foundation

struct Profile: Decodable, Equatable {
    let id: Int
    let name: String
}

struct BasicPayload: Decodable, Equatable {
    let message: String
    let count: Int
}

struct RequiresAge: Decodable {
    let age: Int
}

struct EmptyPayload: Decodable, Equatable {}

struct EncodableBody: Encodable {
    let name: String
    let count: Int
}

struct FailingEncodable: Encodable {
    struct ForcedError: Error {}

    func encode(to encoder: Encoder) throws {
        throw ForcedError()
    }
}
