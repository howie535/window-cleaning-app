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
    /// Typed straight into the page; saved when the box loses focus or the page closes.
    @State private var notesDraft = ""
    @State private var nextVisitDraft = ""
    @FocusState private var focused: Field?
    private enum Field { case notes, nextVisit }

    private func saveDrafts() {
        guard !isDeleted else { return }
        if notesDraft != customer.notesText { customer.notesText = notesDraft }
        let next = nextVisitDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if (next.isEmpty ? nil : next) != customer.nextVisitNote { customer.nextVisitNote = next.isEmpty ? nil : next }
    }

    private func loadDrafts() {
        notesDraft = customer.notesText
        nextVisitDraft = customer.nextVisitNote ?? ""
    }

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
        let owedText = owed.cleans > 0 ? " Their \(owed.amount.pounds) owed drops off Money Owed." : ""
        return "Removes \(customer.name) and \(customer.allVisits.count) visits (\(cleans.count) cleans, \(work.pounds)) from every total, including the tax year.\(owedText) A backup is saved first. To keep their history, cancel instead."
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
            // Doorstep first: contact, money owed, logging. Details and history follow; cancel and delete last.
            Section("Contact") {
                ContactButton(customer: customer)
            }

            if owed.cleans > 0 {
                Section("Owed") {
                    LabeledContent("\(owed.cleans) clean\(owed.cleans == 1 ? "" : "s")") {
                        Text(owed.amount, format: .currency(code: "GBP"))
                            .font(.headline)
                            .foregroundStyle(Color.owedText)
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
                if owed.cleans == 0 && customer.lastCleanDate != nil {
                    Button("Payment in advance...") { isShowingPayment = true }
                }
            }

            Section {
                TextField("Extra job or reminder", text: $nextVisitDraft, axis: .vertical)
                    .focused($focused, equals: .nextVisit)
            } header: {
                Text("Next visit")
            } footer: {
                Text("Shows on the round; cleared when the next clean is logged.")
            }

            Section("Notes") {
                TextField("Add a note", text: $notesDraft, axis: .vertical)
                    .focused($focused, equals: .notes)
            }

            Section {
                CustomerMapView(customer: customer)
            }

            Section {
                LabeledContent("Address", value: customer.address)
                LabeledContent("Phone", value: customer.phone)
                LabeledContent("Price", value: customer.price, format: .currency(code: "GBP"))
                LabeledContent("Last price rise", value: customer.priceSince.map { RoundCalendar.shortWithYear($0) }
                               ?? PriceRise.countedFrom(customer).map { "None since \(RoundCalendar.shortWithYear($0))" } ?? "No date logged")
                if customer.payMethod == .directDebit, let monthly = customer.monthlyAmount {
                    LabeledContent("Direct Debit", value: "\(monthly.formatted(.currency(code: "GBP"))) a month")
                }
                if customer.outstandingBalance != 0 {
                    LabeledContent("Balance") {
                        Text(balanceDescription)
                            .foregroundStyle(customer.outstandingBalance > 0 ? Color.blue : Color.notPaidText)
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

            if !sortedPriceChanges.isEmpty {
                Section {
                    ForEach(sortedPriceChanges) { change in
                        HStack {
                            Text(change.date, format: .dateTime.day().month().year())
                            Spacer()
                            Text(change.oldPrice > 0 ? "\(change.oldPrice.pounds) to \(change.newPrice.pounds)" : "to \(change.newPrice.pounds)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        let changes = sortedPriceChanges
                        for index in offsets { PriceHistoryEditing.delete(changes[index], from: customer, context: modelContext) }
                    }
                } header: {
                    Text("Price history")
                } footer: {
                    Text("Swipe left to delete one entered by mistake. It doesn't change the price.")
                }
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

            Section {
                if customer.status == .cancelled {
                    Button("Reactivate this customer") { customer.status = .active }
                    Button("Someone new has moved in...") { isShowingNewOccupant = true }
                } else {
                    Button("Cancel this customer...", role: .destructive) { isConfirmingCancel = true }
                }
                Button("Delete customer completely...", role: .destructive) { isConfirmingDelete = true }
            } footer: {
                customer.status == .cancelled
                    ? InfoFooter(text: "Their history and anything owed are kept.", title: "Cancelled customers", points: [
                        "Find them under Status › Cancelled on Customers.",
                        "Someone new moved in? Use \"Someone new has moved in\" so each history stays separate.",
                        "Delete is only for mistakes, such as a duplicate. It takes their cleans out of the stats."])
                    : InfoFooter(text: "Cancel keeps their history. Delete is for mistakes.", title: "Cancel or delete", points: [
                        "Cancel when a customer stops using you. Their history and anything owed are kept.",
                        "Delete is only for mistakes, such as a duplicate. It takes their cleans out of the stats."])
            }
        }
        .sudsyBackground()
        .navigationTitle(customer.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if focused != nil {
                    Button("Done") { focused = nil }.bold()
                } else {
                    Button("Edit") { saveDrafts(); isShowingEdit = true }
                }
            }
        }
        .onAppear(perform: loadDrafts)
        .onDisappear(perform: saveDrafts)
        .onChange(of: focused) { _, _ in saveDrafts() }
        .onChange(of: isShowingEdit) { _, showing in if !showing { loadDrafts() } }
        .visitLogSheets(customer: customer, selection: $logSheet)
        .sheet(isPresented: $isShowingNewOccupant) {
            AddEditCustomerView(customer: nil, replacing: customer)
        }
        .confirmationDialog("Cancel \(customer.name)?", isPresented: $isConfirmingCancel, titleVisibility: .visible) {
            Button("Cancel customer", role: .destructive) { customer.status = .cancelled }
            Button("Cancel", role: .cancel) {}
        } message: {
            if owed.cleans > 0 {
                Text("They still owe \(owed.amount.formatted(.currency(code: "GBP"))) from \(owed.cleans) clean\(owed.cleans == 1 ? "" : "s"). That stays on Money Owed after they're cancelled.")
            } else {
                Text("They'll come off the round. Their history is kept.")
            }
        }
        .alert("Delete \(customer.name) completely?", isPresented: $isConfirmingDelete) {
            Button("Delete for good", role: .destructive, action: deleteCustomer)
            Button("Cancel", role: .cancel) {}
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
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if log.kind == .cleaned {
                VStack(alignment: .trailing) {
                    Text(log.charged, format: .currency(code: "GBP"))
                    Text(paymentStatusText)
                        .font(.footnote)
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
        return difference > 0 ? .blue : .notPaidText
    }
}

#Preview {
    NavigationStack {
        CustomerDetailView(customer: Customer(name: "Jane Doe", address: "1 High Street", phone: "447700900123", price: 15, notes: ["Side gate code 1234"]))
    }
    .modelContainer(for: Customer.self, inMemory: true)
}
