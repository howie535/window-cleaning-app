import Foundation
import SwiftData

/// Aggregate figures only (no names or addresses), for checking an import against the
/// the expected figures in Docs/SPEC.md section 7.
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

    /// Machine-readable lines for checking the Weekly, Today and Tax Year figures.
    static func stage5(in context: ModelContext, today: Date) throws -> String {
        let customers = try context.fetch(FetchDescriptor<Customer>())
        let crews = try context.fetch(FetchDescriptor<Crew>())
        let workDays = try context.fetch(FetchDescriptor<WorkDay>())
        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first
        let stats = RoundStats(customers: customers, settings: settings, crews: crews, workDays: workDays, today: today)
        func n(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }

        var lines = ["STAGE5 today=\(RoundCalendar.dayString(today))"]
        for week in stats.weeks {
            lines.append("WEEK \(RoundCalendar.dayString(week.start)) work=\(n(week.work)) houses=\(week.houses) target=\(n(week.target)) worked=\(week.daysWorked)")
        }
        let ahead = stats.aheadBehind()
        lines.append("AHEAD done=\(n(ahead.done)) expected=\(n(ahead.expected)) diff=\(n(ahead.difference))")
        lines.append("THISWEEK work=\(n(stats.thisWeek.work)) target=\(n(stats.thisWeek.target)) houses=\(stats.thisWeek.houses)")
        lines.append("TODAY work=\(n(stats.work(from: today, through: today)))")
        lines.append("THISMONTH work=\(n(stats.work(from: stats.thisMonthStart, through: today))) houses=\(stats.houses(from: stats.thisMonthStart, through: today))")
        for month in stats.months(taxYear: stats.currentTaxYear) {
            lines.append("MONTH \(month.label) work=\(n(month.work)) paid=\(n(month.paid)) notpaid=\(n(month.notYetPaid)) cleans=\(month.cleans) extras=\(n(month.extras))")
        }
        for round in stats.rounds(taxYear: stats.currentTaxYear) {
            lines.append("ROUND \(round.round) work=\(n(round.work)) paid=\(n(round.paid)) notpaid=\(n(round.notYetPaid)) cleans=\(round.cleans)")
        }
        for crew in stats.crewAverages() {
            lines.append("CREW \(crew.crew) days=\(crew.days) avg=\(n(crew.averagePerDay)) houses=\(n(crew.housesPerDay)) perhouse=\(n(crew.perHouse))")
        }
        lines.append("CYCLE weeks=\(stats.cycleWeeks.map(n) ?? "-")")
        lines.append("NEWLOST new=\(stats.newCustomers(taxYear: stats.currentTaxYear)) lost=\(stats.lostCustomers(taxYear: stats.currentTaxYear))")
        lines.append("SKIPRATE \(stats.skipRate)")
        let rise = stats.riseDateInUse
        let preview = stats.risePreview()
        lines.append("PRICERISE date=\(RoundCalendar.dayString(rise.date)) preview=\(rise.isPreview) rows=\(preview.count) withRise=\(preview.filter { $0.effective != nil }.count) extra=\(n(preview.reduce(Decimal(0)) { $0 + $1.extraPerCycle })) due=\(stats.risesDue().count)")
        lines.append("FREQSKIP \(stats.frequentSkippers().count) \(stats.frequentSkippers().map { "\($0.skips)/\($0.ofLast)" }.joined(separator: ","))")
        lines.append("UNDERPRICE \(stats.payingUnderPrice().count)")
        lines.append("DATAISSUES \(stats.dataIssues().count)")
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
