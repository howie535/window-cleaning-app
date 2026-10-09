import SwiftUI
import SwiftData

/// Months with work, paid and not yet paid, then totals by round, for any tax year (Docs/SPEC.md sections 4.2 and 5).
struct TaxYearView: View {
    @Query private var customers: [Customer]
    @Query private var crews: [Crew]
    @Query private var workDays: [WorkDay]
    @Query private var settings: [AppSettings]

    @State private var chosenYear: Int?
    @State private var exportURL: URL?

    private func pounds(_ value: Decimal) -> String {
        value.formatted(.currency(code: "GBP").precision(.fractionLength(0)))
    }

    var body: some View {
        let today = RoundCalendar.startOfDay()
        let stats = RoundStats(customers: customers, settings: settings.first, crews: crews, workDays: workDays, today: today)
        let years = Array(Set(RoundMetrics.taxYearsWithWork(customers) + [stats.currentTaxYear])).sorted()
        let year = chosenYear ?? stats.currentTaxYear
        let months = stats.months(taxYear: year)
        let rounds = stats.rounds(taxYear: year)
        let total = months.reduce(into: WeekMetrics.MonthRow(label: "Tax year total", from: months[0].from, to: months[months.count - 1].to)) { sum, row in
            sum.work += row.work; sum.paid += row.paid; sum.notYetPaid += row.notYetPaid
            sum.cleans += row.cleans; sum.extras += row.extras
        }
        let weeksSoFar = max(1, Decimal((RoundCalendar.london.dateComponents([.day], from: total.from, to: min(today, total.to)).day ?? 0) + 1) / 7)

        List {
            Section {
                Picker("Tax year", selection: Binding(get: { year }, set: { chosenYear = $0 })) {
                    ForEach(years, id: \.self) { Text(TaxYear.label(startYear: $0)).tag($0) }
                }
                LabeledContent("Runs", value: "\(RoundCalendar.shortWithYear(total.from)) to \(RoundCalendar.shortWithYear(total.to))")
            }

            Section("Totals") {
                LabeledContent("Work", value: pounds(total.work))
                LabeledContent("Paid", value: pounds(total.paid))
                LabeledContent("Not yet paid", value: pounds(total.notYetPaid))
                LabeledContent("Cleans", value: "\(total.cleans)")
                LabeledContent("Paid above price (extras)", value: pounds(total.extras))
                LabeledContent("Average a week", value: pounds(total.work / weeksSoFar))
            }

            Section("By month") {
                ForEach(months, id: \.label) { month in
                    if month.work > 0 || month.cleans > 0 {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(month.label).font(.headline)
                                Spacer()
                                Text(pounds(month.work)).font(.headline)
                            }
                            Text("Paid \(pounds(month.paid)) · Not yet paid \(pounds(month.notYetPaid)) · \(month.cleans) cleans"
                                 + (month.extras > 0 ? " · extras \(pounds(month.extras))" : "")
                                 + (month.averagePerWeek.map { " · \(pounds($0)) a week" } ?? ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("By round") {
                ForEach(rounds, id: \.round) { round in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(round.round).font(.headline)
                            Spacer()
                            Text(pounds(round.work)).font(.headline)
                        }
                        Text("Paid \(pounds(round.paid)) · Not yet paid \(pounds(round.notYetPaid)) · \(round.cleans) cleans")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Share CSV for Self Assessment", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button("Prepare CSV for Self Assessment") {
                        exportURL = try? writeCSV(year: year, months: months, rounds: rounds, total: total)
                    }
                }
            } footer: {
                Text("Tips are never counted as income. The file holds totals only, no customer details.")
            }
        }
        .navigationTitle("Tax Year")
        .onChange(of: chosenYear) { exportURL = nil }
    }

    private func writeCSV(year: Int, months: [WeekMetrics.MonthRow], rounds: [RoundStats.RoundRow], total: WeekMetrics.MonthRow) throws -> URL {
        func n(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
        var lines = ["Tax year \(TaxYear.label(startYear: year))", "", "Month,From,To,Work,Paid,Not yet paid,Cleans,Extras"]
        for month in months {
            lines.append("\(month.label),\(RoundCalendar.dayString(month.from)),\(RoundCalendar.dayString(month.to)),\(n(month.work)),\(n(month.paid)),\(n(month.notYetPaid)),\(month.cleans),\(n(month.extras))")
        }
        lines.append("Total,,,\(n(total.work)),\(n(total.paid)),\(n(total.notYetPaid)),\(total.cleans),\(n(total.extras))")
        lines += ["", "Round,Work,Paid,Not yet paid,Cleans"]
        for round in rounds {
            lines.append("\(round.round),\(n(round.work)),\(n(round.paid)),\(n(round.notYetPaid)),\(round.cleans)")
        }
        let url = URL.temporaryDirectory.appendingPathComponent("splash-out-tax-year-\(TaxYear.label(startYear: year)).csv")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
