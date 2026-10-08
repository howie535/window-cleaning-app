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
