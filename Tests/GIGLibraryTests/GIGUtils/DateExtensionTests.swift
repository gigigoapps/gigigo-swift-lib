//
//  DateExtensionTests.swift
//  GIGLibrary
//
//  Created by Alejandro Jiménez Agudo.
//  Copyright © 2026 Gigigo SL. All rights reserved.
//

import Testing
import Foundation
@testable import GIGLibrary

@Suite("Date+GIGExtension")
struct DateExtensionTests {

    // MARK: - dateFromString

    @Test("Given a wrong format, when parsing, then it returns nil")
    func returnsNilWhenFormatIsWrong() {
        #expect(Date.dateFromString("wrong format") == nil)
    }

    @Test("Given a valid ISO string, when parsing, then it returns the expected date")
    func returnsDateWhenFormatIsCorrect() throws {
        let date = try #require(Date.dateFromString("1985-01-24T12:00:00Z"))
        #expect(date == Self.alejandroBirthday())
    }

    @Test("Given a custom format with an AM/PM token, when parsing a PM time, then it decodes the 24h hour")
    func parsesPMTimeWhenFormatUsesAMPMToken() throws {
        let date = try #require(Date.dateFromString("2026-07-01 02:30 PM", format: "yyyy-MM-dd hh:mm a"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let components = calendar.dateComponents([.hour, .minute], from: date)
        #expect(components.hour == 14)
        #expect(components.minute == 30)
    }

    @Test("Given an ISO string with an explicit offset, when parsing, then the offset is honored regardless of device time zone")
    func parsesISOStringWithExplicitOffset() throws {
        let date = try #require(Date.dateFromString("2026-07-01T12:00:00Z"))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        #expect(components.year == 2026)
        #expect(components.month == 7)
        #expect(components.day == 1)
        #expect(components.hour == 12)
    }

    @Test("Given a zone-less format, when parsing, then it is interpreted in GMT regardless of the device time zone")
    func parsesZonelessFormatInGMT() throws {
        // A format without a zone token must resolve to the same instant as the equivalent GMT ISO
        // string on any runner. This pins the intentional deterministic-GMT contract: a device-local
        // implementation would make these differ on a non-UTC machine.
        let zoneless = try #require(Date.dateFromString("2026-07-01 12:00", format: "yyyy-MM-dd HH:mm"))
        let gmt = try #require(Date.dateFromString("2026-07-01T12:00:00Z"))
        #expect(zoneless == gmt)
    }

    // MARK: - string(with:)

    @Test("Given a PM date, when formatted with a lone AM/PM token, then it emits the en_US_POSIX symbol")
    func stringWithAMPMTokenEmitsSymbol() throws {
        // Guards the intentional behavior change: the previous implementation blanked amSymbol/pmSymbol,
        // so a format containing `a` produced an empty string; it now emits the standard "AM"/"PM".
        let pmDate = try #require(Date.dateFromString("2026-07-01T22:13:00Z"))
        #expect(pmDate.string(with: "a") == "PM")

        let amDate = try #require(Date.dateFromString("2026-07-01T09:13:00Z"))
        #expect(amDate.string(with: "a") == "AM")
    }

    @Test("Given a date formatted with an AM/PM token, when parsed back, then it round-trips")
    func stringWithAMPMTokenRoundTrips() throws {
        let format = "yyyy-MM-dd hh:mm a"
        let original = try #require(Date.dateFromString("2026-07-01T22:13:00Z"))

        let formatted = original.string(with: format)
        let reparsed = try #require(Date.dateFromString(formatted, format: format))

        #expect(reparsed == original)
    }

    // MARK: - Adding / subtracting days

    @Test("Given a date, when adding one day, then it returns the next day")
    func addingOneDayReturnsNextDay() throws {
        let date = try #require(Date.dateFromString("1985-01-24T12:00:00Z"))
        #expect(date + 1 == Self.alejandroBirthdayNextDay())
    }

    @Test("Given a date, when subtracting one day, then it returns the previous day")
    func subtractingOneDayReturnsPreviousDay() throws {
        let date = try #require(Date.dateFromString("1985-01-25T12:00:00Z"))
        #expect(date - 1 == Self.alejandroBirthday())
    }

    // MARK: - Comparing dates

    @Test("Given today and tomorrow, then the comparison operators order them correctly")
    func comparisonOperatorsOrderDates() {
        let today = Date.today()
        let tomorrow = today + 1

        #expect(tomorrow > today)
        #expect((today > today) == false)
        #expect(today < tomorrow)
        #expect((today < today) == false)
    }

    // MARK: - setHour

    @Test("Given an hour, when setting it, then the local time is updated keeping the date")
    func setHourUpdatesLocalTime() throws {
        // setHour keeps the local day/month/year and sets the local time, so assert on the
        // device-calendar components to stay independent of the runner's time zone.
        let result = try Self.alejandroBirthday().setHour(14)
        Self.expectLocalTime(of: result, hour: 14, minutes: 0, seconds: 0)
    }

    @Test("Given hour, minutes and seconds, when setting them, then the local time is updated")
    func setHourWithMinutesAndSeconds() throws {
        let result = try Self.alejandroBirthday().setHour(14, minutes: 59, seconds: 59)
        Self.expectLocalTime(of: result, hour: 14, minutes: 59, seconds: 59)
    }

    @Test("Given an out-of-range hour, when setting it, then it throws invalidHour", arguments: [24, -3])
    func setHourThrowsForInvalidHour(hour: Int) {
        #expect(throws: ErrorDate.invalidHour) {
            try Self.alejandroBirthday().setHour(hour)
        }
    }

    @Test("Given out-of-range minutes, when setting them, then it throws invalidMinutes", arguments: [60, -10])
    func setHourThrowsForInvalidMinutes(minutes: Int) {
        #expect(throws: ErrorDate.invalidMinutes) {
            try Self.alejandroBirthday().setHour(14, minutes: minutes)
        }
    }

    @Test("Given out-of-range seconds, when setting them, then it throws invalidSeconds", arguments: [60, -1])
    func setHourThrowsForInvalidSeconds(seconds: Int) {
        #expect(throws: ErrorDate.invalidSeconds) {
            try Self.alejandroBirthday().setHour(14, minutes: 3, seconds: seconds)
        }
    }

    // MARK: - Concurrency

    @Test("Given many concurrent tasks, when they share the formatter cache, then every parse/format round-trips consistently")
    func concurrentFormatterAccessIsConsistent() async {
        // Exercises the lock-guarded cache and the shared, never-mutated formatters that justify
        // DateFormatterCache's @unchecked Sendable: concurrent readers must all agree.
        let iso = "1985-01-24T12:00:00Z"
        let customFormat = "yyyy-MM-dd HH:mm"

        await withTaskGroup(of: Bool.self) { group in
            for index in 0..<200 {
                group.addTask {
                    guard let date = Date.dateFromString(iso) else { return false }
                    if index.isMultiple(of: 2) {
                        let reparsed = Date.dateFromString(date.string(with: DateISOFormat))
                        return reparsed == date
                    } else {
                        // A zone-less format resolves in GMT, matching the 12:00Z instant's date.
                        return date.string(with: customFormat) == "1985-01-24 12:00"
                    }
                }
            }
            for await isConsistent in group {
                #expect(isConsistent)
            }
        }
    }

    // MARK: - Helpers

    private static func expectLocalTime(of date: Date, hour: Int, minutes: Int, seconds: Int, sourceLocation: SourceLocation = #_sourceLocation) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.day, .month, .year, .hour, .minute, .second], from: date)
        #expect(components.day == 24, sourceLocation: sourceLocation)
        #expect(components.month == 1, sourceLocation: sourceLocation)
        #expect(components.year == 1985, sourceLocation: sourceLocation)
        #expect(components.hour == hour, sourceLocation: sourceLocation)
        #expect(components.minute == minutes, sourceLocation: sourceLocation)
        #expect(components.second == seconds, sourceLocation: sourceLocation)
    }

    private static func alejandroBirthday() -> Date {
        Self.date(day: 24)
    }

    private static func alejandroBirthdayNextDay() -> Date {
        Self.date(day: 25)
    }

    private static func date(day: Int) -> Date {
        var components = DateComponents()
        components.day = day
        components.month = 1
        components.year = 1985
        components.hour = 12
        components.timeZone = TimeZone(secondsFromGMT: 0)
        // The fixed components always resolve to a valid gregorian date.
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}
