import Foundation

enum FixtureLoaderError: Error {
    case missingFixture(String)
}

private final class FixtureBundleFinder {}

enum FixtureLoader {
    static func data(named name: String, bundle: Bundle = .module) throws -> Data {
        let resourceName = name.hasSuffix(".json") ? String(name.dropLast(5)) : name
        let candidateBundles = [
            bundle,
            Bundle(for: FixtureBundleFinder.self),
            Bundle.main
        ]

        for candidate in candidateBundles {
            if let url = candidate.url(forResource: resourceName, withExtension: "json") {
                return try Data(contentsOf: url)
            }
        }

        throw FixtureLoaderError.missingFixture(resourceName)
    }
}
