import SwiftUI
import SwiftData

struct CustomerDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var customer: Customer

    @State private var isShowingEdit = false
    @State private var isShowingPayment = false
    @State private var logSheet: VisitSheet?

    private var sortedLogs: [Visit] {
        customer.allVisits.sorted { $0.date > $1.date }
    }

    private var sortedPriceChanges: [PriceChange] {
        (customer.priceChanges ?? []).sorted { $0.date > $1.date }
    }

    private var owed: (amount: Decimal, cleans: Int) {
        RoundMetrics.moneyOwed([customer])
    }

    private var balanceDescription: String {
        let balance = customer.outstandingBalance
        let formatted = abs(balance).formatted(.currency(code: "GBP"))
        return balance > 0 ? "In credit \(formatted)" : "Short by \(formatted)"
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Address", value: customer.address)
                LabeledContent("Phone", value: customer.phone)
                LabeledContent("Price", value: customer.price, format: .currency(code: "GBP"))
                if customer.outstandingBalance != 0 {
                    LabeledContent("Balance") {
                        Text(balanceDescription)
                            .foregroundStyle(customer.outstandingBalance > 0 ? .blue : .orange)
                    }
                    LabeledContent("Next Price", value: customer.suggestedNextPrice, format: .currency(code: "GBP"))
                }
                if !customer.round.isEmpty || !customer.area.isEmpty {
                    LabeledContent("Round", value: [customer.round, customer.area].filter { !$0.isEmpty }.joined(separator: ", "))
                }
                LabeledContent("Status", value: customer.status.label + (customer.everyOther ? " (every other)" : ""))
                if customer.frontOnly {
                    LabeledContent("Front only", value: "Yes")
                }
                if let method = customer.payMethod {
                    LabeledContent("Pays by", value: method.label)
                }
                if let lastClean = customer.lastCleanDate {
                    LabeledContent("Last Clean") {
                        Text(lastClean, style: .date)
                    }
                }
            }

            Section("Notes") {
                if customer.notes.isEmpty {
                    Text("No notes yet. Add them with Edit.")
                        .foregroundStyle(.secondary)
                }
                ForEach(customer.notes, id: \.self) { note in
                    Text(note)
                }
            }

            if owed.cleans > 0 {
                Section("Owed") {
                    LabeledContent("\(owed.cleans) clean\(owed.cleans == 1 ? "" : "s")") {
                        Text(owed.amount, format: .currency(code: "GBP"))
                            .font(.headline)
                            .foregroundStyle(.red)
                    }
                    Button {
                        isShowingPayment = true
                    } label: {
                        Label("Record payment...", systemImage: "sterlingsign.circle")
                            .font(.title3)
                            .padding(.vertical, 6)
                    }
                }
            }

            Section("Log") {
                VisitQuickActions(customer: customer, sheet: $logSheet)
            }

            Section("Contact") {
                ContactButton(customer: customer)
            }

            if !sortedPriceChanges.isEmpty {
                Section("Price history") {
                    ForEach(sortedPriceChanges) { change in
                        HStack {
                            Text(change.date, format: .dateTime.day().month().year())
                            Spacer()
                            Text("\(change.oldPrice.formatted(.currency(code: "GBP"))) to \(change.newPrice.formatted(.currency(code: "GBP")))")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("History") {
                if sortedLogs.isEmpty {
                    Text("No visits yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedLogs) { log in
                        CleanLogRow(log: log)
                    }
                    .onDelete(perform: deleteLogs)
                }
            }
        }
        .navigationTitle(customer.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isShowingEdit = true }
            }
        }
        .visitLogSheets(customer: customer, selection: $logSheet)
        .sheet(isPresented: $isShowingEdit) {
            AddEditCustomerView(customer: customer)
        }
        .sheet(isPresented: $isShowingPayment) {
            RecordPaymentView(customer: customer)
        }
    }

    private func deleteLogs(at offsets: IndexSet) {
        for index in offsets {
            VisitLogger.remove(sortedLogs[index], in: modelContext)
        }
    }
}

/// WhatsApp for most customers; a phone call for those marked "ring".
struct ContactButton: View {
    let customer: Customer

    @State private var isPickingContact = false
    @State private var pickMessage: String?

    var body: some View {
        Group {
            if customer.phone.isEmpty {
                // No number yet: say so, and let one tap fill it in from Contacts.
                Button { isPickingContact = true } label: {
                    Label("Add \(customer.name)'s number from Contacts", systemImage: "person.crop.circle.badge.plus")
                        .font(.title3)
                        .padding(.vertical, 6)
                }
            } else if customer.contact == .ring {
                if let url = URL(string: "tel:\(customer.phone.filter(\.isNumber))") {
                    Link(destination: url) {
                        Label("Ring \(customer.name)", systemImage: "phone")
                            .font(.title3)
                            .padding(.vertical, 6)
                    }
                }
            } else {
                WhatsAppButton(customer: customer)
            }
        }
        .sheet(isPresented: $isPickingContact) {
            ContactPicker { contact in
                let digits = contact.splashOutPhoneDigits
                if digits.isEmpty {
                    pickMessage = "\(contact.splashOutFullName) has no phone number in Contacts."
                } else {
                    customer.phone = digits
                }
            }
        }
        .alert("Contacts", isPresented: Binding(get: { pickMessage != nil }, set: { if !$0 { pickMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pickMessage ?? "")
        }
    }
}

private struct CleanLogRow: View {
    let log: Visit

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(log.date, style: .date)
                if let note = log.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if log.kind == .cleaned {
                VStack(alignment: .trailing) {
                    Text(log.charged, format: .currency(code: "GBP"))
                    Text(paymentStatusText)
                        .font(.caption)
                        .foregroundStyle(paymentStatusColor)
                }
            } else {
                Text(log.kind == .skipped ? "Skipped" : "Not due")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var paymentStatusText: String {
        if log.paid == 0 { return "Unpaid" }
        let difference = log.paymentDifference
        if difference == 0 { return "Paid in full" }
        let formatted = abs(difference).formatted(.currency(code: "GBP"))
        return difference > 0 ? "Overpaid by \(formatted)" : "Underpaid by \(formatted)"
    }

    private var paymentStatusColor: Color {
        if log.paid == 0 { return .red }
        let difference = log.paymentDifference
        if difference == 0 { return .green }
        return difference > 0 ? .blue : .orange
    }
}

#Preview {
    NavigationStack {
        CustomerDetailView(customer: Customer(name: "Jane Doe", address: "1 High Street", phone: "447700900123", price: 15, notes: ["Side gate code 1234"]))
    }
    .modelContainer(for: Customer.self, inMemory: true)
}
