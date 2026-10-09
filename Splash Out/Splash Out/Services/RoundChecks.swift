import Foundation
import SwiftData

/// Price rise preview, frequent skippers and checks (Docs/SPEC.md 4.9 to 4.11).
extension RoundStats {
    // MARK: Price rise

    struct RiseRow: Identifiable {
        var customer: Customer
        var newPrice: Decimal
        /// nil when the rise doesn't apply to them (their price started on or after the rise date).
        var effective: Date?
        var id: UUID { customer.id }
        var extraPerCycle: Decimal {
            guard effective != nil else { return 0 }
            return (newPrice - customer.price) * (customer.everyOther ? Decimal(string: "0.5")! : 1)
        }
    }

    /// The rise date in use: the one set in Settings, otherwise the next 6 April as a preview.
    var riseDateInUse: (date: Date, isPreview: Bool) {
        if let date = settings.priceRiseDate { return (date, false) }
        return (PriceRise.previewDate(after: today, calendar: RoundCalendar.london), true)
    }

    /// Every active or leaving customer with a price, in round order.
    func risePreview() -> [RiseRow] {
        let riseDate = riseDateInUse.date
        let percent = Money.decimal(settings.priceRisePercent * 100) / 100
        return customers
            .filter { ($0.status == .active || $0.status == .leaving) && $0.price > 0 }
            .sorted { $0.sequence < $1.sequence }
            .map { customer in
                RiseRow(
                    customer: customer,
                    newPrice: PriceRise.newPrice(customer.price, percent: percent),
                    effective: PriceRise.effectiveDate(priceSince: customer.priceSince, riseDate: riseDate,
                                                      delayMonths: settings.priceRiseDelayMonths, calendar: RoundCalendar.london)
                )
            }
    }

    /// Active or leaving customers whose price hasn't changed for the "due after" period.
    func risesDue() -> [Customer] {
        customers.filter {
            ($0.status == .active || $0.status == .leaving) && $0.price > 0
                && PriceRise.isDue(priceSince: $0.priceSince, today: today,
                                   dueAfterMonths: settings.priceRiseDueAfterMonths, calendar: RoundCalendar.london)
        }
    }

    /// Applies rises that have taken effect: updates each price, records a PriceChange, and sets "price since".
    /// Past visits are left alone. Returns how many customers changed.
    @discardableResult
    static func applyRises(_ rows: [RiseRow], in context: ModelContext) -> Int {
        var changed = 0
        for row in rows {
            guard let effective = row.effective, row.newPrice != row.customer.price else { continue }
            context.insert(PriceChange(date: effective, oldPrice: row.customer.price, newPrice: row.newPrice, reason: .rise, customer: row.customer))
            row.customer.price = row.newPrice
            row.customer.priceSince = effective
            changed += 1
        }
        return changed
    }

    // MARK: Frequent skips (4.9)

    struct SkipRow: Identifiable {
        var customer: Customer
        var skips: Int
        var ofLast: Int
        var id: UUID { customer.id }
    }

    /// Active or leaving customers who skipped 2 or more times in the last 12 months, counting from their first clean.
    /// Every-other customers' off-cycle visits ("not due") don't count.
    func frequentSkippers() -> [SkipRow] {
        var rows: [SkipRow] = []
        for customer in customers where customer.status == .active || customer.status == .leaving {
            let visits = customer.allVisits.filter { $0.kind != .notDue }.sorted { $0.date < $1.date }
            guard let first = visits.firstIndex(where: { $0.kind == .cleaned }) else { continue }
            let yearAgo = RoundCalendar.london.date(byAdding: .month, value: -12, to: today) ?? today
            let recent = visits[first...].filter { $0.date >= yearAgo }
            let skips = recent.filter { $0.kind == .skipped }.count
            if skips >= 2 { rows.append(SkipRow(customer: customer, skips: skips, ofLast: recent.count)) }
        }
        return rows.sorted { ($0.skips, -$0.customer.sequence) > ($1.skips, -$1.customer.sequence) }
    }

    // MARK: Checks (4.11)

    struct UnderPriceRow: Identifiable {
        var customer: Customer
        var lastPaid: Decimal
        var id: UUID { customer.id }
    }

    /// The last cleaned visit was paid, but for less than the list price, and the customer isn't front only.
    func payingUnderPrice() -> [UnderPriceRow] {
        customers.compactMap { customer in
            guard customer.status == .active || customer.status == .leaving, !customer.frontOnly,
                  let last = customer.allVisits.filter({ $0.kind == .cleaned }).max(by: { $0.date < $1.date }),
                  last.paid > 0, last.paid < last.listPrice
            else { return nil }
            return UnderPriceRow(customer: customer, lastPaid: last.paid)
        }
        .sorted { $0.customer.sequence < $1.customer.sequence }
    }

    struct DataIssue: Identifiable {
        var customer: Customer
        var message: String
        var id: String { customer.id.uuidString + message }
    }

    /// Visits that look wrong: dated in the future, or two on the same day for one customer.
    /// (Impossible dates are left out when a file is imported.)
    func dataIssues() -> [DataIssue] {
        var issues: [DataIssue] = []
        for customer in customers {
            let visits = customer.allVisits
            let future = visits.filter { $0.date > today }.count
            if future > 0 {
                issues.append(DataIssue(customer: customer, message: "\(future) visit\(future == 1 ? "" : "s") dated in the future"))
            }
            var seen = Set<Date>()
            var duplicates = Set<Date>()
            for visit in visits where visit.kind != .notDue {
                if !seen.insert(visit.date).inserted { duplicates.insert(visit.date) }
            }
            for date in duplicates.sorted() {
                issues.append(DataIssue(customer: customer, message: "Two visits on \(RoundCalendar.shortWithYear(date))"))
            }
        }
        return issues.sorted { $0.customer.sequence < $1.customer.sequence }
    }
}
