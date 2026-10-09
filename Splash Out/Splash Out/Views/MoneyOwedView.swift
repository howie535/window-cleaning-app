import SwiftUI
import SwiftData

/// Every unpaid clean, by customer, oldest first (Docs/SPEC.md section 4.8).
struct MoneyOwedView: View {
    @Query private var customers: [Customer]
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var payingCustomer: Customer?
    /// Regular width (iPad): the chosen customer is shown in the right-hand panel, with Record payment on it.
    @State private var selectedID: UUID?

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

        if sizeClass == .regular {
            NavigationSplitView {
                owedList(rows: rows, total: total, cleans: cleans, today: today)
                    .roomyRows()
                    .navigationTitle("Money Owed")
            } detail: {
                NavigationStack {
                    if let customer = customers.first(where: { $0.id == selectedID }) {
                        CustomerDetailView(customer: customer).id(customer.id)
                    } else {
                        ContentUnavailableView("Choose a customer", systemImage: "sterlingsign.circle",
                                               description: Text("Pick someone to see what they owe and record a payment."))
                    }
                }
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            NavigationStack {
                owedList(rows: rows, total: total, cleans: cleans, today: today)
                    .navigationTitle("Money Owed")
                    .sheet(item: $payingCustomer) { customer in
                        RecordPaymentView(customer: customer)
                    }
            }
        }
    }

    private func owedList(rows: [Row], total: Decimal, cleans: Int, today: Date) -> some View {
        List(selection: $selectedID) {
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
                    if sizeClass == .regular {
                        rowContent(row, today: today).tag(row.customer.id)
                    } else {
                        Button { payingCustomer = row.customer } label: {
                            rowContent(row, today: today)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func rowContent(_ row: Row, today: Date) -> some View {
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

    private func detail(for row: Row, today: Date) -> String {
        let weeks = (RoundCalendar.london.dateComponents([.day], from: row.oldest, to: today).day ?? 0) / 7
        var parts = ["\(row.cleans) clean\(row.cleans == 1 ? "" : "s")", "since \(RoundCalendar.shortWithYear(row.oldest))"]
        parts.append(weeks == 1 ? "1 week" : "\(weeks) weeks")
        if let method = row.customer.payMethod { parts.append(method.label) }
        return parts.joined(separator: " · ")
    }
}
