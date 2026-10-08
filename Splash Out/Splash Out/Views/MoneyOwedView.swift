import SwiftUI
import SwiftData

/// Every unpaid clean, by customer, oldest first (Docs/SPEC.md section 4.8).
struct MoneyOwedView: View {
    @Query private var customers: [Customer]

    @State private var payingCustomer: Customer?

    struct Row: Identifiable {
        var customer: Customer
        var amount: Decimal
        var cleans: Int
        var oldest: Date
        var id: UUID { customer.id }
    }

    private var rows: [Row] {
        customers.compactMap { customer in
            let unpaid = VisitLogger.unpaidVisits(for: customer)
            guard let oldest = unpaid.first else { return nil }
            return Row(
                customer: customer,
                amount: unpaid.reduce(0) { $0 + $1.charged - $1.paid },
                cleans: unpaid.count,
                oldest: oldest.date
            )
        }
        .sorted { $0.oldest < $1.oldest }
    }

    var body: some View {
        let rows = rows
        let total = rows.reduce(Decimal(0)) { $0 + $1.amount }
        let cleans = rows.reduce(0) { $0 + $1.cleans }
        let today = RoundCalendar.startOfDay()

        NavigationStack {
            List {
                Section {
                    LabeledContent("Total owed") {
                        Text(total, format: .currency(code: "GBP"))
                            .font(.title3.bold())
                            .foregroundStyle(total > 0 ? .red : .primary)
                    }
                    LabeledContent("Cleans", value: "\(cleans)")
                    LabeledContent("Customers", value: "\(rows.count)")
                }

                Section("Oldest first") {
                    if rows.isEmpty {
                        Text("Nobody owes anything.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(rows) { row in
                        Button { payingCustomer = row.customer } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.customer.name).font(.headline)
                                    Text(detail(for: row, today: today))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(row.amount, format: .currency(code: "GBP"))
                                    .font(.headline)
                                    .foregroundStyle(.red)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Money Owed")
            .sheet(item: $payingCustomer) { customer in
                RecordPaymentView(customer: customer)
            }
        }
    }

    private func detail(for row: Row, today: Date) -> String {
        let weeks = (RoundCalendar.london.dateComponents([.day], from: row.oldest, to: today).day ?? 0) / 7
        var parts = ["\(row.cleans) clean\(row.cleans == 1 ? "" : "s")", "since \(RoundCalendar.shortWithYear(row.oldest))"]
        parts.append(weeks == 1 ? "1 week" : "\(weeks) weeks")
        if let method = row.customer.payMethod { parts.append(method.label) }
        return parts.joined(separator: " · ")
    }
}
