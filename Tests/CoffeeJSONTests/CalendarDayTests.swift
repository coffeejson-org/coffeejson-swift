import Testing
import Foundation
@testable import CoffeeJSON

/// A dated field is a day on a calendar, and the projection must not turn one
/// into an instant.
///
/// A `Date` at UTC midnight, formatted in a local time zone, renders as the
/// previous day west of UTC: `"roast_date": "2026-06-20"` reads **Jun 19,
/// 2026**. The roaster's date, off by one, wearing the roaster's authority.
@Suite("Calendar day")
struct CalendarDayTests {
    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    @Test("a roast date projects to the day the roaster stated")
    func roastDateIsADay() throws {
        let bean = try decodeBean(#"{"coffeejson":"1.0","beans":[{"name":"Nano Challa","roast_date":"2026-06-20"}]}"#)
        let day = try #require(bean.roastDate)
        #expect(day.year == 2026)
        #expect(day.month == 6)
        #expect(day.day == 20)
    }

    @Test("that day reads back as itself in every zone, which is the whole point",
          arguments: ["Pacific/Honolulu", "UTC", "Asia/Tokyo"])   // UTC−10, UTC, UTC+9
    func theDaySurvivesEveryZone(_ zone: String) throws {
        let bean = try decodeBean(#"{"coffeejson":"1.0","beans":[{"name":"Nano Challa","roast_date":"2026-06-20"}]}"#)
        let day = try #require(bean.roastDate)
        let calendar = calendar(zone)
        // The consumer's own calendar, the deliberate step from a day to a
        // moment — and the day comes back out of it unchanged.
        let instant = try #require(day.date(in: calendar))
        let read = calendar.dateComponents([.year, .month, .day], from: instant)
        #expect(read.year == 2026)
        #expect(read.month == 6)
        #expect(read.day == 20)
    }

    @Test("an instant fixed in one zone is what went wrong, and it still does")
    func anInstantIsNotADay() throws {
        let day = try #require(CalendarDay(iso8601: "2026-06-20"))
        // Midnight UTC — the instant a naive projection hands a consumer.
        let utcMidnight = try #require(day.date(in: calendar("UTC")))
        let west = calendar("Pacific/Honolulu").dateComponents([.year, .month, .day], from: utcMidnight)
        #expect(west.day == 19)   // the reported bug, reproduced from the instant
        // Its own zone's midnight is a different instant, and the same day.
        let localMidnight = try #require(day.date(in: calendar("Pacific/Honolulu")))
        #expect(localMidnight != utcMidnight)
    }

    @Test("the same instant is two different days in two calendars")
    func anInstantIsADayOnlyOnceACalendarIsNamed() throws {
        // 2026-06-20T09:00Z — evening in Tokyo, the night before in Honolulu.
        let instant = Date(timeIntervalSince1970: 1_781_946_000)
        #expect(CalendarDay(instant, in: calendar("Asia/Tokyo")) == CalendarDay(year: 2026, month: 6, day: 20))
        #expect(CalendarDay(instant, in: calendar("Pacific/Honolulu")) == CalendarDay(year: 2026, month: 6, day: 19))
    }

    @Test("a day survives the crossing and back in the calendar it was crossed in",
          arguments: ["Pacific/Honolulu", "UTC", "Asia/Tokyo"])
    func theCrossingRoundTrips(_ zone: String) throws {
        let calendar = calendar(zone)
        for text in ["2026-06-20", "2028-02-29", "2019-12-31"] {
            let day = try #require(CalendarDay(iso8601: text))
            let instant = try #require(day.date(in: calendar))
            #expect(CalendarDay(instant, in: calendar) == day)
        }
    }

    @Test("an unresolvable instant is absent, never a fabricated day",
          arguments: [Calendar.Identifier.gregorian, .islamicUmmAlQura, .hebrew, .japanese])
    func anUnresolvedInstantIsNoDay(_ identifier: Calendar.Identifier) {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        for instant in [Date.distantPast, .distantFuture, Date(timeIntervalSince1970: 0)] {
            let read = calendar.dateComponents([.year, .month, .day], from: instant)
            // Absent for two reasons and no third: the calendar resolved no
            // triple, or the triple it resolved is no day on the Gregorian
            // calendar ``iso8601`` spells. Present, each component is the
            // calendar's own answer rather than a substitute.
            guard let day = CalendarDay(instant, in: calendar) else {
                guard let year = read.year, let month = read.month, let stated = read.day
                else { continue }
                #expect(CalendarDay(year: year, month: month, day: stated) == nil)
                continue
            }
            #expect((day.year, day.month, day.day) == (read.year, read.month, read.day))
        }
    }

    @Test("the wire spelling round-trips")
    func iso8601RoundTrips() throws {
        for text in ["2026-06-20", "2028-02-29", "0001-01-01", "2019-12-31"] {
            let day = try #require(CalendarDay(iso8601: text))
            #expect(day.iso8601 == text)
        }
        #expect(CalendarDay(year: 2026, month: 6, day: 5)?.iso8601 == "2026-06-05")
    }

    @Test("a shape that is not the format's ten bytes is not a day",
          arguments: [
            "2026-6-20",       // unpadded
            "2026/06/20",      // wrong separators
            "-2026-01-01",     // a sign `split` would have discarded
            "2026-06-20T00:00:00Z",   // an instant, which this field is not
            "20260620",
            "2026-06-2 ",
            "",
          ])
    func malformedShapesAreNotDays(_ text: String) {
        #expect(CalendarDay(iso8601: text) == nil)
    }

    @Test("a day the calendar does not have is not a day either",
          arguments: ["2026-13-45", "2026-02-31", "2026-00-10", "2026-06-00", "2027-02-29"])
    func impossibleDaysAreNotDays(_ text: String) {
        // `Calendar.date(from:)` normalizes these instead of refusing them, so
        // each would otherwise read as a different, wrong date.
        #expect(CalendarDay(iso8601: text) == nil)
    }

    @Test("a leap day the calendar does have is a day")
    func leapDayIsADay() throws {
        let day = try #require(CalendarDay(iso8601: "2028-02-29"))
        #expect(day == CalendarDay(year: 2028, month: 2, day: 29))
    }

    // The stated day and the parsed one are one constructor: a value this type
    // can hold but the calendar cannot is a wrong claim the wire path already
    // refuses, and `iso8601` would print it.
    @Test("a stated day the calendar does not have is not a day",
          arguments: [(2026, 13, 45), (2026, 2, 31), (2026, 0, 10), (2026, 6, 0), (2027, 2, 29)])
    func impossibleStatedDaysAreNotDays(_ parts: (Int, Int, Int)) {
        #expect(CalendarDay(year: parts.0, month: parts.1, day: parts.2) == nil)
    }

    @Test("a stated leap day the calendar does have is a day")
    func statedLeapDayIsADay() throws {
        let day = try #require(CalendarDay(year: 2028, month: 2, day: 29))
        #expect(day.iso8601 == "2028-02-29")
    }

    @Test("days order as days")
    func daysCompare() throws {
        let june20 = try #require(CalendarDay(year: 2026, month: 6, day: 20))
        #expect(june20 < (try #require(CalendarDay(year: 2026, month: 7, day: 1))))
        #expect(try #require(CalendarDay(year: 2025, month: 12, day: 31))
                    < (try #require(CalendarDay(year: 2026, month: 1, day: 1))))
        #expect(june20 == CalendarDay(year: 2026, month: 6, day: 20))
    }

    @Test("a recipe's publication date is the same kind of thing")
    func datePublishedIsADay() throws {
        let document = try Codec.decodeDocument(Data(#"""
        {"coffeejson":"1.0","recipes":[{"title":"V60","coffee":{"value":15,"unit":"gram"},
          "water":{"value":250,"unit":"gram"},"date_published":"2019-03-27"}]}
        """#.utf8))
        #expect(document.recipes.first?.datePublished == CalendarDay(year: 2019, month: 3, day: 27))
    }
}
