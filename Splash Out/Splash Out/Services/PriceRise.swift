import Foundation
import SwiftData

/// Price rises (Docs/SPEC.md 4.10). A customer is due a rise once their price has gone `dueAfterMonths` without one.
/// With no rise logged, the clock starts at their first clean. The new price is the chosen percentage on top, to the
/// nearest pound; confirming it (Price Rise page) changes the price and logs the rise.
enum PriceRise {
    /// A rise is due when the price has had no change for `dueAfterMonths`, or no date has been logged.
    static func isDue(priceSince: Date?, today: Date, dueAfterMonths: Int, calendar: Calendar) -> Bool {
        guard let priceSince else { return true }
        guard let due = calendar.date(byAdding: .month, value: dueAfterMonths, to: priceSince) else { return false }
        return due <= today
    }

    /// When the current price started: the last rise logged, otherwise the first clean. nil = never cleaned.
    static func countedFrom(_ customer: Customer) -> Date? {
        customer.priceSince ?? customer.allVisits.filter { $0.kind == .cleaned }.map(\.date).min()
    }

    /// When the next rise is due (nil = never cleaned and no rise logged, so not due).
    static func dueDate(_ customer: Customer, dueAfterMonths: Int, calendar: Calendar = RoundCalendar.london) -> Date? {
        countedFrom(customer).flatMap { calendar.date(byAdding: .month, value: dueAfterMonths, to: $0) }
    }

    static func isDue(_ customer: Customer, today: Date, dueAfterMonths: Int, calendar: Calendar = RoundCalendar.london) -> Bool {
        guard customer.price > 0, let due = dueDate(customer, dueAfterMonths: dueAfterMonths, calendar: calendar) else { return false }
        return due <= today
    }

    /// `amount` plus `percent` (0.10 = 10%), to the nearest pound with standard rounding: 50p and above goes up,
    /// below 50p goes down. £15 → £16.50 → £17; £12 → £13.20 → £13.
    static func risen(_ amount: Decimal, percent: Double) -> Decimal {
        let rate = Decimal(string: String(format: "%.4f", percent)) ?? 0
        var exact = amount * (1 + rate)
        var whole = Decimal()
        NSDecimalRound(&whole, &exact, 0, .plain)
        return whole
    }

    struct Proposal {
        var price: Decimal
        var newPrice: Decimal
        /// Monthly payers: the monthly amount goes up instead, and the price per clean follows from it.
        var monthly: Decimal?
        var newMonthly: Decimal?
        var altPrice: Decimal?
        var newAltPrice: Decimal?
        /// Extra a round (every-other customers at half).
        var addsPerRound: Decimal
    }

    static func proposal(for customer: Customer, percent: Double) -> Proposal {
        let weight: Decimal = customer.everyOther ? Decimal(0.5) : 1
        if customer.payMethod == .directDebit, let monthly = customer.monthlyAmount {
            let newMonthly = risen(monthly, percent: percent)
            let newPrice = DirectDebit.perClean(monthly: newMonthly)
            return Proposal(price: customer.price, newPrice: newPrice, monthly: monthly, newMonthly: newMonthly,
                            altPrice: customer.secondPrice, newAltPrice: customer.secondPrice.map { risen($0, percent: percent) },
                            addsPerRound: (newPrice - customer.price) * weight)
        }
        let newPrice = risen(customer.price, percent: percent)
        return Proposal(price: customer.price, newPrice: newPrice,
                        altPrice: customer.secondPrice, newAltPrice: customer.secondPrice.map { risen($0, percent: percent) },
                        addsPerRound: (newPrice - customer.price) * weight)
    }

    /// The rise has been put in place: new price (and monthly amount, second price), logged as a rise dated today.
    @MainActor
    static func confirm(_ customer: Customer, percent: Double, today: Date, context: ModelContext) {
        let p = proposal(for: customer, percent: percent)
        context.insert(PriceChange(date: today, oldPrice: p.price, newPrice: p.newPrice, reason: .rise, customer: customer))
        customer.price = p.newPrice
        if let newMonthly = p.newMonthly { customer.monthlyAmount = newMonthly }
        if let newAlt = p.newAltPrice { customer.altPrice = newAlt }
        customer.priceSince = today
        customer.pendingPrice = nil
        customer.pendingPriceFrom = nil
        customer.pendingPriceToldAt = nil
        try? context.save()
    }
}
