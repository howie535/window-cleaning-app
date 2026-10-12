import SwiftUI

/// How the Ideal figures on Stats are worked out, with the actual numbers: as planned, and as actually worked.
struct IdealWorkingView: View {
    let ideal: Ideal

    private func n(_ value: Decimal) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
    private func money(_ value: Decimal) -> String { value.formatted(.currency(code: "GBP").precision(.fractionLength(2))) }
    private func percent(_ value: Decimal) -> String {
        (NSDecimalNumber(decimal: value).doubleValue).formatted(.percent.precision(.fractionLength(1)))
    }
    private var keepText: String { percent(ideal.keep) }

    var body: some View {
        List {
            if let rate = ideal.rate {
                Section {
                    row("Weekly target", ideal.weeklyTarget.pounds)
                    row("Houses per workday", n(rate.housesPerDay))
                    row("Average per house", money(rate.perHouse), "total £ ÷ houses")
                    row("Not skipped", keepText)
                    row("Customers", "\(ideal.people)", "\(n(ideal.cleansPerRound)) cleans a round, every-other at half")
                    row("Round length", "\(ideal.weeks) weeks", "Settings")
                } header: {
                    Text("Your figures, \(ideal.periodLabel)")
                }
            }
            if let planned = ideal.planned {
                scenario(planned, title: "Planned: \(ideal.usualDays) days a week", note: "These are the figures on the cards.")
            }
            if let actual = ideal.actual, let rate = ideal.rate {
                scenario(actual, title: "As worked: \(n(actual.daysPerWeek)) days a week",
                         note: "\(rate.workedDays) days worked in \(n(rate.weeks)) weeks, weather and holidays included.")
            }
            if let value = ideal.roundValue {
                Section("Round value") {
                    step("Ideal round value", "\(ideal.weeklyTarget.pounds) × \(ideal.weeks) ÷ \(keepText)", money(value))
                }
            }
        }
        .navigationTitle("Ideal figures")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func scenario(_ s: Ideal.Scenario, title: String, note: String) -> some View {
        let rate = ideal.rate
        Section {
            step("Houses a week", "\(n(rate?.housesPerDay ?? 0)) × \(n(s.daysPerWeek)) days", n(s.capacity))
            step("Income now", "\(n(s.housesPerWeek)) × \(money(rate?.perHouse ?? 0))", s.incomeNow.pounds)
            step("Ideal per house", "\(ideal.weeklyTarget.pounds) ÷ \(n(s.housesPerWeek))", money(s.perHouse)).bold()
            step("Round takes now", "\(n(ideal.cleansPerRound)) × \(keepText) ÷ \(n(s.capacity))", "\(n(s.roundWeeksNow)) weeks")
            step("Ideal cleans a round", "\(n(s.capacity)) × \(ideal.weeks) ÷ \(keepText)", n(s.cleansNeeded))
            step("Ideal customers", "same mix of every-other", "\(s.peopleNeeded)").bold()
        } header: {
            Text(title)
        } footer: {
            Text(note + (s.limitedByCustomers
                ? " Too few customers to keep the crew busy, so the price uses the \(n(s.supply)) houses a week the round supplies."
                : ""))
        }
    }

    private func row(_ title: String, _ value: String, _ note: String? = nil) -> some View {
        LabeledContent {
            Text(value).monospacedDigit()
        } label: {
            Text(title)
            if let note { Text(note) }
        }
    }

    private func step(_ title: String, _ sum: String, _ result: String) -> some View {
        row(title, result, sum)
    }
}
