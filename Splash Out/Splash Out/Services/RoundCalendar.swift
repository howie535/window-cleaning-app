import Foundation

/// All round dates are calendar days in the UK. Parsing and formatting always use the
/// Europe/London calendar so a date can't slip a day (it matters at the 6 April tax-year edge).
enum RoundCalendar {
    static let london: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = london
        formatter.timeZone = london.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    private static let dayFormatter = formatter("yyyy-MM-dd")
    private static let timestampFormatter = formatter("yyyy-MM-dd'T'HH:mm:ss")
    private static let fileStampFormatter = formatter("yyyyMMdd-HHmmss")

    static func date(year: Int, month: Int, day: Int) -> Date {
        london.date(from: DateComponents(year: year, month: month, day: day))!
    }

    static func startOfDay(_ date: Date = Date()) -> Date {
        london.startOfDay(for: date)
    }

    /// "2026-04-21" -> start of that day in London. Nil if it isn't a valid date.
    static func parseDay(_ string: String) -> Date? {
        dayFormatter.date(from: string)
    }

    static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func timestampString(_ date: Date = Date()) -> String {
        timestampFormatter.string(from: date)
    }

    static func fileStamp(_ date: Date = Date()) -> String {
        fileStampFormatter.string(from: date)
    }
}

/// Tax years run 6 April to 5 April.
enum TaxYear {
    /// The start year of the tax year containing `date` (6 Apr 2026 ... 5 Apr 2027 -> 2026).
    static func startYear(containing date: Date) -> Int {
        let calendar = RoundCalendar.london
        let year = calendar.component(.year, from: date)
        return date >= RoundCalendar.date(year: year, month: 4, day: 6) ? year : year - 1
    }

    static func range(startYear: Int) -> Range<Date> {
        RoundCalendar.date(year: startYear, month: 4, day: 6) ..< RoundCalendar.date(year: startYear + 1, month: 4, day: 6)
    }

    static func label(startYear: Int) -> String {
        "\(startYear)-\(String((startYear + 1) % 100).leftPadded(to: 2))"
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: "0", count: length - count) + self
    }
}
