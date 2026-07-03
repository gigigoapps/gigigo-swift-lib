//
//  Request+URLBuilding.swift
//  GIGLibrary
//
//  URL assembly for `Request`: it joins `baseURL` and `endpoint` into a single, normalized path
//  and appends `urlParams` as query items. Two correctness rules live here:
//    - the base/endpoint separator is normalized to exactly one `/` (no `/v1items`, no `//`);
//    - query values are converted by type rather than via `String(describing:)`, so arrays expand
//      to repeated items and scalars never leak `Optional(...)`/`[1, 2]`-style text into the URL.
//

import Foundation

extension Request {

    /// Builds the final `URL`, throwing `.invalidURL` when the base/endpoint or the query items
    /// cannot form a valid URL. Entry point used by `buildRequest()`.
    func composeURL() throws -> URL {
        guard let urlString = self.buildURL(), let url = self.addParams(to: URLComponents(string: urlString)) else {
            self.logInvalidURLBuildError()
            throw RequestBuildError.invalidURL
        }
        return url
    }

    /// Joins `baseURL` with the **path-only** `endpoint`. Returns `nil` (→ `.invalidURL`) when
    /// `baseURL` is unparseable or has no scheme — an absolute URL is required. `endpoint` is treated
    /// purely as a path component: any `?query`/`#fragment` it contains is percent-encoded into the
    /// path, so query items must be passed via `urlParams` (or already present in `baseURL`).
    private func buildURL() -> String? {
        guard var components = URLComponents(string: self.baseURL), components.scheme != nil else {
            return nil
        }
        components.path = self.normalizedPath(base: components.path, appending: self.endpoint)
        // Assigning a path with reserved characters can make `string` nil; returning it as-is lets
        // `composeURL` surface the failure as `.invalidURL` instead of crashing downstream.
        return components.string
    }

    /// Joins `base` and `appending` with exactly one `/` separator: inserts one when neither side
    /// supplies it (avoids `/v1items`) and collapses a duplicate when both do (avoids `//`).
    private func normalizedPath(base: String, appending endpoint: String) -> String {
        guard !endpoint.isEmpty else {
            return base
        }
        guard !base.isEmpty else {
            return endpoint.hasPrefix("/") ? endpoint : "/" + endpoint
        }

        switch (base.hasSuffix("/"), endpoint.hasPrefix("/")) {
        case (true, true):
            return base + endpoint.dropFirst()
        case (false, false):
            return base + "/" + endpoint
        default:
            return base + endpoint
        }
    }

    private func addParams(to urlComponents: URLComponents?) -> URL? {
        guard var urlComponents else { return nil }

        if let urlParams = self.urlParams {
            let newItems = urlParams.flatMap { key, value in
                self.queryItems(name: key, value: value)
            }
            let urlConcat = concat(urlComponents.queryItems, newItems)
            urlComponents.queryItems = urlConcat
        }
        guard let string = urlComponents.string else { return nil }
        return URL(string: string)
    }

    /// Builds the query items for a single param. Arrays expand to one item per element under the
    /// same name; every other value is converted explicitly (see `queryValue(for:)`) instead of
    /// via `String(describing:)`, which leaks `Optional(...)`/`[1, 2]`-style text into the URL.
    private func queryItems(name: String, value: Any) -> [URLQueryItem] {
        // `urlParams` is `[String: Any]`, so a caller can pass `Optional("x") as Any` or a nil
        // optional. Unwrap it first: a nil optional becomes a single valueless item, and a wrapped
        // value (incl. an optional array) is processed as if it had been passed directly.
        guard let unwrapped = self.unwrapOptional(value) else {
            return [URLQueryItem(name: name, value: nil)]
        }
        if let array = unwrapped as? [Any] {
            return array.map { URLQueryItem(name: name, value: self.queryValue(for: $0)) }
        }
        return [URLQueryItem(name: name, value: self.queryValue(for: unwrapped))]
    }

    /// Fully unwraps nested `Optional`s from an `Any`, returning `nil` if any level is `.none`.
    private func unwrapOptional(_ value: Any) -> Any? {
        var current = value
        while true {
            let mirror = Mirror(reflecting: current)
            guard mirror.displayStyle == .optional else {
                return current
            }
            guard let inner = mirror.children.first?.value else {
                return nil
            }
            current = inner
        }
    }

    private func queryValue(for value: Any) -> String? {
        // Array elements (and any value) may themselves be optionals; unwrap before encoding so a
        // nil optional drops its value instead of stringifying to "nil"/"Optional(...)".
        guard let value = self.unwrapOptional(value) else {
            return nil
        }
        switch value {
        case is NSNull:
            return nil
        case let string as String:
            return string
        case let number as NSNumber:
            // Swift `Int`/`Double`/`Bool` and ObjC-bridged numbers all funnel here. CFBoolean
            // identity separates a genuine boolean from a numeric 0/1: a bridged `NSNumber(0)`/`(1)`
            // also satisfies `as? Bool`, so casting to `Bool` first would mangle those integers into
            // "false"/"true". Genuine booleans render as "true"/"false"; numbers keep their canonical
            // string form ("0", "1", "42", "1.5").
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            // A non-finite Double (NaN/±Inf) would render as "nan"/"inf" via stringValue and ship
            // silent garbage to the backend; treat it as non-encodable (valueless item) instead.
            if !number.doubleValue.isFinite {
                return nil
            }
            return number.stringValue
        default:
            return String(describing: value)
        }
    }
}

func concat(_ lhs: [URLQueryItem]?, _ rhs: [URLQueryItem]?) -> [URLQueryItem] {
    guard let left = lhs else {
        return rhs ?? []
    }

    guard let right = rhs else {
        return left
    }

    return left + right
}
