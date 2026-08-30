import Foundation

/// A calendar day — a year, a month and a day, and **no instant**.
///
/// The format's dated fields (`roast_date`, `date_published`) are days on a
/// calendar, not moments: a bag roasted on 2026-06-20 was roasted on that day
/// wherever it is read. A `Date` cannot say that. It is an instant, so a
/// projection that produced one would have to pick a midnight in some zone, and
/// a reader west of it renders the day before — the roaster's date, off by one,
/// wearing the roaster's authority.
///
/// So this carries the day and stops. A consumer that needs an instant asks for
/// one explicitly with its own calendar (``date(in:)``), and a consumer that
/// re-emits states the day with ``iso8601``, the one spelling of the wire form.
public struct CalendarDay: Equatable, Hashable, Sendable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    /// A day, as stated, or `nil` when the Gregorian calendar has no such day.
    ///
    /// Validated here and not only on the wire path: ``iso8601`` prints whatever
    /// this holds, so an unchecked 2026-13-45 would leave as a producer's claim.
    public init?(year: Int, month: Int, day: Int) {
        guard DateComponents(year: year, month: month, day: day)
            .isValidDate(in: Self.gregorian) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// A day from the wire's `yyyy-MM-dd`, or `nil` when the string is not one.
    ///
    /// Both checks below guard the same failure, which is not "a bad date is
    /// rejected" but "a bad date reads as a *different* date".
    ///
    /// The **shape** check is why the string is not split on `-`: `split` drops
    /// empty subsequences, so `-2026-01-01` would yield three parts and parse as
    /// the year 2026 with its sign silently discarded.
    ///
    /// The **validity** check is ``init(year:month:day:)``'s, for the reason
    /// stated there: `Calendar.date(from:)` *normalizes* out-of-range components
    /// instead of refusing them, so `2026-13-45` would read as 2027-02-14 and
    /// `2026-02-31` as 2026-03-03. A roast date is read as coffee freshness, and
    /// a date two months out is a wrong claim wearing the roaster's authority.
    /// Absent is honest.
    public init?(iso8601 string: String) {
        // ASCII positions, so the UTF-8 view is the right unit: `Character`
        // would let a combining mark ride along inside a "digit".
        let bytes = Array(string.utf8)
        guard bytes.count == 10,
              bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-"),
              [0, 1, 2, 3, 5, 6, 8, 9].allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[$0]) })
        else { return nil }
        func number(_ range: Range<Int>) -> Int {
            range.reduce(0) { $0 * 10 + Int(bytes[$1] - UInt8(ascii: "0")) }
        }
        self.init(year: number(0 ..< 4), month: number(5 ..< 7), day: number(8 ..< 10))
    }

    /// This day as the wire writes it, `yyyy-MM-dd` — zero-padded, never
    /// localized. The counterpart of ``init(iso8601:)``, here rather than at
    /// each consumer so one rule has one spelling.
    public var iso8601: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var dateComponents: DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    /// The instant this day *begins* in `calendar` — the deliberate step from a
    /// day to a moment, which is the consumer's to take and never this
    /// package's. Pass the calendar the reader is in; the result is only ever as
    /// meaningful as that choice.
    public func date(in calendar: Calendar) -> Date? {
        calendar.date(from: dateComponents)
    }

    /// The day `date` falls on in `calendar` — the same deliberate crossing as
    /// ``date(in:)``, in the other direction. The calendar decides which day an
    /// instant is, and a reader in another zone gets another day, so it is a
    /// parameter here too. `nil` when the calendar resolves no year, month and
    /// day for that instant, and equally when the triple it resolves is no day
    /// on the Gregorian calendar ``iso8601`` spells — absent rather than a day
    /// nobody stated.
    public init?(_ date: Date, in calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// The calendar the format's dates are stated in — proleptic Gregorian, per
    /// ISO 8601. Validity is calendar-dependent and a leap day is the case that
    /// proves it, so an impossible day is refused against this one. Never used
    /// to place a day in time.
    private static let gregorian = Calendar(identifier: .gregorian)
}
