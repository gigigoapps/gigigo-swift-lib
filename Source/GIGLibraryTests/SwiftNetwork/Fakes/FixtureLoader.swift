import Foundation

enum FixtureLoaderError: Error {
    case missingFixture(String)
}

enum FixtureLoader {
    static func data(named name: String, bundle: Bundle = .module) throws -> Data {
        let resourceName = name.hasSuffix(".json") ? String(name.dropLast(5)) : name
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw FixtureLoaderError.missingFixture(resourceName)
        }
        return try Data(contentsOf: url)
    }
}
