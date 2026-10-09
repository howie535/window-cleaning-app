import SwiftUI
import SwiftData

/// Things worth a look. Nothing here changes any figures (Docs/SPEC.md 4.11).
struct ChecksView: View {
    @Query private var customers: [Customer]
    @Query private var crews: [Crew]
    @Query private var workDays: [WorkDay]
    @Query private var settings: [AppSettings]

    var body: some View {
        let stats = RoundStats(customers: customers, settings: settings.first, crews: crews, workDays: workDays)
        let under = stats.payingUnderPrice()
        let issues = stats.dataIssues()

        List {
            Section {
                if under.isEmpty { Text("Nobody is paying under their price.").foregroundStyle(.secondary) }
                ForEach(under) { row in
                    NavigationLink {
                        CustomerDetailView(customer: row.customer)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.customer.name).font(.headline)
                                Text(row.customer.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("Price \(row.customer.price.formatted(.currency(code: "GBP").precision(.fractionLength(0))))")
                                Text("Last paid \(row.lastPaid.formatted(.currency(code: "GBP").precision(.fractionLength(0))))")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }
            } header: {
                Text("Paying under price (\(under.count))")
            } footer: {
                Text("The last clean was paid for less than the list price. Front-only customers are left out.")
            }

            Section {
                if issues.isEmpty { Text("No problems found.").foregroundStyle(.secondary) }
                ForEach(issues) { issue in
                    NavigationLink {
                        CustomerDetailView(customer: issue.customer)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(issue.customer.name).font(.headline)
                            Text(issue.message).font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            } header: {
                Text("Visits to check (\(issues.count))")
            } footer: {
                Text("Visits dated in the future, or two on the same day. Dates that weren't real dates in the spreadsheet were left out at import and are listed in its import report.")
            }
        }
        .navigationTitle("Checks")
    }
}
