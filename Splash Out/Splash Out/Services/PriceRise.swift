import Foundation
import SwiftData

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

    // MARK: Rises that have been set (pending)

    static let messageKey = "whatsapp.priceRiseTemplate"
    static let defaultMessage = "Hi {name}, from {date} your window clean will be {new} (currently {old}). Thank you for your custom."

    /// The price rise message for a customer.
    static func message(template: String, name: String, old: Decimal, new: Decimal, from date: Date) -> String {
        template
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{old}", with: old.pounds)
            .replacingOccurrences(of: "{new}", with: new.pounds)
            .replacingOccurrences(of: "{date}", with: DayMessage.fullDate(date))
    }

    /// Sets a rise for a customer: the new price starts on `from`.
    @MainActor
    static func set(_ customer: Customer, to price: Decimal, from date: Date) {
        customer.pendingPrice = price
        customer.pendingPriceFrom = RoundCalendar.startOfDay(date)
        customer.pendingPriceToldAt = nil
    }

    @MainActor
    static func cancel(_ customer: Customer) {
        customer.pendingPrice = nil
        customer.pendingPriceFrom = nil
        customer.pendingPriceToldAt = nil
    }

    /// Switches a customer to their new price if its day has come (or `now` is true), recording it in their history.
    /// Returns true if the price changed.
    @MainActor @discardableResult
    static func applyIfDue(_ customer: Customer, today: Date = RoundCalendar.startOfDay(), now: Bool = false, in context: ModelContext) -> Bool {
        guard let price = customer.pendingPrice, let from = customer.pendingPriceFrom, now || from <= today else { return false }
        let effective = now ? min(from, today) : from
        if price != customer.price {
            context.insert(PriceChange(date: effective, oldPrice: customer.price, newPrice: price, reason: .rise, customer: customer))
            customer.price = price
            customer.priceSince = effective
        }
        cancel(customer)
        return true
    }

    static let lastAppliedKey = "priceRise.lastApplied"

    /// Every rise whose day has come. Run when the app opens and at midnight. Returns how many prices changed.
    @MainActor @discardableResult
    static func applyDue(in context: ModelContext, today: Date = RoundCalendar.startOfDay(), defaults: UserDefaults = .standard) -> Int {
        let customers = (try? context.fetch(FetchDescriptor<Customer>())) ?? []
        var changed = 0
        for customer in customers where customer.pendingPrice != nil {
            if applyIfDue(customer, today: today, in: context) { changed += 1 }
        }
        if changed > 0 {
            try? context.save()
            defaults.set("\(RoundCalendar.dayString(today)):\(changed)", forKey: lastAppliedKey)
        }
        return changed
    }
}
