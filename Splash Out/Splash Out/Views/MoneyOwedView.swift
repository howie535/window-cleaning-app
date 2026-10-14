import SwiftUI
import SwiftData

/// Every unpaid clean, by customer, oldest first (Docs/SPEC.md section 4.8).
struct MoneyOwedView: View {
    @Environment(RoundClock.self) private var clock
    /// nil outside the tab bar (always shown).
    @Environment(TabState.self) private var tabs: TabState?
    @Query private var customers: [Customer]
    @Query private var visits: [Visit]
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var payingCustomer: Customer?
    /// Regular width (iPad): the chosen customer is shown in the right-hand panel, with Record payment on it.
    @State private var selectedID: UUID?
    @State private var search = ""

    struct Row: Identifiable {
        var customer: Customer
        var amount: Decimal
        var cleans: Int
        var oldest: Date
        var id: UUID { customer.id }
    }

    private func matches(_ customer: Customer) -> Bool {
        let term = search.trimmingCharacters(in: .whitespaces)
        return term.isEmpty || customer.name.localizedCaseInsensitiveContains(term) || customer.address.localizedCaseInsensitiveContains(term)
    }

    /// Customers who've paid more than they've been charged (taken off their next clean).
    private var inCredit: [(customer: Customer, credit: Decimal)] {
        customers.compactMap { customer in
            let balance = customer.outstandingBalance
            return balance > 0 ? (customer, balance) : nil
        }
        .sorted { $0.customer.name < $1.customer.name }
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
        // Hidden tabs stay alive; skip the sums until this tab is showing again.
        if tabs == nil || tabs?.selection == .owed {
            content
        } else {
            Color(.systemGroupedBackground)
        }
    }

    @ViewBuilder
    private var content: some View {
        let perfStart = PerfProbe.now()
        let _ = VisitLookup.begin(visits)
        let rows = rows
        let credits = inCredit
        let _ = VisitLookup.end()
        let total = rows.reduce(Decimal(0)) { $0 + $1.amount }
        let cleans = rows.reduce(0) { $0 + $1.cleans }
        let today = clock.today
        let _ = PerfProbe.end("Owed", perfStart)

        if sizeClass == .regular {
            NavigationSplitView {
                owedList(rows: rows, credits: credits, total: total, cleans: cleans, today: today)
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
                owedList(rows: rows, credits: credits, total: total, cleans: cleans, today: today)
                    .navigationTitle("Money Owed")
                    .sheet(item: $payingCustomer) { customer in
                        RecordPaymentView(customer: customer)
                    }
            }
        }
    }

    private func owedList(rows: [Row], credits allCredits: [(customer: Customer, credit: Decimal)], total: Decimal, cleans: Int, today: Date) -> some View {
        let shown = rows.filter { matches($0.customer) }
        let credits = allCredits.filter { matches($0.customer) }
        return List(selection: sizeClass == .regular ? $selectedID : .constant(nil)) {
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
                if shown.isEmpty {
                    Text(search.isEmpty ? "Nobody owes anything." : "Nobody owing matches \"\(search)\".")
                        .foregroundStyle(.secondary)
                }
                ForEach(shown) { row in
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

            if !credits.isEmpty {
                Section {
                    ForEach(credits, id: \.customer.id) { item in
                        let label = HStack {
                            Text(item.customer.name).font(.headline)
                            Spacer()
                            Text(item.credit, format: .currency(code: "GBP"))
                                .font(.headline)
                                .foregroundStyle(.blue)
                        }
                        .contentShape(Rectangle())
                        if sizeClass == .regular {
                            label.tag(item.customer.id)
                        } else {
                            NavigationLink { CustomerDetailView(customer: item.customer) } label: { label }
                        }
                    }
                } header: {
                    Text("In credit")
                } footer: {
                    Text("Paid more than they were charged. It's taken off their next clean.")
                }
            }
        }
        .searchable(text: $search, prompt: "Name or address")
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
