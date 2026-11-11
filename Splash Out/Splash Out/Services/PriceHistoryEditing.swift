import Foundation
import SwiftData

/// Keeping a customer's price history tidy when the price is edited by hand.
@MainActor
enum PriceHistoryEditing {
    /// Logs a price change made on the edit page. A second change the same day updates that day's entry instead of
    /// adding another (so going in and out of Edit leaves one line), and one that puts the price back removes it.
    static func record(_ customer: Customer, from old: Decimal, to new: Decimal, context: ModelContext, now: Date = .now) {
        let calendar = RoundCalendar.london
        if let today = (customer.priceChanges ?? []).filter({ calendar.isDate($0.date, inSameDayAs: now) }).max(by: { $0.date < $1.date }) {
            if today.oldPrice == new {
                delete(today, from: customer, price: new, context: context)
                return
            }
            today.newPrice = new
            today.reason = new > today.oldPrice ? .rise : .correction
            today.date = now
        } else {
            context.insert(PriceChange(date: now, oldPrice: old, newPrice: new, reason: new > old ? .rise : .correction, customer: customer))
        }
        customer.priceSince = now
    }

    /// Removes one entry. The price stays as it is; if "last rise" came from this entry, it goes back to the latest
    /// remaining change that set the current price (or to none, so it counts from the first clean).
    static func delete(_ change: PriceChange, from customer: Customer, price: Decimal? = nil, context: ModelContext) {
        let calendar = RoundCalendar.london
        let wasLastRise = customer.priceSince.map { calendar.isDate($0, inSameDayAs: change.date) } ?? false
        context.delete(change)
        if wasLastRise {
            customer.priceSince = (customer.priceChanges ?? [])
                .filter { $0 !== change && !$0.isDeleted && $0.newPrice == (price ?? customer.price) }
                .map(\.date).max()
        }
        try? context.save()
    }
}
