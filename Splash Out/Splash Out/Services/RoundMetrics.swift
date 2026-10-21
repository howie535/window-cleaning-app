import Foundation

/// Pure calculations from Docs/SPEC.md section 4. No UI, no storage.
enum RoundMetrics {
    struct PeriodTotals {
        var work: Decimal = 0
        var paid: Decimal = 0
        var cleans = 0
    }

    /// 4.1: work for a period is the sum of `charged` over cleaned visits in it, paid or not.
    static func totals(for customers: [Customer], in range: Range<Date>) -> PeriodTotals {
        var totals = PeriodTotals()
        for customer in customers {
            for visit in customer.allVisits where visit.kind == .cleaned && range.contains(visit.date) {
                totals.work += visit.charged
                totals.paid += visit.paid
                totals.cleans += 1
            }
        }
        return totals
    }

    /// 4.7: sum of price over active, leaving and not-started customers; every-other count at half.
    static func roundValue(_ customers: [Customer]) -> Decimal {
        customers
            .filter { [.active, .leaving, .notStarted].contains($0.status) }
            .reduce(0) { $0 + ($1.everyOther ? $1.price / 2 : $1.price) }
    }

    /// Customers on the round: active, leaving and not started (they'll all be cleaned).
    static func onRound(_ customers: [Customer]) -> [Customer] {
        customers.filter { [.active, .leaving, .notStarted].contains($0.status) }
    }

    /// One clean's list price: the price, or for someone who alternates between two prices, the middle of the two.
    /// Extras aren't included: they can't be counted on.
    static func perCleanPrice(_ customer: Customer) -> Decimal {
        guard let second = customer.secondPrice else { return customer.price }
        return (customer.price + second) / 2
    }

    /// Average price per house: every priced customer on the round's per-clean price, totalled, ÷ the number of them.
    static func averagePrice(_ customers: [Customer]) -> (average: Decimal, customers: Int) {
        let priced = onRound(customers).filter { $0.price > 0 }
        guard !priced.isEmpty else { return (0, 0) }
        return (priced.reduce(Decimal(0)) { $0 + perCleanPrice($1) } / Decimal(priced.count), priced.count)
    }

    /// 4.8: every cleaned visit not yet fully paid.
    static func moneyOwed(_ customers: [Customer]) -> (amount: Decimal, cleans: Int) {
        var amount: Decimal = 0
        var cleans = 0
        for customer in customers {
            for visit in customer.allVisits where visit.isUnpaid {
                amount += visit.charged - visit.paid
                cleans += 1
            }
        }
        return (amount, cleans)
    }

    /// Start years of every tax year that has at least one cleaned visit, oldest first.
    static func taxYearsWithWork(_ customers: [Customer]) -> [Int] {
        var years = Set<Int>()
        for customer in customers {
            for visit in customer.allVisits where visit.kind == .cleaned {
                years.insert(TaxYear.startYear(containing: visit.date))
            }
        }
        return years.sorted()
    }
}
