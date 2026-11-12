import SwiftUI
import SwiftData

/// Things worth a look; nothing here changes any figures (Docs/SPEC.md 4.11). A part of To Check.
struct ChecksSections: View {
    let under: [RoundStats.UnderPriceRow]
    let issues: [RoundStats.DataIssue]

    var body: some View {
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
                                Text("Price \(row.customer.price.pounds)")
                                Text("Last paid \(row.lastPaid.pounds)")
                                    .font(.caption).foregroundStyle(Color.notPaidText)
                            }
                        }
                    }
                }
            } header: {
                Text("Paying Under Price (\(under.count))")
            } footer: {
                Text("Last clean paid under list price. Front-only left out.")
            }

            Section {
                if issues.isEmpty { Text("No problems found.").foregroundStyle(.secondary) }
                ForEach(issues) { issue in
                    NavigationLink {
                        CustomerDetailView(customer: issue.customer)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(issue.customer.name).font(.headline)
                            Text(issue.message).font(.caption).foregroundStyle(Color.notPaidText)
                        }
                    }
                }
            } header: {
                Text("Dates to Check (\(issues.count))")
            } footer: {
                Text("Future dates, or two visits on one day. Probably a typing slip.")
            }
    }
}
