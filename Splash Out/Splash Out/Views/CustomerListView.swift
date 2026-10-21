import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CustomerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(UndoCenter.self) private var undoCenter
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(sort: \Customer.sequence) private var customers: [Customer]

    /// Regular width (iPad): the chosen customer is shown in the right-hand panel.
    @State private var selectedID: UUID?

    @State private var criteria = CustomerFilter.Criteria()
    /// The customer whose group is being changed from the long-press menu.
    @State private var grouping: Customer?
    @State private var isShowingAddCustomer = false
    @State private var isShowingFileImporter = false
    @State private var pendingImport: PendingImport?
    @State private var importErrorMessage: String?
    @State private var skipAsk: Customer?
    /// A "Paid" swipe for someone who already owes: asks about the older cleans.
    @State private var paidRequest: PaidRequest?

    private struct PendingImport: Identifiable {
        let id = UUID()
        let headers: [String]
        let rows: [[String]]
    }

    private var rounds: [String] { Set(customers.map(\.round).filter { !$0.isEmpty }).sorted() }
    private var areas: [String] {
        Set(customers.filter { criteria.round == nil || $0.round == criteria.round }.map(\.area).filter { !$0.isEmpty }).sorted()
    }

    var body: some View {
        let perfStart = PerfProbe.now()
        let shown = CustomerFilter.apply(criteria, to: customers)
        let _ = PerfProbe.end("Customers", perfStart)
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    configured(customerList(shown))
                } detail: {
                    NavigationStack {
                        if let customer = customers.first(where: { $0.id == selectedID }) {
                            CustomerDetailView(customer: customer).id(customer.id)
                        } else {
                            ContentUnavailableView("Choose a customer", systemImage: "person.crop.circle",
                                                   description: Text("Pick someone from the list to see their details and history."))
                        }
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack {
                    configured(customerList(shown))
                        .navigationDestination(for: Customer.self) { customer in
                            CustomerDetailView(customer: customer)
                        }
                }
            }
        }
        .sheet(item: $grouping) { GroupPickerView(customer: $0) }
        .sheet(isPresented: $isShowingAddCustomer) {
            AddEditCustomerView(customer: nil)
        }
        .sheet(item: $pendingImport) { pending in
            ImportCustomersView(headers: pending.headers, rows: pending.rows)
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            onCompletion: handleFileImport
        )
        .owedOnPaidPrompt($paidRequest)
        .alert("Skip anyway?", isPresented: Binding(get: { skipAsk != nil }, set: { if !$0 { skipAsk = nil } }), presenting: skipAsk) { person in
            if OwedReminder.canSend(to: person) {
                Button("Skip and send a reminder") { OwedReminder.open(for: person); perform(.skipped, for: person) }
            }
            Button("Skip anyway", role: .destructive) { perform(.skipped, for: person) }
            Button("Go back", role: .cancel) {}
        } message: { person in
            let owed = RoundMetrics.moneyOwed([person])
            Text("\(person.name) still owes \(owed.amount.formatted(.currency(code: "GBP"))) from \(owed.cleans) earlier clean\(owed.cleans == 1 ? "" : "s").")
        }
        .alert("Couldn't Import File", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    private func customerList(_ shown: [Customer]) -> some View {
        List(selection: sizeClass == .regular ? $selectedID : .constant(nil)) {
            if !customers.isEmpty {
            Section {
                Picker("Round", selection: $criteria.round) {
                    Text("All rounds").tag(String?.none)
                    ForEach(rounds, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                Picker("Area", selection: $criteria.area) {
                    Text("All areas").tag(String?.none)
                    ForEach(areas, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                Picker("Status", selection: $criteria.status) {
                    Text("Any status").tag(CustomerStatus?.none)
                    ForEach(CustomerStatus.allCases) { Text($0.label).tag(CustomerStatus?.some($0)) }
                }
            } footer: {
                if criteria.isActive {
                    Text("\(shown.count) of \(customers.count) customers. Clear the search and filters to see the groups.")
                } else {
                    Text("Groups are kept on the same day. Press and hold a customer to drag them into another group (drop on a customer to go after them, or on a heading to go first), or for more options.")
                }
            }
            }

            if criteria.isActive {
                ForEach(shown) { customer in row(customer, draggable: false) }
            } else {
                let clusters = GroupEditing.clusters(customers)
                ForEach(clusters) { cluster in
                    Section {
                        ForEach(cluster.members) { customer in row(customer, draggable: true) }
                    } header: {
                        HStack {
                            Text(cluster.name)
                            Spacer()
                            Text("\(cluster.members.count) house\(cluster.members.count == 1 ? "" : "s")")
                        }
                        .contentShape(Rectangle())
                        .dropDestination(for: String.self) { items, _ in
                            guard let mover = dragged(items) else { return false }
                            withAnimation { GroupEditing.move(mover, toStartOf: cluster, all: customers) }
                            return true
                        }
                    }
                }
                let offRound = customers.filter { $0.status == .cancelled || $0.status == .paused }
                if !offRound.isEmpty {
                    Section("Not on the round") {
                        ForEach(offRound) { customer in row(customer, draggable: false) }
                    }
                }
            }
        }
    }

    /// The customer being dragged, from the id carried by the drag.
    private func dragged(_ items: [String]) -> Customer? {
        guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return nil }
        return customers.first { $0.id == id && $0.status != .cancelled && $0.status != .paused }
    }

    @ViewBuilder
    private func row(_ customer: Customer, draggable: Bool) -> some View {
        let base = customerRow(customer)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { log(.cleanedPaid, for: customer) } label: {
                    Label("Paid", systemImage: "checkmark.circle.fill")
                }
                .tint(.green)
                Button { log(.cleanedNotPaid, for: customer) } label: {
                    Label("Not paid", systemImage: "clock.badge.exclamationmark")
                }
                .tint(.orange)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button { log(.skipped, for: customer) } label: {
                    Label("Skipped", systemImage: "forward.circle")
                }
                .tint(.red)
            }
        if draggable {
            base
                .draggable(customer.id.uuidString) { CustomerRow(customer: customer).padding().background(.background).frame(width: 320) }
                .dropDestination(for: String.self) { items, _ in
                    guard let mover = dragged(items), mover !== customer else { return false }
                    withAnimation { GroupEditing.move(mover, after: customer, all: customers) }
                    return true
                }
                .contextMenu {
                    Button { withAnimation { GroupEditing.newGroup(after: customer, all: customers) } } label: {
                        Label("Start a new group after \(customer.name)", systemImage: "rectangle.split.1x2")
                    }
                    if isFirstInGroup(customer) {
                        Button { withAnimation { GroupEditing.joinGroupAbove(customer, all: customers) } } label: {
                            Label("Join the group above", systemImage: "arrow.up.square")
                        }
                    }
                    Button { grouping = customer } label: { Label("Move to another group...", systemImage: "square.stack.3d.up") }
                }
        } else {
            base
        }
    }

    /// First of their group, with a group above to join.
    private func isFirstInGroup(_ customer: Customer) -> Bool {
        let clusters = GroupEditing.clusters(customers)
        guard let index = clusters.firstIndex(where: { $0.members.first === customer }) else { return false }
        return index > 0
    }

    @ViewBuilder
    private func customerRow(_ customer: Customer) -> some View {
        if sizeClass == .regular {
            CustomerRow(customer: customer).tag(customer.id)
        } else {
            NavigationLink(value: customer) {
                CustomerRow(customer: customer)
            }
        }
    }

    /// Search, title, toolbar and empty state shared by both layouts.
    private func configured<Content: View>(_ list: Content) -> some View {
        list
            .roomyRows()
            .searchable(text: $criteria.search, prompt: "Name, address, area or note")
            .navigationTitle("Customers")
            .overlay {
                if customers.isEmpty {
                    ContentUnavailableView {
                        Label("No Customers Yet", systemImage: "person.crop.circle.badge.plus")
                    } description: {
                        Text("Add your first customer to get started.")
                    } actions: {
                        Button("Add Customer") {
                            isShowingAddCustomer = true
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Import Customers from File") {
                            isShowingFileImporter = true
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingAddCustomer = true
                    } label: {
                        Label("Add Customer", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingFileImporter = true
                    } label: {
                        Label("Import Customers from File", systemImage: "square.and.arrow.down")
                    }
                }
            }
    }

    private func log(_ action: VisitLogger.Action, for customer: Customer) {
        if case .skipped = action, RoundMetrics.moneyOwed([customer]).cleans > 0 {
            skipAsk = customer
            return
        }
        if case .cleanedPaid = action, RoundMetrics.moneyOwed([customer]).cleans > 0 {
            paidRequest = PaidRequest(customer: customer)
            return
        }
        perform(action, for: customer)
    }

    /// Swipes save straight away, animated, so a full swipe slides the row off and the list closes up behind it.
    private func perform(_ action: VisitLogger.Action, for customer: Customer) {
        withAnimation {
            let undo = VisitLogger.perform(action, for: customer, in: modelContext)
            // Saved now, so the list updates in the same moment the row slides away (no flicker back).
            try? modelContext.save()
            undoCenter.offer("\(customer.name): \(action.summary)", undo: undo)
        }
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure:
            importErrorMessage = "Couldn't open that file. Try picking it again."
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                importErrorMessage = "Couldn't access that file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
                importErrorMessage = "Couldn't read that file as text. Make sure it's a CSV file."
                return
            }

            let parsed = CSVParser.parse(text)
            guard let firstRow = parsed.first, !parsed.isEmpty else {
                importErrorMessage = "That file appears to be empty."
                return
            }

            pendingImport = PendingImport(headers: firstRow, rows: Array(parsed.dropFirst()))
        }
    }
}

private struct CustomerRow: View {
    let customer: Customer

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(customer.name)
                    .font(.headline)
                Text(customer.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if customer.status != .active {
                Text(customer.status.label)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.15))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            } else if !customer.area.isEmpty {
                Text(customer.area)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    CustomerListView()
        .modelContainer(for: Customer.self, inMemory: true)
}
