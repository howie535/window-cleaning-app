import SwiftUI
import SwiftData

/// Customers who skipped 2 or more times in the last 12 months (a part of To Check).
struct FrequentSkipsSections: View {
    let rows: [RoundStats.SkipRow]

    var body: some View {
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
                            Text("\(row.skips) of \(row.ofLast) visits").font(.headline).foregroundStyle(Color.notPaidText)
                        }
                    }
                }
            } header: {
                Text("Skipping Often (\(rows.count))")
            } footer: {
                InfoFooter(text: "Skips in the last 12 months.", points: [
                    "Counted from each customer's first clean.",
                    "Active and leaving customers only.",
                    "Every-other customers' off rounds aren't skips."])
            }
    }
}
