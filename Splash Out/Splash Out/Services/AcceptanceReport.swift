import Foundation
import SwiftData

/// Aggregate figures only (no names or addresses), for checking an import against the
/// workbook and Docs/SPEC.md section 7.
@MainActor
enum AcceptanceReport {
    static func make(in context: ModelContext) throws -> String {
        let customers = try context.fetch(FetchDescriptor<Customer>())
        var statusCounts: [String: Int] = [:]
        for customer in customers { statusCounts[customer.statusRaw, default: 0] += 1 }

        let visits = customers.flatMap(\.allVisits)
        let owed = RoundMetrics.moneyOwed(customers)
        let skipped = visits.filter { $0.kind == .skipped }.count
        let notDue = visits.filter { $0.kind == .notDue }.count

        var lines = [
            "ACCEPTANCE REPORT",
            "Customers: \(customers.count)  " + statusCounts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "),
            "Visits: \(visits.filter { $0.kind == .cleaned }.count) cleans, \(skipped) skipped, \(notDue) not due",
            "Round value per cycle: \(format(RoundMetrics.roundValue(customers)))",
            "Money owed: \(format(owed.amount)) over \(owed.cleans) cleans",
        ]
        for year in RoundMetrics.taxYearsWithWork(customers) {
            let totals = RoundMetrics.totals(for: customers, in: TaxYear.range(startYear: year))
            lines.append("Tax year \(TaxYear.label(startYear: year)): work \(format(totals.work)), paid \(format(totals.paid)), \(totals.cleans) cleans")
        }
        lines.append("Diary entries: \(try context.fetchCount(FetchDescriptor<WorkDay>()))  Tips: \(try context.fetchCount(FetchDescriptor<Tip>()))")
        return lines.joined(separator: "\n")
    }

    private static func format(_ value: Decimal) -> String {
        "£" + (NumberFormatter.report.string(from: value as NSDecimalNumber) ?? "\(value)")
    }
}

private extension NumberFormatter {
    static let report: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "en_GB")
        return formatter
    }()
}
