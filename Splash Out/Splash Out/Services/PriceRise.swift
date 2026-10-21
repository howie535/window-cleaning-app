import Foundation

/// Price rises (Docs/SPEC.md 4.10), kept simple: prices are changed by hand on a customer's page, and the app tracks
/// when each customer's price last went up ("price since"), so the ones due a rise can be listed.
enum PriceRise {
    /// A rise is due when the price has had no change for `dueAfterMonths`, or no date has been logged.
    static func isDue(priceSince: Date?, today: Date, dueAfterMonths: Int, calendar: Calendar) -> Bool {
        guard let priceSince else { return true }
        guard let due = calendar.date(byAdding: .month, value: dueAfterMonths, to: priceSince) else { return false }
        return due <= today
    }
}
