import Foundation

/// Weekly targets, ahead/behind, and tax-year month totals (Docs/SPEC.md 4.2 to 4.5), used by the Weekly,
/// Today and Tax Year screens. Pure logic on plain values, so it can be tested alone.
enum WeekMetrics {
    struct Config {
        /// Usual day target in pounds, Monday = index 0 ... Sunday = 6 (0 means not a working day).
        var usualTargets: [Decimal]
        /// Target for an extra (non-usual) worked day.
        var extraTarget: Decimal
        /// Cleans needed on a date for it to count as a worked day.
        var minHouses: Int
        /// Dates logged as a day off (holiday or illness).
        var daysOff: Set<Date>
    }

    struct DayTotals {
        var houses = 0
        var work: Decimal = 0
        var paid: Decimal = 0
    }

    struct Week: Equatable {
        var start: Date
        var work: Decimal
        var paid: Decimal
        var houses: Int
        var target: Decimal
        var daysWorked: Int
        var usualDays: Int
        var isCurrent: Bool
    }

    // MARK: Dates

    /// Monday of the week containing `date` (weeks run Monday to Sunday).
    static func monday(onOrBefore date: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
        let sinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -sinceMonday, to: calendar.startOfDay(for: date))!
    }

    private static func weekdayIndex(_ date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    private static func addDays(_ date: Date, _ days: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)!
    }

    // MARK: Weeks

    /// Usual-pattern target for one date, zero if it was logged as a day off.
    private static func usualTarget(on date: Date, config: Config, calendar: Calendar) -> Decimal {
        if config.daysOff.contains(date) { return 0 }
        return config.usualTargets[weekdayIndex(date, calendar: calendar)]
    }

    static func week(
        starting start: Date,
        today: Date,
        days: [Date: DayTotals],
        config: Config,
        calendar: Calendar
    ) -> Week {
        var work: Decimal = 0, paid: Decimal = 0, houses = 0
        var base: Decimal = 0, usualDays = 0, worked = 0
        for offset in 0..<7 {
            let date = addDays(start, offset, calendar: calendar)
            let target = usualTarget(on: date, config: config, calendar: calendar)
            base += target
            if target > 0 { usualDays += 1 }
            if let totals = days[date] {
                work += totals.work
                paid += totals.paid
                houses += totals.houses
                if totals.houses >= config.minHouses { worked += 1 }
            }
        }
        let end = addDays(start, 6, calendar: calendar)
        let isCurrent = start <= today && today <= end
        let isPast = end < today
        let extra = Decimal(max(0, worked - usualDays)) * config.extraTarget
        // A past week with no worked days was a week off. The current week still counts its usual days.
        let target = (isPast && worked == 0) ? 0 : base + extra
        return Week(start: start, work: work, paid: paid, houses: houses, target: target,
                    daysWorked: worked, usualDays: usualDays, isCurrent: isCurrent)
    }

    /// Weeks from the one containing `firstDate` up to and including the current week.
    static func weeks(
        from firstDate: Date,
        today: Date,
        days: [Date: DayTotals],
        config: Config,
        calendar: Calendar
    ) -> [Week] {
        var result: [Week] = []
        var start = monday(onOrBefore: firstDate, calendar: calendar)
        let last = monday(onOrBefore: today, calendar: calendar)
        while start <= last {
            result.append(week(starting: start, today: today, days: days, config: config, calendar: calendar))
            start = addDays(start, 7, calendar: calendar)
        }
        return result
    }

    // MARK: Ahead / behind (4.5)

    struct AheadBehind: Equatable {
        var done: Decimal
        var expected: Decimal
        var difference: Decimal { done - expected }
    }

    /// Tax-year work to date against the weekly targets of finished weeks plus this week's usual days so far.
    static func aheadBehind(
        taxYearStart: Date,
        today: Date,
        days: [Date: DayTotals],
        config: Config,
        calendar: Calendar
    ) -> AheadBehind {
        var done: Decimal = 0
        for (date, totals) in days where date >= taxYearStart && date <= today { done += totals.work }

        let thisMonday = monday(onOrBefore: today, calendar: calendar)
        var expected: Decimal = 0
        var start = monday(onOrBefore: taxYearStart, calendar: calendar)
        while start < thisMonday {
            expected += week(starting: start, today: today, days: days, config: config, calendar: calendar).target
            start = addDays(start, 7, calendar: calendar)
        }

        // This week: usual days up to and including today, plus any extra days already worked.
        var usualSoFar = 0
        var workedSoFar = 0
        for offset in 0..<7 {
            let date = addDays(thisMonday, offset, calendar: calendar)
            guard date <= today else { break }
            let target = usualTarget(on: date, config: config, calendar: calendar)
            expected += target
            if target > 0 { usualSoFar += 1 }
            if (days[date]?.houses ?? 0) >= config.minHouses { workedSoFar += 1 }
        }
        expected += Decimal(max(0, workedSoFar - usualSoFar)) * config.extraTarget
        return AheadBehind(done: done, expected: expected)
    }

    // MARK: Tax-year months

    struct MonthRow: Equatable {
        var label: String
        var from: Date
        /// Last day included.
        var to: Date
        var work: Decimal = 0
        var paid: Decimal = 0
        var notYetPaid: Decimal = 0
        var cleans = 0
        var extras: Decimal = 0
        var averagePerWeek: Decimal?
    }

    /// Calendar months across a tax year, with April split at the 6th: "April (from 6th)", May ... March, "April (to 5th)".
    static func monthRanges(taxYearStart year: Int, calendar: Calendar) -> [(label: String, from: Date, to: Date)] {
        func date(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d))! }
        let names = ["May", "June", "July", "August", "September", "October", "November", "December", "January", "February", "March"]
        var ranges: [(String, Date, Date)] = [("April (from 6th)", date(year, 4, 6), date(year, 4, 30))]
        for (index, name) in names.enumerated() {
            let month = 5 + index
            let y = month > 12 ? year + 1 : year
            let m = month > 12 ? month - 12 : month
            let firstOfNext = date(m == 12 ? y + 1 : y, m == 12 ? 1 : m + 1, 1)
            ranges.append((name, date(y, m, 1), calendar.date(byAdding: .day, value: -1, to: firstOfNext)!))
        }
        ranges.append(("April (to 5th)", date(year + 1, 4, 1), date(year + 1, 4, 5)))
        return ranges
    }
}
