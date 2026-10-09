import Foundation

/// Price rise rules (Docs/SPEC.md 4.10).
/// Pure logic on plain values, so it can be tested alone.
enum PriceRise {
    /// round(price x (1 + percent)) to the nearest pound, with exactly 50p going down.
    /// 15 -> 16, 12 -> 13, 20 -> 22, 25 -> 27.
    static func newPrice(_ price: Decimal, percent: Decimal) -> Decimal {
        var raised = price * (1 + percent)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raised, 2, .plain)       // to the penny first
        var shifted = rounded - Decimal(string: "0.5")!
        var result = Decimal()
        NSDecimalRound(&result, &shifted, 0, .up)           // then ceiling: x.5 goes down, x.51 goes up
        return result
    }

    /// When the rise takes effect for this customer, or nil if it doesn't apply to them.
    /// - Doesn't apply if their price started on or after the rise date.
    /// - If their price started less than `delayMonths` before the rise date, it waits until `delayMonths` after it started.
    static func effectiveDate(priceSince: Date?, riseDate: Date, delayMonths: Int, calendar: Calendar) -> Date? {
        guard let priceSince else { return riseDate }       // blank means before records began
        if priceSince >= riseDate { return nil }
        let delayed = calendar.date(byAdding: .month, value: delayMonths, to: priceSince) ?? riseDate
        return max(riseDate, delayed)
    }

    /// A rise is due when the price has had no change for `dueAfterMonths` (or has never been recorded).
    static func isDue(priceSince: Date?, today: Date, dueAfterMonths: Int, calendar: Calendar) -> Bool {
        guard let priceSince else { return true }
        guard let due = calendar.date(byAdding: .month, value: dueAfterMonths, to: priceSince) else { return false }
        return due <= today
    }

    /// The rise date to preview with when none has been set: the next 6 April.
    static func previewDate(after today: Date, calendar: Calendar) -> Date {
        let year = calendar.component(.year, from: today)
        let thisYears = calendar.date(from: DateComponents(year: year, month: 4, day: 6))!
        return today <= thisYears ? thisYears : calendar.date(from: DateComponents(year: year + 1, month: 4, day: 6))!
    }
}
