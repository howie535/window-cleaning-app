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
    @State private var editMode: EditMode = .inactive
    @State private var isShowingAddCustomer = false
    @State private var isShowingFileImporter = false
    @State private var pendingImport: PendingImport?
    @State private var importErrorMessage: String?

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
        let shown = CustomerFilter.apply(criteria, to: customers)
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
        List(selection: $selectedID) {
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
                Toggle("Reorder round", isOn: Binding(
                    get: { editMode == .active },
                    set: { editMode = $0 ? .active : .inactive }
                ))
                .disabled(criteria.isActive)
            } footer: {
                if criteria.isActive {
                    Text("\(shown.count) of \(customers.count) customers. Clear the search and filters to reorder the round.")
                } else {
                    Text("Reorder round lets you drag customers into their place. The round order decides who's next.")
                }
            }

            ForEach(shown) { customer in
                customerRow(customer)
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
            }
            .onMove { offsets, destination in
                // Only meaningful for the whole round, so it's switched off while filtering.
                guard !criteria.isActive else { return }
                RoundOrder.move(customers, from: offsets, to: destination)
            }
        }
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
            .environment(\.editMode, $editMode)
            .searchable(text: $criteria.search, prompt: "Name, address, area or note")
            .onChange(of: criteria.isActive) { _, active in if active { editMode = .inactive } }
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
        let undo = VisitLogger.perform(action, for: customer, in: modelContext)
        undoCenter.offer("\(customer.name): \(action.summary)", undo: undo)
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
