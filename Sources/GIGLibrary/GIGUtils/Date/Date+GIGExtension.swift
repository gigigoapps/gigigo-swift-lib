//
//  Date+GIGExtension.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo on 22/2/16.
//  Copyright © 2016 Gigigo S.L. All rights reserved.
//

import Foundation


public let DateISOFormat = "yyyy-MM-dd'T'HH:mm:ssZ"


/**
Error type for invalid values

Cases:
* invalidHour: Thrown when the hour set is not in the 0..<24 range
* invalidMinutes: Thrown when the minutes set are not in the 0..<60 range
* invalidSeconds: Thrown when the seconds set are not in the 0..<60 range
* invalidDate: Thrown when the resulting date could not be built

- Author: Alejandro Jiménez
- Since: 1.1.3
*/
public enum ErrorDate: Error, Equatable {
	case invalidHour
	case invalidMinutes
	case invalidSeconds
	case invalidDate
}


/// Thread-safe cache of configured `DateFormatter` instances, keyed by format string.
///
/// Creating a `DateFormatter` is one of the most expensive Foundation operations, and these
/// helpers are called in loops/per-row, so formatters are built once and reused. Each cached
/// formatter is fully configured up front (locale, time zone, format) and never reconfigured
/// afterwards; a `DateFormatter` in that state is safe to use from multiple threads (Apple only
/// guarantees this while its configuration is not mutated), and the mutable cache itself is
/// guarded by a lock.
private final class DateFormatterCache: @unchecked Sendable {

	static let shared = DateFormatterCache()

	private let lock = NSLock()
	// Assumes a bounded set of format strings (the usual case: format literals). A caller that
	// generates unbounded distinct formats at runtime would grow this cache without limit.
	private var formatters: [String: DateFormatter] = [:]

	func formatter(for format: String) -> DateFormatter {
		lock.lock()
		defer { lock.unlock() }

		if let cached = formatters[format] {
			return cached
		}

		let formatter = DateFormatter()
		formatter.dateFormat = format
		formatter.locale = Locale(identifier: "en_US_POSIX")
		// Fixed time zone so custom formats without a zone token behave deterministically
		// regardless of the device time zone (ISO strings carry their own offset via `Z`).
		// AM/PM symbols are left at their en_US_POSIX defaults so custom formats using the
		// `a` token still parse and format correctly (the shared formatter serves both paths).
		formatter.timeZone = TimeZone(secondsFromGMT: 0)
		formatters[format] = formatter
		return formatter
	}
}


public extension Date {

	/// Date from string with ISO format.
	static func dateFromString(_ dateString: String, format: String = DateISOFormat) -> Date? {
		return DateFormatterCache.shared.formatter(for: format).date(from: dateString)
	}

	static func today() -> Date {
		return Date()
	}

	func dateAdding(_ days: Int) -> Date {
		self.addingTimeInterval(TimeInterval(60 * 60 * 24 * days))
	}

	func string(with format: String = DateISOFormat) -> String {
		return DateFormatterCache.shared.formatter(for: format).string(from: self)
	}


	/**
	Set the time to a `Date`

	- parameters:
		- hour: The hour to be set
		- minutes: The minutes to be set. Optional, 0 by default
		- seconds: The seconds to be set. Optional, 0 by default

	- important: The time is set in local time respecting the user time zone.
	Examples (in Spain):
	* setHour(14) to a summer date (UTC+2) returns -> 12:00:00 +0000
	* setHour(14) to a winter date (UTC+1) returns -> 13:00:00 +0000

	- throws: An error of type ErrorDate
	- returns: A new `Date` with the same date and the time set.
	- Author: Alejandro Jiménez
	- Since: 1.1.3
	*/
	func setHour(_ hour: Int, minutes: Int = 0, seconds: Int = 0) throws -> Date {
		guard (0..<24).contains(hour) else { throw ErrorDate.invalidHour }
		guard (0..<60).contains(minutes) else { throw ErrorDate.invalidMinutes }
		guard (0..<60).contains(seconds) else { throw ErrorDate.invalidSeconds }

		let calendar = Calendar(identifier: .gregorian)
		var components = calendar.dateComponents([.day, .month, .year], from: self)
		components.hour = hour
		components.minute = minutes
		components.second = seconds

		guard let result = calendar.date(from: components) else {
			throw ErrorDate.invalidDate
		}
		return result
	}
}


/// Add days to a date
public func + (date: Date, days: Int) -> Date {
	date.dateAdding(days)
}

/// Substract days to a date
public func - (date: Date, days: Int) -> Date {
	return date + (-days)
}
