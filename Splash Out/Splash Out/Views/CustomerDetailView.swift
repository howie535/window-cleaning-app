import SwiftUI
import SwiftData

struct CustomerDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var customer: Customer

    @State private var isShowingEdit = false
    @State private var isShowingPayment = false
    @State private var logSheet: VisitSheet?
    @State private var isConfirmingCancel = false
    @State private var isShowingNewOccupant = false
    @State private var isConfirmingDelete = false
    @State private var editingVisit: Visit?
    @State private var isChangingRise = false
    @State private var isChangingGroup = false
    @Query private var everyone: [Customer]
    @State private var riseText = ""
    /// Set while deleting, so nothing reads the customer once it's gone.
    @State private var isDeleted = false
    @Environment(\.dismiss) private var dismiss

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
        if isDeleted {
            ContentUnavailableView("Customer deleted", systemImage: "trash")
        } else {
            details
        }
    }

    /// What deleting would take out of the stats.
    private var deleteSummary: String {
        let cleans = customer.allVisits.filter { $0.kind == .cleaned }
        let work = cleans.reduce(Decimal(0)) { $0 + $1.charged }
        let owedText = owed.cleans > 0 ? " They owe \(owed.amount.pounds), which will no longer show on Money Owed." : ""
        return "This removes \(customer.name) and all \(customer.allVisits.count) visits (\(cleans.count) cleans, \(work.pounds) of work) from every total, including the tax year.\(owedText) It can't be undone here, but a backup is saved first. To keep their history, cancel them instead."
    }

    private func deleteCustomer() {
        // A one-off backup just before, kept apart from the daily copies.
        if let data = try? ExportService.data(from: modelContext) {
            let directory = ExportService.backupDirectory
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
            try? data.write(to: directory.appendingPathComponent("splash-out-before-delete-\(stamp).json"), options: .atomic)
        }
        isDeleted = true
        let target = customer
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            modelContext.delete(target)
            try? modelContext.save()
        }
    }

    private var details: some View {
        List {
            Section {
                CustomerMapView(customer: customer)
            }
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

            if customer.status != .cancelled && customer.status != .paused {
                Section {
                    let cluster = GroupEditing.clusters(everyone).first { $0.members.contains { $0 === customer } }
                    if let cluster {
                        LabeledContent("Group", value: "\(cluster.name) · \(cluster.members.count) house\(cluster.members.count == 1 ? "" : "s")")
                    }
                    Button("Change group...") { isChangingGroup = true }
                } footer: {
                    Text("Houses in a group are kept on the same day.")
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

            if let rise = customer.pendingPrice, let from = customer.pendingPriceFrom {
                Section {
                    LabeledContent("Rising to") {
                        Text("\(rise.pounds) from \(RoundCalendar.shortWithYear(from))").foregroundStyle(.purple)
                    }
                    LabeledContent("Told", value: customer.pendingPriceToldAt.map { RoundCalendar.shortWithYear($0) } ?? "Not yet")
                    Button("Start the new price now") { PriceRise.applyIfDue(customer, now: true, in: modelContext) }
                    Button("Change the new price...") {
                        riseText = NSDecimalNumber(decimal: rise).stringValue
                        isChangingRise = true
                    }
                    Button("Cancel this rise", role: .destructive) { PriceRise.cancel(customer) }
                } header: {
                    Text("Price rise")
                } footer: {
                    Text("Starts by itself on \(RoundCalendar.shortWithYear(from)). Set from More > Price Rise.")
                }
            }

            Section("Log") {
                VisitQuickActions(customer: customer, sheet: $logSheet)
                if owed.cleans == 0 && customer.lastCleanDate != nil {
                    Button("Payment in advance...") { isShowingPayment = true }
                }
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

            Section {
                if customer.status == .cancelled {
                    Button("Reactivate this customer") { customer.status = .active }
                    Button("Someone new has moved in...") { isShowingNewOccupant = true }
                } else {
                    Button("Cancel this customer...", role: .destructive) { isConfirmingCancel = true }
                }
                Button("Delete customer completely...", role: .destructive) { isConfirmingDelete = true }
            } footer: {
                Text((customer.status == .cancelled
                     ? "Cancelled customers stay in the list and keep their history and anything they owe. Find them with Status > Cancelled on the Customers screen. If a new person has moved into the house, \"Someone new has moved in\" starts a fresh customer at the same address, so this customer's history stays separate and your stats stay right."
                     : "Use this when a customer stops using you. Their history is kept, and so is anything they owe.")
                     + " Delete is only for mistakes such as a duplicate: it takes their cleans out of the stats.")
            }

            Section {
                if sortedLogs.isEmpty {
                    Text("No visits yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedLogs) { log in
                        Button { editingVisit = log } label: {
                            CleanLogRow(log: log).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteLogs)
                }
            } header: {
                Text("History")
            } footer: {
                if !sortedLogs.isEmpty { Text("Tap a visit to correct it or delete it.") }
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
        .sheet(isPresented: $isShowingNewOccupant) {
            AddEditCustomerView(customer: nil, replacing: customer)
        }
        .confirmationDialog("Cancel \(customer.name)?", isPresented: $isConfirmingCancel, titleVisibility: .visible) {
            Button("Cancel customer", role: .destructive) { customer.status = .cancelled }
            Button("Keep them", role: .cancel) {}
        } message: {
            if owed.cleans > 0 {
                Text("They still owe \(owed.amount.formatted(.currency(code: "GBP"))) from \(owed.cleans) clean\(owed.cleans == 1 ? "" : "s"). That stays on Money Owed after they're cancelled.")
            } else {
                Text("They'll come off the round. Their history is kept.")
            }
        }
        .alert("New price for \(customer.name)", isPresented: $isChangingRise) {
            TextField("Price", text: $riseText).keyboardType(.decimalPad)
            Button("Save") {
                if let value = Decimal(string: riseText), value > 0, let from = customer.pendingPriceFrom {
                    let told = customer.pendingPriceToldAt
                    PriceRise.set(customer, to: value, from: from)
                    customer.pendingPriceToldAt = told
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete \(customer.name) completely?", isPresented: $isConfirmingDelete) {
            Button("Delete for good", role: .destructive, action: deleteCustomer)
            Button("Keep them", role: .cancel) {}
        } message: {
            Text(deleteSummary)
        }
        .sheet(isPresented: $isChangingGroup) { GroupPickerView(customer: customer) }
        .sheet(item: $editingVisit) { visit in
            EditVisitView(visit: visit)
        }
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
