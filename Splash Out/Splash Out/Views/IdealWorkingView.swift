import SwiftUI

/// How the Ideal figures on Stats are worked out: the current figures, then Ideal (every usual day worked) beside
/// Actual (days really worked, weather and holidays included), each line with its sum.
struct IdealWorkingView: View {
    let ideal: Ideal

    private func n(_ value: Decimal) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
    private func money(_ value: Decimal) -> String { value.formatted(.currency(code: "GBP").precision(.fractionLength(2))) }
    private func percent(_ value: Decimal) -> String {
        (NSDecimalNumber(decimal: value).doubleValue).formatted(.percent.precision(.fractionLength(1)))
    }

    var body: some View {
        List {
            if let rate = ideal.rate {
                Section {
                    figure("Weekly target", ideal.weeklyTarget.pounds)
                    figure("Houses a workday", n(rate.housesPerDay))
                    figure("Average price", money(ideal.averagePrice))
                    figure("Not skipped", percent(ideal.keep))
                    figure("Customers", "\(ideal.people)")
                    figure("Cleans a round", n(ideal.cleansPerRound), "every-other at half")
                    figure("Target round", "\(ideal.weeks) weeks")
                } header: {
                    Text("Current figures")
                } footer: {
                    Text(ideal.periodLabel.prefix(1).uppercased() + ideal.periodLabel.dropFirst() + ".")
                }
            }
            if let planned = ideal.planned {
                comparison(ideal: planned, actual: ideal.actual)
            }
            if let value = ideal.roundValue {
                Section {
                    figure("Round value needed", money(value), "weekly target × \(ideal.weeks) weeks ÷ not skipped")
                }
            }
            if ideal.rate == nil || ideal.planned == nil {
                Section { Text("Not enough worked days yet.").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Targets")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func figure(_ title: String, _ value: String, _ how: String? = nil) -> some View {
        LabeledContent {
            Text(value).monospacedDigit()
        } label: {
            Text(title)
            if let how { Text(how) }
        }
    }

    /// Ideal and Actual in two columns, one line per figure with its sum underneath.
    private func comparison(ideal i: Ideal.Scenario, actual a: Ideal.Scenario?) -> some View {
        Section {
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    Text("Ideal").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Actual").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                line("Days a week", "usual week · days worked", n(i.daysPerWeek), a.map { n($0.daysPerWeek) })
                line("Houses a week", "houses a day × days", n(i.capacity), a.map { n($0.capacity) })
                line("Income a week", "houses × average price", i.incomeNow.pounds, a.map { $0.incomeNow.pounds })
                line("Price needed", "weekly target ÷ houses", money(i.perHouse), a.map { money($0.perHouse) }, bold: true)
                line("Round takes", "cleans × not skipped ÷ houses", "\(n(i.roundWeeksNow)) wk", a.map { "\(n($0.roundWeeksNow)) wk" })
                line("Customers needed", "to fill \(ideal.weeks) weeks", "\(i.peopleNeeded)", a.map { "\($0.peopleNeeded)" }, bold: true)
            }
            .monospacedDigit()
        } header: {
            Text("Ideal vs actual")
        } footer: {
            let limited = i.limitedByCustomers || (a?.limitedByCustomers ?? false)
            Text("Ideal: every usual day worked (\(ideal.usualDays) a week). Actual: days really worked."
                 + (limited ? " Too few customers to fill the days, so the price uses the houses the round has." : ""))
        }
    }

    @ViewBuilder
    private func line(_ title: String, _ how: String, _ idealValue: String, _ actualValue: String?, bold: Bool = false) -> some View {
        Divider()
        GridRow {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(bold ? .semibold : .regular)
                Text(how).font(.caption2).foregroundStyle(.secondary)
            }
            .gridColumnAlignment(.leading)
            Text(idealValue).fontWeight(bold ? .semibold : .regular)
            Text(actualValue ?? "–").fontWeight(bold ? .semibold : .regular)
        }
    }
}
