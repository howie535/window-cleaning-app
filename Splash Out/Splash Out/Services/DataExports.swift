import Foundation
import SwiftData

/// Files for sharing: the customer list as a CSV, the tax-year income list, and a report for analysis
/// (for example to give to Claude). Everything here is built from the stored data and written to a temporary file.
@MainActor
enum DataExports {
    // MARK: Helpers

    private static func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func row(_ fields: [String]) -> String { fields.map(csvField).joined(separator: ",") }

    private static func n(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }

    private static func day(_ date: Date?) -> String { date.map(RoundCalendar.dayString) ?? "" }

    private static func write(_ text: String, named name: String) throws -> URL {
        let url = URL.temporaryDirectory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func customers(_ context: ModelContext) throws -> [Customer] {
        try context.fetch(FetchDescriptor<Customer>(sortBy: [SortDescriptor(\.sequence)]))
    }

    /// "C001": an ID that says nothing about who the customer is.
    private static func anonymousID(_ customer: Customer) -> String {
        "C" + String(format: "%03d", customer.sequence)
    }

    // MARK: Customer list

    /// Every customer with all their details, one row each, in round order. Opens in Numbers or Excel,
    /// and the same columns can be brought back in with Customers > Import.
    static func customersCSV(context: ModelContext) throws -> URL {
        var lines = [row(["Name", "Address", "Phone", "Price", "Round", "Area", "Status", "Every other", "Front only",
                          "Contact", "Pay method", "Price since", "Notes"])]
        for customer in try customers(context) {
            lines.append(row([
                customer.name, customer.address, customer.phone, n(customer.price), customer.round, customer.area,
                customer.status.rawValue, customer.everyOther ? "yes" : "no", customer.frontOnly ? "yes" : "no",
                customer.contact.rawValue, customer.payMethod?.rawValue ?? "", day(customer.priceSince),
                customer.notes.joined(separator: " | "),
            ]))
        }
        return try write(lines.joined(separator: "\n"), named: "splash-out-customers-\(RoundCalendar.fileStamp()).csv")
    }

    // MARK: Tax year

    /// One line per clean in the tax year: what was charged, what was paid and when.
    /// Customer names are left out unless asked for.
    static func incomeListCSV(taxYear: Int, includeNames: Bool, context: ModelContext) throws -> URL {
        let range = TaxYear.range(startYear: taxYear)
        var header = ["Date", "Customer ID"]
        if includeNames { header += ["Name", "Address"] }
        header += ["Round", "Charged", "Paid", "Paid date", "Not yet paid"]
        var lines = [row(header)]
        var work: Decimal = 0, paid: Decimal = 0
        let visits: [(Date, Customer, Visit)] = try customers(context).flatMap { customer in
            customer.allVisits.filter { $0.kind == .cleaned && range.contains($0.date) }.map { ($0.date, customer, $0) }
        }
        for (_, customer, visit) in visits.sorted(by: { ($0.0, $0.1.sequence) < ($1.0, $1.1.sequence) }) {
            var fields = [day(visit.date), anonymousID(customer)]
            if includeNames { fields += [customer.name, customer.address] }
            fields += [customer.round, n(visit.charged), n(visit.paid), day(visit.paidDate), n(max(0, visit.charged - visit.paid))]
            lines.append(row(fields))
            work += visit.charged
            paid += visit.paid
        }
        lines.append("")
        lines.append(row(["Total charged", n(work), "Total paid", n(paid), "Not yet paid", n(work - paid), "Cleans", "\(visits.count)"]))
        lines.append("Tips are never counted as income.")
        return try write(lines.joined(separator: "\n"), named: "splash-out-income-\(TaxYear.label(startYear: taxYear)).csv")
    }

    // MARK: Analysis report

    /// One Markdown file with everything needed to analyse the round: a short description of the business and the
    /// columns, the main figures, then the customers and every visit as tables. Customers are "C001"-style IDs;
    /// names and addresses and customer notes (gate codes and the like) are only included when asked for.
    static func analysisReport(includeNames: Bool, includeNotes: Bool = true, context: ModelContext) throws -> URL {
        let all = try customers(context)
        let settings = try context.fetch(FetchDescriptor<AppSettings>()).first
        let crews = try context.fetch(FetchDescriptor<Crew>(sortBy: [SortDescriptor(\.name)]))
        let workDays = try context.fetch(FetchDescriptor<WorkDay>(sortBy: [SortDescriptor(\.date)]))
        let stats = RoundStats(customers: all, settings: settings, crews: crews, workDays: workDays)
        let year = stats.currentTaxYear
        let today = RoundCalendar.startOfDay()

        var out: [String] = []
        out += [
            "# Window cleaning round: data for analysis",
            "",
            "Exported \(RoundCalendar.dayString(today)) from the Splash Out app. All dates are UK dates, all money is in pounds.",
            includeNames ? "Customer names and addresses are included in this file." : "Customers are anonymous IDs (C001 and so on). There are no names, addresses or phone numbers in this file.",
            includeNotes ? "Customer notes are included (access and other notes the crew keep on each customer)." : "Customer notes are not included.",
            "",
            "## About the business",
            "",
            "A small window cleaning round run by a crew of one or two people. Customers are cleaned roughly every 5 weeks, in a fixed round order, and the weather makes the schedule flexible.",
            "A customer's `price` is what they normally pay per clean. 'Every other' customers are only cleaned every other round (so count as half). 'Front only' customers have the front of the house done only.",
            "Weeks run Monday to Sunday, and the tax year runs 6 April to 5 April.",
            "",
            "## Columns",
            "",
            "- **kind**: `cleaned`, `skipped` (customer not cleaned this round, e.g. away or no access) or `not_due` (an every-other customer's off round).",
            "- **list_price**: the price at the time. **charged**: what was actually charged (extras make it higher). **paid**: what has been paid so far (0 if unpaid). **paid_date**: when it was paid.",
            "- **Work** means the sum of `charged` over cleaned visits, whether or not it has been paid yet.",
            "",
            "## Tax year \(TaxYear.label(startYear: year)) so far",
            "",
        ]
        let totals = RoundMetrics.totals(for: all, in: TaxYear.range(startYear: year))
        let ahead = stats.aheadBehind()
        let owed = RoundMetrics.moneyOwed(all)
        out += [
            "- Work: £\(n(totals.work)), paid: £\(n(totals.paid)), cleans: \(totals.cleans)",
            "- Ahead/behind weekly targets: £\(n(ahead.difference)) (£\(n(ahead.done)) done against £\(n(ahead.expected)) expected)",
            "- Money owed now: £\(n(owed.amount)) over \(owed.cleans) cleans",
            "- Round value per cycle: £\(n(RoundMetrics.roundValue(all))) (every-other customers at half)",
            "- Skip rate (all visits ever, cancelled customers left out): \((stats.skipRate * 100).formatted(.number.precision(.fractionLength(1))))%",
            "- New customers this tax year: \(stats.newCustomers(taxYear: year)), cancelled: \(stats.lostCustomers(taxYear: year))",
            "",
            "### By month",
            "",
            "| Month | Work | Paid | Not yet paid | Cleans | Extras |",
            "|---|---|---|---|---|---|",
        ]
        for month in stats.months(taxYear: year) {
            out.append("| \(month.label) | \(n(month.work)) | \(n(month.paid)) | \(n(month.notYetPaid)) | \(month.cleans) | \(n(month.extras)) |")
        }
        out += ["", "### By round", "", "| Round | Work | Paid | Not yet paid | Cleans |", "|---|---|---|---|---|"]
        for round in stats.rounds(taxYear: year) {
            out.append("| \(round.round) | \(n(round.work)) | \(n(round.paid)) | \(n(round.notYetPaid)) | \(round.cleans) |")
        }
        out += ["", "## Weeks", "", "| Week starting | Work | Paid | Houses | Target | Days worked |", "|---|---|---|---|---|---|"]
        for week in stats.weeks {
            out.append("| \(day(week.start)) | \(n(week.work)) | \(n(week.paid)) | \(week.houses) | \(n(week.target)) | \(week.daysWorked) |")
        }
        let averages = stats.crewAverages()
        if !averages.isEmpty {
            out += ["", "## Crew averages (days with a diary entry)", "", "| Crew | Days | Average per day | Houses per day | Per house |", "|---|---|---|---|---|"]
            for average in averages {
                out.append("| \(average.crew) | \(average.days) | \(n(average.averagePerDay)) | \(n(average.housesPerDay)) | \(n(average.perHouse)) |")
            }
        }
        if !workDays.isEmpty {
            out += ["", "## Diary (days that differ from the usual week)", "", "| Date | Day off | Crew | Note |", "|---|---|---|---|"]
            for entry in workDays {
                out.append("| \(day(entry.date)) | \(entry.dayOff ? "yes" : "") | \(entry.crewMembers.joined(separator: " + ")) | \(includeNotes ? (entry.note ?? "") : "") |")
            }
        }

        out += ["", "## Customers", ""]
        var header = ["id"]
        if includeNames { header += ["name", "address"] }
        header += ["round", "area", "status", "price", "price_since", "every_other", "front_only", "contact", "pay_method"]
        header += [includeNotes ? "notes" : "has_notes"]
        header += ["cleans", "skips", "last_clean", "owed"]
        out.append("| " + header.joined(separator: " | ") + " |")
        out.append("|" + String(repeating: "---|", count: header.count))
        for customer in all {
            let visits = customer.allVisits
            var fields = [anonymousID(customer)]
            if includeNames { fields += [customer.name, customer.address] }
            fields += [
                customer.round, customer.area, customer.status.rawValue, n(customer.price), day(customer.priceSince),
                customer.everyOther ? "yes" : "no", customer.frontOnly ? "yes" : "no", customer.contact.rawValue,
                customer.payMethod?.rawValue ?? "",
                includeNotes ? customer.notes.joined(separator: " / ") : (customer.notes.isEmpty ? "no" : "yes"),
                "\(visits.filter { $0.kind == .cleaned }.count)", "\(visits.filter { $0.kind == .skipped }.count)",
                day(customer.lastCleanDate), n(RoundMetrics.moneyOwed([customer]).amount),
            ]
            out.append("| " + fields.map { $0.replacingOccurrences(of: "|", with: "/") }.joined(separator: " | ") + " |")
        }

        out += ["", "## Every visit", "", "| customer | date | kind | list_price | charged | paid | paid_date |", "|---|---|---|---|---|---|---|"]
        let visits: [(Customer, Visit)] = all.flatMap { customer in customer.allVisits.map { (customer, $0) } }
        for (customer, visit) in visits.sorted(by: { ($0.1.date, $0.0.sequence) < ($1.1.date, $1.0.sequence) }) {
            out.append("| \(anonymousID(customer)) | \(day(visit.date)) | \(visit.kind.rawValue) | \(n(visit.listPrice)) | \(n(visit.charged)) | \(n(visit.paid)) | \(day(visit.paidDate)) |")
        }

        return try write(out.joined(separator: "\n"), named: "splash-out-analysis-\(RoundCalendar.fileStamp()).md")
    }
}
