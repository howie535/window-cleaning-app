import SwiftUI
import SwiftData

/// Customers due a price rise, with the new price at the chosen percentage (to the nearest pound). Tap Done once the
/// rise has been put in place: the price changes and the rise is logged with today's date. With no rise logged, the
/// time is counted from the customer's first clean.
struct PriceRiseView: View {
    @Environment(RoundClock.self) private var clock
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Customer.sequence) private var customers: [Customer]
    @Query private var visits: [Visit]
    @Query private var settings: [AppSettings]
    @State private var confirming: Customer?
    @State private var showingHelp = false
    @State private var opened: Customer?

    private var percent: Double { settings.first?.priceRisePercent ?? 0.10 }
    private var percentText: String { percent.formatted(.percent.precision(.fractionLength(0...1))) }

    var body: some View {
        let _ = VisitLookup.begin(visits)
        let months = settings.first?.priceRiseDueAfterMonths ?? 24
        let today = clock.today
        let onRound = customers.filter { ($0.status == .active || $0.status == .leaving) && $0.price > 0 }
        let rows = onRound.map { (customer: $0, from: PriceRise.countedFrom($0)) }
        let due = rows.filter { PriceRise.isDue($0.customer, today: today, dueAfterMonths: months) }
            .sorted { ($0.from ?? .distantPast) < ($1.from ?? .distantPast) }
        let notYet = rows.filter { r in r.from != nil && !due.contains { $0.customer === r.customer } }
            .sorted { $0.from! < $1.from! }
        let proposals = Dictionary(uniqueKeysWithValues: due.map { ($0.customer.id, PriceRise.proposal(for: $0.customer, percent: percent)) })
        let adds = proposals.values.reduce(Decimal(0)) { $0 + $1.addsPerRound }
        let _ = VisitLookup.end()

        List {
            Section {
                LabeledContent("Rise", value: "\(percentText), to the nearest £")
                LabeledContent("Due after", value: "\(months) months")
                if !due.isEmpty {
                    LabeledContent("Adds a round", value: adds.pounds)
                }
            } footer: {
                Button("How this works") { showingHelp = true }.font(.footnote)
            }
            if !due.isEmpty {
                Section("Due (\(due.count))") {
                    ForEach(due, id: \.customer.id) { row in
                        dueRow(row.customer, from: row.from, proposal: proposals[row.customer.id]!)
                    }
                }
            } else {
                Section { Text("No rises due.").foregroundStyle(.secondary) }
            }
            if !notYet.isEmpty {
                Section("Not due yet (\(notYet.count))") {
                    ForEach(notYet, id: \.customer.id) { row in
                        link(row.customer) {
                            Text("Due \(PriceRise.dueDate(row.customer, dueAfterMonths: months).map(RoundCalendar.shortWithYear) ?? "–")")
                                .font(.caption).foregroundStyle(.secondary)
                        } trailing: {
                            Text(row.customer.price.pounds)
                        }
                    }
                }
            }
        }
        .navigationTitle("Price Rise")
        .navigationDestination(item: $opened) { CustomerDetailView(customer: $0) }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible) {
            Button("Rise done") {
                if let customer = confirming { PriceRise.confirm(customer, percent: percent, today: today, context: modelContext) }
                confirming = nil
            }
        } message: {
            Text("Changes their price and logs the rise as \(RoundCalendar.shortWithYear(today)).")
        }
        .alert("Price rises", isPresented: $showingHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A rise is due once a price hasn't gone up for the months set in Settings. With no rise logged, it's counted from their first clean. The new price is \(percentText) on top, to the nearest pound (50p and above goes up, below 50p goes down). Monthly payers get the rise on their monthly amount. Tap Done once you've told them and the new price has started. Percentage and months are in Settings.")
        }
    }

    private var confirmTitle: String {
        guard let customer = confirming else { return "" }
        let p = PriceRise.proposal(for: customer, percent: percent)
        if let m = p.monthly, let nm = p.newMonthly { return "\(customer.name): \(m.pounds) → \(nm.pounds) a month?" }
        return "\(customer.name): \(p.price.pounds) → \(p.newPrice.pounds)?"
    }

    private func dueRow(_ customer: Customer, from: Date?, proposal p: PriceRise.Proposal) -> some View {
        HStack {
            link(customer) {
                Text(customer.priceSince != nil ? "Last rise \(from.map(RoundCalendar.shortWithYear) ?? "")"
                     : "No rise logged · first clean \(from.map(RoundCalendar.shortWithYear) ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            } trailing: {
                VStack(alignment: .trailing, spacing: 2) {
                    if let m = p.monthly, let nm = p.newMonthly {
                        Text("\(m.pounds) → \(nm.pounds)").bold()
                        Text("a month").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("\(p.price.pounds) → \(p.newPrice.pounds)").bold()
                    }
                    if let a = p.altPrice, let na = p.newAltPrice {
                        Text("\(customer.secondPriceName) \(a.pounds) → \(na.pounds)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .monospacedDigit()
            }
            Button("Done") { confirming = customer }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    /// Name and detail on the left, figures on the right; tapping it opens the customer (the Done button stays separate).
    private func link<Detail: View, Trailing: View>(_ customer: Customer, @ViewBuilder detail: () -> Detail,
                                                    @ViewBuilder trailing: () -> Trailing) -> some View {
        Button { opened = customer } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(customer.name).font(.headline)
                    detail()
                }
                Spacer()
                trailing()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .tint(.primary)
    }
}
