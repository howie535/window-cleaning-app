import SwiftUI

/// How the Ideal figures on Stats are worked out, with the actual numbers.
struct IdealWorkingView: View {
    let ideal: Ideal

    private func n(_ value: Decimal) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
    private func money(_ value: Decimal) -> String { value.formatted(.currency(code: "GBP").precision(.fractionLength(2))) }
    private var keepText: String { ideal.keep.formatted(.percent.precision(.fractionLength(1))) }

    var body: some View {
        List {
            Section("What goes in") {
                LabeledContent("Weekly target", value: ideal.weeklyTarget.pounds)
                LabeledContent("Working days", value: "\(ideal.workingDays) a week")
                LabeledContent("Houses per workday", value: ideal.housesPerDay.map(n) ?? "–")
                LabeledContent("Customers on the round", value: n(ideal.customersPerRound))
                LabeledContent("Not skipped", value: keepText)
                LabeledContent("Round length", value: "\(ideal.weeks) weeks")
            }

            if let capacity = ideal.capacity, let supply = ideal.supply, let rate = ideal.housesPerDay {
                let used = min(capacity, supply)
                Section {
                    step("Crew can do", "\(n(rate)) × \(ideal.workingDays) days", "\(n(capacity)) a week")
                    step("Round supplies", "\(n(ideal.customersPerRound)) × \(keepText) ÷ \(ideal.weeks) weeks", "\(n(supply)) a week")
                    step("Houses a week", "the lower of the two", n(used))
                    if let price = ideal.perHouse {
                        step("Ideal per house", "\(ideal.weeklyTarget.pounds) ÷ \(n(used))", money(price)).bold()
                    }
                } header: {
                    Text("Average per house")
                } footer: {
                    Text(ideal.limitedByCustomers ? "Too few customers to keep the crew busy, so customers set the price." : "Your work rate sets the price.")
                }

                Section("Customers") {
                    step("Ideal customers", "\(n(capacity)) × \(ideal.weeks) ÷ \(keepText)", ideal.customers.map { "\($0)" } ?? "–").bold()
                }
            }

            if let value = ideal.roundValue {
                Section {
                    step("Ideal round value", "\(ideal.weeklyTarget.pounds) × \(ideal.weeks) ÷ \(keepText)", money(value)).bold()
                } header: {
                    Text("Round value")
                } footer: {
                    Text("Change the round length in Settings.")
                }
            }
        }
        .navigationTitle("Ideal figures")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ title: String, _ sum: String, _ result: String) -> some View {
        LabeledContent {
            Text(result).monospacedDigit()
        } label: {
            Text(title)
            Text(sum).monospacedDigit()
        }
    }
}
