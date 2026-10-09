import SwiftUI
import SwiftData

/// Customers who skipped 2 or more times in the last 12 months.
struct FrequentSkipsView: View {
    @Query private var customers: [Customer]
    @Query private var crews: [Crew]
    @Query private var workDays: [WorkDay]
    @Query private var settings: [AppSettings]

    var body: some View {
        let stats = RoundStats(customers: customers, settings: settings.first, crews: crews, workDays: workDays)
        let rows = stats.frequentSkippers()

        List {
            Section {
                if rows.isEmpty { Text("Nobody has skipped twice in the last year.").foregroundStyle(.secondary) }
                ForEach(rows) { row in
                    NavigationLink {
                        CustomerDetailView(customer: row.customer)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.customer.name).font(.headline)
                                Text([row.customer.area, row.customer.address].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                if let last = row.customer.lastCleanDate {
                                    Text("Last clean \(RoundCalendar.short(last))\(row.customer.status == .leaving ? " · leaving" : "")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(row.skips) of \(row.ofLast) visits").font(.headline).foregroundStyle(.orange)
                        }
                    }
                }
            } footer: {
                Text("Skips in the last 12 months, counted from each customer's first clean. Active and leaving customers only. Every-other customers' off-cycle visits don't count as skips.")
            }
        }
        .navigationTitle("Frequent Skips")
    }
}
